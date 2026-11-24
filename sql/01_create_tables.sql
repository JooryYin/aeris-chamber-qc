-- 01_create_tables.sql
-- Staging table (raw text), clean typed table, and field-log (closure) table.
USE FieldData;
GO

-- Staging table: all 53 Aeris columns stored as TEXT, exactly as the instrument wrote them.
-- Importing as text avoids silent corruption by regional number settings
-- (e.g. a Danish locale treating "." as a thousands separator).
IF OBJECT_ID('dbo.raw_aeris') IS NOT NULL DROP TABLE dbo.raw_aeris;
CREATE TABLE dbo.raw_aeris (
    Time_Stamp nvarchar(50), Inlet_Number nvarchar(50), P_mbar nvarchar(50),
    T0_degC nvarchar(50), T1_degC nvarchar(50), T2_degC nvarchar(50), T5_degC nvarchar(50),
    Tgas_degC nvarchar(50), Laser_PID_Readout nvarchar(50), Det_PID_Readout nvarchar(50),
    win0Fit0 nvarchar(50), win0Fit1 nvarchar(50), win0Fit2 nvarchar(50), win0Fit3 nvarchar(50), win0Fit4 nvarchar(50),
    win0Fit5 nvarchar(50), win0Fit6 nvarchar(50), win0Fit7 nvarchar(50), win0Fit8 nvarchar(50), win0Fit9 nvarchar(50),
    win1Fit0 nvarchar(50), win1Fit1 nvarchar(50), win1Fit2 nvarchar(50), win1Fit3 nvarchar(50), win1Fit4 nvarchar(50),
    win1Fit5 nvarchar(50), win1Fit6 nvarchar(50), win1Fit7 nvarchar(50), win1Fit8 nvarchar(50), win1Fit9 nvarchar(50),
    Det_Bkgd nvarchar(50), Ramp_Ampl nvarchar(50),
    CO2_ppm_wet nvarchar(50), CO2_ppm nvarchar(50), H2O_ppm nvarchar(50),
    N2O_ppm_wet nvarchar(50), N2O_ppm nvarchar(50),
    Battery_Charge_V nvarchar(50), Power_Input_mV nvarchar(50), Current_mA nvarchar(50), SOC_pct nvarchar(50),
    Battery_T_degC nvarchar(50), FET_T_degC nvarchar(50), TEC_Temp_degC nvarchar(50),
    TEC_Sink_Temp_degC nvarchar(50), TEC_Power_W nvarchar(50), Wall_Code nvarchar(50),
    GPS_Time nvarchar(50), Latitude nvarchar(50), Longitude nvarchar(50), Alt_m nvarchar(50),
    mpfit_ms nvarchar(50), buffer_size nvarchar(50)
);

-- Clean table: typed values, one row per instrument reading, all files appended.
IF OBJECT_ID('dbo.aeris_clean') IS NOT NULL DROP TABLE dbo.aeris_clean;
CREATE TABLE dbo.aeris_clean (
    measurement_id int IDENTITY(1,1) PRIMARY KEY,
    source_file    nvarchar(200) NOT NULL,   -- provenance: raw file each row came from
    ts             datetime2(3),             -- instrument clock (see README: time zones)
    inlet          tinyint,
    p_mbar         float,
    tgas_degC      float,
    co2_ppm        float,                    -- dry
    h2o_ppm        float,
    n2o_ppm        float,                    -- dry
    co2_ppm_wet    float,
    n2o_ppm_wet    float
);

-- Field log as structured metadata: one row per chamber closure.
-- start_ts is stored in the INSTRUMENT clock so it can be joined to the data.
IF OBJECT_ID('dbo.chamber_closure') IS NOT NULL DROP TABLE dbo.chamber_closure;
CREATE TABLE dbo.chamber_closure (
    closure_id    int IDENTITY(1,1) PRIMARY KEY,
    source_file   nvarchar(200) NULL,
    point_id      int           NOT NULL,
    start_ts      datetime2(3)  NOT NULL,
    duration_min  decimal(4,1)  NOT NULL,
    end_ts        AS DATEADD(SECOND, CAST(duration_min * 60 AS int), start_ts),
    note          nvarchar(400) NULL
);

-- Day-level metadata: clocks, weather, crop stage
IF OBJECT_ID('dbo.field_day') IS NOT NULL DROP TABLE dbo.field_day;
CREATE TABLE dbo.field_day (
    day                 date          PRIMARY KEY,
    instrument_offset_h int           NOT NULL,   -- local time (CEST) = instrument clock + offset
    log_clock           nvarchar(20)  NOT NULL,   -- clock used in the handwritten log
    weather             nvarchar(200) NULL,
    crop_stage          nvarchar(200) NULL,
    note                nvarchar(400) NULL
);
GO
