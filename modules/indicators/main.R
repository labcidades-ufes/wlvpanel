# Restores the catalogue, international comparisons, map and tables from
# panel_indicators.R at ebe8168, using the current method display contracts.
wlv_indicator_helpers <- if (file.exists("utils/indicator_rankings.R")) "utils" else file.path("..", "..", "utils")
source(file.path(wlv_indicator_helpers, "indicator_rankings.R"), local = TRUE, encoding = "UTF-8")
source(file.path(wlv_indicator_helpers, "indicator_ranking_chart.R"), local = TRUE, encoding = "UTF-8")

wlv_indicators_text <- function(key, lang = "pt") {
  dictionary <- list(
    title = c("Indicadores", "Indicators"),
    indicator = c("Indicador", "Indicator"), countries = c("Países para comparar", "Countries to compare"),
    methods = c("Bases para comparar", "Databases to compare"), year = c("Ano", "Year"),
    map_method = c("Base do mapa", "Map database"), series = c("Série histórica", "Time series"),
    map = c("Mapa", "Map"), catalogue = c("Catálogo de indicadores", "Indicator catalogue"),
    ranking = c("Ranking", "Ranking"), ranking_method = c("Base do ranking", "Ranking database"),
    ranking_title = c("Posição dos países ao longo do tempo", "Country rankings over time"),
    ranking_note = c("1º = maior valor do indicador. Empates recebem a mesma posição. O ranking inclui os países com dados em cada ano e exclui agregados; sua cobertura pode variar. Nos destaques, a posição aparece acima e o valor abaixo.",
      "1st = highest indicator value. Ties share the same rank. Rankings include countries with data in each year and exclude aggregates; coverage may vary. Highlights show rank above and value below."),
    ranking_high = c("Maiores valores", "Higher values"), ranking_low = c("Menores valores", "Lower values"),
    ranking_colors = c("Cores: quintos do ranking anual", "Colors: fifths of each year's ranking"),
    ranking_scroll = c("Deslize o gráfico horizontalmente para percorrer os anos.", "Scroll the chart horizontally to explore the years."),
    group = c("Grupo", "Group"), subgroup = c("Subgrupo", "Subgroup"),
    all_groups = c("Todos os grupos", "All groups"), all_subgroups = c("Todos os subgrupos", "All subgroups"),
    back = c("Voltar ao catálogo", "Back to catalogue"),
    search = c("Buscar no catálogo", "Search the catalogue"), all = c("Todos os países", "All countries"),
    selected = c("Países selecionados", "Selected countries"), country = c("País", "Country"),
    hint = c("Toque em uma linha ou em um país no mapa para adicioná-lo à comparação.", "Tap a row or a country on the map to add it to the comparison."),
    selected_hint = c("Toque em uma linha para retirar o país da comparação.", "Tap a row to remove the country from the comparison."),
    empty = c("Não há observações para esta seleção.", "No observations are available for this selection."),
    choose = c("Selecione pelo menos um país e uma base para comparar.", "Select at least one country and database to compare."),
    no_match = c("Nenhum indicador encontrado.", "No indicators found."),
    export = c("Baixar série selecionada (CSV)", "Download selected series (CSV)"),
    workbooks = c("Indicador completo por base (XLSX)", "Complete indicator by database (XLSX)"),
    export_hint = c("Inclui todos os anos dos países e bases selecionados, nas unidades exibidas.", "Includes all years for the selected countries and databases, in display units."),
    missing = c("Sem dados", "No data"), unit = c("Unidade", "Unit"),
    unit_note = c("Bases com unidades diferentes aparecem em gráficos separados.", "Databases with different units appear in separate charts."),
    table_search = c("Buscar país:", "Search country:"), table_info = c("_START_–_END_ de _TOTAL_ países", "_START_–_END_ of _TOTAL_ countries"),
    previous = c("Anterior", "Previous"), next_page = c("Próxima", "Next")
  )
  wlv_tr(dictionary[[key]][[1L]], dictionary[[key]][[2L]], lang)
}

wlv_indicators_label <- function(language, key, lang = "pt", fallback = key) {
  # paste0("ISO3.", character()) produces one string; its empty fallback
  # still denotes an empty selection and must not invent a country label.
  if (!length(key) || !length(fallback)) return(character())
  result <- wlv_label(key, lang, language)
  invalid <- is.na(result) | !nzchar(result) | result == key
  result[invalid] <- rep_len(fallback, length(result))[invalid]
  result
}

