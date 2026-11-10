# =============================================================================
# filters.R
# Shared by the data review and the composite-table step. Applies the filters
# defined in the lookups, so every step works on the same set of records.
# Source 00_config.R before this file.
# =============================================================================

# The filtered records of the filter table, as an Arrow query. Nothing is
# loaded into memory until the query is counted or collected.
filtered_events <- function(variables, level_lookup) {
  filter_vars  <- variables |> filter(role == "filter")
  filter_table <- unique(filter_vars$source_table)

  if (length(filter_table) != 1) {
    stop("All role = filter variables must come from one table in the variable lookup.")
  }

  kept <- arrow::open_dataset(parquet_path(filter_table))

  # A record is kept when each filter variable holds a code marked keep = TRUE.
  for (v in filter_vars$standard_name) {
    keep_codes <- level_lookup |> filter(standard_name == v, keep) |> pull(code)
    if (length(keep_codes) == 0) {
      stop("No code is marked keep = TRUE for '", v, "' in the level lookup.")
    }
    kept <- kept |> filter(.data[[v]] %in% keep_codes)
  }

  kept
}

# The rows of the table holding variable v that belong to the filtered records.
filtered_rows <- function(v, kept, variables) {
  source_table <- variables$source_table[variables$standard_name == v]
  filter_table <- unique(variables$source_table[variables$role == "filter"])

  if (source_table == filter_table) {
    kept
  } else {
    arrow::open_dataset(parquet_path(source_table)) |>
      semi_join(select(kept, all_of(key_column)), by = key_column)
  }
}
