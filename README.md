# Workshop Observatório — Kit dos Participantes

Kit de apoio ao workshop de construção de um **observatório de saúde e ambiente**.
Reúne scripts de recolha de dados abertos em R, ligações geográficas (NUTS/freguesias/ULS),
e um relatório Power BI de diagnóstico.

O foco não é o "download" dos dados, mas a **limpeza, validação e integração** de séries
provenientes de fontes com formatos, sinalética de qualidade e nomenclaturas heterogéneas.

## Estrutura

```
.
├── Workshop_Observatório.pdf          # Apresentação do workshop
└── kit/
    ├── r/                             # Scripts de recolha (R)
    │   ├── OpenMeteo.R                # [1/6] Temperatura (Open-Meteo: histórico + previsão) 
    │   ├── EVM.r                      # [2/6] Mortalidade semanal por concelho (EVM, Min-Saúde)
    │   ├── Portal_Transparência.R     # [3/6] ICARO   [4/6] FRIESA (SNS)
    │   ├── QualAR.r                   # [5/6] Qualidade do ar (APA/QualAr)
    │   └── INE.r                      # [6/6] Exemplo de script de extração de dados do INE
    ├── dados/                         # Acesso à API do INE + dicionário geográfico
    │   ├── fetch_ine.R                # Indicador 0014469 (suicídio)
    │   ├── ine_0014469_suicidio.csv   # Exemplo já extraído/limpo
    │   ├── geo_linkage_2024_v7.csv    # Correspondência freguesia/município/NUTS 2013 ↔ 2024/ULS
    │   └── nuts_verificacao.csv       # Verificação de códigos NUTS 2013 vs 2024
    └── powerbi/                       # Relatório (Dashboard - Diagnóstico)
        ├── Diagnóstico_function.pbix / .pbip
        ├── Diagnóstico_function.Report/ + .SemanticModel/   # formato PBIP (TMDL/PBIR)
        ├── Diagnóstico_database.pbix # Ficheiro com dados extraído
        ├── Diagnóstico_noData.pbix   # Ficheiro com funções de extração das várias API
        └── codigo_extracao_ine_pbi.pq   # M: mesmo indicador em NUTS 2013 e NUTS 2024
```

## Fontes de dados

| Área | Fonte | Script / consulta | Granularidade |
|------|-------|-------------------|---------------|
| Temperatura | Open-Meteo | `kit/r/OpenMeteo.R` | Diária, Figueira / Montemor / Soure |
| Mortalidade | EVM (Min-Saúde) | `kit/r/EVM.r` | Semanal, por concelho |
| Índices de risco | Portal Transparência SNS (ICARO, FRIESA) | `kit/r/Portal_Transparência.R` | Diária |
| Qualidade do ar | QualAr (APA) | `kit/r/QualAR.r` | Diária, por estação/poluente |
| Indicadores socioeconómicos | API JSON INE | `kit/dados/fetch_ine.R`, `nuts_vintage.pq` | Anual, por NUTS |

```
# Dados do ICARO e FRIESA com delay
# IPMA também tem dados de histórico mas limitado a alguns locais
# Codigo do EVM é esperado que necessite de ser alterado
# Dados QualAR assumem o conhecimento do número das estações a avaliar
```

## Requisitos

- **R** (≥ 4.2) e **Power BI Desktop**.
- Pacotes R: `tidyverse`, `janitor`, `here`, `rio`, `lubridate`, `readxl`,
  `httr2`, `rvest`, `jsonlite`, `tsibble`.
- `fetch_ine.R` usa `pacman` como alternativa a loop (`p_load(jsonlite, tidyverse)`).

Os scripts instalam automaticamente os pacotes em falta e escrevem por omissão em `data/`
(relativo à raiz do projeto R).

## Como usar

1. Abra o projeto R no diretório que contém a pasta `data/` (os scripts usam `here()`);
2. Execute um script de recolha, por exemplo:
   ```r
   source("kit/r/OpenMeteo.R")
   source("kit/r/EVM.r")
   source("kit/r/Portal_Transparência.R")
   source("kit/r/QualAR.r")
   ```
3. Para o INE, na raiz de `kit/`;
4. Abra `kit/powerbi/Diagnóstico_function.pbip` (ou o `.pbix`) no Power BI Desktop.

## Notas de qualidade de dados

- **NUTS 2013 vs 2024**: o mesmo território pode ter código diferente (ex.: `16B1001` →
  `1D11001`). **Nunca** juntar séries por código nem por nome — use a correspondência oficial
  (`codigo_extracao_ine_pbi.pq`, `geo_linkage_2024_v7.csv`).