wlv_indicators_unit_label <- function(unit, lang = "pt") {
  unit <- sub("^legacy:", "", unit)
  labels <- list(percent = c("%", "%"), usd = c("US$", "US$"), index = c("Índice", "Index"),
    index_point = c("Pontos de índice", "Index points"), person = c("Pessoas", "People"),
    integer = c("Pessoas", "People"), hour = c("Horas", "Hours"), hours = c("Horas", "Hours"),
    value = c("Horas de trabalho abstrato", "Abstract labour hours"),
    abstract_labour_hour = c("Horas de trabalho abstrato", "Abstract labour hours"),
    abstract_labour_hour_per_person = c("mv/pessoa", "mv/person"),
    abstract_labour_hour_per_usd = c("mv/US$", "mv/US$"),
    local_currency_per_usd = c("Moeda local/US$", "Local currency/US$"),
    ratio = c("Razão", "Ratio"), multiplier = c("Multiplicador", "Multiplier"))
  if (unit %in% names(labels)) wlv_tr(labels[[unit]][[1L]], labels[[unit]][[2L]], lang) else gsub("_", " ", unit, fixed = TRUE)
}

wlv_indicators_fold <- function(value) {
  tolower(stringi::stri_trans_general(enc2utf8(value), "Latin-ASCII"))
}

# Locate matches in folded text, but preserve accents and escape every original
# text segment before adding markup. Neither the query nor a label is HTML.
wlv_indicators_highlight <- function(value, search = "") {
  if (is.null(search) || !nzchar(trimws(search))) return(value)
  characters <- strsplit(value, "", fixed = TRUE)[[1L]]
  lengths <- nchar(wlv_indicators_fold(characters))
  folded <- paste0(wlv_indicators_fold(characters), collapse = "")
  query <- wlv_indicators_fold(trimws(search))
  if (!nzchar(query)) return(value)
  matches <- gregexpr(query, folded, fixed = TRUE)[[1L]]
  if (matches[[1L]] < 0L) return(value)
  ends <- cumsum(lengths)
  starts <- ends - lengths + 1L
  marked <- rep(FALSE, length(characters))
  for (position in matches) marked <- marked | (ends >= position & starts < position + nchar(query))
  segments <- split(seq_along(characters), cumsum(c(TRUE, diff(marked) != 0L)))
  htmltools::HTML(paste0(vapply(segments, function(indices) {
    text <- htmltools::htmlEscape(paste0(characters[indices], collapse = ""))
    if (marked[[indices[[1L]]]]) paste0("<mark>", text, "</mark>") else text
  }, character(1L)), collapse = ""))
}

# Keep all dimensions: singleton methods, years and countries are valid inputs.
# Conversion takes place once, before any chart, table, tooltip or export.
wlv_indicators_series <- function(countries, indicator, methods, contracts) {
  axes <- dimnames(countries)
  stopifnot(length(dim(countries)) == 4L, length(indicator) == 1L)
  methods <- intersect(as.character(methods), axes[[1L]])
  methods <- methods[vapply(methods, function(method) {
    indicator %in% axes[[3L]] && any(is.finite(countries[method, , indicator, , drop = FALSE]))
  }, logical(1L))]
  empty <- data.frame(method = character(), year = integer(), country = character(), value = numeric(), unit = character())
  if (!length(methods)) return(empty)
  do.call(rbind, lapply(methods, function(method) {
    grid <- expand.grid(year = axes[[2L]], country = axes[[4L]], stringsAsFactors = FALSE)
    raw <- as.numeric(countries[method, , indicator, , drop = FALSE])
    data.frame(method = method, year = as.integer(grid$year), country = grid$country,
      value = wlv_display_values(raw, method, indicator, contracts),
      unit = wlv_display_unit(contracts, method, indicator), stringsAsFactors = FALSE)
  }))
}

wlv_indicators_snapshot <- function(series, year, methods) {
  year <- suppressWarnings(as.integer(year))
  valid_year <- length(year) == 1L && is.finite(year)
  current <- if (valid_year) series[series$year == year, , drop = FALSE] else series[FALSE, , drop = FALSE]
  countries <- unique(current$country[is.finite(current$value)])
  result <- data.frame(country = countries, stringsAsFactors = FALSE)
  for (method in methods) {
    rows <- current[current$method == method, , drop = FALSE]
    result[[method]] <- rows$value[match(countries, rows$country)]
  }
  result
}

# Older metadata stores only groups. Subgroups follow each stable indicator
# family; an explicit metadata subgroup takes precedence when supplied.
wlv_indicators_catalogue_rows <- function(metadata, codes) {
  rows <- metadata[match(codes, metadata$value), , drop = FALSE]
  subgroup_column <- intersect(c("subgroups", "subgroup"), names(rows))
  rows$subgroup <- if (length(subgroup_column)) as.character(rows[[subgroup_column[[1L]]]]) else sub("[.].*$", "", rows$value)
  rows$subgroup[is.na(rows$subgroup)] <- ""
  rows
}

