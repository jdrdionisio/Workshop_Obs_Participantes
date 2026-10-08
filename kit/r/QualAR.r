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

qualar_por_poluente <- list()   # dados para charts por poluente
qualar_all <- NULL
hoje <- Sys.Date()
ontem <- hoje - 1

fetch_qualar_v2 <- function(date_str, station_id = 1021) {
  url <- paste0("https://qualar.apambiente.pt/api/app.php?type=dados&data=",
                date_str, "&estacao_id=", station_id, "&range=d")
  tryCatch({
    resp <- request(url) %>%
      req_retry(max_tries = 2) %>%
      req_perform()
    if (resp_status(resp) != 200) return(NULL)

    raw_json <- resp_body_json(resp, simplifyVector = FALSE)
    if (is.null(raw_json$vals) || length(raw_json$vals) == 0) return(NULL)

    # --- FIX: cats são DIAS DO MÊS, x no vals é o próprio valor do dia ---
    cats <- as.integer(raw_json$cats)  # day numbers e.g., 2,3,...,16 or 30,31,1,2
    if (length(cats) == 0) return(NULL)

    query_date <- as.Date(date_str)
    query_month <- month(query_date)
    query_year  <- year(query_date)
    prev_date   <- query_date %m-% months(1)
    prev_month  <- month(prev_date)
    prev_year   <- year(prev_date)

    # Determine which cats belong to previous vs current month.
    # cats é uma série cíclica de dias do mês que termina na data consultada
    # (ex.: range=d em 2026-10-01 -> 17,18,...,30,1). Só pode ocorrer uma
    # "quebra": os dias reiniciam em 1 quando começa o mês corrente. Tudo o que
    # antecede essa quebra pertence ao mês anterior.
    n <- length(cats)
    belongs_prev <- logical(n)
    wrap <- which(cats[-1] < cats[-n])   # posições i onde cats[i] < cats[i-1]
    if (length(wrap) > 0) {
      first_current <- wrap[1] + 1
      belongs_prev[seq_len(first_current - 1)] <- TRUE
    }

    # Build date mapping: day_number → actual Date
    vals_list <- raw_json$vals
    records <- list()

    # Known pollutant codes from QualAr (lookup table: code → name)
    pol_lookup <- c(
      "0" = "PM10", "1" = "PM2.5", "4" = "O3", "5" = "NO2",
      "6" = "SO2", "7" = "CO", "8" = "C6H6", "9" = "NO", "10" = "NOx"
    )

    for (v in vals_list) {
      p_code <- as.integer(v$p)
      day_val <- as.integer(v$x)   # this IS the day number directly
      valor   <- as.numeric(v$v)
      indice  <- as.integer(v$i)

      # Find this day's position in cats to determine which month
      day_pos <- which(cats == day_val)
      if (length(day_pos) == 0) next

      if (belongs_prev[day_pos[1]]) {
        actual_date <- tryCatch(
          as.Date(sprintf("%d-%02d-%02d", prev_year, prev_month, day_val)),
          error = function(e) NA
        )
      } else {
        actual_date <- tryCatch(
          as.Date(sprintf("%d-%02d-%02d", query_year, query_month, day_val)),
          error = function(e) NA
        )
      }
      if (is.na(actual_date)) next

      pol_name <- pol_lookup[as.character(p_code)]
      if (is.na(pol_name)) pol_name <- paste0("P", p_code)
      idx_label <- c("Muito Bom", "Bom", "Médio", "Fraco", "Mau")[indice]
      if (is.na(idx_label)) idx_label <- as.character(indice)

      records[[length(records) + 1]] <- tibble(
        data     = actual_date,
        poluente = pol_name,
        valor    = valor,
        indice   = idx_label,
        codigo_indice = indice
      )
    }

    if (length(records) == 0) return(NULL)
    bind_rows(records)
  }, error = function(e) {
    message("  !! Erro QualAr ", date_str, ": ", e$message)
    return(NULL)
  })
}

# Fetch last 7 days (avoid zoo-masked seq.Date; iterate by index to keep Date class)
dates_to_fetch <- hoje - 6:0
for (i in seq_along(dates_to_fetch)) {
  d <- dates_to_fetch[i]
  d_str <- format(d, "%Y-%m-%d")
  Sys.sleep(0.3)
  result <- fetch_qualar_v2(d_str)
  if (!is.null(result) && nrow(result) > 0) {
    qualar_all <- bind_rows(qualar_all, result)
  }
}

# Save QualAr daily data
if (!is.null(qualar_all) && nrow(qualar_all) > 0) {
  dir.create(here("data"), showWarnings = FALSE, recursive = TRUE)
  write_csv(qualar_all, here("data", "qualar_diario.csv"))
  cat("  -> QualAr guardado:", nrow(qualar_all), "registos\n")
} else {
  cat("  ! QualAr: sem dados\n")
}