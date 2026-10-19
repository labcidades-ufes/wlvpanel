# Sourcing registers light functions. Data and widgets are mounted on first visit.
source("utils/trade_data.R", encoding = "UTF-8")
source("modules/trade/text.R", encoding = "UTF-8")
source("modules/trade/charts.R", encoding = "UTF-8")
source("utils/trade_map.R", encoding = "UTF-8")
source("utils/trade_workbooks.R", encoding = "UTF-8")
source("utils/download_requests.R", encoding = "UTF-8")

trade_ui <- function(id, assets = NULL) {
  ns <- shiny::NS(id)
  text <- function(name) shiny::textOutput(ns(name), inline = TRUE)
  chart_heading <- function(name) shiny::div(class = "wlv-trade-chart-heading", shiny::h3(text(name)), shiny::p(text(paste0(name, "_unit"))))
  shiny::tagList(assets,
    shiny::div(class = "wlv-explore-page wlv-trade-page",
    shiny::div(class = "wlv-trade wlv-explore-content", id = ns("app"),
      shiny::tags$header(class = "wlv-explore-heading", shiny::h1(text("title"))),
      shiny::div(class = "wlv-trade-layout",
        shiny::tags$aside(class = "wlv-trade-controls panel panel-default", `aria-label` = "Filtros de comércio",
          shiny::tags$details(open = "open", class = "wlv-trade-filter-group",
            shiny::tags$summary(text("filters_label")),
            shiny::selectInput(ns("method"), "Base", choices = c("…" = "__initial__")),
            shiny::selectizeInput(ns("country"), "País em análise", choices = NULL),
            shiny::sliderInput(ns("year"), "Ano", min = 1995, max = 2014, value = 2007, sep = "", animate = FALSE),
            shiny::selectInput(ns("metric"), "Medida", choices = c("Transferências líquidas de valor" = "transfer", "Exportações" = "exports", "Importações" = "imports", "Saldo comercial" = "balance")),
            shiny::selectInput(ns("scope"), "Atividades fornecedoras", choices = c("Produtivas" = "productive", "Todas" = "total", "Improdutivas" = "unproductive")),
            shiny::selectInput(ns("unit"), "Unidade", choices = c("Horas de trabalho abstrato" = "value", "Dólares (US$)" = "usd"))),
          shiny::tags$details(open = "open", class = "wlv-trade-filter-group",
            shiny::tags$summary(text("detail_label")),
            shiny::selectizeInput(ns("partner"), "Parceiro comercial", choices = c("Todos os parceiros" = "")),
            shiny::selectizeInput(ns("sector"), "Setor do produto", choices = c("Todos os setores" = "")),
            shiny::radioButtons(ns("dimension"), "Detalhar por", choices = c("Parceiros" = "partner", "Setores" = "sector"), inline = TRUE),
            shiny::actionButton(ns("reset"), "Limpar detalhamento", icon = shiny::icon("arrow-left"), class = "wlv-trade-reset")),
          shiny::tags$details(class = "wlv-trade-notes",
            shiny::tags$summary(text("definitions_label")), shiny::p(text("definition_body")),
            shiny::p(text("unit_body")), shiny::p(text("sector_body")), shiny::p(text("base_body")))),
        shiny::div(class = "wlv-trade-main",
          shiny::div(class = "wlv-trade-overview panel panel-default",
            shiny::uiOutput(ns("context")),
            shiny::p(class = "wlv-trade-intro", text("intro")), shiny::uiOutput(ns("summary")),
            shiny::p(class = "wlv-trade-sign", text("sign_note")), shiny::uiOutput(ns("status"))),
          shiny::div(class = "wlv-trade-canvas panel panel-default",
            shiny::tabsetPanel(id = ns("view"),
              shiny::tabPanel(text("rank_label"), value = "rank", chart_heading("rank_title"), plotly::plotlyOutput(ns("rank"), height = "910px")),
              shiny::tabPanel(text("composition_label"), value = "composition", chart_heading("composition_title"), shiny::uiOutput(ns("composition_legend")), plotly::plotlyOutput(ns("composition"), height = "560px")),
              shiny::tabPanel(text("map_label"), value = "map", chart_heading("map_title"),
                shiny::conditionalPanel("input.metric === 'transfer'", ns = ns,
                  shiny::div(class = "wlv-trade-map-toolbar", shiny::checkboxInput(ns("map_flows"), "Exibir fluxos", value = TRUE), text("flow_caption"))),
                leaflet::leafletOutput(ns("map"), height = "550px"), shiny::p(class = "wlv-trade-chart-note", text("map_note"))),
              shiny::tabPanel(text("series_label"), value = "series", chart_heading("series_title"), plotly::plotlyOutput(ns("series"), height = "530px")),
              shiny::tabPanel(text("table_label"), value = "table", DT::DTOutput(ns("table"))))),
          shiny::div(class = "wlv-trade-bottom panel panel-default",
            shiny::p(class = "wlv-trade-drill", text("drill_hint")),
            shiny::div(class = "wlv-trade-downloads",
              shiny::downloadButton(ns("download"), text("download_label")),
              shiny::downloadButton(ns("download_series"), text("download_series_label")))),
          shiny::p(class = "wlv-trade-provenance", text("provenance")))))))
}

