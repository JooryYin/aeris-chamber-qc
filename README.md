# aeris-chamber-qc

A small, reproducible SQL Server pipeline for **static-chamber N₂O/CO₂ field measurements** made with an
Aeris Ultra N₂O/CO₂/H₂O analyser (1 Hz logging). It takes the raw instrument files and a handwritten field
log and produces quality-controlled, analysis-ready data, with every step documented and repeatable.

The goal is data management rather than flux science: keep the raw data unchanged, make every
transformation explicit, store field metadata next to instrument data, and flag problems instead of
silently deleting them.

## Pipeline

```
raw .txt files ──► raw_aeris (text) ──► aeris_clean (typed) ──► aeris_qc (row flags) ──► closure_summary
                                                                    ▲
handwritten field log ──► chamber_closure (structured metadata) ────┘
```

| Script | What it does |
|---|---|
| `sql/00_create_database.sql` | Creates the `FieldData` database |
| `sql/01_create_tables.sql` | Staging table (all text), clean typed table, field-log and field-day tables |
| `sql/02_load_procedure.sql` | `load_aeris_file`: detects the export format, loads one raw file, appends it and logs the load; refuses duplicate files and overlapping data |
| `sql/03_qc_view.sql` | `aeris_qc`: one flag per QC rule for every reading |
| `sql/04_closure_summary_view.sql` | `closure_summary`: one row per chamber closure with slopes, R² and a QC verdict |
| `sql/05_field_log_20240529.sql` | Field log for 29 May 2024 |
| `sql/06_field_log_20240612.sql` | Field log for 12 June 2024 (three files, two instrument restarts) |
| `sql/07_run_pipeline.sql` | Example run: load files and inspect results |

## How to run

1. SQL Server (tested on SQL Server 2025, version 17) and SQL Server Management Studio.
2. Copy the raw Aeris files to a local folder readable by the SQL Server service, e.g. `C:\data\aeris`.
3. Run the scripts in order, `00` to `07`.

To add a new measurement day: copy the raw file(s) to the folder, add a field-log script for that day
(closures and a `field_day` row),
and call `EXEC dbo.load_aeris_file` once per file. If the instrument was restarted, there are several
files for one day. Each file is loaded separately, and closures are matched to data by time.

## Quality-control rules

Row level (`aeris_qc`). Flags never delete data.

| Flag | Rule | Why |
|---|---|---|
| `flag_no_closure` | Reading not inside any logged closure | The instrument logs whenever it is on, not only while measuring |
| `flag_missing` | CO₂, N₂O or H₂O is NULL | Incomplete reading |
| `flag_warmup` | First 120 s of each file | Unstable readings after switch-on or restart |
| `flag_gap` | More than 5 s since the previous reading | Logging interruption |
| `flag_range` | N₂O outside 0.25–50 ppm or CO₂ outside 300–10 000 ppm | Physically implausible values |
| `flag_pressure` | Cell pressure more than 2 mbar from 140 mbar | Concentrations are unreliable at the wrong cell pressure |
| `flag_co2_baseline` | Mean CO₂ of the whole file outside 380–600 ppm | Catches a file-wide CO₂ offset that a per-value range check cannot see |

Closure level (`closure_summary`):

| Verdict | Rule |
|---|---|
| `INVALID: instrument` | Any pressure or range flag inside the closure window |
| `CHECK: incomplete data` | Less than 90 % of the expected seconds (e.g. a restart during the closure) |
| `CHECK: CO2 offset (N2O only)` | The closure lies in a file with an implausible CO₂ level; N₂O may still be usable, CO₂ is not |
| `CHECK: poor CO2 fit` | CO₂ R² < 0.90. Soil always respires, so a sealed chamber should show a linear CO₂ rise; a poor fit suggests a leak, a disturbance or a wrong start time |
| `ok` | Passed all checks |

N₂O R² is reported but not used as a criterion, because a near-zero N₂O flux legitimately has a low R².

## Data dictionary

**`aeris_clean`**: one row per instrument reading

| Column | Type | Unit | Description |
|---|---|---|---|
| `measurement_id` | int | | Surrogate key |
| `source_file` | text | | Raw file the row came from (provenance) |
| `ts` | datetime2(3) | | Timestamp in the **instrument clock** |
| `inlet` | tinyint | | Inlet number |
| `p_mbar` | float | mbar | Cell pressure (nominal 140) |
| `tgas_degC` | float | °C | Gas temperature |
| `co2_ppm`, `n2o_ppm` | float | ppm | Dry mole fractions |
| `h2o_ppm` | float | ppm | Water vapour |
| `co2_ppm_wet`, `n2o_ppm_wet` | float | ppm | Wet mole fractions |

