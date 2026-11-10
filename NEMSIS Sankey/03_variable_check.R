# =============================================================================
# 03_variable_check.R
# Data-quality check run before any composite table is built.
#   - Filter variables (role = filter) are applied in the order they appear in
#     lookups/variables.csv. Each one is checked on the records that the
#     filters before it kept, because a record with a missing filter value is
#     silently dropped by that filter.
#   - Every other variable is checked on the records left after all filters.
# Each variable is split into: valid, blank, each Not Value, no record in its
# table, and valid codes that are missing from lookups/levels.csv.
# =============================================================================

# ---- CONFIG -----------------------------------------------------------------
source("NEMSIS/00_config.R")

library(arrow)

variables    <- load_variables()
level_lookup <- load_levels()

unmapped_label   <- "Valid code missing from levels.csv"
missing_statuses <- c("Blank", unname(not_value_codes), "No record in table")

# ---- Open the table that holds the filter variables ----------------------------

filter_vars  <- variables |> filter(role == "filter")
other_vars   <- variables |> filter(role != "filter")
filter_table <- unique(filter_vars$source_table)

if (length(filter_table) != 1) {
  stop("All role = filter variables must come from one table in lookups/variables.csv.")
}

events <- open_dataset(parquet_path(filter_table))
n_all  <- nrow(events)

# ---- Count the values of one variable -------------------------------------------
# data is the set of rows to count, denominator is the number of records those
# rows should cover, and population is the label written to the report.

check_variable <- function(v, data, denominator, population) {
  var_row     <- variables |> filter(standard_name == v)
  known_codes <- level_lookup |> filter(standard_name == v) |> pull(code)

  counts <- data |>
    select(value = all_of(v)) |>
    count(value) |>
    collect() |>
    mutate(
      status = case_when(
        is.na(value)                                      ~ "Blank",
        value %in% names(not_value_codes)                 ~ unname(not_value_codes[value]),
        length(known_codes) > 0 & !value %in% known_codes ~ unmapped_label,
        TRUE                                              ~ "Valid"
      )
    )

  # Records with no row at all in this variable's table.
  no_record <- denominator - sum(counts$n)

  if (no_record > 0) {
    counts <- counts |>
      add_row(value = NA_character_, n = no_record, status = "No record in table")
  }
  if (no_record < 0) {
    warning("'", v, "': ", var_row$source_table, " has more than one row per ",
            key_column, ", so its percentages are per row, not per record.")
  }

  counts |>
    mutate(
      year          = run_year,
      standard_name = v,
      source_column = var_row$source_column,
      population    = population
    )
}

# ---- Check and apply the filters, one at a time ------------------------------------
# A record is kept when the filter variable holds a code marked keep = TRUE in
# lookups/levels.csv.

kept           <- events
n_kept         <- n_all
population     <- "All records"
filter_results <- list()

message("Records in ", filter_table, ": ", n_all)

for (v in filter_vars$standard_name) {
  filter_results[[v]] <- check_variable(v, kept, n_kept, population)

  keep_codes <- level_lookup |> filter(standard_name == v, keep) |> pull(code)
  if (length(keep_codes) == 0) {
    stop("No code is marked keep = TRUE for '", v, "' in lookups/levels.csv.")
  }

  kept   <- kept |> filter(.data[[v]] %in% keep_codes)
  n_kept <- kept |> count() |> collect() |> pull(n)

  if (n_kept == 0) {
    stop("The '", v, "' filter kept no records. Check its keep = TRUE codes in ",
         "lookups/levels.csv against the ", run_year, " data manual.")
  }

  message("Kept after the ", v, " filter: ", n_kept)
  population <- paste0("After ", v, " filter")
}

# ---- Check every other variable on the filtered records -------------------------------

# Rows of a variable's table that belong to the filtered records.
filtered_rows <- function(v) {
  source_table <- variables$source_table[variables$standard_name == v]
  if (source_table == filter_table) {
    kept
  } else {
    open_dataset(parquet_path(source_table)) |>
      semi_join(select(kept, all_of(key_column)), by = key_column)
  }
}

other_results <- map(
  other_vars$standard_name,
  \(v) check_variable(v, filtered_rows(v), n_kept, "After all filters")
)

value_counts <- bind_rows(c(unname(filter_results), other_results))

# ---- Summarise --------------------------------------------------------------------

# Counts and percents by status, one block per variable.
status_counts <- value_counts |>
  group_by(year, standard_name, source_column, population, status) |>
  summarise(n = sum(n), .groups = "drop_last") |>
  mutate(pct = signif(100 * n / sum(n), 3)) |>
  ungroup()

# One line per variable with a verdict.
check_summary <- value_counts |>
  group_by(year, standard_name, source_column, population) |>
  summarise(
    records      = sum(n),
    pct_missing  = signif(100 * sum(n[status %in% missing_statuses]) / sum(n), 3),
    pct_unmapped = signif(100 * sum(n[status == unmapped_label]) / sum(n), 3),
    .groups = "drop"
  ) |>
  mutate(
    result = case_when(
      pct_missing > missing_threshold_pct ~ "FAIL: too much missing",
      pct_unmapped > 0                    ~ "FIX LOOKUP: add codes to levels.csv",
      TRUE                                ~ "PASS"
    )
  )

# Codes present in the data but absent from lookups/levels.csv.
unmapped_codes <- value_counts |>
  filter(status == unmapped_label) |>
  select(year, standard_name, source_column, code = value, n) |>
  arrange(standard_name, desc(n))

# ---- Save and print -----------------------------------------------------------------

write_csv(status_counts,
          file.path(report_dir, paste0("variable_check_detail_", run_year, ".csv")))
write_csv(check_summary,
          file.path(report_dir, paste0("variable_check_summary_", run_year, ".csv")))
write_csv(unmapped_codes,
          file.path(report_dir, paste0("unmapped_codes_", run_year, ".csv")))

print(status_counts, n = Inf)
print(check_summary, n = Inf)
print(unmapped_codes, n = Inf)

# ---- Compare with the years already checked -------------------------------------------

reports_root <- dirname(report_dir)

all_years <- list.files(reports_root, pattern = "^variable_check_summary_\\d{4}\\.csv$",
                        recursive = TRUE, full.names = TRUE) |>
  map(\(f) read_csv(f, show_col_types = FALSE)) |>
  bind_rows() |>
  arrange(standard_name, year)

write_csv(all_years, file.path(reports_root, "variable_check_all_years.csv"))

print(select(all_years, standard_name, year, records, pct_missing, result), n = Inf)

# ---- Verdict ------------------------------------------------------------------------------

if (all(check_summary$result == "PASS")) {
  message(run_year, " passed the variable check.")
} else {
  message(run_year, " did NOT pass. See the result column above before building anything.")
}
