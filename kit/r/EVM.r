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
dir.create(here("data", "mortalidade"), showWarnings = FALSE, recursive = TRUE)

cat("\n[2/5] Mortalidade (EVM min-saude.pt)...\n")

page <- tryCatch(
  read_html("https://evm.min-saude.pt/table?t=concelho&s=0", encoding = "UTF-8"),
  error = function(e) {
    cat("  !! ERRO: Não foi possível aceder ao EVM:", e$message, "\n")
    return(NULL)
  }
)

if (!is.null(page)) {
  script_nodes <- page %>%
    html_elements('div.tab-pane > script[type="application/json"]')

  if (length(script_nodes) > 0) {
    all_years_data <- script_nodes %>%
      map(~ {
        table_json  <- .x %>% html_text() %>% fromJSON()
        col_headers <- table_json$x$container %>%
          read_html(encoding = "UTF-8") %>%
          html_elements("th") %>% html_text()
        data_list  <- table_json$x$data
        names_data <- data_list[1, ] %>% replace_na("Vazio")
        data_list  <- data_list[-1, ]
        wide_df    <- as.data.frame(data_list, check.names = FALSE)
        colnames(wide_df) <- names_data
        row_names  <- table_json$x$options$columnDefs$name[-c(1, 2)]
        wide_df    <- wide_df %>%
          mutate(Semana = row_names) %>% relocate(Semana)
        wide_df %>%
          pivot_longer(cols = -Semana, names_to = "Concelho",
                       values_to = "Obitos") %>%
          separate_wider_delim(Semana, delim = " ",
                               names = c(NA, "WeekYearStr"),
                               too_few = "align_start") %>%
          mutate(
            Week   = yearweek(gsub("(\\d{2})-(\\d{4})", "\\2 W\\1", WeekYearStr)),
            Date   = as.Date(Week, format = "%Y %U"),
            Obitos = as.integer(Obitos),
            Concelho = as.character(Concelho)
          )
      }) %>%
      list_rbind()

    export(all_years_data, here("data", "mortalidade", "all_years_data.xlsx"))
    cat("  -> Mortalidade nacional guardada.\n")

    uls_bm <- all_years_data %>%
      filter(Concelho %in% c("Figueira da Foz","Montemor-o-Velho","Soure"))
    export(uls_bm, here("data", "mortalidade", "all_years_data_uls_bm.xlsx"))
    cat("  -> Mortalidade ULSBM filtrada. Última data:",
        as.character(max(uls_bm$Date, na.rm = TRUE)), "\n")
  } else {
    cat("  !! AVISO: Nenhum script JSON encontrado no EVM.\n")
  }
}