**`chamber_closure`**: the field log, one row per closure

| Column | Type | Unit | Description |
|---|---|---|---|
| `closure_id` | int | | Surrogate key |
| `source_file` | text | | Raw file (optional; matching is by time) |
| `point_id` | int | | Measurement point (chamber position) |
| `start_ts` | datetime2(3) | | Closure start in the **instrument clock** |
| `duration_min` | decimal | min | Analysis window length |
| `end_ts` | computed | | `start_ts + duration_min` |
| `note` | text | | Remarks from the log, time-zone conversion applied |

**`field_day`**: one row per measurement day

| Column | Type | Description |
|---|---|---|
| `day` | date | Measurement day |
| `instrument_offset_h` | int | Local time (CEST) = instrument clock + offset |
| `log_clock` | text | Clock used in the handwritten log (`instrument` or `local`) |
| `weather`, `crop_stage`, `note` | text | Field conditions and remarks |

**`load_log`**: one row per loaded file. Records file name, detected format, row count, bad timestamps,
time range, and who loaded it and when.

**`closure_summary`**: one row per closure. Includes `n_sec`, `n_pressure`, `n_range`,
`n2o_slope_ppm_min`, `n2o_r2`, `co2_slope_ppm_min`, `co2_r2` and `closure_qc`. Slopes are linear
regressions of concentration on time (ppm min⁻¹). They are not yet fluxes: converting them needs
chamber volume, area, temperature and pressure.

## Lessons learned (issues found while building this)

1. **Regional settings silently corrupted numbers.** Importing with the SSMS wizard on a Danish-locale
   PC treated "." as a thousands separator: 28.5511 °C became 285511, and values with different numbers
   of decimals ended up on different scales. *Fix:* import everything as text, then convert explicitly
   with `TRY_CONVERT`, which is locale-independent.
2. **Instruments log whenever they are on, not only while you measure.** On 29 May the file covers about 4 h,
   but the closures cover about 2 h; the rest is warm-up, packing up and idle logging. Values outside
   closures can look perfectly plausible. *Fix:* store the field log as data and flag readings outside closures.
3. **QC caught a real invalid measurement.** On 29 May, cell pressure dropped from 140 to about 71 mbar
   from 04:02 to 04:10, exactly during the closure of point 23. All 120 seconds were flagged and the closure
   was marked invalid. Without the check, a wrong slope would have entered the results unnoticed.
4. **Time zones.** The instrument clock runs 7 h behind Danish summer time (US Central, UTC−5).
   The field log can be written in either clock, depending on whether times are read from the instrument
   display or from a watch. On 12 June the sheet header says "8:26 a.m." (local), and the first file starts
   at 01:26 instrument time, which confirms the 7 h offset from the data rather than by assumption.
   *Fix:* store all timestamps in the instrument clock, and record the offset and the log clock per day
   in `field_day`.
5. **Field procedure shows up in the data.** On 29 May, the two closures with poor CO₂ fits were each the
   first closure after a longer break in the field schedule. That points to a field-procedure cause
   (for example, the start time written before the chamber was fully sealed), not random noise.
6. **The same fault on different days.** On 12 June, cell pressure dropped to about 71 mbar from
   01:46:08 to 01:47:17, between two closures (P8 and P7), followed by an 8-minute break in the log.
   It is the same ~71 mbar signature as on 29 May. A fault that repeats across days points to a recurring
   cause, e.g. the inlet tube being pinched or blocked while the chamber is moved.
7. **Two export formats, and duplicates with different names.** The instrument software can export a
   full (53-column) or a short (19-column) file of the same recording. The loader detects the format from
   the header. Because the two versions have different file names but identical data, checking file names
   is not enough: the loader also refuses any file whose time range overlaps data that is already loaded.
8. **Plausible values can still be wrong.** After the second restart on 12 June, CO₂ read about 1130–1200 ppm
   for the rest of the day, roughly 750 ppm above the ~410 ppm just before the restart, while N₂O stayed at
   normal ambient levels (about 0.34 ppm). Every single value was inside the 300–10 000 ppm range, so the
   range check passed it. A file-level baseline check now flags it, and the affected closures are marked
   "N2O only". QC rules are not written once: each new failure mode becomes a new rule.

## Data availability

Raw instrument files are not included in this repository. The transcribed field logs (closure start times and notes) are in sql/05_field_log_20240529.sql and sql/06_field_log_20240612.sql.

## Author

Jingru Yin (Joory), Department of Agroecology, Aarhus University
