analytics_download_api <- function() {
  root <- normalizePath(if (file.exists("utils/analytics_downloads.R")) "." else "../..")
  api <- new.env(parent = globalenv())
  api$source <- function(file, local = api, ...) {
    path <- if (file.exists(file)) file else file.path(root, file)
    base::source(path, local = api, ...)
  }
  for (helper in c("i18n", "display_contracts", "download_workbooks", "download_requests", "analytics_downloads")) {
    base::source(file.path(root, "utils", paste0(helper, ".R")), local = api, encoding = "UTF-8")
  }
  api$root <- root
  api
}

testthat::test_that("telemetria exige configuração habilitada e preferência inicializada como true", {
  api <- analytics_download_api()
  messages <- list()
  mock <- shiny::MockShinySession$new()
  mock$sendCustomMessage <- function(type, message) {
    messages[[length(messages) + 1L]] <<- list(type = type, message = message)
  }
  config <- list2env(list(enabled = TRUE, release = "release-test"))
  shiny::testServer(function(input, output, session) {
    api$wlv_analytics_download_bind(input, session, function() config)
  }, session = mock, {
    emit <- api$wlv_analytics_download_emitter(session)
    send <- function() emit(list(kind = "aggregate", filename = "BRA.WIOD16.xlsx", format = "xlsx"), "request-1", "requested")
    send()
    session$setInputs(wlv_analytics_enabled = FALSE); send()
    session$setInputs(wlv_analytics_enabled = "true"); send()
    testthat::expect_length(messages, 0L)
    session$setInputs(wlv_analytics_enabled = TRUE); send()
    testthat::expect_length(messages, 1L)
    testthat::expect_identical(messages[[1L]]$type, "wlv-analytics-download")
    testthat::expect_identical(messages[[1L]]$message$release, "release-test")
    child <- session$makeScope("child")
    testthat::expect_identical(api$wlv_analytics_download_emitter(child), emit)
    config$enabled <- FALSE; send()
    testthat::expect_length(messages, 1L)
    config$enabled <- TRUE
    session$setInputs(wlv_analytics_enabled = FALSE); send()
    testthat::expect_length(messages, 1L)
  })
})

testthat::test_that("somente códigos públicos com tamanho limitado entram na mensagem", {
  api <- analytics_download_api()
  payload <- api$wlv_analytics_download_payload(list(kind = "trade_selection",
    filename = "WLVD-trade-BRA-WIOD16-2007.xlsx", format = "xlsx", method = "WIOD16",
    country = c("BRA", "CHN", "BRA"), partner = "USA", indicator = "transfer.total.value",
    sector = "23", years = c(2007, 2005, 2006), token = "private", ip = "192.0.2.1",
    rows = data.frame(private = 1)), "request-1", "generated", "release-test")
  testthat::expect_identical(names(payload), c("event_id", "status", "kind", "filename", "format",
    "method", "country", "partner", "indicator", "years", "sector", "release"))
  testthat::expect_identical(payload$country, "BRA,CHN")
  testthat::expect_identical(payload$years, "2005-2007")
  testthat::expect_false(any(grepl("private|192\\.0", unlist(payload))))
  rejected <- api$wlv_analytics_download_payload(list(kind = "unknown", format = "exe",
    filename = "/private/session/token.xlsx", method = list(token = "private"),
    country = paste(rep("A", 300L), collapse = ""), partner = "https://private/?token=1",
    indicator = "<script>", sector = TRUE, years = list(ip = "192.0.2.1")), "request-1", "requested", "/private/path")
  testthat::expect_identical(rejected$kind, "download")
  testthat::expect_true(all(unlist(rejected[c("format", "filename", "method", "country", "partner", "indicator", "years", "sector", "release")]) == ""))
  testthat::expect_identical(api$wlv_analytics_download_payload(list(years = c(1995, 1997)),
    "request-2", "requested")$years, "1995,1997")
})

