-- 05_field_log_20240529.sql
-- Field log 29 May 2024, transcribed from the handwritten sheet.
-- Times were recorded from the instrument display, i.e. in the INSTRUMENT clock (no offset).
USE FieldData;

DELETE FROM dbo.field_day WHERE day = '2024-05-29';
INSERT INTO dbo.field_day (day, instrument_offset_h, log_clock, note)
VALUES ('2024-05-29', 7, N'instrument', N'Offset assumed equal to 12 June (same instrument clock setting).');

DELETE FROM dbo.chamber_closure WHERE start_ts >= '2024-05-29' AND start_ts < '2024-05-30';

INSERT INTO dbo.chamber_closure (source_file, point_id, start_ts, duration_min, note)
SELECT N'Ultra100704_240529_013840Eng.txt', v.point_id,
       CAST('2024-05-29T' + v.t AS datetime2(3)), v.m,
       N'Log recorded in instrument clock'
FROM (VALUES
    (25,'01:54:00',3), (26,'01:58:30',2), ( 1,'02:05:15',2), ( 2,'02:09:00',2),
    (29,'02:15:00',2), (30,'02:18:45',2), ( 7,'02:24:45',2), ( 8,'02:27:45',2),
    (31,'02:33:00',2), (32,'02:36:45',2), (35,'02:41:15',2), (36,'02:45:00',2),
    (11,'02:52:30',2), (12,'02:56:15',2), (37,'03:01:30',2), (38,'03:04:30',2),
    (33,'03:09:45',2), (34,'03:13:30',2), ( 9,'03:18:45',2), (10,'03:22:30',2),
    ( 5,'03:27:00',2), ( 6,'03:30:45',2), ( 3,'03:35:15',2), ( 4,'03:38:15',2),
    (27,'03:42:45',2), (28,'03:46:30',2), (47,'03:54:45',2), (48,'03:58:30',2),
    (23,'04:03:45',2), (24,'04:11:15',3)
) AS v(point_id, t, m);
