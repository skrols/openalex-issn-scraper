# =============================================================================
# OPENALEX SCRAPER — por ISSN
# Campos: ISSN, Nome do Periódico, Editora, Ano de Publicação, DOI, Título,
#         Nº Autores, Citações por Ano, Indexadores, Open Access, Afiliação,
#         APC, Países, Referências, Works Relacionados
# Separador múltiplo: pipe "|"
# =============================================================================

library(httr2)
library(tidyverse)
library(jsonlite)
library(progress)

# -----------------------------------------------------------------------------
# CONFIGURAÇÃO
# -----------------------------------------------------------------------------

EMAIL        <- "Adicione o seu email"    # <-- substitua (polite pool OpenAlex)
ISSN_LIST    <- c("Liste aqui o ou os ISSNs que deseja capturar os metadados") # <-- substitua pela sua lista de ISSNs
CHECKPOINT   <- "checkpoint_openalex.rds"   # arquivo de progresso
OUTPUT_FILE  <- "openalex_resultado.csv"
PER_PAGE     <- 200    # máximo permitido pelo OpenAlex
SLEEP_OK     <- 0.1    # pausa entre requests bem-sucedidos (segundos)
SLEEP_RETRY  <- 5      # pausa após erro (segundos)
MAX_RETRIES  <- 3      # tentativas por request

BASE_URL     <- "https://api.openalex.org/works"

# Campos solicitados ao OpenAlex em uma constante para evitar repetição
FIELDS <- paste0(
  "id,doi,title,publication_year,authorships,",
  "cited_by_count,counts_by_year,referenced_works_count,",
  "related_works,locations,primary_location,open_access"
)

# -----------------------------------------------------------------------------
# FUNÇÕES AUXILIARES
# -----------------------------------------------------------------------------

pipe_collapse <- function(x) {
  x <- x[!is.na(x) & x != ""]
  if (length(x) == 0) return(NA_character_)
  paste(unique(x), collapse = " | ")
}

safe_request <- function(url, email, retries = MAX_RETRIES) {
  for (i in seq_len(retries)) {
    res <- tryCatch(
      request(url) |>
        req_headers(`User-Agent` = paste0("mailto:", email)) |>
        req_timeout(30) |>
        req_perform(),
      error = function(e) NULL
    )
    if (!is.null(res) && resp_status(res) == 200) return(res)
    if (!is.null(res) && resp_status(res) == 429) {
      message(sprintf("  [429] Rate limit — aguardando %ds...", SLEEP_RETRY * 3))
      Sys.sleep(SLEEP_RETRY * 3)
    } else {
      Sys.sleep(SLEEP_RETRY)
    }
  }
  return(NULL)
}

# -----------------------------------------------------------------------------
# PARSER DE UM TRABALHO (work) DO OPENALEX
# -----------------------------------------------------------------------------

parse_work <- function(w, issn_origem = NA_character_) {
  
  # DOI
  doi <- w$doi %||% NA_character_
  doi <- gsub("https://doi.org/", "", doi)
  
  # Título
  titulo <- w$title %||% NA_character_
  
  # Ano de publicação
  ano_publicacao <- w$publication_year %||% NA_integer_
  
  # Periódico e editora — primary_location > source
  # Extraído aqui uma única vez e reutilizado no bloco APC abaixo
  primary_src    <- w$primary_location$source %||% list()
  nome_periodico <- primary_src$display_name %||% NA_character_
  editora        <- primary_src$host_organization_name %||% NA_character_
  
  # Autores, afiliações e países
  authorships <- w$authorships %||% list()
  autores     <- map_chr(authorships, ~ .x$author$display_name %||% NA_character_)
  n_autores   <- length(autores)
  
  afiliacao <- map(authorships, function(a) {
    insts <- a$institutions %||% list()
    map_chr(insts, ~ .x$display_name %||% NA_character_)
  }) |> unlist()
  
  paises <- map(authorships, function(a) {
    insts <- a$institutions %||% list()
    map_chr(insts, ~ .x$country_code %||% NA_character_)
  }) |> unlist()
  
  # Citações totais e por ano
  total_citacoes <- w$cited_by_count %||% NA_integer_
  
  cit_por_ano <- w$counts_by_year %||% list()
  cit_str <- if (length(cit_por_ano) > 0) {
    map_chr(cit_por_ano, ~ paste0(.x$year, ":", .x$cited_by_count)) |>
      paste(collapse = " | ")
  } else NA_character_
  
  # Referências e works relacionados
  total_referencias <- w$referenced_works_count %||% NA_integer_
  related_str       <- pipe_collapse(unlist(w$related_works %||% character(0)))
  
  # Indexadores
  locs        <- w$locations %||% list()
  indexadores <- map_chr(locs, function(l) {
    src <- l$source
    if (is.null(src)) return(NA_character_)
    src$display_name %||% NA_character_
  })
  
  # Open Access
  oa        <- w$open_access %||% list()
  is_oa     <- oa$is_oa %||% FALSE
  oa_status <- oa$oa_status %||% NA_character_
  oa_url    <- oa$oa_url %||% NA_character_
  
  # APC — reutiliza primary_src já extraído acima
  #apc_usd    <- primary_src$apc_usd %||% NA_real_
  #apc_found  <- primary_src$has_apc %||% NA
  #apc_prices <- primary_src$apc_prices %||% list()
  #apc_moeda  <- if (length(apc_prices) > 0) {
  #  map_chr(apc_prices, ~ paste0(.x$currency, ":", .x$price)) |>
  #    paste(collapse = " | ")
  #} else NA_character_
  
  tibble(
    issn_origem        = issn_origem,
    nome_periodico     = nome_periodico,
    editora            = editora,
    ano_publicacao     = ano_publicacao,
    DOI                = doi,
    titulo             = titulo,
    n_autores          = n_autores,
    autores            = pipe_collapse(autores),
    afiliacao          = pipe_collapse(afiliacao),
    paises             = pipe_collapse(paises),
    total_citacoes     = total_citacoes,
    citacoes_por_ano   = cit_str,
    total_referencias  = total_referencias,
    works_relacionados = related_str,
    indexadores        = pipe_collapse(indexadores),
    open_access        = is_oa,
    oa_tipo            = oa_status,
    oa_url             = oa_url
  )
}

