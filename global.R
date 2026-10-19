##
##
##

## load required packages ####
if (.Platform$OS.type == "windows") {
  invisible(Sys.setlocale("LC_CTYPE", "Portuguese_Brazil.utf8"))
}
options(encoding = "UTF-8")
source("requirements.R", encoding = "UTF-8")
source("utils/display_contracts.R", encoding = "UTF-8")
source("utils/local_storage.R", encoding = "UTF-8")
source("utils/i18n.R", encoding = "UTF-8")
source("utils/initial_language.R", encoding = "UTF-8")
source("utils/analytics.R", encoding = "UTF-8")
source("utils/analytics_downloads.R", encoding = "UTF-8")
wlv_analytics_config <- wlv_read_analytics_config()

# Capturar os assets junto do código R evita que um processo já aberto use
# um módulo antigo com CSS/JavaScript de uma atualização posterior do disco.
# Os módulos também incorporam seus CSS/JS na construção da interface para
# não reutilizar arquivos de uma versão anterior no cache do navegador.
wlv_shared_assets <- tagList(
  includeCSS("www/wlv-panel.css"),
  includeCSS("www/wlv-language.css"),
  includeCSS("www/wlv-explore.css"),
  includeCSS("www/wlv-about.css"),
  includeCSS("www/wlv-analytics.css"),
  includeScript("www/wlv-panel.js"),
  includeScript("www/wlv-analytics.js"),
  includeScript("www/wlv-equal-earth.js")
)

download_directory <- wlvpanel_generated_directory("downloads")
if (!dir.exists(download_directory) &&
    !dir.create(download_directory, recursive = TRUE)) {
  stop("Cannot create the panel download directory.", call. = FALSE)
}
shiny::addResourcePath(
  "download",
  normalizePath(download_directory, winslash = "/", mustWork = TRUE)
)

## Define disk caching
shinyOptions(cache = cachem::cache_disk(
  wlvpanel_generated_directory("cache"),
  max_size = 256 * 1024^2,
  max_age = 7 * 24 * 60 * 60
))

## load data ####
language_file <- wlv_complete_language(readRDS("data/language_file.RDS"))
language_file <- wlv_complete_language(language_file, "config/about-translations.json")
language_file <- wlv_complete_language(language_file, "config/indicator-translations.json")
language_file <- wlv_complete_language(language_file, "config/method-translations.json")
language_file <- wlv_complete_language(language_file, "config/legacy-translations.json")
language_file <- wlv_complete_language(language_file, "config/analytics-translations.json")
language_file <- wlv_complete_locale_languages(language_file)
wlv_language_messages <- wlv_language_payload_cache(language_file)
sea_countries <- readRDS("data/sea_countries.RDS")
sea_sectors <- readRDS("data/sea_sectors.RDS")
meta_methods <- readRDS("data/meta_methods.RDS")
meta_indicators <- readRDS("data/meta_indicators.RDS")
wlv_validate_legacy_indicator_identity(meta_indicators)
legacy_indicator_metadata <- meta_indicators
meta_indicators <- wlv_public_indicator_metadata(meta_indicators)
groups <- meta_indicators$groups |> unique()
countries_sp  <- readRDS("data/countries_sp.RDS")
list_methods <- as.character(meta_methods$code)
method_indicator_availability <- wlv_method_indicator_availability(
  sea_sectors,
  indicator_axis = 2L
)
if (file.exists("data/meta_indicator_contracts.RDS")) {
  meta_indicator_contracts <- readRDS("data/meta_indicator_contracts.RDS")
  wlv_validate_display_contract_coverage(
    meta_indicator_contracts,
    method_indicator_availability
  )
} else {
  meta_indicator_contracts <- wlv_bind_display_contracts(lapply(
    list_methods,
    function(method) {
      indicators <- method_indicator_availability$indicator[
        method_indicator_availability$method == method
      ]
      wlv_legacy_display_contract(
        method_dir = method,
        method = method,
        indicators = indicators,
        legacy_metadata = legacy_indicator_metadata,
        warn = TRUE
      )
    }
  ))
  wlv_validate_display_contract_coverage(
    meta_indicator_contracts,
    method_indicator_availability
  )
}
display_contract_version <- wlv_display_contract_version(
  meta_indicator_contracts
)

