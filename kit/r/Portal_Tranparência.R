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

cat("\n[3/5] ICARO (Portal Transparência SNS)...\n")

icaro_url <- paste0(
  "https://transparencia.sns.gov.pt/api/explore/v2.1/catalog/datasets/",
  "evolucao-diaria-do-indice-icaro/records?order_by=periodo%20DESC&limit=100"
)

icaro_resp <- tryCatch(
  request(icaro_url) %>% req_retry(max_tries = 3) %>% req_perform(),
  error = function(e) {
    cat("  !! ERRO ICARO:", e$message, "\n"); return(NULL)
  }
)

if (!is.null(icaro_resp) && resp_status(icaro_resp) == 200) {
  icaro_data <- resp_body_json(icaro_resp, simplifyVector = TRUE)
  icaro_df <- as_tibble(icaro_data$results) %>%
    mutate(
      periodo = as.Date(periodo),
      ii      = as.numeric(ii)
    ) %>%
    arrange(periodo)

  # Guardar snapshot xlsx (inspeção manual)
  export(icaro_df, here("data", "icaro_diario.xlsx"))
  cat("  -> ICARO snapshot xlsx guardado. Último registo:", as.character(max(icaro_df$periodo)),
      " - valor:", tail(icaro_df$ii, 1), "\n")

  # Merge com histórico CSV (acumulação de dados)
  icaro_hist_file <- here("data", "icaro_historico.csv")
  if (file.exists(icaro_hist_file)) {
    icaro_hist <- read_csv(icaro_hist_file, show_col_types = FALSE,
      col_types = cols(periodo = col_date(format = ""), ii = col_double()))
  } else {
    icaro_hist <- tibble(periodo = as.Date(character()), ii = numeric())
    cat("  -> Histórico ICARO não existe. A criar de raiz...\n")
  }

  icaro_all <- bind_rows(icaro_hist, icaro_df) %>%
    group_by(periodo) %>%
    slice_tail(n = 1) %>%
    ungroup() %>%
    arrange(periodo)

  write_csv(icaro_all, icaro_hist_file)
  cat("  -> ICARO histórico atualizado:", nrow(icaro_all), "registos,",
      "última data:", as.character(max(icaro_all$periodo)), "\n")

  # Níveis ICARO (fonte: INSA):
  #   ii < 0.5  -> Verde (normal)
  #   0.5 <= ii < 1.0 -> Amarelo (atenção)
  #   1.0 <= ii < 2.0 -> Laranja (alerta)
  #   ii >= 2.0 -> Vermelho (emergência)
  icaro_ultima <- max(icaro_all$periodo, na.rm = TRUE)
  icaro_recent <- icaro_all %>% filter(periodo >= icaro_ultima - days(10))
  icaro_alerta <- icaro_recent %>%
    mutate(nivel = case_when(
      ii >= 2.0 ~ "Vermelho",
      ii >= 1.0 ~ "Laranja",
      ii >= 0.5 ~ "Amarelo",
      TRUE      ~ "Verde"
    ))
  cat("  -> Níveis ICARO últimos 10 dias (ref:", as.character(icaro_ultima), "):\n")
  print(icaro_alerta %>% select(periodo, ii, nivel), n = 20)
}

cat("\n[4/5] FRIESA (Portal Transparência SNS)...\n")

friesa_url <- paste0(
  "https://transparencia.sns.gov.pt/api/explore/v2.1/catalog/datasets/",
  "indice-friesa/records?order_by=data%20DESC&limit=100"
)

friesa_resp <- tryCatch(
  request(friesa_url) %>% req_retry(max_tries = 3) %>% req_perform(),
  error = function(e) {
    cat("  !! ERRO FRIESA:", e$message, "\n"); return(NULL)
  }
)

if (!is.null(friesa_resp) && resp_status(friesa_resp) == 200) {
  friesa_data <- resp_body_json(friesa_resp, simplifyVector = TRUE)
  friesa_df <- as_tibble(friesa_data$results) %>%
    mutate(data = as.Date(data)) %>%
    arrange(data)

  # Guardar snapshot xlsx (inspeção manual)
  export(friesa_df, here("data", "friesa_diario.xlsx"))
  cat("  -> FRIESA snapshot xlsx guardado. Último registo:", as.character(max(friesa_df$data)), "\n")

  # Merge com histórico CSV (acumulação de dados)
  friesa_hist_file <- here("data", "friesa_historico.csv")
  if (file.exists(friesa_hist_file)) {
    friesa_hist <- read_csv(friesa_hist_file, show_col_types = FALSE,
      col_types = cols(data = col_date(format = ""),
        lisboa = col_double(), lisboa65 = col_double(),
        porto = col_double(), porto65 = col_double()))
  } else {
    friesa_hist <- tibble(data = as.Date(character()),
      lisboa = numeric(), lisboa65 = numeric(),
      porto = numeric(), porto65 = numeric())
    cat("  -> Histórico FRIESA não existe. A criar de raiz...\n")
  }

  friesa_all <- bind_rows(friesa_hist, friesa_df) %>%
    group_by(data) %>%
    slice_tail(n = 1) %>%
    ungroup() %>%
    arrange(data)

  write_csv(friesa_all, friesa_hist_file)
  cat("  -> FRIESA histórico atualizado:", nrow(friesa_all), "registos,",
      "última data:", as.character(max(friesa_all$data)), "\n")

  # Níveis FRIESA (fonte: INSA):
  #   Para efeitos deste plano, usamos o valor mais alto entre Lisboa e Porto
  #   NOTA: FRIESA apenas cobre Lisboa e Porto (não Coimbra).
  #   FRIESA é sazonal: só há dados na época de frio (aprox. nov–mar)
  friesa_ultima <- max(friesa_all$data, na.rm = TRUE)
  friesa_recent <- friesa_all %>% filter(data >= friesa_ultima - days(10))
  friesa_recent <- friesa_recent %>%
    mutate(
      max_val = pmax(lisboa, lisboa65, porto, porto65, na.rm = TRUE),
      nivel = case_when(
        max_val >= 2.0 ~ "Vermelho",
        max_val >= 1.0 ~ "Laranja",
        max_val >= 0.5 ~ "Amarelo",
        TRUE ~ "Verde"
      )
    )
  cat("  -> Níveis FRIESA (máx Lisboa/Porto) últimos 10 dias (ref:",
      as.character(friesa_ultima), "):\n")
  print(friesa_recent %>% select(data, max_val, nivel), n = 20)
}