# -----------------------------------------------------------------------------
# SCRAPING POR ISSN
# -----------------------------------------------------------------------------

scrape_issn <- function(issn, email = EMAIL) {
  
  message(sprintf("\n[ISSN %s] Iniciando...", issn))
  
  url_base <- sprintf(
    "%s?filter=locations.source.issn:%s&per-page=%d&cursor=*&select=%s",
    BASE_URL, issn, PER_PAGE, FIELDS
  )
  
  res <- safe_request(url_base, email)
  if (is.null(res)) {
    message(sprintf("  [ERRO] Não foi possível acessar ISSN %s", issn))
    return(tibble())
  }
  
  json    <- resp_body_json(res)
  total   <- json$meta$count %||% 0
  n_pages <- ceiling(total / PER_PAGE)
  
  message(sprintf("  Total de works: %d | Páginas: %d", total, n_pages))
  if (total == 0) return(tibble())
  
  all_works <- list()
  cursor    <- "*"
  page      <- 1
  
  pb <- progress_bar$new(
    format = sprintf("  ISSN %s [:bar] :percent (:current/:total páginas) eta: :eta", issn),
    total  = n_pages,
    clear  = FALSE
  )
  
  repeat {
    url <- sprintf(
      "%s?filter=locations.source.issn:%s&per-page=%d&cursor=%s&select=%s",
      BASE_URL, issn, PER_PAGE, cursor, FIELDS
    )
    
    res <- safe_request(url, email)
    if (is.null(res)) {
      message(sprintf("  [AVISO] Falha na página %d do ISSN %s — pulando", page, issn))
      break
    }
    
    json      <- resp_body_json(res)
    works_raw <- json$results %||% list()
    if (length(works_raw) == 0) break
    
    # issn_origem é passado para cada work da página
    page_data <- map_dfr(works_raw, ~ tryCatch(
      parse_work(.x, issn_origem = issn),
      error = function(e) tibble()
    ))
    
    all_works[[page]] <- page_data
    pb$tick()
    Sys.sleep(SLEEP_OK)
    
    next_cursor <- json$meta$next_cursor
    if (is.null(next_cursor) || next_cursor == cursor) break
    cursor <- next_cursor
    page   <- page + 1
  }
  
  bind_rows(all_works)
}

# -----------------------------------------------------------------------------
# LOOP PRINCIPAL COM CHECKPOINT
# -----------------------------------------------------------------------------

if (file.exists(CHECKPOINT)) {
  checkpoint_data <- readRDS(CHECKPOINT)
  resultados      <- checkpoint_data$resultados
  issns_feitos    <- checkpoint_data$issns_feitos
  message(sprintf("Checkpoint encontrado — %d ISSNs já processados.", length(issns_feitos)))
} else {
  resultados   <- list()
  issns_feitos <- character(0)
}

issns_pendentes <- setdiff(ISSN_LIST, issns_feitos)
message(sprintf("ISSNs pendentes: %d", length(issns_pendentes)))

for (issn in issns_pendentes) {
  
  dados_issn <- tryCatch(
    scrape_issn(issn),
    error = function(e) {
      message(sprintf("  [ERRO FATAL] ISSN %s: %s", issn, e$message))
      tibble()
    }
  )
  
  if (nrow(dados_issn) > 0) resultados[[issn]] <- dados_issn
  
  issns_feitos <- c(issns_feitos, issn)
  saveRDS(list(resultados = resultados, issns_feitos = issns_feitos), CHECKPOINT)
  message(sprintf("  Checkpoint salvo (%d ISSNs concluídos)", length(issns_feitos)))
}

# -----------------------------------------------------------------------------
# CONSOLIDAÇÃO E EXPORTAÇÃO
# -----------------------------------------------------------------------------

df_final <- bind_rows(resultados) |>
  distinct(DOI, .keep_all = TRUE)

message(sprintf("\nTotal de works únicos: %d", nrow(df_final)))
write_csv(df_final, OUTPUT_FILE, na = "")
message(sprintf("Arquivo salvo: %s", OUTPUT_FILE))

if (file.exists(CHECKPOINT)) file.remove(CHECKPOINT)
