# =============================================================================
# 01_inventory.R
# Lists what the year's download contains and checks that every variable in
# lookups/variables.csv is where the lookup says it is. This is the step that
# catches a renamed or moved variable in a new year.
#
# Only the files named in the lookup are opened. The other files are opened
# only if a lookup column is missing, to find where it went.
# =============================================================================

# ---- CONFIG -----------------------------------------------------------------
source("NEMSIS/00_config.R")

# ---- Load the lookup and list the raw files ----------------------------------
# Listing reads file names and sizes only; no file is opened here.

variables <- load_variables()
files     <- list_raw_files()

if (nrow(files) == 0) {
  stop("No .sas7bdat, .csv or .txt files found in ", raw_dir)
}

# A file is needed when a table in the lookup matches its name.
lookup_tables <- str_to_lower(unique(variables$source_table))

files <- files |>
  mutate(needed = map_lgl(table, \(t) any(str_starts(t, fixed(lookup_tables)))))

# ---- Read column names from the needed files only ------------------------------

columns <- files |>
  filter(needed) |>
  mutate(column = map(path, read_column_names)) |>
  select(table, file, column) |>
  unnest(column)

# ---- Check the lookup against those files --------------------------------------

# TRUE when the named table has the named column (upper/lower case ignored).
has_column <- function(source_table, source_column) {
  any(str_starts(columns$table, fixed(str_to_lower(source_table))) &
        str_to_lower(columns$column) == str_to_lower(source_column))
}

lookup_check <- variables |>
  mutate(
    file_found   = map_lgl(source_table,
                           \(t) any(str_starts(files$table, fixed(str_to_lower(t))))),
    column_found = map2_lgl(source_table, source_column, has_column),
    key_found    = map_lgl(source_table, \(t) has_column(t, key_column)),
    found_in     = ""
  )

# ---- Only if a column is missing: search the other files for it ------------------
# A file that cannot be opened is skipped and named, not treated as an error.

missing_columns <- lookup_check |> filter(!column_found)

if (nrow(missing_columns) > 0) {
  message("Not found where the lookup says: ",
          paste(missing_columns$source_column, collapse = ", "),
          ". Searching the other files.")
  
  safe_column_names <- possibly(read_column_names, otherwise = NA_character_)
  
  other_columns <- files |>
    filter(!needed) |>
    mutate(column = map(path, safe_column_names)) |>
    select(table, file, column) |>
    unnest(column)
  
  unreadable <- other_columns |> filter(is.na(column)) |> pull(file)
  if (length(unreadable) > 0) {
    message("Skipped, could not be opened: ", paste(unreadable, collapse = ", "))
  }
  
  searched <- bind_rows(columns, other_columns)
  
  # Every table that holds a column with the missing name.
  tables_with <- function(source_column) {
    searched |>
      filter(str_to_lower(column) == str_to_lower(source_column)) |>
      pull(table) |>
      unique() |>
      paste(collapse = "; ")
  }
  
  lookup_check <- lookup_check |>
    mutate(found_in = if_else(column_found, "", map_chr(source_column, tables_with)))
}

# ---- Save and print ----------------------------------------------------------

write_csv(select(files, file, table, ext, size_gb, needed),
          file.path(report_dir, paste0("inventory_files_", run_year, ".csv")))
write_csv(columns,
          file.path(report_dir, paste0("inventory_columns_", run_year, ".csv")))
write_csv(lookup_check,
          file.path(report_dir, paste0("lookup_check_", run_year, ".csv")))

print(select(files, file, size_gb, needed), n = Inf)
print(select(lookup_check, standard_name, source_table, source_column,
             file_found, column_found, key_found, found_in), n = Inf)

lookup_ok <- all(lookup_check$file_found & lookup_check$column_found & lookup_check$key_found)

if (lookup_ok) {
  message("Lookup matches the ", run_year, " files. Continue to 02_convert_to_parquet.R.")
} else {
  message("Lookup does NOT match the ", run_year, " files. Fix NEMSIS/lookups/variables.csv ",
          "using the found_in column and the data manual, then rerun this script.")
}

# ---- Optional: delete raw data files the lookup does not use -------------------
# Runs only when delete_unneeded_files is TRUE in 00_config.R and the lookup
# check passed. Deletion is permanent; the original download is the backup.

if (delete_unneeded_files && lookup_ok) {
  unneeded <- files |> filter(!needed)
  file.remove(unneeded$path)
  message("Deleted ", nrow(unneeded), " unneeded files (",
          signif(sum(unneeded$size_gb), 3), " GB).")
}