trade_server <- function(id, store, data, lang, bases, active) {
  shiny::moduleServer(id, function(input, output, session) {
    tr <- function(key) wlv_trade_text(key, lang())
    label <- function(key, fallback = key) wlv_trade_label(data$language, key, lang(), fallback)
    country_label <- function(codes) if (length(codes)) label(paste0("ISO3.", codes), codes) else character()
    sector_label <- function(codes) {
      if (!length(codes)) return(character())
      source <- data$methods$source[match(input$method, data$methods$code)]
      if (length(source) != 1L || is.na(source)) source <- tolower(input$method)
      label(paste0(source, ".", codes), codes)
    }
    choices <- function(keys) stats::setNames(keys, vapply(keys, tr, character(1L)))
    choose <- function(value, options, fallback = head(options, 1L)) {
      if (length(value) == 1L && !is.na(value) && value %in% options) value else fallback
    }
    optional <- function(value) if (length(value) == 1L && !is.na(value) && nzchar(value)) value else NULL
    error <- shiny::reactiveVal(NULL)
    failures <- list()
    safe <- function(expression, fallback = NULL, key = paste(deparse(substitute(expression)), collapse = " ")) {
      record <- function(message = NULL) {
        failures[[key]] <<- message
        error(if (length(failures)) unname(failures[[1L]]) else NULL)
      }
      tryCatch({ value <- force(expression); record(); value }, error = function(condition) {
        if (inherits(condition, "shiny.silent.error")) stop(condition)
        record(conditionMessage(condition)); fallback
      })
    }
    output_keys <- c(title = "title", intro = "intro", filters_label = "filters", detail_label = "detail", definitions_label = "definitions", definition_body = "definition_body", unit_body = "unit_body", sector_body = "sector_body", base_body = "base_body", composition_label = "composition", map_label = "map", series_label = "series", table_label = "table", download_label = "download", download_series_label = "download_series", drill_hint = "drill", map_note = "map_note")
    lapply(names(output_keys), function(name) { output[[name]] <- shiny::renderText(tr(output_keys[[name]])) })
    output$rank_label <- shiny::renderText(tr(if (identical(input$metric, "transfer")) "rank" else "ranking"))
    output$sign_note <- shiny::renderText(if (identical(input$metric, "transfer")) tr("sign") else "")
    lapply(c("rank_title", "composition_title", "map_title", "series_title"), function(name) {
      output[[paste0(name, "_unit")]] <- shiny::renderText(unit_label())
    })
    output$rank_title <- shiny::renderText({ shiny::req(input$year); paste0(tr(if (identical(input$dimension, "sector")) "sectors" else "partners"), " (", input$year, ")") })
    output$composition_title <- shiny::renderText({ shiny::req(input$year); paste0(tr("composition"), " (", input$year, ")") })
    output$composition_legend <- shiny::renderUI({
      shiny::req(active(), input$metric)
      words <- wlv_trade_chart_words(lang())
      transfer <- identical(input$metric, "transfer")
      item <- function(sign, label) shiny::span(class = "wlv-trade-legend-item",
        shiny::span(class = paste("wlv-trade-legend-swatch", paste0("is-", sign)), `aria-hidden` = "true"), label)
      shiny::div(class = "wlv-trade-legend", role = "group", `aria-label` = tr("legend"),
        item("negative", if (transfer) words$sending else words$negative),
        item("positive", if (transfer) words$receipts else words$positive))
    })
    output$map_title <- shiny::renderText({ shiny::req(input$year); paste0(tr("map"), " (", input$year, ")") })
    output$series_title <- shiny::renderText(tr("series"))

    methods <- shiny::reactive({ shiny::req(active()); safe(intersect(bases(), store$methods()), character()) })
    restored <- FALSE
    initial <- shiny::isolate(shiny::parseQueryString(session$clientData$url_search))
    restore <- function(key, default = NULL) {
      value <- initial[[paste0("trade_", key)]]
      if (is.null(value)) default else value
    }
    shiny::observe({
      shiny::req(active(), input$method); available <- methods()
      selected <- shiny::isolate(input$method)
      if (!restored) selected <- restore("method", "WIOD16")
      shiny::updateSelectInput(session, "method", label = tr("method"), choices = available, selected = choose(selected, available, if ("WIOD16" %in% available) "WIOD16" else head(available, 1L)))
      shiny::updateSelectInput(session, "metric", label = tr("metric"), choices = choices(c("transfer", "exports", "imports", "balance")), selected = choose(if (!restored) restore("metric", "transfer") else shiny::isolate(input$metric), c("transfer", "exports", "imports", "balance"), "transfer"))
      shiny::updateSelectInput(session, "scope", label = tr("scope"), choices = choices(c("productive", "total", "unproductive")), selected = choose(if (!restored) restore("scope", "productive") else shiny::isolate(input$scope), c("productive", "total", "unproductive"), "productive"))
      shiny::updateSelectInput(session, "unit", label = tr("unit"), choices = choices(c("value", "usd")), selected = choose(if (!restored) restore("unit", "value") else shiny::isolate(input$unit), c("value", "usd"), "value"))
      shiny::updateRadioButtons(session, "dimension", label = tr("dimension"), choices = stats::setNames(c("partner", "sector"), c(tr("partners"), tr("sectors"))), selected = choose(if (!restored) restore("dimension", "partner") else shiny::isolate(input$dimension), c("partner", "sector"), "partner"))
      shiny::updateActionButton(session, "reset", label = tr("reset"))
      shiny::updateCheckboxInput(session, "map_flows", label = tr("flows"))
    })
    bilateral <- shiny::reactive({ shiny::req(active(), input$method, input$method %in% methods()); safe(store$bilateral(input$method)) })
    countries <- shiny::reactive({ values <- bilateral(); if (is.null(values)) character() else dimnames(values)[[3L]] })
    country_restored <- FALSE
    shiny::observe({
      codes <- countries(); shiny::req(length(codes))
      selected <- shiny::isolate(input$country)
      if (!country_restored) selected <- restore("country", "BRA")
      selected <- choose(selected, codes, if ("BRA" %in% codes) "BRA" else codes[[1L]])
      shiny::updateSelectizeInput(session, "country", label = tr("country"), choices = stats::setNames(codes, country_label(codes)), selected = selected, server = FALSE)
      country_restored <<- TRUE
    })
    years <- shiny::reactive({
      shiny::req(active(), input$method, input$country, input$metric, input$scope, input$unit)
      safe(store$years(input$method, input$country, input$metric, input$scope, input$unit), character())
    })
    year_restored <- FALSE
    shiny::observe({
      available <- as.integer(years()); shiny::req(length(available))
      selected <- suppressWarnings(as.integer(shiny::isolate(input$year)))
      if (!year_restored) selected <- suppressWarnings(as.integer(restore("year", "2007")))
      if (length(selected) != 1L || !is.finite(selected)) selected <- max(available)
      selected <- available[[which.min(abs(available - selected))]]
      shiny::updateSliderInput(session, "year", label = tr("year"), min = min(available), max = max(available), value = selected, step = 1L)
      year_restored <<- TRUE
    })
    partner_restored <- FALSE
    shiny::observe({
      codes <- setdiff(countries(), input$country); shiny::req(length(codes))
      selected <- shiny::isolate(input$partner)
      if (!partner_restored) selected <- restore("partner", "")
      shiny::updateSelectizeInput(session, "partner", label = tr("partner"), choices = c(stats::setNames("", tr("all_partners")), stats::setNames(codes, country_label(codes))), selected = choose(selected, c("", codes), ""), server = FALSE)
      partner_restored <<- TRUE
    })
    detail_years <- shiny::reactive({ shiny::req(active(), input$method); safe(store$detail_years(input$method), character()) })
    detail <- shiny::reactive({
      shiny::req(active(), input$method, input$year)
      if (!as.character(input$year) %in% as.character(detail_years())) return(NULL)
      safe(store$detail(input$method, input$year))
    })
    sector_restored <- FALSE
    shiny::observe({
      part <- detail()
      codes <- if (is.null(part)) character() else unique(as.character(part$sector))
      selected <- shiny::isolate(input$sector)
      if (!sector_restored) selected <- restore("sector", "")
      shiny::updateSelectizeInput(session, "sector", label = tr("sector"), choices = c(stats::setNames("", tr("all_sectors")), stats::setNames(codes, sector_label(codes))), selected = choose(selected, c("", codes), ""), server = FALSE)
      if (length(codes)) sector_restored <<- TRUE
    })
    shiny::observeEvent(input$reset, {
      shiny::updateSelectizeInput(session, "partner", selected = "")
      shiny::updateSelectizeInput(session, "sector", selected = "")
      shiny::updateRadioButtons(session, "dimension", selected = "partner")
    })
    selection <- shiny::reactive({
      shiny::req(active(), bilateral(), input$country, input$year, input$metric, input$scope, input$unit, input$dimension)
      shiny::req(input$country %in% countries(), as.character(input$year) %in% as.character(years()))
      list(country = input$country, year = input$year, metric = input$metric, scope = input$scope, unit = input$unit, dimension = input$dimension, partner = optional(input$partner), sector = optional(input$sector))
    })
    snapshot_for <- function(dimension = NULL, partner = TRUE) {
      selected <- selection()
      if (!is.null(dimension)) selected$dimension <- dimension
      if (!partner) selected$partner <- NULL
      needed <- selected$dimension == "sector" || !is.null(selected$sector)
      if (needed && is.null(detail())) return(NULL)
      do.call(wlv_trade_snapshot, c(list(data = bilateral(), detail = if (needed) detail() else NULL), selected))
    }
    rows <- shiny::reactive(safe(snapshot_for()))
    totals <- shiny::reactive(safe(snapshot_for("partner")))
    annotate <- function(values, dimension = input$dimension) {
      if (is.null(values)) return(data.frame(id = character(), label = character(), value = numeric(), outgoing = numeric(), incoming = numeric()))
      values$label <- if (identical(dimension, "sector")) sector_label(values$id) else country_label(values$id)
      values
    }
    plot_rows <- shiny::reactive(annotate(rows()))
    unit_label <- shiny::reactive(tr(if (identical(input$unit, "value")) "value" else if (identical(input$metric, "transfer")) "usd_transfer" else "usd_trade"))
    context_title <- shiny::reactive({
      selected <- selection()
      paste(c(tr(selected$metric), country_label(selected$country), if (!is.null(selected$partner)) country_label(selected$partner), if (!is.null(selected$sector)) sector_label(selected$sector)), collapse = " · ")
    })
    output$context <- shiny::renderUI({
      selected <- selection()
      shiny::div(class = "wlv-trade-context", shiny::h2(context_title()), shiny::p(paste(input$method, selected$year, tr(selected$scope), unit_label(), sep = " · ")))
    })
    output$summary <- shiny::renderUI({
      values <- totals(); shiny::req(!is.null(values))
      net <- wlv_trade_total(values$value); out <- wlv_trade_total(values$outgoing); inc <- wlv_trade_total(values$incoming)
      transfer <- identical(input$metric, "transfer")
      card <- function(name, number, hero = FALSE, note = NULL) {
        sign <- if (!is.finite(number) || number == 0) "neutral" else if (number > 0) "positive" else "negative"
        shiny::div(class = paste("wlv-trade-stat", if (hero) "wlv-trade-stat-main", paste0("is-", sign)),
          shiny::span(class = "wlv-trade-stat-label", name), shiny::strong(wlv_trade_number(number, lang())),
          shiny::span(class = "wlv-trade-stat-unit", unit_label()), if (!is.null(note)) shiny::span(class = "wlv-trade-stat-note", note))
      }
      note <- if (transfer && is.finite(net)) tr(if (net > 0) "gain" else if (net < 0) "loss" else "zero") else NULL
      shiny::div(class = "wlv-trade-summary", card(tr(if (transfer) "net" else "selected_value"), net, TRUE, note),
        card(tr(if (transfer) "outgoing" else "exports"), out), card(tr(if (transfer) "incoming" else "imports"), if (transfer) -inc else inc))
    })
    output$status <- shiny::renderUI({
      selected <- selection(); values <- rows()
      detail_years()
      message <- if (!is.null(error())) tr("data_error") else if (is.null(values)) tr("detail_missing") else if (!any(is.finite(values$value))) tr("empty") else if (any(values$coverage != "complete")) tr("partial") else NULL
      version <- store$info()$version
      if (!is.null(restore("version")) && !is.null(version) && !identical(restore("version"), version)) message <- c(message, tr("version_changed"))
      if (length(message)) shiny::p(class = "wlv-trade-status", role = "status", paste(message, collapse = " "))
    })
    output$rank <- plotly::renderPlotly({
      shiny::req(active()); wlv_trade_rank_chart(plot_rows(), unit_label(), paste(tr(if (input$dimension == "sector") "sectors" else "partners"), input$year, sep = " · "), lang(), source = session$ns("rank"), metric = input$metric, show_title = FALSE)
    })
    output$composition <- plotly::renderPlotly({
      shiny::req(active()); wlv_trade_composition_chart(plot_rows(), unit_label(), paste(tr("composition"), input$year, sep = " · "), lang(), source = session$ns("composition"), metric = input$metric, show_title = FALSE)
    })
    series_data <- shiny::reactive({
      shiny::req(active(), bilateral(), input$country, input$metric, input$scope, input$unit)
      failures[startsWith(as.character(names(failures)), "series:")] <<- NULL
      error(if (length(failures)) unname(failures[[1L]]) else NULL)
      arguments <- list(country = input$country, metric = input$metric, scope = input$scope, unit = input$unit, partner = optional(input$partner))
      if (is.null(optional(input$sector))) {
        result <- safe(do.call(wlv_trade_series, c(list(data = bilateral()), arguments)), data.frame())
        available <- as.integer(years())
        if (nrow(result) && length(available)) result <- result[result$year >= min(available) & result$year <= max(available), , drop = FALSE]
        return(result)
      }
      available <- intersect(as.character(years()), as.character(detail_years()))
      if (!length(available)) return(data.frame())
      result <- lapply(available, function(year) {
        part <- safe(store$detail(input$method, year), key = paste0("series:", year))
        if (is.null(part)) return(data.frame(year = as.integer(year), value = NA_real_, outgoing = NA_real_, incoming = NA_real_, coverage = "missing"))
        values <- do.call(wlv_trade_snapshot, c(list(data = bilateral(), detail = part, year = as.integer(year), dimension = "partner", sector = input$sector), arguments))
        data.frame(year = as.integer(year), value = wlv_trade_total(values$value), outgoing = wlv_trade_total(values$outgoing), incoming = wlv_trade_total(values$incoming), coverage = if (!nrow(values)) "missing" else if (all(values$coverage == "complete")) "complete" else "partial")
      })
      do.call(rbind, result)
    })
    output$series <- plotly::renderPlotly({
      shiny::req(active()); wlv_trade_series_chart(series_data(), unit_label(), tr("series"), lang(), source = session$ns("series"), metric = input$metric, show_title = FALSE)
    })
    select_item <- function(id, dimension = input$dimension) {
      if (length(id) != 1L || is.na(id) || !nzchar(id)) return()
      if (identical(dimension, "partner") && id %in% setdiff(countries(), input$country)) {
        shiny::updateSelectizeInput(session, "partner", selected = id)
        if (!is.null(detail())) shiny::updateRadioButtons(session, "dimension", selected = "sector")
      } else if (identical(dimension, "sector") && id %in% plot_rows()$id) {
        shiny::updateSelectizeInput(session, "sector", selected = id)
        shiny::updateSelectizeInput(session, "partner", selected = "")
        shiny::updateRadioButtons(session, "dimension", selected = "partner")
      }
    }
    lapply(c("rank", "composition"), function(view) {
      shiny::observeEvent(plotly::event_data("plotly_click", source = session$ns(view)), {
        shiny::req(active(), input$view == view)
        event <- plotly::event_data("plotly_click", source = session$ns(view))
        if (!is.null(event$customdata)) select_item(as.character(event$customdata[[1L]]))
      }, ignoreInit = TRUE)
    })
    output$table <- DT::renderDT({
      shiny::req(active()); values <- plot_rows()
      shiny::validate(shiny::need(nrow(values), tr("empty")))
      shown <- data.frame(values$label, values$value, values$outgoing, if (identical(input$metric, "transfer")) -values$incoming else values$incoming)
      names(shown) <- c(tr(if (input$dimension == "sector") "sector" else "partner"), tr(input$metric), tr(if (input$metric == "transfer") "outgoing" else "exports"), tr(if (input$metric == "transfer") "incoming" else "imports"))
      DT::formatRound(DT::datatable(shown, rownames = FALSE, selection = "single", escape = TRUE,
        options = list(pageLength = 15, scrollX = TRUE, dom = "tip", order = list(list(1, "desc")), language = list(emptyTable = tr("empty"), info = wlv_tr("_START_–_END_ de _TOTAL_", "_START_–_END_ of _TOTAL_", lang()), paginate = list(previous = "‹", `next` = "›")))), columns = 2:4, digits = 2, mark = wlv_number_marks(lang())$grouping, dec.mark = wlv_number_marks(lang())$decimal)
    }, server = FALSE)
    shiny::observeEvent(input$table_rows_selected, {
      i <- input$table_rows_selected
      if (length(i) == 1L && i <= nrow(plot_rows())) select_item(plot_rows()$id[[i]])
    })
    polygons <- NULL
    flow_caption <- shiny::reactiveVal("")
    output$flow_caption <- shiny::renderText(flow_caption())
    output$map <- leaflet::renderLeaflet({
      shiny::req(shiny::isolate(active()))
      polygons <<- data$polygons[[1L]]
      if (length(data$polygons) > 1L) for (i in 2:length(data$polygons)) {
        extra <- data$polygons[[i]]; keep <- !as.character(extra@data$ISO3) %in% as.character(polygons@data$ISO3)
        if (any(keep)) polygons <<- rbind(polygons, extra[keep, ], makeUniqueIDs = TRUE)
      }
      widget <- leaflet::leaflet(options = leaflet::leafletOptions(mapFactory = htmlwidgets::JS("function(el,options){options.crs=WLVEqualEarth.install(L);return L.map(el,options);}"), minZoom = -2, maxZoom = 10, zoomSnap = 0, worldCopyJump = FALSE, preferCanvas = TRUE, trackResize = FALSE, doubleClickZoom = FALSE))
      widget <- leaflet::setView(widget, 0, 0, 0)
      widget <- leaflet::addMapPane(widget, "wlv-trade-polygons", zIndex = 400)
      widget <- leaflet::addPolygons(widget, data = polygons, layerId = as.character(polygons@data$ISO3), fillColor = "#d9dce0", fillOpacity = .8, color = "#ffffff", weight = .6, options = leaflet::pathOptions(pane = "wlv-trade-polygons"))
      htmlwidgets::onRender(widget, "function(el,x){this.attributionControl.addAttribution('Natural Earth / rworldmap · Equal Earth');WLVTrade.attach(el,this);}")
    })
    shiny::observe({
      shiny::req(active(), input$view == "map", input$map_ready, !is.null(polygons))
      values <- safe(snapshot_for("partner"))
      codes <- as.character(polygons@data$ISO3)
      numbers <- if (is.null(values)) rep(NA_real_, length(codes)) else values$value[match(codes, values$id)]
      finite <- numbers[is.finite(numbers)]; limit <- if (length(finite)) max(abs(finite)) else 1
      if (!is.finite(limit) || limit == 0) limit <- 1
      signed <- input$metric %in% c("transfer", "balance") || any(finite < 0)
      palette <- leaflet::colorNumeric(if (signed) c("#8D2028", "#faf7ee", "#b37b15") else c("#faf7ee", "#b37b15"), domain = if (signed) c(-limit, limit) else c(0, limit), na.color = "#d9dce0")
      payload <- lapply(seq_along(codes), function(i) list(color = if (codes[[i]] == input$country) "#354a58" else palette(numbers[[i]]), missing = codes[[i]] != input$country && !is.finite(numbers[[i]]), label = paste0("<strong>", htmltools::htmlEscape(country_label(codes[[i]])), "</strong><br>", htmltools::htmlEscape(if (codes[[i]] == input$country) tr("country") else paste(wlv_trade_number(numbers[[i]], lang()), unit_label())), "<br>", htmltools::htmlEscape(paste(input$method, input$year, sep = " · ")))))
      names(payload) <- codes
      flow_payload <- list(rows = list(), enabled = FALSE)
      caption <- ""
      if (identical(input$metric, "transfer") && isTRUE(input$map_flows) && !is.null(values)) {
        coordinates <- sp::coordinates(polygons)
        flows <- wlv_trade_map_flows(values, input$country,
          data.frame(id = codes, lng = coordinates[, 1L], lat = coordinates[, 2L]),
          partner = optional(input$partner))
        flow_payload$enabled <- TRUE
        if (nrow(flows)) {
          flows$label <- vapply(seq_len(nrow(flows)), function(i) paste0(
            "<strong>", htmltools::htmlEscape(paste(country_label(flows$from[[i]]), "→", country_label(flows$to[[i]]))), "</strong><br>",
            htmltools::htmlEscape(paste(wlv_trade_number(flows$amount[[i]], lang()), unit_label())), "<br>",
            htmltools::htmlEscape(paste(input$method, input$year, sep = " · "))), character(1L))
          flow_payload$rows <- lapply(seq_len(nrow(flows)), function(i) as.list(flows[i, , drop = FALSE]))
          caption <- paste0(nrow(flows), " ", tr(if (attr(flows, "omitted") > 0L) "flow_top" else if (nrow(flows) == 1L) "flow_one" else "flow_shown"))
        } else caption <- tr("flow_empty")
      }
      flow_caption(caption)
      session$sendCustomMessage("wlvTradeMap", list(id = session$ns("map"), countries = payload, label = tr("map"), flows = flow_payload))
      proxy <- leaflet::removeControl(leaflet::leafletProxy("map", session), "trade-legend")
      if (length(finite)) leaflet::addLegend(proxy, layerId = "trade-legend", position = "bottomleft", pal = palette, values = if (signed) c(-limit, limit) else c(0, limit), title = htmltools::htmlEscape(unit_label()), labFormat = function(type, cuts, p) vapply(cuts, wlv_trade_number, character(1L), lang = lang()))
    })
    shiny::observeEvent(input$map_shape_click, select_item(input$map_shape_click$id, "partner"))
    export_frame <- function(values, provenance = store$info()) {
      shiny::req(!is.null(values), nrow(values))
      values$method <- input$method; values$country <- input$country; values$country_name <- country_label(input$country)
      values$selected_partner <- if (is.null(optional(input$partner))) "" else input$partner
      values$selected_sector <- if (is.null(optional(input$sector))) "" else input$sector
      values$metric <- input$metric; values$scope <- input$scope; values$unit <- unit_label()
      values$sign_convention <- switch(input$metric, transfer = "outgoing_minus_incoming; positive_receipt_for_focal_country", balance = "outgoing_minus_incoming; positive_trade_surplus", exports = "outgoing", imports = "incoming")
      values$export_contribution <- values$outgoing
      values$import_contribution <- if (input$metric %in% c("transfer", "balance")) -values$incoming else values$incoming
      values$data_version <- if (is.null(provenance$version)) "bilateral" else provenance$version
      values
    }
    workbook_request <- function(values, kind) {
      selected <- selection(); selected$method <- input$method
      context <- list(title = context_title(), unit_label = unit_label(), country_label = country_label(input$country),
        partner_label = if (is.null(selected$partner)) tr("all_partners") else country_label(selected$partner),
        sector_label = if (is.null(selected$sector)) tr("all_sectors") else sector_label(selected$sector))
      info <- store$info()
      list(filename = if (identical(kind, "series"))
          paste0("WLVD-trade-", selected$country, "-", selected$method, "-series.xlsx") else
          paste0("WLVD-trade-", selected$country, "-", selected$method, "-", selected$year, ".xlsx"),
        rows = export_frame(values, info), selection = selected, context = context,
        lang = lang(), provenance = info, kind = kind,
        analytics = list(kind = paste0("trade_", kind), format = "xlsx",
          method = selected$method, country = selected$country, partner = selected$partner,
          sector = selected$sector, indicator = paste(selected$metric, selected$scope, selected$unit, sep = "."),
          years = if (identical(kind, "series")) unique(values$year) else selected$year))
    }
    write_request <- function(request, file) {
      wlv_write_trade_xlsx(file, rows = request$rows, selection = request$selection, context = request$context,
        lang = request$lang, provenance = request$provenance, kind = request$kind)
    }
    write_workbook <- function(file, values, kind) {
      write_request(workbook_request(values, kind), file)
    }
    xlsx_type <- "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    selection_callbacks <- wlv_download_callbacks(function() workbook_request(plot_rows(), "selection"), writer = write_request)
    series_callbacks <- wlv_download_callbacks(function() workbook_request(series_data(), "series"), writer = write_request)
    output$download <- shiny::downloadHandler(filename = selection_callbacks$filename,
      contentType = xlsx_type, content = selection_callbacks$content)
    output$download_series <- shiny::downloadHandler(filename = series_callbacks$filename,
      contentType = xlsx_type, content = series_callbacks$content)
    output$provenance <- shiny::renderText({
      available <- as.integer(years()); shiny::req(length(available))
      paste(tr("source"), input$method, paste0(tr("periods"), ": ", min(available), "–", max(available)), sep = " · ")
    })
    shiny::observe({
      selected <- selection(); selected$method <- input$method; selected$view <- input$view
      detail_years()
      selected$version <- store$info()$version
      session$sendCustomMessage("wlvTradeState", list(id = session$ns("app"), state = selected, lang = lang()))
      if (!restored) {
        restored <<- TRUE
        view <- restore("view", "rank")
        if (view %in% c("rank", "composition", "map", "series", "table")) shiny::updateTabsetPanel(session, "view", selected = view)
      }
    })
    list(rows = rows, totals = totals, series = series_data, store = store, selection = selection)
  })
}