wlv_indicators_subgroup_label <- function(code, lang = "pt") {
  dictionary <- list(
    capital_stock = c("Estoque de capital", "Capital stock"), profit = c("Lucro", "Profit"),
    capital_depreciation = c("Depreciação do capital", "Capital depreciation"),
    appropriated_profit = c("Lucro apropriado", "Appropriated profit"),
    trade_transfers = c("Transferência de valor pelo comércio", "Value transfers through trade"),
    exports = c("Exportações", "Exports"), imports = c("Importações", "Imports"),
    trade_balance = c("Saldo comercial", "Trade balance"), hours_worked = c("Horas trabalhadas", "Hours worked"),
    emp = c("Pessoas ocupadas", "Employed people"), empe = c("Trabalhadores assalariados", "Employees"),
    abstract_labour = c("Trabalho abstrato", "Abstract labour"), exchange = c("Taxa de câmbio", "Exchange rate"),
    go_price = c("Preços do produto total", "Gross output prices"),
    complex_labour_multiplier = c("Multiplicador de trabalho complexo", "Complex labour multiplier"),
    basket_price = c("Preço da cesta de consumo", "Consumption basket price"),
    basket_value = c("Valor da cesta de consumo", "Consumption basket value"),
    gross_output = c("Produto total", "Gross output"), gdp = c("Produto Interno Bruto", "Gross Domestic Product"),
    value = c("Valor", "Value"), surplus_value = c("Mais-valor", "Surplus value"),
    compensation = c("Remuneração do trabalho", "Labour compensation"),
    labour_force_value = c("Valor da força de trabalho", "Value of labour power")
  )
  vapply(code, function(value) {
    if (value %in% names(dictionary)) wlv_tr(dictionary[[value]][[1L]], dictionary[[value]][[2L]], lang) else value
  }, character(1L), USE.NAMES = FALSE)
}

indicators_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    htmltools::includeCSS("www/wlv-indicators.css"),
    htmltools::includeScript("www/wlv-indicators.js"),
    htmltools::includeScript("www/wlv-indicator-ranking.js"),
    shiny::div(class = "wlv-explore-page",
     shiny::div(class = "wlv-indicators wlv-explore-content",
      shiny::tags$header(class = "wlv-explore-heading",
        shiny::h1(shiny::textOutput(ns("title"), inline = TRUE))),
      shiny::conditionalPanel("output.page === 'catalogue'", ns = ns,
        shiny::div(class = "wlv-indicators-catalogue-page",
          shiny::div(class = "wlv-indicators-catalogue-filters",
            shiny::textInput(ns("search"), "Buscar no catálogo", width = "100%"),
            shiny::selectizeInput(ns("group"), "Grupo", choices = stats::setNames("", wlv_indicators_text("all_groups")), selected = "", width = "100%",
              options = list(allowEmptyOption = TRUE, onInitialize = I("function() { var option = this.options['']; if (option) { this.settings.placeholder = option.label; this.updatePlaceholder(); } }"))),
            shiny::selectizeInput(ns("subgroup"), "Subgrupo", choices = stats::setNames("", wlv_indicators_text("all_subgroups")), selected = "", width = "100%",
              options = list(allowEmptyOption = TRUE, onInitialize = I("function() { var option = this.options['']; if (option) { this.settings.placeholder = option.label; this.updatePlaceholder(); } }")))),
          shiny::uiOutput(ns("catalogue")))),
      shiny::conditionalPanel("output.page === 'detail'", ns = ns,
       shiny::div(class = "wlv-indicators-grid",
        shiny::div(class = "wlv-indicators-controls panel panel-default",
          shiny::actionButton(ns("back"), "Voltar ao catálogo", icon = shiny::icon("arrow-left"), width = "100%"),
          shiny::selectizeInput(ns("indicator"), "Indicador", choices = NULL, width = "100%"),
          shiny::selectizeInput(ns("countries"), "Países para comparar", choices = NULL, multiple = TRUE, width = "100%"),
          shiny::selectizeInput(ns("methods"), "Bases para comparar", choices = NULL, multiple = TRUE, width = "100%"),
          shiny::uiOutput(ns("workbooks")),
          shiny::downloadButton(ns("download"), shiny::textOutput(ns("export_label"), inline = TRUE)),
          shiny::tags$small(shiny::textOutput(ns("export_hint"), inline = TRUE))) ,
        shiny::div(class = "wlv-indicators-main",
          shiny::div(class = "wlv-indicators-detail-heading panel panel-default",
            shiny::h3(shiny::textOutput(ns("indicator_title"), inline = TRUE)),
            shiny::uiOutput(ns("description"))),
          shiny::div(class = "wlv-indicators-views panel panel-default", shiny::tabsetPanel(id = ns("view"),
            shiny::tabPanel(shiny::textOutput(ns("series_label"), inline = TRUE), value = "series", plotly::plotlyOutput(ns("series"), height = "420px")),
            shiny::tabPanel(shiny::textOutput(ns("map_label"), inline = TRUE), value = "map",
              shiny::div(class = "wlv-indicators-map-frame",
                leaflet::leafletOutput(ns("map"), height = "420px"),
                shiny::div(class = "wlv-indicators-map-base",
                  shiny::selectInput(ns("map_method"), "Base do mapa", choices = NULL, width = "100%")),
                shiny::conditionalPanel("output.map_available !== 'yes'", ns = ns,
                  shiny::p(class = "wlv-indicators-map-empty", role = "status", shiny::textOutput(ns("map_empty"), inline = TRUE)))),
              shiny::div(class = "wlv-indicators-map-year",
                shiny::sliderInput(ns("year"), "Ano", min = 1995, max = 2020, value = 2007, step = 1, sep = "", width = "100%"))),
            shiny::tabPanel(shiny::textOutput(ns("ranking_label"), inline = TRUE), value = "ranking",
              shiny::div(class = "wlv-indicators-ranking",
                shiny::div(class = "wlv-ranking-toolbar",
                  shiny::div(shiny::h3(shiny::textOutput(ns("ranking_title"), inline = TRUE)),
                    shiny::p(class = "wlv-ranking-context", shiny::textOutput(ns("ranking_context"), inline = TRUE))),
                  shiny::selectInput(ns("ranking_method"), "Base do ranking", choices = NULL, width = "100%")),
                shiny::div(class = "wlv-ranking-key",
                  shiny::span(shiny::textOutput(ns("ranking_high"), inline = TRUE)),
                  shiny::span(class = "wlv-ranking-key-colors", `aria-hidden` = "true",
                    lapply(seq_len(5L), function(i) shiny::span())),
                  shiny::span(shiny::textOutput(ns("ranking_low"), inline = TRUE)),
                  shiny::span(class = "wlv-ranking-key-caption", shiny::textOutput(ns("ranking_colors"), inline = TRUE))),
                shiny::p(class = "wlv-ranking-readout", role = "status", `aria-live` = "polite"),
                shiny::div(class = "wlv-indicators-ranking-scroll", tabindex = "0",
                  plotly::plotlyOutput(ns("ranking"), height = "640px")),
                shiny::p(class = "wlv-ranking-mobile-hint", shiny::textOutput(ns("ranking_scroll"), inline = TRUE)),
                shiny::p(class = "wlv-ranking-note", shiny::textOutput(ns("ranking_note"), inline = TRUE)))))),
          shiny::div(class = "wlv-indicators-table-panel panel panel-default",
            shiny::div(class = "panel-heading", shiny::h3(shiny::textOutput(ns("selected_title"), inline = TRUE))),
            shiny::div(class = "panel-body", shiny::p(class = "wlv-indicators-table-hint", shiny::textOutput(ns("selected_hint"), inline = TRUE)), DT::DTOutput(ns("selected")))),
          shiny::div(class = "wlv-indicators-table-panel panel panel-default",
            shiny::div(class = "panel-heading", shiny::h3(shiny::textOutput(ns("all_title"), inline = TRUE))),
            shiny::div(class = "panel-body", shiny::p(class = "wlv-indicators-table-hint", shiny::textOutput(ns("hint"), inline = TRUE)), DT::DTOutput(ns("all"))))))))))
}