testthat::test_that("chamadas repetidas de filename compartilham requisição, bytes e seleção", {
  api <- analytics_download_api()
  sent <- list()
  api$wlv_analytics_download_emitter <- function(...) function(metadata, event_id, status) {
    sent[[length(sent) + 1L]] <<- c(list(event_id = event_id, status = status), metadata)
  }
  selected <- list(filename = "BRA.WIOD16.csv", data = data.frame(country = "BRA", value = 12345678901.125),
    analytics = list(kind = "indicators_csv", method = "WIOD16", country = "BRA", years = 2007))
  request_count <- 0L
  writer <- function(request, file) {
    utils::write.csv(request$data, file, row.names = FALSE, na = "", fileEncoding = "UTF-8")
    invisible("same-return")
  }
  files <- c(tempfile(fileext = ".csv"), tempfile(fileext = ".csv"))
  on.exit(unlink(files), add = TRUE)
  writer(selected, files[[1L]])
  callbacks <- api$wlv_download_callbacks(function() { request_count <<- request_count + 1L; selected }, writer)
  testthat::expect_identical(callbacks$filename(), "BRA.WIOD16.csv")
  testthat::expect_identical(callbacks$filename(), "BRA.WIOD16.csv")
  selected$filename <- "CHN.WIOD13.csv"; selected$data$value <- 0; selected$analytics$country <- "CHN"
  testthat::expect_identical(withVisible(callbacks$content(files[[2L]])), list(value = "same-return", visible = FALSE))
  testthat::expect_identical(readBin(files[[1L]], "raw", n = file.info(files[[1L]])$size),
    readBin(files[[2L]], "raw", n = file.info(files[[2L]])$size))
  testthat::expect_identical(request_count, 1L)
  testthat::expect_identical(vapply(sent, `[[`, "", "status"), c("requested", "generated"))
  testthat::expect_identical(sent[[1L]]$event_id, sent[[2L]]$event_id)
  testthat::expect_identical(sent[[2L]]$country, "BRA")
  callbacks$content(files[[2L]])
  testthat::expect_identical(request_count, 2L)
  testthat::expect_false(identical(sent[[1L]]$event_id, sent[[3L]]$event_id))
  testthat::expect_identical(sent[[4L]]$country, "CHN")
})

testthat::test_that("erros originais são relançados e a telemetria não pode interromper exportações", {
  api <- analytics_download_api()
  sent <- character()
  api$wlv_analytics_download_emitter <- function(...) function(metadata, event_id, status) sent <<- c(sent, status)
  failure <- structure(list(message = "Original exporter failure", call = NULL, marker = "kept"), class = c("export_failure", "error", "condition"))
  request <- function() list(filename = "test.xlsx", analytics = list(kind = "aggregate"))
  callbacks <- api$wlv_download_callbacks(request, function(...) stop(failure))
  testthat::expect_identical(tryCatch(callbacks$content(tempfile()), error = identity), failure)
  testthat::expect_identical(sent, c("requested", "failed"))
  sent <- character()
  callbacks <- api$wlv_download_callbacks(function() stop(failure))
  testthat::expect_identical(tryCatch(callbacks$filename(), error = identity), failure)
  testthat::expect_identical(sent, c("requested", "failed"))
  api$wlv_analytics_download_emitter <- function(...) function(...) stop("Telemetry is offline")
  file <- tempfile(); on.exit(unlink(file), add = TRUE)
  callbacks <- api$wlv_download_callbacks(request, function(request, file) { writeBin(as.raw(1:8), file); "ok" })
  testthat::expect_identical(callbacks$content(file), "ok")
  testthat::expect_identical(readBin(file, "raw", n = 8), as.raw(1:8))
})

