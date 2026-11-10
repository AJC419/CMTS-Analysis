# =============================================================================
# 00_config.R
# Settings for one yearly run. Every numbered script starts by sourcing this
# file, so a routine new year only needs edits here and in lookups/.
# =============================================================================

library(tidyverse)

# ---- CONFIG: edit these -----------------------------------------------------

run_year  <- 2022          # NEMSIS year being processed
data_root <- "NEMSIS/data" #Data root

chunk_rows            <- 5e6       # rows read at a time; lower it if R runs short of memory
csv_delim             <- ","       # delimiter, used only for .csv / .txt files
key_column            <- "PcrKey"  # record ID shared by every NEMSIS table
missing_threshold_pct <- 25.5       # a variable above this percent missing fails the check
note_threshold_pct    <- 10   # a variable above this percent missing is named in the Sankey note
delete_unneeded_files <- FALSE     # TRUE = 01_inventory.R deletes raw data files the lookup does not use

# NEMSIS "Not Values": something was entered, but it carries no information.
not_value_codes <- c(
  "7701001" = "Not Applicable",
  "7701003" = "Not Recorded",
  "7701005" = "Not Reporting"
)

# ---- Paths built from the settings above (no edits needed) -------------------

raw_dir <- file.path(data_root, paste("SAS", run_year))      # the unzipped download
parquet_dir <- file.path(data_root, "parquet", run_year)  # written by 02_convert_to_parquet.R
report_dir  <- file.path("reports", run_year)             # small CSV reports, kept in the repo

dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

# ---- Shared helpers (no edits needed) ----------------------------------------

# This year's rows of the variable lookup.
load_variables <- function() {
  variables <- read_csv("NEMSIS/lookups/variables.csv", show_col_types = FALSE) |>
    filter(year == run_year)
  if (nrow(variables) == 0) {
    stop("NEMSIS/lookups/variables.csv has no rows for ", run_year,
         ". Copy the previous year's rows and change the year.")
  }
  variables
}

# The code-to-label lookup. Codes are read as text so they match the data.
load_levels <- function() {
  read_csv(
    "NEMSIS/lookups/levels.csv",
    col_types = cols(
      standard_name = col_character(),
      code          = col_character(),
      label         = col_character(),
      keep          = col_logical()
    )
  )
}

# Every data file in this year's raw folder.
list_raw_files <- function() {
  tibble(path = list.files(raw_dir, full.names = TRUE, recursive = TRUE)) |>
    mutate(
      file    = basename(path),
      table   = str_to_lower(tools::file_path_sans_ext(file)),
      ext     = str_to_lower(tools::file_ext(file)),
      size_gb = signif(file.size(path) / 1024^3, 3)
    ) |>
    filter(ext %in% c("sas7bdat", "csv", "txt"))
}

# The one raw file that holds a table named in the lookup. An exact file name
# is preferred; otherwise a file that starts with the table name is used
# (for example pub_pcrevents_2022.csv for pub_pcrevents).
find_table_file <- function(source_table) {
  wanted <- str_to_lower(source_table)
  files  <- list_raw_files()
  hits   <- files |> filter(table == wanted)
  if (nrow(hits) == 0) {
    hits <- files |> filter(str_starts(table, fixed(wanted)))
  }
  if (nrow(hits) != 1) {
    stop("Expected exactly one file for table '", source_table, "' in ", raw_dir,
         " but found ", nrow(hits), ": ", paste(hits$file, collapse = ", "))
  }
  hits$path
}

# Column names of a raw file, read from its first row only.
read_column_names <- function(path) {
  if (str_to_lower(tools::file_ext(path)) == "sas7bdat") {
    names(haven::read_sas(path, n_max = 1))
  } else {
    names(read_delim(path, delim = csv_delim, n_max = 1,
                     col_types = cols(.default = col_character())))
  }
}

# Folder holding the Parquet version of a table.
parquet_path <- function(source_table) {
  file.path(parquet_dir, str_to_lower(source_table))
}
