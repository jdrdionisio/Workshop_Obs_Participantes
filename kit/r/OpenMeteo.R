required_packages <- c(
  "tidyverse", "janitor", "here", "rio", "lubridate",
  "readxl", "httr2", "rvest", "jsonlite", "tsibble"
)

for (pkg in required_packages) {
  if (!pkg %in% rownames(installed.packages())) {
    install.packages(pkg, repos = "https://cran.us.r-project.org")
  }
  library(pkg, character.only = TRUE)
}

DATA_DIR <- here("data")
dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)

cat("[1/5] Temperatura (Open-Meteo)...\n")

locations <- tribble(
  ~location_name, ~latitude,  ~longitude,
  "Figueira",     40.151,     -8.863,
  "Montemor",     40.174,     -8.684,
  "Soure",        40.061,     -8.628
)

daily_vars <- c(
  "temperature_2m_max", "temperature_2m_min", "temperature_2m_mean",
  "apparent_temperature_max", "apparent_temperature_min", "apparent_temperature_mean"
)

fetch_single_temperature <- function(base_url, location_row,
                                     start_date_str = NULL, end_date_str = NULL,
                                     is_forecast, extra_params = list()) {
  query_params <- list(
    latitude  = location_row$latitude,
    longitude = location_row$longitude,
    daily     = paste(daily_vars, collapse = ","),
    timezone  = "auto"
  )
  if (!is.null(start_date_str)) query_params$start_date <- start_date_str
  if (!is.null(end_date_str))   query_params$end_date   <- end_date_str
  final_query <- c(query_params, extra_params)

  req <- request(base_url) %>%
    req_url_query(!!!final_query) %>%
    req_retry(max_tries = 3)
  resp <- tryCatch(
    req_perform(req),
    error = function(e) e
  )

  if (inherits(resp, "error")) {
    stop(
      sprintf(
        "Open-Meteo request failed for %s: %s",
        location_row$location_name,
        resp$message
      ),
      call. = FALSE
    )
  }

  if (resp_status(resp) != 200L) {
    body_text <- tryCatch(resp_body_string(resp), error = function(e) "")
    stop(
      sprintf(
        "Open-Meteo API failed for %s (HTTP %s): %s",
        location_row$location_name,
        resp_status(resp),
        if (nzchar(body_text)) substr(body_text, 1, 200) else "empty response"
      ),
      call. = FALSE
    )
  }

  body_text <- resp_body_string(resp)

  response_data <- tryCatch(
    jsonlite::fromJSON(body_text, simplifyVector = TRUE, flatten = TRUE),
    error = function(e) {
      stop(
        sprintf(
          "Open-Meteo returned invalid JSON for %s: %s",
          location_row$location_name,
          e$message
        ),
        call. = FALSE
      )
    }
  )

  if (isTRUE(response_data$error)) {
    stop(
      sprintf(
        "API Error for %s: %s",
        location_row$location_name,
        response_data$reason
      ),
      call. = FALSE
    )
  }

  if (is.null(response_data$daily)) {
    stop(
      sprintf("Open-Meteo response has no 'daily' data for %s.", location_row$location_name),
      call. = FALSE
    )
  }

  as_tibble(response_data$daily) %>%
    select(date = time, all_of(daily_vars)) %>%
    mutate(
      date          = as.Date(date),
      location_name = location_row$location_name,
      is_forecast   = is_forecast
    ) %>%
    select(location_name, date, everything())
}

temp_file <- here("data", "ipma", "ipma_weather.csv")
dir.create(dirname(temp_file), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(temp_file)) {
  cat("  -> Ficheiro não existe. A criar de raiz...\n")
  historical <- locations %>%
    group_split(location_name) %>%
    map_dfr(~fetch_single_temperature(
      "https://archive-api.open-meteo.com/v1/archive",
      .x, "2013-01-01", format(Sys.Date(), "%Y-%m-%d"), FALSE
    ))
  forecast <- locations %>%
    group_split(location_name) %>%
    map_dfr(~fetch_single_temperature(
      "https://api.open-meteo.com/v1/forecast",
      .x, is_forecast = TRUE,
      extra_params = list(forecast_days = 14)
    ))
  final_data <- bind_rows(historical, forecast) %>%
    distinct(location_name, date, .keep_all = TRUE) %>%
    arrange(location_name, date)
  write_csv(final_data, temp_file)
  cat("  -> Criado:", temp_file, "\n")
} else {
  cat("  -> Ficheiro existe. A atualizar...\n")
  existing <- read_csv(temp_file,
    col_types = cols(date = col_date(format = "")))
  last_hist <- existing %>%
    filter(is_forecast == FALSE) %>%
    summarise(last_date = max(date)) %>% pull(last_date)

  new_historical <- NULL
  if (last_hist < Sys.Date()) {
    new_historical <- locations %>%
      group_split(location_name) %>%
      map_dfr(~fetch_single_temperature(
        "https://archive-api.open-meteo.com/v1/archive",
        .x, format(last_hist + 1, "%Y-%m-%d"),
        format(Sys.Date(), "%Y-%m-%d"), FALSE
      ))
  }
  new_forecast <- locations %>%
    group_split(location_name) %>%
    map_dfr(~fetch_single_temperature(
      "https://api.open-meteo.com/v1/forecast",
      .x, is_forecast = TRUE,
      extra_params = list(forecast_days = 14)
    ))
  final_data <- existing %>%
    filter(is_forecast == FALSE) %>%
    bind_rows(new_historical, new_forecast) %>%
    distinct(location_name, date, .keep_all = TRUE) %>%
    arrange(location_name, date)
  write_csv(final_data, temp_file)
  cat("  -> Atualizado. Última data histórica:", as.character(last_hist), "\n")
}