## Theme definition ####

# theme <- "yeti"
# bar_height <- 45
# item_color <- "white"
# bg_color <- "black"

theme <- "simplex"
bar_height <- 41
item_color <- "darkgrey"
bg_color <- "white"
panel_bgcolor <- "rgba(252,252,252,1)"

## Initial setup ####
default_year <- 2007
default_indicator <- "surplus_value.empe_p.r.pc"
default_language <- "Português"
profile_indicators <- c("surplus_value.empe_p.r.pc",
                        "gdp.s.mv",
                        "gdp.s.us",
                        "labour_force_value.m.mv",
                        "abstract_labour.empe.m.mv")
init_bases <- c("WIOD13", "WIOD16")

## functions ####
# Rótulos da UI são traduzidos em lote pelo navegador.
l <- function(lab_code) {
  tags$span(`data-wlv-label` = lab_code, lb(lab_code))
}

# Label function to be used on server side: need to specify input$l
lb <- function(lab_code,lang = default_language){
  wlv_label(lab_code, lang, language_file)
}

# Format a value that has already been converted to its display unit.
display_f2s <- function(x, ind, method, lang = "English") {
  if (!is.numeric(x) || length(x) != 1L) {
    stop("`display_f2s` requires one numeric value.", call. = FALSE)
  }
  if (is.na(x)) {
    x
  } else {
    # reduce order of magnitude
    x.abs <-  x |> abs()
    suffix <- ""
    if (x.abs >= 1000000000000) {
      x <- x/1000000000000
      suffix <- "T"
    } else if (x.abs >= 1000000000) {
      x <- x/1000000000
      suffix <- "G"
    } else if (x.abs >= 1000000) {
      x <- x/1000000
      suffix <- "M"
    } else if (x.abs >= 1000) {
      x <- x/1000
      suffix <- "K"
    }
    
    # Method-specific display units are authoritative when available.
    type <- wlv_display_format_type(
      meta_indicator_contracts,
      method,
      ind
    )

    # defines nsmall
    x.abs <-  x |> abs()
    if (x.abs >=100) {
      x <- round(x, 0)
      ns <- 0
    } else if (x.abs >= 10) {
      x <- round(x, 1)
      ns <- 1
    } else {
      x <- round(x, 2)
      ns <- 2
    }

    # Format number
    x <- format(x, 
                big.mark = lb("big.mark", lang), 
                decimal.mark = lb("decimal.mark", lang), 
                nsmall = ns)

    # add suffix and prefix
    switch(
      type,
      "index" = paste0(x, suffix),
      "usd" = paste0("US$ ", x, suffix),
      "value" = paste0(x, suffix, "mv"),
      "hours" = paste0(x, suffix, lb("hours", lang)),
      "integer" = paste0(x, suffix),
      "percent" = paste0(x, suffix, "%"),
      paste0(x, suffix)
    )
  }
}

# Canonical values cross the presentation boundary exactly once here.
f2s <- function(x, ind, method, lang = "English") {
  display_f2s(
    wlv_display_values(
      x,
      method,
      ind,
      meta_indicator_contracts,
      meta_indicators
    ),
    ind,
    method,
    lang
  )
}

list_f2s <- function(z, ind, method, lng) {
  lapply(
    seq_along(z),
    function(i, w = z, name = ind) {
      f2s(w[i], name, method, lang = lng)
    }
  )
}

list_display_f2s <- function(z, ind, method, lng) {
  lapply(
    seq_along(z),
    function(i, w = z, name = ind) {
      display_f2s(w[i], name, method, lang = lng)
    }
  )
}

## modules ####
modules_server <- NULL
modules_ui <- NULL
source("modules/panel_setup/main.R", encoding = "UTF-8")
source("modules/how_to_quote/main.R", encoding = "UTF-8")
source("modules/about/main.R", encoding = "UTF-8")
source("modules/countries/main.R", encoding = "UTF-8")
source("modules/country/main.R", encoding = "UTF-8")
source("modules/indicators/main.R", encoding = "UTF-8")
source("modules/trade/main.R", encoding = "UTF-8")
source("modules/download/main.R", encoding = "UTF-8")
source("modules/publications/main.R", encoding = "UTF-8")