testthat::test_that("geração bem-sucedida exige arquivo não vazio e encerra a requisição uma só vez", {
  api <- analytics_download_api()
  sent <- character()
  emit <- function(metadata, event_id, status) sent <<- c(sent, status)
  event <- api$wlv_analytics_download_events(emit)
  event$requested(list(filename = "test.xlsx")); event$generated(tempfile()); event$failed()
  testthat::expect_identical(sent, c("requested", "failed"))
  sent <- character()
  file <- tempfile(); on.exit(unlink(file), add = TRUE)
  file.create(file)
  event <- api$wlv_analytics_download_events(emit); event$generated(file)
  testthat::expect_identical(sent, c("requested", "failed"))
})

testthat::test_that("metadados agregados e bilaterais acompanham as seleções esparsas exportadas", {
  api <- analytics_download_api()
  countries <- array(NA_real_, c(1L, 3L, 2L, 2L),
    dimnames = list("WIOD16", c("2000", "2001", "2002"), c("ratio", "output"), c("BRA", "CHN")))
  countries[, c("2000", "2002"), , ] <- 0
  sectors <- list(WIOD16 = array(1, c(2L, 2L, 1L, 2L),
    dimnames = list(c("2000", "2002"), c("ratio", "output"), "23", c("BRA", "CHN"))))
  methods <- data.frame(code = "WIOD16", name = "WIOD 2016", source = "WIOD16")
  language <- matrix("", 0L, 1L, dimnames = list(character(), "English"))
  for (selection in list(list(country = "BRA"), list(indicator = "ratio"),
      list(country = "BRA", indicator = "ratio"), list(country = "BRA", sector = "23"),
      list(indicator = "ratio", sector = "23"))) {
    request <- do.call(api$wlv_aggregated_download_request, c(selection,
      list(method = "WIOD16", countries = countries, sectors = sectors, methods = methods,
        language = language, contracts = NULL, metadata = data.frame(value = c("ratio", "output")))))
    testthat::expect_identical(request$analytics$country, selection$country)
    testthat::expect_identical(request$analytics$indicator, selection$indicator)
    testthat::expect_identical(request$analytics$sector, selection$sector)
    testthat::expect_identical(request$analytics$years, colnames(request$data))
  }
  keys <- c("exports_values", "exports_mp", "exports_productive_mp", "transfers_values", "transfers_dp",
    "transfers_productive_values", "transfers_productive_dp")
  values <- array(1, c(2L, 7L, 2L, 2L), dimnames = list(c("2000", "2002"), keys, c("BRA", "CHN"), c("BRA", "CHN")))
  bilateral <- api$wlv_multilateral_download_request("WIOD16", "BRA", "CHN",
    values = list(WIOD16 = values), methods = methods, language = language)
  testthat::expect_identical(bilateral$analytics$kind, "bilateral")
  testthat::expect_identical(bilateral$analytics$partner, "CHN")
  testthat::expect_identical(bilateral$analytics$method, "WIOD16")
  multilateral <- api$wlv_multilateral_download_request("WIOD16", "BRA", category = "CX.", scope = "T.", unit = "MP",
    values = list(WIOD16 = values), methods = methods, language = language)
  testthat::expect_identical(multilateral$analytics$kind, "multilateral")
  testthat::expect_identical(multilateral$analytics$indicator, "CX.T.MP")
  testthat::expect_identical(multilateral$analytics$years, colnames(multilateral$data))
})

