# NEMSIS yearly pipeline

This private repo holds the code that turns one year of the NEMSIS public release into small composite tables for the research website. Raw NEMSIS data never enters either repo: it is processed on a local computer, and only vetted composite tables are copied to the public website repo.

## Status

| Step | Where it lives | State |
|----|----|----|
| 1\. Inventory the year's files and check the lookup | `01_inventory.R` | Written |
| 2\. Convert the needed columns to Parquet | `02_convert_to_parquet.R` | Written |
| 3\. Variable check (missingness, Not Values, unmapped codes) | `03_variable_check.R` | Written |
| 4\. Data review (groupings for the Sankey stages) | `04_data_review.Rmd` | Written |
| 5\. Build composite tables | `05_composite_tables.Rmd` | Written |
| 6\. Vet composite tables with test Sankeys | `06_sankeys.Rmd` | Written |
| 7\. Copy vetted tables to the public repo | Done by hand | See "Handing the year to the website" |

## Layout

These files sit in the `NEMSIS/` folder of the shared project, alongside the HCUP work. Every path in the scripts starts with `NEMSIS/`, so R's working directory must be the top project folder, the one that contains `NEMSIS/`.

Inside `NEMSIS/`:

| Path | Purpose |
|----|----|
| `00_config.R` | Year, data location, and thresholds. Sourced by every step. |
| `01_inventory.R` | Step 1. Lists the year's files and reports whether every lookup variable was found. |
| `02_convert_to_parquet.R` | Step 2. Writes the needed columns of each table to Parquet, reading `chunk_rows` rows at a time. |
| `03_variable_check.R` | Step 3. Applies the filters in order and reports missingness and unmapped codes for every variable. |
| `04_data_review.Rmd` | A standalone review of the three grouping decisions: impression groups, transport-time ranges, and transport type and capability. It builds nothing; it shows the effect of each draft grouping so the lookups can be adjusted. |
| `05_composite_tables.Rmd` | Step 5. Builds the year's composite path table in three passes and writes it to the composite folder. |
| `06_sankeys.Rmd` | Step 6. Draws the year's Sankey from the composite table alone, so the table can be vetted before it leaves the repo. |
| `filters.R` | Applies the lookup's filters. Shared by the data review and the composite-table step so both use the same records. |
| `groupings.R` | Turns raw values into the bands shown in the Sankeys, using the four grouping lookups. |
| `sankey_builder.R` | Draws the interactive Sankey. Shared with the website repo. |
| `lookups/impression_groups.csv` | ICD-10 prefixes and the impression group each maps to. Anything unmatched is "Medical (other)". |
| `lookups/time_ranges.csv` | The lower bound and label of each transport-time range. |
| `lookups/value_groups.csv` | How levels of care and transport methods are collapsed into Sankey bands. |
| `lookups/transport_bands.csv` | The band shown for each combination of transport type and capability. |
| `lookups/variables.csv` | Where each variable lives in each year's files. |
| `lookups/levels.csv` | What each code means, and which codes the filters keep. |
| `reports/<year>/` | The year's HTML reports and small CSV summaries. No record-level data; safe to commit. |

Under `data_root` (set in `00_config.R`):

| Path | Purpose |
|----|----|
| `SAS <year>/` | The year's folder of SAS files, exactly as it arrives (for example `SAS 2020`). |
| `parquet/<year>/<table>/` | Written by step 2. One folder per table. |
| `parquet/<year>/working/` | Written and deleted again by step 5. Holds one row per record, so it never leaves the data folder. |

Beside `reports/`:

| Path | Purpose |
|----|----|
| `composite/<year>/sankey_paths_<year>.csv` | The year's composite path table, written by step 5. One row per path, no record-level data, no count below the small-cell minimum. This is the only file copied to the website repo. |

Record-level data must never be committed. Keep `data_root` outside the repo, or, if it sits inside, make sure its folder is listed in `.gitignore` before the first commit.

## One-time setup

1.  Install R packages: `install.packages(c("tidyverse", "haven", "arrow", "rmarkdown", "knitr", "networkD3", "htmlwidgets"))`.
2.  Open the top project folder (the one containing `NEMSIS/`) as an RStudio project so the working directory is that folder.
3.  Set `data_root` in `00_config.R`.