indicators_server <- function(id, data, lang, bases) {
  shiny::moduleServer(id, function(input, output, session) {
    tr <- function(key) wlv_indicators_text(key, lang())
    label <- function(key, fallback = key) wlv_indicators_label(data$language, key, lang(), fallback)
    subgroup_label <- function(code) label(paste0("subgroup.", code), wlv_indicators_subgroup_label(code, lang()))
    page <- shiny::reactiveVal("catalogue")
    output$page <- shiny::renderText(page())
    shiny::outputOptions(output, "page", suspendWhenHidden = FALSE)
    shiny::observeEvent(input$back, page("catalogue"))
    output_labels <- c(title = "title", export_label = "export", export_hint = "export_hint", series_label = "series", map_label = "map", hint = "hint", selected_hint = "selected_hint", selected_title = "selected", all_title = "all", ranking_label = "ranking", ranking_title = "ranking_title", ranking_note = "ranking_note", ranking_high = "ranking_high", ranking_low = "ranking_low", ranking_colors = "ranking_colors", ranking_scroll = "ranking_scroll")
    lapply(names(output_labels), function(id) { output[[id]] <- shiny::renderText(tr(output_labels[[id]])) })
    available_methods <- shiny::reactive(intersect(bases(), dimnames(data$countries)[[1L]]))
    available_indicators <- shiny::reactive({
      methods <- available_methods()
      if (!length(methods)) return(character())
      values <- data$countries[methods, , , , drop = FALSE]
      observed <- dimnames(values)[[3L]][apply(values, 3L, function(x) any(is.finite(x)))]
      intersect(data$metadata$value, observed)
    })
    methods_initialized <- FALSE
    countries_initialized <- FALSE
    shiny::observe({
      methods <- available_methods()
      indicators <- available_indicators()
      groups <- data$metadata$groups[match(indicators, data$metadata$value)]
      choices <- split(stats::setNames(indicators, label(indicators)), label(paste0("group.", groups), groups))
      selected <- shiny::isolate(input$indicator)
      if (!length(selected) || !selected %in% indicators) selected <- if ("surplus_value.empe_p.r.pc" %in% indicators) "surplus_value.empe_p.r.pc" else head(indicators, 1L)
      # The public catalogue is small (dozens of indicators). Local options
      # avoid an asynchronous Selectize reload that temporarily clears the
      # indicator and then restores stale country selections after a relabel.
      shiny::updateSelectizeInput(session, "indicator", label = tr("indicator"), choices = choices, selected = selected, server = FALSE)
      previous_methods <- shiny::isolate(input$methods)
      selected_methods <- intersect(previous_methods, methods)
      if (!methods_initialized || (length(previous_methods) && !length(selected_methods))) selected_methods <- methods
      if (length(methods)) methods_initialized <<- TRUE
      shiny::updateSelectizeInput(session, "methods", label = tr("methods"), choices = methods, selected = selected_methods)
      shiny::updateTextInput(session, "search", label = tr("search"))
      shiny::updateActionButton(session, "back", label = tr("back"))
    })
    catalogue_rows <- shiny::reactive(wlv_indicators_catalogue_rows(data$metadata, available_indicators()))
    shiny::observe({
      groups <- unique(catalogue_rows()$groups)
      selected <- shiny::isolate(input$group)
      if (!length(selected) || !selected %in% groups) selected <- ""
      choices <- stats::setNames(groups, label(paste0("group.", groups), groups))
      shiny::updateSelectInput(session, "group", label = tr("group"),
        choices = c(stats::setNames("", tr("all_groups")), choices[order(names(choices))]), selected = selected)
    })
    shiny::observe({
      rows <- catalogue_rows()
      if (length(input$group) && nzchar(input$group)) rows <- rows[rows$groups == input$group, , drop = FALSE]
      subgroups <- unique(rows$subgroup)
      selected <- shiny::isolate(input$subgroup)
      if (!length(selected) || !selected %in% subgroups) selected <- ""
      choices <- stats::setNames(subgroups, subgroup_label(subgroups))
      shiny::updateSelectInput(session, "subgroup", label = tr("subgroup"),
        choices = c(stats::setNames("", tr("all_subgroups")), choices[order(names(choices))]), selected = selected)
    })
    series <- shiny::reactive({
      shiny::req(input$indicator)
      wlv_indicators_series(data$countries, input$indicator, intersect(input$methods, available_methods()), data$contracts)
    })
    shiny::observe({
      values <- series()
      # Keep the country selection while comparison methods are temporarily
      # empty, so choosing methods again restores the same comparison.
      if (!nrow(values)) {
        shiny::updateSelectizeInput(session, "countries", label = tr("countries"))
        shiny::updateSelectInput(session, "map_method", label = tr("map_method"))
        return(invisible(NULL))
      }
      countries <- unique(values$country[is.finite(values$value)])
      current <- shiny::isolate(input$countries)
      selected <- intersect(current, countries)
      if (!countries_initialized || (length(current) && !length(selected))) selected <- if ("BRA" %in% countries) "BRA" else head(countries, 1L)
      if (length(countries)) countries_initialized <<- TRUE
      names(countries) <- label(paste0("ISO3.", countries), countries)
      countries <- countries[order(names(countries))]
      shiny::updateSelectizeInput(session, "countries", label = tr("countries"), choices = countries, selected = selected)
      methods <- unique(values$method)
      current_method <- shiny::isolate(input$map_method)
      selected_method <- if (length(current_method) && current_method %in% methods) current_method else head(methods, 1L)
      shiny::updateSelectInput(session, "map_method", label = tr("map_method"), choices = methods, selected = selected_method)
    })
    shiny::observe({
      methods <- unique(series()$method)
      current <- shiny::isolate(input$ranking_method)
      selected <- if (length(current) == 1L && current %in% methods) current else head(methods, 1L)
      shiny::updateSelectInput(session, "ranking_method", label = tr("ranking_method"), choices = methods, selected = selected)
    })
    ranking_rows <- shiny::reactive({
      method <- input$ranking_method
      if (!length(method) || !nzchar(method) || !method %in% unique(series()$method)) method <- NULL
      wlv_indicator_rankings(series(), method)
    })
    output$ranking_context <- shiny::renderText({
      rows <- ranking_rows()
      if (!nrow(rows)) return(tr("empty"))
      coverage <- range(rows$count)
      coverage_label <- paste0(if (coverage[[1L]] == coverage[[2L]]) coverage[[1L]] else paste(coverage, collapse = "–"),
        wlv_tr(" países por ano", " countries per year", lang()))
      paste(rows$method[[1L]], paste(range(rows$year), collapse = "–"),
        wlv_indicators_unit_label(rows$unit[[1L]], lang()), coverage_label, sep = " · ")
    })
    output$ranking <- plotly::renderPlotly({
      rows <- ranking_rows()
      shiny::validate(shiny::need(nrow(rows), tr("empty")))
      countries <- unique(rows$country)
      wlv_indicator_ranking_chart(rows, input$countries,
        stats::setNames(label(paste0("ISO3.", countries), countries), countries),
        label(input$indicator), wlv_indicators_unit_label(rows$unit[[1L]], lang()), lang(),
        countries_input = session$ns("countries"))
    })
    shiny::observe({
      values <- series()
      method <- input$map_method
      years <- sort(unique(values$year[values$method %in% method & is.finite(values$value)]))
      if (length(years)) {
        # Empty select controls reach the server as "" before their choices are
        # acknowledged by the browser. Never index with which.min(NA).
        current_year <- suppressWarnings(as.integer(shiny::isolate(input$year)))
        if (length(current_year) != 1L || !is.finite(current_year)) current_year <- 2007L
        current_year <- years[[which.min(abs(years - current_year))]]
        shiny::updateSliderInput(session, "year", label = tr("year"), min = min(years), max = max(years), value = current_year, step = 1)
      }
    })
    output$indicator_title <- shiny::renderText({ shiny::req(input$indicator); label(input$indicator) })
    output$description <- shiny::renderUI({
      shiny::req(input$indicator)
      description <- label(paste0("desc.", input$indicator), "")
      shiny::tagList(if (nzchar(description)) shiny::p(description), if (length(unique(series()$unit)) > 1L) shiny::p(tr("unit_note")))
    })
    output$catalogue <- shiny::renderUI({
      rows <- catalogue_rows()
      if (length(input$group) && nzchar(input$group)) rows <- rows[rows$groups == input$group, , drop = FALSE]
      if (length(input$subgroup) && nzchar(input$subgroup) && input$subgroup %in% rows$subgroup) rows <- rows[rows$subgroup == input$subgroup, , drop = FALSE]
      search <- input$search
      if (!is.null(search) && nzchar(search)) {
        # Accent-insensitive matching keeps a plain keyboard search useful in
        # Portuguese, and fixed=TRUE treats punctuation as text, not a regexp.
        haystack <- paste(label(rows$value), label(paste0("group.", rows$groups), rows$groups), subgroup_label(rows$subgroup))
        rows <- rows[grepl(wlv_indicators_fold(trimws(search)), wlv_indicators_fold(haystack), fixed = TRUE), , drop = FALSE]
      }
      if (!nrow(rows)) return(shiny::p(role = "status", tr("no_match")))
      grouped <- split(rows, rows$groups)
      shiny::tagList(lapply(names(grouped), function(group) {
        values <- grouped[[group]]
        families <- split(values$value, values$subgroup)
        shiny::tags$section(class = "wlv-indicators-catalogue-group",
          shiny::h3(wlv_indicators_highlight(label(paste0("group.", group), group), search)),
          shiny::div(class = "wlv-indicators-catalogue-families", lapply(names(families), function(family) {
            codes <- families[[family]]
            shiny::div(class = "wlv-indicators-catalogue-family", shiny::h4(wlv_indicators_highlight(subgroup_label(family), search)),
              shiny::tags$ul(lapply(codes[order(label(codes))], function(code) {
                shiny::tags$li(shiny::actionLink(session$ns(paste0("catalogue_", code)), wlv_indicators_highlight(label(code), search)))
              })))
          })))
      }))
    })
    lapply(data$metadata$value, function(code) {
      shiny::observeEvent(input[[paste0("catalogue_", code)]], {
        shiny::updateSelectizeInput(session, "indicator", selected = code)
        page("detail")
      }, ignoreInit = TRUE)
    })
    selected_series <- shiny::reactive(series()[series()$country %in% input$countries, , drop = FALSE])
    output$map_empty <- shiny::renderText(tr("empty"))
    output$map_available <- shiny::renderText({
      values <- series()
      method <- input$map_method
      year <- suppressWarnings(as.integer(input$year))
      if (!length(method) || length(year) != 1L || !is.finite(year)) return("no")
      if (any(values$method == method & values$year == year & is.finite(values$value))) "yes" else "no"
    })
    shiny::outputOptions(output, "map_available", suspendWhenHidden = FALSE)
    output$series <- plotly::renderPlotly({
      values <- selected_series()
      shiny::validate(shiny::need(nrow(values) && any(is.finite(values$value)), tr("choose")))
      units <- unique(values$unit)
      charts <- lapply(units, function(unit) {
        unit_label <- wlv_indicators_unit_label(unit, lang())
        current <- values[values$unit == unit, , drop = FALSE]
        chart <- plotly::plot_ly()
        for (country in unique(current$country)) for (method in unique(current$method)) {
          rows <- current[current$country == country & current$method == method, , drop = FALSE]
          if (!any(is.finite(rows$value))) next
          country_name <- label(paste0("ISO3.", country), country)
          chart <- plotly::add_trace(chart, x = rows$year, y = rows$value, type = "scatter", mode = "lines+markers", name = paste(country_name, method, sep = " · "), connectgaps = FALSE, hovertemplate = paste0("%{x}: %{y:.4~g} ", htmltools::htmlEscape(unit_label), "<extra>%{fullData.name}</extra>"))
        }
        # The numeral in the family name requires CSS quotes. Without them,
        # SVG text falls back to Open Sans after Plotly has measured the legend.
        chart_font <- list(family = "'Source Sans 3', sans-serif", size = 13, color = "#292B2E")
        plotly::layout(chart, font = chart_font, xaxis = list(title = "", tickformat = "d"), yaxis = list(title = unit_label), separators = wlv_plotly_separators(lang()), legend = list(font = chart_font, orientation = "h", y = -0.2), margin = list(t = 15, b = 90))
      })
      chart <- if (length(charts) == 1L) charts[[1L]] else plotly::subplot(charts, nrows = length(charts), shareX = TRUE, titleY = TRUE)
      wlv_plotly_config(chart, lang(), displaylogo = FALSE, responsive = TRUE)
    })
    snapshot <- shiny::reactive(wlv_indicators_snapshot(series(), input$year, unique(series()$method)))
    table_widget <- function(values) {
      values$country <- label(paste0("ISO3.", values$country), values$country)
      methods <- setdiff(names(values), "country")
      names(values) <- c(tr("country"), vapply(methods, function(method) paste0(method, " (", wlv_indicators_unit_label(wlv_display_unit(data$contracts, method, input$indicator), lang()), ")"), character(1L)))
      table <- DT::datatable(values, rownames = FALSE, selection = "single", class = "display wlv-indicators-table", options = list(paging = FALSE, info = FALSE, ordering = TRUE, order = list(list(0L, "asc")), lengthChange = FALSE, scrollX = TRUE, language = list(search = tr("table_search"), infoEmpty = tr("empty"), zeroRecords = tr("empty"), emptyTable = tr("empty"))))
      if (length(methods)) table <- DT::formatRound(table, columns = seq_along(methods) + 1L, digits = 2L, mark = wlv_number_marks(lang())$grouping, dec.mark = wlv_number_marks(lang())$decimal)
      table
    }
    output$all <- DT::renderDT(table_widget(snapshot()), server = TRUE)
    selected_snapshot <- shiny::reactive(snapshot()[snapshot()$country %in% input$countries, , drop = FALSE])
    output$selected <- DT::renderDT(table_widget(selected_snapshot()), server = TRUE)
    add_country <- function(country) {
      if (length(country) == 1L && country %in% unique(series()$country)) shiny::updateSelectizeInput(session, "countries", selected = unique(c(input$countries, country)))
    }
    shiny::observeEvent(input$all_rows_selected, {
      row <- input$all_rows_selected
      if (length(row) == 1L && row > 0L && row <= nrow(snapshot())) {
        add_country(snapshot()$country[[row]])
        DT::selectRows(DT::dataTableProxy("all", session), NULL)
      }
    })
    shiny::observeEvent(input$selected_rows_selected, {
      row <- input$selected_rows_selected
      values <- selected_snapshot()
      if (length(row) == 1L && row > 0L && row <= nrow(values)) {
        shiny::updateSelectizeInput(session, "countries", selected = setdiff(input$countries, values$country[[row]]))
        DT::selectRows(DT::dataTableProxy("selected", session), NULL)
      }
    })
    polygons <- data$polygons[[1L]]
    for (method in names(data$polygons)[-1L]) {
      additional <- data$polygons[[method]]
      keep <- !as.character(additional@data$ISO3) %in% as.character(polygons@data$ISO3)
      if (any(keep)) polygons <- rbind(polygons, additional[keep, ], makeUniqueIDs = TRUE)
    }
    output$map <- leaflet::renderLeaflet({
      widget <- leaflet::leaflet(options = leaflet::leafletOptions(
        mapFactory = htmlwidgets::JS("function(el, options) { options.crs = window.WLVEqualEarth.install(L); return L.map(el, options); }"),
        minZoom = -2, maxZoom = 10, zoomSnap = 0, zoomDelta = 0.25, worldCopyJump = FALSE,
        preferCanvas = TRUE, trackResize = FALSE, doubleClickZoom = FALSE))
      widget <- leaflet::setView(widget, lng = 0, lat = 0, zoom = 0)
      widget <- leaflet::addMapPane(widget, "wlv-indicator-polygons", zIndex = 400)
      widget <- leaflet::addPolygons(widget, data = polygons, layerId = as.character(polygons@data$ISO3), fillColor = "#e2e8f0", fillOpacity = 0.8, color = "#ffffff", weight = 0.6, options = leaflet::pathOptions(pane = "wlv-indicator-polygons"))
      htmlwidgets::onRender(widget, "function(el,x){this.attributionControl.addAttribution('<a href=\"https://www.naturalearthdata.com/\" target=\"_blank\" rel=\"noopener\">Natural Earth</a> / rworldmap · Equal Earth'); WLVIndicators.attach(el,this);}")
    })
    shiny::observe({
      shiny::req(input$map_ready, input$map_method, input$year)
      current <- series()
      current <- current[current$method == input$map_method & current$year == input$year, , drop = FALSE]
      codes <- as.character(polygons@data$ISO3)
      values <- current$value[match(codes, current$country)]
      values[!is.finite(values)] <- NA_real_
      finite <- values[is.finite(values)]
      domain <- if (length(finite)) range(c(0, finite)) else c(0, 1)
      if (diff(domain) == 0) domain <- domain + c(-1, 1)
      palette <- leaflet::colorNumeric("YlOrRd", domain = domain, na.color = "#cbd5e1")
      unit <- wlv_indicators_unit_label(wlv_display_unit(data$contracts, input$map_method, input$indicator), lang())
      labels <- lapply(seq_along(codes), function(i) {
        number <- if (!is.finite(values[[i]])) tr("missing") else paste(format(values[[i]], digits = 5L, big.mark = wlv_number_marks(lang())$grouping, decimal.mark = wlv_number_marks(lang())$decimal, trim = TRUE), unit)
        list(color = palette(values[[i]]), missing = !is.finite(values[[i]]), label = paste0(
          "<div class='wlv-indicator-tooltip-country'>", htmltools::htmlEscape(label(paste0("ISO3.", codes[[i]]), codes[[i]])), "</div>",
          "<div class='wlv-indicator-tooltip-name'>", htmltools::htmlEscape(label(input$indicator)), "</div>",
          "<div class='wlv-indicator-tooltip-value'>", htmltools::htmlEscape(number), "</div>",
          "<div class='wlv-indicator-tooltip-source'>", htmltools::htmlEscape(paste(input$map_method, input$year, sep = " · ")), "</div>"))
      })
      names(labels) <- codes
      session$sendCustomMessage("wlvIndicatorsMap", list(id = session$ns("map"), countries = labels))
      proxy <- leaflet::removeControl(leaflet::leafletProxy("map", session), "indicator-legend")
      if (length(finite)) leaflet::addLegend(proxy, layerId = "indicator-legend", position = "bottomleft", pal = palette, values = finite, title = htmltools::htmlEscape(unit))
    })
    shiny::observeEvent(input$map_shape_click, add_country(input$map_shape_click$id))
    workbook_plans <- shiny::reactive({
      shiny::req(input$indicator)
      if (is.null(data$sectors) || is.null(data$methods)) return(list())
      methods <- unique(series()$method)
      stats::setNames(lapply(methods, function(method) wlv_aggregated_download_plan(
        method, indicator = input$indicator, countries = data$countries, sectors = data$sectors,
        metadata = data$metadata, methods = data$methods, contracts = data$contracts)), methods)
    })
    output$workbooks <- shiny::renderUI({
      requests <- workbook_plans()
      available <- names(requests)[!vapply(requests, is.null, logical(1L))]
      links <- lapply(available, function(method) shiny::tags$li(
        shiny::downloadLink(session$ns(paste0("workbook_", method)), method)))
      if (length(links)) shiny::tagList(shiny::tags$strong(tr("workbooks")), shiny::tags$ul(links))
    })
    lapply(dimnames(data$countries)[[1L]], function(method) {
      numeric_data <- shiny::reactive(wlv_aggregated_download_data(workbook_plans()[[method]]))
      output[[paste0("workbook_", method)]] <- wlv_request_download_handler(function()
        wlv_aggregated_download_localize(numeric_data(), data$language, lang()))
    })
    csv_callbacks <- wlv_download_callbacks(function() {
      values <- selected_series()
      values$indicator <- input$indicator
      values$country_name <- label(paste0("ISO3.", values$country), values$country)
      list(filename = paste0("WLVD-", input$indicator, ".csv"), data = values,
        analytics = list(kind = "indicators_csv", format = "csv", indicator = input$indicator,
          method = unique(values$method), country = unique(values$country), years = unique(values$year)))
    }, writer = function(request, file) {
      utils::write.csv(request$data, file, row.names = FALSE, na = "", fileEncoding = "UTF-8")
    })
    output$download <- shiny::downloadHandler(filename = csv_callbacks$filename,
      contentType = "text/csv; charset=utf-8", content = csv_callbacks$content)
    list(series = series, snapshot = snapshot, selected_series = selected_series)
  })
}

if (exists("modules_ui", inherits = FALSE) && exists("modules_server", inherits = FALSE)) {
  TABPANEL <- shiny::tabPanel(l("tab_name.indicators"), value = "indicators", indicators_ui("indicators"))
  modules_ui[[length(modules_ui) + 1L]] <- TABPANEL
  SERVER <- function(IP, OP, RV, SESSION) {
    indicators_server("indicators", data = list(countries = sea_countries, sectors = sea_sectors, methods = meta_methods, metadata = meta_indicators, contracts = meta_indicator_contracts, language = language_file, polygons = countries_sp, downloads = download_directory), lang = shiny::reactive(wlv_language_code(IP$l)), bases = RV$bases)
  }
  modules_server[[length(modules_server) + 1L]] <- SERVER
}