if (exists("modules_ui", inherits = FALSE) && exists("modules_server", inherits = FALSE)) {
  language_file["tab_name.trade", c("Português", "English")] <- c("Comércio", "Trade")
  wlv_trade_store <- wlv_trade_data_store()
  wlv_trade_assets <- shiny::tagList(htmltools::includeCSS("www/wlv-trade.css"), htmltools::includeScript("www/wlv-trade.js"))
  modules_ui[[length(modules_ui) + 1L]] <- shiny::tabPanel(l("tab_name.trade"), value = "trade", shiny::uiOutput("trade_mount"))
  SERVER <- function(IP, OP, RV, SESSION) {
    mounted <- FALSE
    shiny::observeEvent(IP$main_nav, {
      if (!identical(IP$main_nav, "trade") || mounted) return()
      mounted <<- TRUE
      trade_server("trade", wlv_trade_store, data = list(language = language_file, methods = meta_methods, polygons = countries_sp),
        lang = shiny::reactive(wlv_language_code(IP$l)), bases = RV$bases,
        active = shiny::reactive(identical(IP$main_nav, "trade")))
      OP$trade_mount <- shiny::renderUI(trade_ui("trade", wlv_trade_assets))
    }, ignoreInit = FALSE)
  }
  modules_server[[length(modules_server) + 1L]] <- SERVER
}