## Adding a new year

1.  Put the year's folder of SAS files in `data_root`, named `SAS <year>` (for example `SAS 2020`).
2.  In `00_config.R`, set `run_year`.
3.  In `lookups/variables.csv`, copy the previous year's rows and change `year` to the new year.
4.  Restart R and run `01_inventory.R`. If it reports that a lookup variable was not found, the lookup does not match the year's files. See "When something changed" below, fix the lookup, and run it again.
5.  Run `02_convert_to_parquet.R`. This is the slow step, and it rereads the raw files every time it is run, so it is run once per year unless a `source_column` has been corrected.
6.  Run `03_variable_check.R` and read the `result` column it prints.
7.  Do not build anything from the year until every variable shows `PASS`, or a `FAIL` has been looked at and a decision recorded.
8.  Knit `04_data_review.Rmd` and read the report. The groupings are meant to stay fixed across years so the Sankeys remain comparable; for a new year the review is a check that they still fit, for example that no common impression code has appeared in "Medical (other)" that belongs in another group.
9.  Knit `05_composite_tables.Rmd`. It writes `composite/<year>/sankey_paths_<year>.csv` and the missingness summary for the year.
10. Knit `06_sankeys.Rmd` and look at the diagram. It reads the composite table only, so what it draws is what the website will draw.

Each `.Rmd` moves its own working directory to the project folder when it is knitted, so all three can be knitted from RStudio without changing anything first. While working on a step, the numbered scripts can also be run line by line.

## Handing the year to the website

Once the Sankey in step 6 looks right, copy `composite/<year>/sankey_paths_<year>.csv` into the `data/` folder of the website repo. Nothing else moves between the two repos. The site reads whatever path tables it finds there, so a new year appears once its table is in place.

## When something changed

All year-to-year changes are handled in the two lookup files. The scripts are not edited.

**A variable was renamed or moved to another table.** The inventory reports `column_found = FALSE`, and its `found_in` column lists the tables that do contain that column name. Confirm against the year's data manual, then correct `source_table` or `source_column` in that year's row of `variables.csv`. The `standard_name` stays the same, so everything downstream is unaffected.

**A variable was replaced by a different element.** Example: NEMSIS v3.5 replaces eDisposition.12 with eDisposition.27 to .30. Point that year's `transport_disposition` row at the new column, then add the new element's codes to `levels.csv` under the same `standard_name`, marking the ones the filter should keep.

**A new code appeared.** The variable check reports `FIX LOOKUP` and lists the codes in `reports/<year>/unmapped_codes_<year>.csv`. Look each one up in the data manual and add a row to `levels.csv`. Codes are not tied to a year: a NEMSIS code keeps its meaning across versions, so each code is entered once.

**A new variable is needed.** Add one row per year to `variables.csv`, add its codes to `levels.csv`, and rerun steps 4 to 10 above.

## The grouping lookups

These four files hold the choices reviewed in `04_data_review.Rmd`. Changing a grouping is an edit to a file, followed by knitting the review again.

`impression_groups.csv`: one row per ICD-10 prefix, with the group it maps to. When several prefixes match a code, the longest wins, so a specific rule (for example `G45`) overrides a general one. A code matching no prefix is "Medical (other)".

`time_ranges.csv`: one row per range, in increasing order, with its lower bound in minutes and its label. Each range runs up to the next row's lower bound. Missing and negative times are "Not recorded".

`value_groups.csv`: one row per code, with the band it is shown as. A code with no row keeps its own label.

`transport_bands.csv`: one row per combination of transport type (Ground, Rotor) and capability (BLS, ALS, Critical care), with the band it is shown as in the Sankey. Giving several combinations the same band collapses them.

## The variable and level lookups

`variables.csv`, one row per variable per year:

| Column | Meaning |
|----|----|
| `standard_name` | The name used everywhere after conversion. Never changes. |
| `year` | The NEMSIS year the row applies to. |
| `source_table` | The file that holds the variable, without extension or year suffix. |
| `source_column` | The column name in that file. Upper/lower case is ignored. |
| `role` | `filter` for variables that decide which records are kept; anything else for variables that are analyzed. Filters are applied in the order their rows appear, and all filter variables must come from one table. |

`levels.csv`, one row per code:

| Column | Meaning |
|----|----|
| `standard_name` | Matches `variables.csv`. |
| `code` | The NEMSIS code as it appears in the data. |
| `label` | The plain-language meaning. |
| `keep` | For `filter` variables only: `TRUE` keeps records with this code. |

Variables with an open set of values, such as `primary_impression` (ICD-10) and `transport_time_min` (a number), have no rows in `levels.csv` and are not checked for unmapped codes. A text variable with a short list of expected values, such as `urbanicity`, is entered with the value itself as the code, so anything unexpected is reported.

## Reading the variable check

Filters are checked and applied one at a time, in lookup order. Each filter variable is checked on the records the earlier filters kept, because a record with a missing filter value is silently dropped by that filter. Checking in sequence also avoids false alarms: transport method is legitimately Not Applicable on a call with no transport, so it is only checked on transported records. Every other variable is checked on the records left after all filters. The `population` column of each report says which set of records a line refers to.

Each value falls into one status:

| Status | Meaning |
|----|----|
| Valid | A real value. |
| Blank | Nothing entered. |
| Not Applicable / Not Recorded / Not Reporting | A NEMSIS Not Value (7701001 / 7701003 / 7701005). Counted as missing. |
| No record in table | The record has no row in the table that holds this variable. Counted as missing. |
| Valid code missing from levels.csv | A real value the lookup does not know yet. Not missing data; fix the lookup. |

A variable fails when its missing percent exceeds `missing_threshold_pct` in `00_config.R`. `reports/variable_check_all_years.csv` stacks every year checked so far for comparison.

## Settings

Set in `00_config.R`:

| Setting | Current value | Meaning |
|----|----|----|
| `run_year` | 2022 | The NEMSIS year being processed. |
| `data_root` | `NEMSIS/data` | Where the raw folders and Parquet files live. |
| `chunk_rows` | 5,000,000 | Rows read at a time during conversion. Lower it if R runs short of memory. |
| `key_column` | `PcrKey` | The record ID shared by every NEMSIS table. |
| `missing_threshold_pct` | 25.5 | A variable above this percent missing fails the check. |
| `note_threshold_pct` | 10 | A variable above this percent missing is named in the note beneath the Sankey. |
| `delete_unneeded_files` | `FALSE` | `TRUE` lets step 1 delete raw files the lookup does not use. |

Set at the top of the step that uses them:

| Setting | Where | Current value | Meaning |
|----|----|----|----|
| `small_cell_min` | `05_composite_tables.Rmd` | 10 | Paths with fewer records than this are left out of the composite table, so no count below it is ever published. |
| `min_link_pct` | `06_sankeys.Rmd` | 0.01 | A path running through a flow smaller than this percent of the records shown is not drawn. Free to change; 0 turns it off. |
| `min_flow_n` | `06_sankeys.Rmd` | 10 | A floor that applies whatever `min_link_pct` is set to: no flow of fewer records than this is ever drawn. |
| `sankey_height` | `06_sankeys.Rmd` | `82vh` | Share of the window height the diagram fills. |

## The reports folder

Every step writes its results to `reports/`. None of these files holds record-level data.

| File | Written by | Scope |
|----|----|----|
| `inventory_files_<year>.csv` | Inventory (01) | The year's files and which are needed |
| `inventory_columns_<year>.csv` | Inventory (01) | Column names of the needed files |
| `lookup_check_<year>.csv` | Inventory (01) | Whether each lookup variable was found |
| `conversion_log_<year>.csv` | Conversion (02) | Rows written per table |
| `variable_check_summary_<year>.csv` | Variable check (03) | One line per variable: percent missing, verdict |
| `variable_check_detail_<year>.csv` | Variable check (03) | Counts by status for each variable |
| `unmapped_codes_<year>.csv` | Variable check (03) | Codes missing from the lookup |
| `review_..._<year>.csv` (five files) | Data review (04) | The tables behind each grouping decision |
| `sankey_missingness_<year>.csv` | Composite tables (05) | Percent missing per Sankey stage, for the note beneath the diagram |
| `variable_check_all_years.csv` | Variable check (03) | Every year's summary, stacked |

Notes on the chart:

