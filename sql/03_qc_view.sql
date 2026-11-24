-- 03_qc_view.sql
-- Row-level QC. Every reading keeps its values plus one flag per check.
-- Flags mark problems; they never delete data.
USE FieldData;
GO

CREATE OR ALTER VIEW dbo.aeris_qc AS
WITH base AS (
    SELECT c.*, k.closure_id, k.point_id,
        DATEDIFF_BIG(MILLISECOND, k.start_ts, c.ts) / 1000.0                                   AS sec_in_closure,
        DATEDIFF(SECOND, MIN(c.ts) OVER (PARTITION BY c.source_file), c.ts)                     AS sec_since_start,
        DATEDIFF_BIG(MILLISECOND, LAG(c.ts) OVER (PARTITION BY c.source_file ORDER BY c.ts), c.ts) / 1000.0 AS dt_s,
        AVG(c.co2_ppm) OVER (PARTITION BY c.source_file)                                        AS file_co2_mean
    FROM dbo.aeris_clean c
    LEFT JOIN dbo.chamber_closure k                 -- closures matched by time only (one instrument),
           ON c.ts >= k.start_ts AND c.ts < k.end_ts -- so several files per day (restarts) are fine
)
SELECT *,
    CASE WHEN closure_id IS NULL THEN 1 ELSE 0 END                                      AS flag_no_closure,  -- not field data
    CASE WHEN co2_ppm IS NULL OR n2o_ppm IS NULL OR h2o_ppm IS NULL THEN 1 ELSE 0 END   AS flag_missing,
    CASE WHEN sec_since_start < 120 THEN 1 ELSE 0 END                                   AS flag_warmup,      -- first 2 min of each file
    CASE WHEN dt_s > 5 THEN 1 ELSE 0 END                                                AS flag_gap,         -- >5 s since previous reading
    CASE WHEN n2o_ppm NOT BETWEEN 0.25 AND 50
           OR co2_ppm NOT BETWEEN 300  AND 10000 THEN 1 ELSE 0 END                      AS flag_range,       -- physically implausible
    CASE WHEN ABS(p_mbar - 140) > 2 THEN 1 ELSE 0 END                                   AS flag_pressure,    -- cell pressure off nominal
    CASE WHEN file_co2_mean NOT BETWEEN 380 AND 600 THEN 1 ELSE 0 END                   AS flag_co2_baseline -- whole file's CO2 level implausible
FROM base;
GO
