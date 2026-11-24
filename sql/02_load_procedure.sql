-- 02_load_procedure.sql
-- Reusable loader: loads one Aeris .txt file and APPENDS it to dbo.aeris_clean.
-- Handles both Aeris export formats, detected from the header:
--   * full export   : 53 columns (incl. wet mole fractions and spectral fit parameters)
--   * short export  : 19 columns
-- Usage:
--   EXEC dbo.load_aeris_file @folder = N'C:\data\aeris', @file = N'<file name>.txt';
-- Note: BULK INSERT runs as the SQL Server service account, so the folder must be
-- readable by that account (a local folder such as C:\data\aeris works; OneDrive often does not).
USE FieldData;
GO

-- Staging table for the short (19-column) export, all text
IF OBJECT_ID('dbo.raw_aeris_short') IS NULL
CREATE TABLE dbo.raw_aeris_short (
    Time_Stamp nvarchar(50), Inlet_Number nvarchar(50), P_mbar nvarchar(50),
    T0_degC nvarchar(50), T1_degC nvarchar(50), T2_degC nvarchar(50), T5_degC nvarchar(50),
    Tgas_degC nvarchar(50), CO2_ppm nvarchar(50), H2O_ppm nvarchar(50), N2O_ppm nvarchar(50),
    Battery_Charge_V nvarchar(50), Power_Input_mV nvarchar(50), Current_mA nvarchar(50), SOC_pct nvarchar(50),
    TEC_Sink_Temp_degC nvarchar(50), Wall_Code nvarchar(50), Latitude nvarchar(50), Longitude nvarchar(50)
);

-- Load log: one row per loaded file (what, when, which format, how many rows)
IF OBJECT_ID('dbo.load_log') IS NULL
CREATE TABLE dbo.load_log (
    load_id        int IDENTITY(1,1) PRIMARY KEY,
    source_file    nvarchar(200) NOT NULL,
    file_format    nvarchar(20)  NOT NULL,
    n_rows         int           NOT NULL,
    bad_timestamps int           NOT NULL,
    first_ts       datetime2(3),
    last_ts        datetime2(3),
    loaded_at      datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    loaded_by      nvarchar(128) NOT NULL DEFAULT SUSER_SNAME()
);
GO

-- Timestamp parser for both Aeris timestamp styles
CREATE OR ALTER FUNCTION dbo.parse_aeris_ts (@s nvarchar(50))
RETURNS datetime2(3)
AS
BEGIN
    RETURN CASE
        -- style A: 2024-05-29T01.38.40.100
        WHEN @s LIKE '[0-9][0-9][0-9][0-9]-%' THEN
            TRY_CONVERT(datetime2(3), LEFT(@s, 10) + 'T'
              + REPLACE(SUBSTRING(@s, 12, 8), '.', ':') + SUBSTRING(@s, 20, 4), 126)
        -- style B: 05/29/2024 01:38:40.100  (US month/day/year)
        ELSE
            TRY_CONVERT(datetime2(3), SUBSTRING(@s, 7, 4) + '-' + LEFT(@s, 2) + '-'
              + SUBSTRING(@s, 4, 2) + 'T' + SUBSTRING(@s, 12, 12), 126)
    END;
END
GO