-   Files named for a year sit in `reports/<year>/` and are overwritten whenever that year's step is run again.
-   `variable_check_all_years.csv` sits directly in `reports/` because it spans years. It is rebuilt from scratch each time the variable check runs, by reading every `variable_check_summary_<year>.csv` it finds. Running a new year adds that year, and rerunning a year updates its rows. It changes only when the variable check runs.
-   `conversion_log_<year>.csv` is written only when a conversion finishes, so its presence marks a complete conversion.
-   The five review files are `review_impression_codes`, `review_transport_times`, `review_type_capability`, `review_urbanicity`, and `review_acuity`.

## Decisions on record

| Date | Decision | Basis |
|----|----|----|
| 2026-10-05 | The missingness threshold is 25% (`missing_threshold_pct`). | Set after the first real run (2020); the earlier 20% was a placeholder. |
| 2026-10-05 | `initial_acuity` is kept as the severity stage. Records with no usable acuity are shown as their own "Not recorded" flow, not dropped. | 21.8% missing in 2020 among the filtered records. Dropping them would assume the missing records resemble the rest. |
| 2026-10-05 | Acuity is the only stage where missing values are drawn in the Sankey. For every other stage, records with a missing value are left out of the diagram, and a note beneath it names each variable whose missingness is over 10%, with its percent. | Keeps the diagram readable while still reporting the gaps large enough to matter. |
| 2026-10-05 | Impression groups: chest pain (R07) is Cardiac; overdoses and poisonings (T36-T65) are Medical (other); substance use (F10-F19) is Psych. | Clinical judgment of the project lead. |
| 2026-10-05 | Transport-time ranges are cut at 15, 30, 45, and 60 minutes: under 15, 15 to under 30, 30 to under 45, 45 to under 60, and 60 or more. Each range includes its lower bound and excludes its upper bound. | Even 15-minute steps up to one hour. Held in `time_ranges.csv`. |
| 2026-10-05 | Rotor transports are shown as two bands: BLS and ALS combined, and critical care. Ground transports are shown as BLS, ALS, and critical care. | Held in `transport_bands.csv`. |
| 2026-10-05 | Individual crew levels (for example BLS-Basic/EMT or ALS-Paramedic) are not reported; only the collapsed capability is used. | The individual levels are not needed for the Sankeys. Their breakdown was removed from the data review. |
| 2026-10-05 | Destinations are shown as six bands: Hospital ED, Hospital non-ED, Freestanding ED, Handoff to air, Handoff to ground, and Other. Other combines home, nursing home or assisted living, clinic, urgent care, morgue, police or jail, and other. | Held in `value_groups.csv`. |
| 2026-11-09 | Destination is not a stage of the published Sankey. The bands above remain in `value_groups.csv` but are not drawn. | NEMSIS disposition data is not reliable enough to publish. |
| 2026-11-09 | The composite table carries no count below 10 (`small_cell_min`), and no flow of fewer than 10 records is ever drawn (`min_flow_n`). | Small-cell suppression applied at the point the data leaves the private repo, and again at the point it is drawn. |

## Current scope

The filters keep, in order: 911 scene responses (`service_type`), where the patient was treated and transported by the reporting unit (`transport_disposition`), by ground ambulance or rotor craft (`transport_method`).

One Sankey is built per year. Its five variables are held together in one composite table, so that any of them can be switched on or off, and any of them can be made the first column, when the diagram is viewed:

| Stage | Variable | Source |
|----|----|----|
| Urbanicity | `urbanicity` | computedelements, Urbanicity |
| Condition | `primary_impression` | eSituation.11 |
| Severity | `initial_acuity` | eSituation.13 |
| Care level | `transport_method`, `unit_level_of_care` | eDisposition.16, eResponse.15 |
| Transport time | `transport_time_min` | computedelements, EMSTransportTimeMin |

All values are stored as text in the Parquet files, including `transport_time_min`, which is converted to a number when the composite tables are built.

## Packages

| Package | Used by |
|----|----|
| tidyverse | Every step |
| haven | Reading SAS files (01, 02) |
| arrow | Parquet datasets (02, 03, 05, `filters.R`) |
| knitr, rmarkdown | Knitting 04, 05, 06 |
| networkD3, htmlwidgets | Drawing the Sankey (06, `sankey_builder.R`) |
