# OpenAlex ISSN Scraper

[![Licença: MIT](https://img.shields.io/badge/Licen%C3%A7a-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![R](https://img.shields.io/badge/R-4.0+-blue.svg)](https://www.r-project.org/)

> Coleta automatizada de metadados bibliográficos da API OpenAlex usando ISSNs.  
> *Automated collection of bibliographic metadata from the OpenAlex API using ISSNs.*

---

## 🇧🇷 Português

### Descrição

Este script R foi desenvolvido para buscar metadados de artigos científicos indexados na **OpenAlex** a partir de uma lista de ISSNs de periódicos. Ele é ideal para quem precisa coletar dados bibliométricos em larga escala, como:

- Títulos dos artigos
- Autores e afiliações
- Citações recebidas (total e por ano)
- Status de acesso aberto (Open Access)
- DOI, referências, fontes de indexação, etc.

### Funcionalidades

- Consulta automática à API OpenAlex (com paginação baseada em cursor)
- Tratamento de falhas e tentativas automáticas (retry)
- Sistema de **checkpoint** – se a coleta for interrompida, você pode retomar de onde parou
- Remoção de duplicatas baseada em DOI
- Exportação final em **CSV UTF-8**, com separador `|` para campos com múltiplos valores

### Dados coletados

O script retorna as seguintes colunas no CSV:

| Campo | Descrição |
|-------|------------|
| work_id | ID do trabalho na OpenAlex |
| ISSN | ISSN do periódico |
| DOI | Digital Object Identifier |
| title | Título do artigo |
| n_authors | Número de autores |
| authors | Nomes dos autores (separados por `\|`) |
| affiliations | Afiliações institucionais (separadas por `\|`) |
| countries | Países das afiliações (separados por `\|`) |
| total_citations | Total de citações recebidas |
| citations_by_year | Citações por ano (formato JSON ou string) |
| n_references | Número de referências bibliográficas |
| related_works | Trabalhos relacionados (IDs separados por `\|`) |
| indexing_sources | Fontes de indexação (ex.: Scopus, WoS) |
| is_oa | Se é acesso aberto (TRUE/FALSE) |
| oa_status | Tipo de acesso aberto (gold, hybrid, green, etc.) |

### Requisitos

- R (versão 4.0 ou superior)
- Pacotes R:
  ```r
  install.packages(c("httr2", "tidyverse", "jsonlite", "progress"))

## Configuração

1. **Informe seu e-mail** (obrigatório para usar o OpenAlex):

   ```r
   EMAIL <- "seu_email@exemplo.com"
   

2. **Defina os ISSNs** que deseja consultar:
```r
ISSN_LIST <- c("1808-5245", "1517-4522", "0103-3786")  
```

### Como executar
- Abra o script no RStudio ou no terminal R.
- Ajuste as configurações acima.
- Execute o código completo (selecionando tudo ou usando source("script.R")).
- Acompanhe o progresso no console.
- Ao final, o arquivo openalex_resultado.csv será gerado no diretório de trabalho.

### Observações importantes

- Respeite a política da OpenAlex: forneça um e-mail real e evite fazer muitas requisições por segundo (o script já tem pausas automáticas).
- O script salva checkpoints a cada 500 trabalhos. Se a execução falhar, rode novamente que ele continuará de onde parou.
- A remoção de duplicatas é feita por DOI. Artigos sem DOI serão mantidos, mas podem haver duplicatas não removidas (caso o mesmo artigo apareça em mais de um ISSN).