CREATE OR ALTER PROCEDURE dbo.load_aeris_file
    @folder nvarchar(400),
    @file   nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;

    -- Never load the same file twice (by name)
    IF EXISTS (SELECT 1 FROM dbo.aeris_clean WHERE source_file = @file)
    BEGIN
        RAISERROR('File already loaded: %s', 16, 1, @file);
        RETURN;
    END

    DECLARE @path nvarchar(600) = @folder + N'\' + @file;
    DECLARE @sql nvarchar(max), @txt nvarchar(max), @header nvarchar(max), @ncol int, @format nvarchar(20);

    -- 1. Read the header line and detect the export format from the number of columns
    SET @sql = N'SELECT @t = BulkColumn FROM OPENROWSET(BULK ''' + @path + N''', SINGLE_CLOB) AS f;';
    EXEC sp_executesql @sql, N'@t nvarchar(max) OUTPUT', @t = @txt OUTPUT;
    SET @header = LEFT(@txt, CHARINDEX(CHAR(10), @txt + CHAR(10)) - 1);
    SET @ncol   = LEN(@header) - LEN(REPLACE(@header, ',', '')) + 1;

    -- 2. Load into the matching staging table and convert into a temporary table
    CREATE TABLE #new (
        ts datetime2(3), inlet tinyint, p_mbar float, tgas_degC float,
        co2_ppm float, h2o_ppm float, n2o_ppm float, co2_ppm_wet float, n2o_ppm_wet float
    );

    IF @ncol = 53
    BEGIN
        SET @format = N'full (53 col)';
        TRUNCATE TABLE dbo.raw_aeris;
        SET @sql = N'BULK INSERT dbo.raw_aeris FROM ''' + @path + N''' '
                 + N'WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', TABLOCK);';
        EXEC (@sql);

        INSERT INTO #new
        SELECT dbo.parse_aeris_ts(Time_Stamp),
               TRY_CONVERT(tinyint, Inlet_Number), TRY_CONVERT(float, P_mbar), TRY_CONVERT(float, Tgas_degC),
               TRY_CONVERT(float, CO2_ppm), TRY_CONVERT(float, H2O_ppm), TRY_CONVERT(float, N2O_ppm),
               TRY_CONVERT(float, CO2_ppm_wet), TRY_CONVERT(float, N2O_ppm_wet)
        FROM dbo.raw_aeris;
    END
    ELSE IF @ncol = 19
    BEGIN
        SET @format = N'short (19 col)';
        TRUNCATE TABLE dbo.raw_aeris_short;
        SET @sql = N'BULK INSERT dbo.raw_aeris_short FROM ''' + @path + N''' '
                 + N'WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', TABLOCK);';
        EXEC (@sql);

        INSERT INTO #new
        SELECT dbo.parse_aeris_ts(Time_Stamp),
               TRY_CONVERT(tinyint, Inlet_Number), TRY_CONVERT(float, P_mbar), TRY_CONVERT(float, Tgas_degC),
               TRY_CONVERT(float, CO2_ppm), TRY_CONVERT(float, H2O_ppm), TRY_CONVERT(float, N2O_ppm),
               NULL, NULL                                   -- wet values not in the short export
        FROM dbo.raw_aeris_short;
    END
    ELSE
    BEGIN
        RAISERROR('Unknown file format: %d columns in the header of %s', 16, 1, @ncol, @file);
        RETURN;
    END

    -- 3. Never load the same DATA twice: refuse if the time range overlaps data already loaded
    --    (e.g. the short and the full export of the same recording have different names but identical data)
    DECLARE @first datetime2(3), @last datetime2(3), @clash nvarchar(200);
    SELECT @first = MIN(ts), @last = MAX(ts) FROM #new;
    SELECT TOP 1 @clash = source_file
    FROM dbo.aeris_clean
    WHERE ts BETWEEN @first AND @last;

    IF @clash IS NOT NULL
    BEGIN
        RAISERROR('Not loaded: %s overlaps in time with data already loaded from %s', 16, 1, @file, @clash);
        RETURN;
    END

    -- 4. Append to the clean table
    INSERT INTO dbo.aeris_clean
        (source_file, ts, inlet, p_mbar, tgas_degC, co2_ppm, h2o_ppm, n2o_ppm, co2_ppm_wet, n2o_ppm_wet)
    SELECT @file, ts, inlet, p_mbar, tgas_degC, co2_ppm, h2o_ppm, n2o_ppm, co2_ppm_wet, n2o_ppm_wet
    FROM #new;

    -- 5. Record the load and report it
    INSERT INTO dbo.load_log (source_file, file_format, n_rows, bad_timestamps, first_ts, last_ts)
    SELECT @file, @format, COUNT(*), SUM(CASE WHEN ts IS NULL THEN 1 ELSE 0 END), MIN(ts), MAX(ts)
    FROM #new;

    SELECT source_file, file_format, n_rows, bad_timestamps, first_ts, last_ts
    FROM dbo.load_log
    WHERE source_file = @file;
END
GO
