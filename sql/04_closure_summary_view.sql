-- 04_closure_summary_view.sql
-- One row per chamber closure: data coverage, instrument QC,
-- linear concentration slopes (ppm/min) and R^2, and a closure-level QC verdict.
USE FieldData;
GO

CREATE OR ALTER VIEW dbo.closure_summary AS
WITH d AS (
    SELECT closure_id, sec_in_closure / 60.0 AS x,
           n2o_ppm AS n2o, co2_ppm AS co2, flag_pressure, flag_range, flag_co2_baseline
    FROM dbo.aeris_qc
    WHERE closure_id IS NOT NULL
), s AS (
    SELECT closure_id,
           COUNT(*) AS n, SUM(flag_pressure) AS n_pressure, SUM(flag_range) AS n_range,
           SUM(flag_co2_baseline) AS n_co2_baseline,
           SUM(x) AS sx, SUM(x*x) AS sxx,
           SUM(n2o) AS sn, SUM(n2o*n2o) AS snn, SUM(x*n2o) AS sxn,
           SUM(co2) AS sc, SUM(co2*co2) AS scc, SUM(x*co2) AS sxc
    FROM d GROUP BY closure_id
), r AS (
    SELECT closure_id, n, n_pressure, n_range, n_co2_baseline,
           (n*sxn - sx*sn) / NULLIF(n*sxx - sx*sx, 0) AS n2o_slope,
           (n*sxc - sx*sc) / NULLIF(n*sxx - sx*sx, 0) AS co2_slope,
           SQUARE((n*sxn - sx*sn) / NULLIF(SQRT((n*sxx - sx*sx) * (n*snn - sn*sn)), 0)) AS n2o_r2,
           SQUARE((n*sxc - sx*sc) / NULLIF(SQRT((n*sxx - sx*sx) * (n*scc - sc*sc)), 0)) AS co2_r2
    FROM s
)
SELECT k.closure_id,
       CAST(k.start_ts AS date)        AS day,
       k.start_ts, k.point_id, k.duration_min, k.note,
       r.n AS n_sec, r.n_pressure, r.n_range, r.n_co2_baseline,
       r.n2o_slope AS n2o_slope_ppm_min, r.n2o_r2,
       r.co2_slope AS co2_slope_ppm_min, r.co2_r2,
       CASE WHEN r.n_pressure + r.n_range > 0     THEN 'INVALID: instrument'
            WHEN r.n < 0.9 * k.duration_min * 60   THEN 'CHECK: incomplete data'
            WHEN r.n_co2_baseline > 0              THEN 'CHECK: CO2 offset (N2O only)'
            WHEN r.co2_r2 < 0.90                   THEN 'CHECK: poor CO2 fit'
            ELSE 'ok' END AS closure_qc
FROM r
JOIN dbo.chamber_closure k ON k.closure_id = r.closure_id;
GO