testthat::test_that("callbacks reais de Comércio preservam a seleção do clique nas duas exportações", {
  api <- analytics_download_api()
  api$source("modules/trade/main.R", encoding = "UTF-8")
  keys <- c("exports_mp", "exports_productive_mp", "exports_values", "transfers_values",
    "transfers_productive_values", "transfers_dp", "transfers_productive_dp")
  values <- array(1, c(2L, 7L, 2L, 2L),
    dimnames = list(c("2000", "2001"), keys, c("BRA", "CHN"), c("BRA", "CHN")))
  attr(values, "method") <- "TEST"
  store <- list(methods = function() "TEST", bilateral = function(...) values,
    years = function(...) 2000:2001, detail_years = function(...) integer(),
    detail = function(...) NULL, info = function() list(version = "test-v1"))
  language <- matrix(c("Brasil", "China", "Brazil", "China"), 2L,
    dimnames = list(c("ISO3.BRA", "ISO3.CHN"), c("Português", "English")))
  state <- new.env(parent = emptyenv()); state$messages <- list(); state$written <- list()
  mock <- shiny::MockShinySession$new()
  mock$sendCustomMessage <- function(type, message) {
    if (identical(type, "wlv-analytics-download")) state$messages[[length(state$messages) + 1L]] <- message
  }
  api$wlv_analytics_download_bind(mock$input, mock, list(enabled = TRUE, release = "release-test"))
  # Intercepta somente o gravador; seleção e tradução usam o módulo real.
  api$wlv_write_trade_xlsx <- function(file, ...) {
    state$written[[length(state$written) + 1L]] <- list(...)
    writeBin(serialize(list(...), NULL), file)
  }
  language_choice <- shiny::reactiveVal("pt")
  files <- c(tempfile(fileext = ".xlsx"), tempfile(fileext = ".xlsx"))
  on.exit(unlink(files), add = TRUE)
  shiny::testServer(api$trade_server, session = mock,
    args = list(store = store, data = list(language = language,
      methods = data.frame(code = "TEST", source = "test"), polygons = NULL),
      lang = language_choice, bases = shiny::reactiveVal("TEST"), active = shiny::reactiveVal(TRUE)), {
    session$userData$plotlyShinyEventIDs <- paste0("plotly_click-", session$ns(c("rank", "composition")))
    session$rootScope()$setInputs(wlv_analytics_enabled = TRUE)
    session$setInputs(method = "TEST", country = "BRA", year = 2000L, metric = "transfer",
      scope = "total", unit = "value", dimension = "partner", partner = "CHN", sector = "", view = "rank")
    expected_rows <- export_frame(plot_rows())
    testthat::expect_identical(selection_callbacks$filename(), "WLVD-trade-BRA-TEST-2000.xlsx")
    testthat::expect_identical(selection_callbacks$filename(), "WLVD-trade-BRA-TEST-2000.xlsx")
    session$setInputs(country = "CHN", partner = "BRA", year = 2001L)
    language_choice("en"); session$flushReact()
    selection_callbacks$content(files[[1L]])
    testthat::expect_identical(state$written[[1L]]$rows, expected_rows)
    testthat::expect_identical(state$written[[1L]]$selection$country, "BRA")
    testthat::expect_identical(state$written[[1L]]$lang, "pt")
    testthat::expect_identical(state$messages[[2L]]$country, "BRA")
    testthat::expect_identical(state$messages[[2L]]$years, "2000")
    testthat::expect_identical(state$messages[[2L]]$indicator, "transfer.total.value")
    testthat::expect_identical(series_callbacks$filename(), "WLVD-trade-CHN-TEST-series.xlsx")
    session$setInputs(country = "BRA", partner = "CHN")
    series_callbacks$content(files[[2L]])
    testthat::expect_identical(state$written[[2L]]$selection$country, "CHN")
    testthat::expect_identical(state$written[[2L]]$kind, "series")
    testthat::expect_identical(state$messages[[4L]]$kind, "trade_series")
    testthat::expect_identical(state$messages[[4L]]$country, "CHN")
    testthat::expect_identical(state$messages[[4L]]$years, "2000-2001")
    testthat::expect_identical(vapply(state$messages, `[[`, "", "status"),
      c("requested", "generated", "requested", "generated"))
    testthat::expect_identical(readBin(files[[1L]], "raw", n = file.info(files[[1L]])$size),
      serialize(state$written[[1L]], NULL))
  })
})

