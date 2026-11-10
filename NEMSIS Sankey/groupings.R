# =============================================================================
# groupings.R
# Turns raw values into the bands shown in the Sankeys, using the grouping
# lookups. Source 00_config.R before this file.
# =============================================================================

# Reads the four grouping lookups into one named list.
load_groupings <- function(lookup_dir) {
  list(
    impression_groups = read_csv(file.path(lookup_dir, "impression_groups.csv"),
                                 show_col_types = FALSE),
    time_ranges       = read_csv(file.path(lookup_dir, "time_ranges.csv"),
                                 show_col_types = FALSE),
    value_groups      = read_csv(file.path(lookup_dir, "value_groups.csv"),
                                 col_types = cols(.default = col_character())),
    transport_bands   = read_csv(file.path(lookup_dir, "transport_bands.csv"),
                                 show_col_types = FALSE)
  )
}

# TRUE for a blank or a NEMSIS Not Value.
is_missing_value <- function(x) {
  is.na(x) | x %in% names(not_value_codes)
}

# Impression group for each ICD-10 code. The longest matching prefix wins, a
# code matching no prefix is "Medical (other)", and a missing code is
# "Not recorded".
impression_group <- function(code, impression_groups) {
  prefix_rules <- impression_groups |> arrange(desc(str_length(prefix)))

  missing <- is_missing_value(code)
  code    <- str_to_upper(code)
  group   <- rep(NA_character_, length(code))

  for (i in seq_len(nrow(prefix_rules))) {
    hit <- !missing & is.na(group) & str_starts(code, fixed(prefix_rules$prefix[i]))
    group[hit] <- prefix_rules$group[i]
  }

  case_when(
    missing      ~ "Not recorded",
    is.na(group) ~ "Medical (other)",
    TRUE         ~ group
  )
}

# Band for each code of variable v: its group in value_groups.csv when one is
# set, otherwise its label in levels.csv, otherwise the code itself.
value_band <- function(code, v, value_groups, level_lookup) {
  groups <- value_groups |> filter(standard_name == v)
  labels <- level_lookup |> filter(standard_name == v)

  case_when(
    is_missing_value(code) ~ "Not recorded",
    code %in% groups$code  ~ groups$group[match(code, groups$code)],
    code %in% labels$code  ~ labels$label[match(code, labels$code)],
    TRUE                   ~ code
  )
}

# Time range for each transport time in minutes. Each range runs from its
# lower bound up to, but not including, the next one. Missing and negative
# times are "Not recorded".
time_band <- function(minutes, time_ranges) {
  band <- cut(minutes,
              breaks = c(time_ranges$lower_min, Inf),
              labels = time_ranges$label,
              right  = FALSE)
  if_else(is.na(band), "Not recorded", as.character(band))
}

# Band for each combination of transport type and capability. A combination
# with no row in transport_bands.csv is shown under its own name.
transport_band <- function(transport_type, capability, transport_bands) {
  key  <- paste(transport_type, capability)
  rule <- paste(transport_bands$transport_type, transport_bands$capability)
  band <- transport_bands$band[match(key, rule)]

  case_when(
    transport_type == "Not recorded" | capability == "Not recorded" ~ "Not recorded",
    is.na(band) ~ key,
    TRUE        ~ band
  )
}
