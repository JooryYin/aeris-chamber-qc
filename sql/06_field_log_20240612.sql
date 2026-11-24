-- 06_field_log_20240612.sql
-- Field log 12 June 2024, transcribed from the handwritten sheet.
-- Three raw files (instrument restarted twice): 01:26:03-02:00:18, 02:03:14-03:01:02, 03:06:38-04:39:19.
-- Times were recorded from the instrument display, i.e. in the INSTRUMENT clock (no offset needed).
-- The sheet header "8:26 a.m." (local time) matches the first file's start at 01:26 instrument time,
-- confirming the instrument clock runs 7 h behind Danish summer time (CEST).
-- Closure lengths were not logged per point; one entry (P36) gives 02:15:45-02:17:15 = 90 s.
-- A 90 s analysis window is used, automatically shortened when the next closure starts earlier.
USE FieldData;

-- Day-level metadata (created here if it does not exist yet)
IF OBJECT_ID('dbo.field_day') IS NULL
CREATE TABLE dbo.field_day (
    day                 date          PRIMARY KEY,
    instrument_offset_h int           NOT NULL,   -- local time (CEST) = instrument clock + offset
    log_clock           nvarchar(20)  NOT NULL,   -- clock used in the handwritten log
    weather             nvarchar(200) NULL,
    crop_stage          nvarchar(200) NULL,
    note                nvarchar(400) NULL
);

DELETE FROM dbo.field_day WHERE day = '2024-06-12';
INSERT INTO dbo.field_day (day, instrument_offset_h, log_clock, weather, crop_stage, note)
VALUES ('2024-06-12', 7, N'instrument', N'windy', N'stem elongation',
        N'Start 8:26 a.m. local = 01:26 instrument. Two instrument restarts.');

DECLARE @window_s int = 90;

DELETE FROM dbo.chamber_closure WHERE start_ts >= '2024-06-12' AND start_ts < '2024-06-13';

WITH v AS (
    SELECT * FROM (VALUES
        -- Strip 1 (file 1, then file 2 after restart)
        (26,'01:28:30',NULL), (25,'01:30:00',NULL), ( 2,'01:33:45',NULL), ( 1,'01:35:55',NULL),
        (30,'01:39:30',NULL), (29,'01:40:45',NULL), ( 8,'01:44:15',NULL),
        ( 7,'01:52:30',N'after 8-min break; instrument restarted after this closure'),
        (32,'02:08:15',NULL), (31,'02:10:30',NULL),
        (36,'02:15:45',N'log gives end time 02:17:15'), (35,'02:18:15',NULL),
        -- Strip 2
        (12,'02:25:30',N'arrow in log'), (11,'02:28:00',N'arrow in log'),
        (38,'02:33:00',NULL), (37,'02:36:15',NULL), (34,'02:40:30',N'seconds corrected in log'),
        (33,'02:43:30',NULL), (10,'02:47:15',NULL), ( 9,'02:51:00',NULL), ( 6,'02:54:45',NULL),
        ( 5,'02:57:30',N'instrument restarted after this closure'),
        ( 4,'03:09:30',NULL), ( 3,'03:11:15',N'seconds unclear in log'),
        (28,'03:15:45',N'seconds corrected in log'), (27,'03:17:30',NULL),
        -- Strip 3
        (48,'03:24:00',NULL), (47,'03:26:40',NULL), (24,'03:29:30',NULL), (23,'03:31:30',NULL),
        (46,'03:36:00',NULL), (45,'03:37:30',N'log note: starts to get warm'),
        (20,'03:43:40',N'seconds unclear in log'), (19,'03:45:45',NULL), (42,'03:50:15',NULL),
        (41,'03:52:00',NULL), (18,'03:55:30',NULL), (17,'03:58:30',NULL), (14,'04:02:15',NULL),
        (13,'04:04:30',NULL),
        -- Strip 4
        (16,'04:12:45',NULL), (15,'04:15:45',N'seconds corrected in log'), (40,'04:20:15',NULL),
        (39,'04:23:00',NULL), (44,'04:27:30',NULL), (43,'04:31:20',N'minute corrected in log'),
        (22,'04:34:15',NULL), (21,'04:37:00',NULL)
    ) AS x(point_id, t, note)
), s AS (
    SELECT point_id, note, CAST('2024-06-12T' + t AS datetime2(3)) AS start_ts FROM v
), w AS (
    SELECT *, LEAD(start_ts) OVER (ORDER BY start_ts) AS next_ts FROM s
)
INSERT INTO dbo.chamber_closure (source_file, point_id, start_ts, duration_min, note)
SELECT NULL, point_id, start_ts,     -- 3 files this day: closures are matched to data by time
       ROUND(CASE WHEN next_ts IS NULL OR DATEDIFF(SECOND, start_ts, next_ts) > @window_s
                  THEN @window_s ELSE DATEDIFF(SECOND, start_ts, next_ts) END / 60.0, 1, 1),
       CONCAT(N'Log recorded in instrument clock', N'; ' + note)
FROM w;

SELECT COUNT(*) AS n_closures_20240612 FROM dbo.chamber_closure
WHERE start_ts >= '2024-06-12' AND start_ts < '2024-06-13';
