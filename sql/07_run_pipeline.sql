-- 07_run_pipeline.sql
-- Example run: load the raw files, then inspect QC results.
-- Run scripts 00-06 first. Raw data files are NOT included in this repository (see README).
USE FieldData;

EXEC dbo.load_aeris_file @folder = N'C:\data\aeris', @file = N'Ultra100704_240529_013840Eng.txt';
EXEC dbo.load_aeris_file @folder = N'C:\data\aeris', @file = N'Ultra100704_240612_012603Eng.txt';
EXEC dbo.load_aeris_file @folder = N'C:\data\aeris', @file = N'Ultra100704_240612_020314Eng.txt';
EXEC dbo.load_aeris_file @folder = N'C:\data\aeris', @file = N'Ultra100704_240612_030638Eng.txt';

-- Duplicate test: the short export of the same recording must be REFUSED (overlapping data)
-- EXEC dbo.load_aeris_file @folder = N'C:\data\aeris', @file = N'Ultra100704_240612_012603.txt';

SELECT * FROM dbo.load_log ORDER BY first_ts;

-- Overlap check on the field log (should return no rows)
SELECT a.point_id, a.start_ts, b.point_id AS overlaps_point, b.start_ts AS overlaps_start
FROM dbo.chamber_closure a
JOIN dbo.chamber_closure b
  ON a.closure_id < b.closure_id AND a.start_ts < b.end_ts AND b.start_ts < a.end_ts;

-- Row-level QC overview per file
SELECT source_file, COUNT(*) AS n_rows,
       SUM(flag_no_closure) AS n_not_field_data, SUM(flag_warmup) AS n_warmup,
       SUM(flag_gap) AS n_gaps, SUM(flag_range) AS n_out_of_range, SUM(flag_pressure) AS n_pressure
FROM dbo.aeris_qc
GROUP BY source_file;

-- Closure-level results
SELECT day, closure_qc, COUNT(*) AS n_closures
FROM dbo.closure_summary
GROUP BY day, closure_qc
ORDER BY day, closure_qc;

SELECT * FROM dbo.closure_summary ORDER BY start_ts;
