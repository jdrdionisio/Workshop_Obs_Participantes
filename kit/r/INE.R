#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# fetch_ine.R -- indicador da Base de Dados do INE via API JSON
# Caso: 0014469 Taxa de mortalidade por lesões autoprovocadas intencionalmente
#       (suicídio) por 100 000 habitantes, por Local de residência (NUTS),
#       sexo e grupo etário. Anual - INE, Óbitos por causa de morte.
#
# Uso:   Rscript dados/fetch_ine.R
# Saída: dados/ine_0014469_suicidio.csv  + relatório de qualidade em stdout
#
# Lição central (workshop): a API entrega TEXTO com sinalética de qualidade e
# supressão, chaves heterogéneas entre registos e grupos etários que se
# sobrepõem. A limpeza e a validação são o trabalho, não o download.
# ---------------------------------------------------------------------------
if (!requireNamespace("pacman", quietly = TRUE)) {
  install.packages("pacman", repos = "https://cloud.r-project.org")
}
library(pacman)
p_load(jsonlite, tidyverse)

VARCD   <- "0014469"
# Código do indicador na base de dados do INE a
URL     <- paste0("https://www.ine.pt/ine/json_indicador/pindica.jsp?op=2&varcd=", VARCD,"&lang=PT")
# https://www.ine.pt/xportal/xmain?xpid=INE&xpgid=ine_api_v2&xlang=pt
# Local onde é possível ver a documentação da API do INE
DESTINO <- "dados/ine_0014469_suicidio.csv"
#Exemplo específico - Pasta de destino pode ser definido no momento após extração se forem feitos vários pedidos
#API tem limitações que podem ser consultadas na documentação
# Existe um pacote Alternativo que é o ineptr2
# https://cran.r-project.org/web/packages/ineptr2/index.html
# Aqui o objetivo será o de mostrar como funciona a API e como se estruturam os dados

dir.create("dados", showWarnings = FALSE)

# 0. Conversão de texto -> número ------------------------------------------
# A API devolve "8,4 §" (vírgula decimal + sinal de qualidade) ou "x"
# (dado não disponível). Cuidado com o pipe nativo:
#   x |> suppressWarnings(as.numeric())  =>  suppressWarnings(x, as.numeric())
# ou seja, NÃO converte nada e devolve a coluna em texto, sem erro visível.
# Por isso a conversão vive numa função explícita, testável.
converter_numero <- function(x) {
  limpo <- x |>
    str_remove_all("[§*[:space:]]") |>
    str_replace(",", ".")
  suppressWarnings(as.numeric(limpo))
}

# 1. Obtenção ---------------------------------------------------------------
#    simplifyVector = FALSE: cada registo fica como lista com nomes próprios,
#    porque as chaves VARIAM entre registos (uns têm "valor", outros não).
# Os dados em json podem ser utilizados mas limitação de trabalho local para quem vem do Excel
raw <- fromJSON(URL, simplifyVector = FALSE)[[1]]

tibble(
  indicador_cod  = raw$IndicadorCod,
  indicador      = raw$IndicadorDsg,
  atualizacao    = raw$DataUltimoAtualizacao,
  ultimo_periodo = raw$UltimoPref,
  n_registos     = length(raw$Dados[[1]])
) |> print()

# imprime o que foi extraído quando falha imprime o Erro

# 2. JSON -> tabela longa ---------------------------------------------------
# Dados vêm em  estrutura à parte, daí que tenham de ser trabalhados antes da porção final
# Apesar de aparecer ano o periodo entre dados pode não ser um ano
dados <- bind_rows(lapply(names(raw$Dados), function(ano) {
  bind_rows(lapply(raw$Dados[[ano]], function(r) {
    as_tibble(r) |> mutate(ano = as.character(ano))
  }))
})) |>
  # chaves ausentes tornam-se NA explícitos, não colunas desaparecidas
  mutate(across(c(sinal_conv, sinal_conv_desc, valor), ~ replace_na(.x, NA_character_)))

# 3. Limpeza ----------------------------------------------------------------
dados <- dados |>
  mutate(
    # "8,4 §"  -> valor 8.4 e sinal "§" ; "x" -> NA + suprimido
    valor_sinal = str_extract(ind_string, "[§*]+"),
    valor_num   = converter_numero(ind_string),
    suprimido   = is.na(valor_num) & !is.na(ind_string),
    nivel_geo   = case_when(
      str_detect(geocod, "^[A-Z]+$")       ~ "código especial",
      geocod %in% c("0", "00", "9", "99")  ~ "código especial",
      nchar(geocod) == 6                    ~ "Município",
      nchar(geocod) == 4                    ~ "NUTS III",
      nchar(geocod) <= 2                    ~ "NUTS II / agregado",
      TRUE                                  ~ "por classificar"
    )
  )

write_excel_csv(dados, DESTINO)

cat("\nFicheiro escrito:", DESTINO, "\n")