testthat::test_that("CSV de Indicadores preserva valores traduzidos, nome e filtros da mesma seleção", {
  api <- analytics_download_api()
  api$source("modules/indicators/main.R", encoding = "UTF-8")
  values <- array(seq_len(8L), c(1L, 2L, 2L, 2L),
    dimnames = list("WIOD16", c("2000", "2001"), c("ratio", "output"), c("BRA", "CHN")))
  language <- matrix(c("Razão", "Produto", "Grupo", "Brasil", "China", "Ratio", "Output", "Group", "Brazil", "China"), 5L,
    dimnames = list(c("ratio", "output", "group.test", "ISO3.BRA", "ISO3.CHN"), c("Português", "English")))
  metadata <- data.frame(value = c("ratio", "output"), type = "percent", groups = "test", reverted = FALSE)
  contracts <- data.frame(method_dir = "WIOD16", method = "WIOD16", indicator = c("ratio", "output"),
    canonical_unit = "ratio", display_unit = "percent", display_multiplier = 100,
    index_base_year = NA_character_, index_storage_base = NA_real_, metadata_source = "method_metadata", legacy_type = NA_character_)
  make_polygon <- function(x, id) sp::Polygons(list(sp::Polygon(matrix(
    c(x, 0, x + 1, 0, x + 1, 1, x, 1, x, 0), byrow = TRUE, ncol = 2L))), ID = id)
  polygons <- sp::SpatialPolygons(list(make_polygon(0, "BRA"), make_polygon(2, "CHN")),
    proj4string = sp::CRS("+proj=longlat +datum=WGS84"))
  polygons <- sp::SpatialPolygonsDataFrame(polygons, data.frame(ISO3 = c("BRA", "CHN"), row.names = c("BRA", "CHN")))
  state <- new.env(parent = emptyenv()); state$messages <- list()
  mock <- shiny::MockShinySession$new()
  mock$sendCustomMessage <- function(type, message) {
    if (identical(type, "wlv-analytics-download")) state$messages[[length(state$messages) + 1L]] <- message
  }
  api$wlv_analytics_download_bind(mock$input, mock, list(enabled = TRUE, release = "release-test"))
  language_choice <- shiny::reactiveVal("pt")
  files <- c(tempfile(fileext = ".csv"), tempfile(fileext = ".csv"))
  on.exit(unlink(files), add = TRUE)
  shiny::testServer(api$indicators_server, session = mock,
    args = list(data = list(countries = values, metadata = metadata, language = language,
      contracts = contracts, polygons = list(WIOD16 = polygons)),
      lang = language_choice, bases = shiny::reactiveVal("WIOD16")), {
    session$rootScope()$setInputs(wlv_analytics_enabled = TRUE)
    session$setInputs(indicator = "ratio", methods = "WIOD16", countries = "BRA", year = 2000, map_method = "WIOD16")
    expected <- selected_series(); expected$indicator <- "ratio"; expected$country_name <- "Brasil"
    utils::write.csv(expected, files[[1L]], row.names = FALSE, na = "", fileEncoding = "UTF-8")
    testthat::expect_identical(csv_callbacks$filename(), "WLVD-ratio.csv")
    testthat::expect_identical(csv_callbacks$filename(), "WLVD-ratio.csv")
    session$setInputs(indicator = "output", countries = "CHN")
    language_choice("en"); session$flushReact()
    csv_callbacks$content(files[[2L]])
    testthat::expect_identical(readBin(files[[1L]], "raw", n = file.info(files[[1L]])$size),
      readBin(files[[2L]], "raw", n = file.info(files[[2L]])$size))
    testthat::expect_identical(state$messages[[2L]]$filename, "WLVD-ratio.csv")
    testthat::expect_identical(state$messages[[2L]]$kind, "indicators_csv")
    testthat::expect_identical(state$messages[[2L]]$country, "BRA")
    testthat::expect_identical(state$messages[[2L]]$indicator, "ratio")
    testthat::expect_identical(state$messages[[2L]]$years, "2000-2001")
    testthat::expect_identical(vapply(state$messages, `[[`, "", "status"), c("requested", "generated"))
  })
})
