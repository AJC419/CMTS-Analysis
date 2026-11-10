# =============================================================================
# 02_convert_to_parquet.R
# Converts each table named in lookups/variables.csv to Parquet, keeping only
# the record ID and the lookup's columns. The raw file is read in chunks so the
# full table is never held in memory. Columns are renamed to their standard
# names here, so later scripts never see year-specific names.
# =============================================================================

# ---- CONFIG -----------------------------------------------------------------
source("NEMSIS/00_config.R")

library(haven)
library(arrow)

variables <- load_variables()

# ---- Cleaning applied to every value ------------------------------------------
# Everything except the record ID is stored as trimmed text, with blanks as NA.
# Numbers are written without scientific notation so codes stay intact.

to_text <- function(x) {
  if (is.numeric(x)) {
    text <- format(x, scientific = FALSE, trim = TRUE, drop0trailing = TRUE)
    text[is.na(x)] <- NA
    x <- text
  }
  na_if(str_trim(as.character(x)), "")
}

# ---- Convert one table ---------------------------------------------------------

convert_table <- function(source_table) {
  table_vars <- variables |> filter(source_table == !!source_table)
  path       <- find_table_file(source_table)
  out_dir    <- parquet_path(source_table)

  # Match the lookup's column names to the file's, ignoring upper/lower case.
  file_columns <- read_column_names(path)
  wanted       <- c(key_column, table_vars$source_column)
  cols         <- file_columns[match(str_to_lower(wanted), str_to_lower(file_columns))]
  new_names    <- c(key_column, table_vars$standard_name)

  if (anyNA(cols)) {
    stop("Columns not found in ", basename(path), ": ",
         paste(wanted[is.na(cols)], collapse = ", "),
         ". Run 01_inventory.R and fix lookups/variables.csv.")
  }

  # Start from an empty output folder so parts from an earlier run cannot mix in.
  unlink(out_dir, recursive = TRUE)
  dir.create(out_dir, recursive = TRUE)

  write_chunk <- function(chunk, part) {
    chunk |>
      select(all_of(cols)) |>
      set_names(new_names) |>
      mutate(across(-all_of(key_column), to_text)) |>
      mutate(across(all_of(key_column), as.numeric), year = run_year) |>
      write_parquet(file.path(out_dir, sprintf("part-%04d.parquet", part)))
    message("  ", source_table, ": part ", part, " written")
  }

  if (str_to_lower(tools::file_ext(path)) == "sas7bdat") {

    # SAS file: read chunk_rows rows at a time, skipping the rows already done.
    skip <- 0
    part <- 1
    repeat {
      chunk <- read_sas(path, col_select = all_of(cols), skip = skip, n_max = chunk_rows)
      if (nrow(chunk) == 0) break
      write_chunk(chunk, part)
      if (nrow(chunk) < chunk_rows) break
      skip <- skip + chunk_rows
      part <- part + 1
    }

  } else {

    # Text file: readr streams the file and hands over one chunk at a time.
    # Only the needed columns are read, all as text.
    column_types <- do.call(
      cols_only,
      set_names(rep(list(col_character()), length(cols)), cols)
    )
    read_delim_chunked(
      path,
      delim      = csv_delim,
      chunk_size = chunk_rows,
      col_types  = column_types,
      callback   = SideEffectChunkCallback$new(
        function(chunk, pos) write_chunk(chunk, ceiling(pos / chunk_rows))
      )
    )
  }

  tibble(source_table = source_table,
         rows_written = nrow(open_dataset(out_dir)))
}

# ---- Run for every table in the lookup -----------------------------------------

conversion_log <- unique(variables$source_table) |>
  map(convert_table) |>
  bind_rows()

write_csv(conversion_log,
          file.path(report_dir, paste0("conversion_log_", run_year, ".csv")))

print(conversion_log)
message("Parquet files are in ", parquet_dir, ". Continue to 03_variable_check.R.")
