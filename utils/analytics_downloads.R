# Eventos técnicos de exportação, sem identificador de visitante e sem HTTP no R.
# Falhas de telemetria nunca interferem no arquivo nem no erro do exportador.
wlv_analytics_download_safe <- function(expression, fallback = NULL) {
  tryCatch(withCallingHandlers(expression, warning = function(warning) {
    invokeRestart("muffleWarning")
  }), error = function(error) fallback)
}

wlv_analytics_download_codes <- function(value, limit = 255L) {
  if (!(is.character(value) || is.numeric(value)) || length(value) > 100L) return("")
  value <- unique(as.character(value))
  value <- value[!is.na(value) & nzchar(value)]
  if (!length(value) || any(!grepl("^[A-Za-z0-9_.:-]+$", value))) return("")
  value <- paste(value, collapse = ",")
  if (nchar(value, type = "bytes") > limit) "" else value
}

wlv_analytics_download_payload <- function(metadata, event_id, status, release = "") {
  if (!is.list(metadata)) metadata <- list()
  scalar <- function(value, pattern, limit) {
    if (!is.character(value) || length(value) != 1L || is.na(value) ||
        nchar(value, type = "bytes") > limit || !grepl(pattern, value)) return("")
    value
  }
  kind <- scalar(metadata$kind, "^[a-z_]+$", 32L)
  if (!kind %in% c("aggregate", "bilateral", "multilateral", "indicators_csv",
      "trade_selection", "trade_series", "download")) kind <- "download"
  format <- scalar(metadata$format, "^(csv|xlsx)$", 4L)
  years <- metadata$years
  if (is.numeric(years) || is.character(years)) {
    years <- unique(as.character(years))
    years <- years[!is.na(years) & grepl("^[12][0-9]{3}$", years)]
    years <- sort(as.integer(years))
    if (length(years) > 1L && all(diff(years) == 1L)) {
      years <- paste(range(years), collapse = "-")
    }
  } else years <- character()
  list(event_id = scalar(event_id, "^[A-Za-z0-9_-]+$", 96L),
    status = if (status %in% c("requested", "generated", "failed")) status else "failed",
    kind = kind,
    filename = scalar(metadata$filename, "^[A-Za-z0-9][A-Za-z0-9_.-]*$", 180L),
    format = format, method = wlv_analytics_download_codes(metadata$method),
    country = wlv_analytics_download_codes(metadata$country),
    partner = wlv_analytics_download_codes(metadata$partner),
    indicator = wlv_analytics_download_codes(metadata$indicator),
    years = wlv_analytics_download_codes(years),
    sector = wlv_analytics_download_codes(metadata$sector),
    release = scalar(release, "^[A-Za-z0-9_.-]*$", 128L))
}

wlv_analytics_download_bind <- function(input, session, config) {
  session$userData$wlv_analytics_download <- function(metadata, event_id, status) {
    wlv_analytics_download_safe({
      settings <- if (is.function(config)) config() else config
      if (!isTRUE(settings$enabled) ||
          !isTRUE(shiny::isolate(input$wlv_analytics_enabled))) return(invisible(FALSE))
      payload <- wlv_analytics_download_payload(metadata, event_id, status,
        release = settings$release)
      session$sendCustomMessage("wlv-analytics-download", payload)
      invisible(TRUE)
    }, fallback = FALSE)
  }
  invisible(NULL)
}

wlv_analytics_download_emitter <- function(session = shiny::getDefaultReactiveDomain()) {
  wlv_analytics_download_safe({
    if (is.null(session)) return(NULL)
    emitter <- session$userData$wlv_analytics_download
    if (is.function(emitter)) emitter else NULL
  })
}

# O ID identifica somente esta requisição; não usa RNG, cookie, IP ou token Shiny.
# O navegador usa o ID para deduplicar em memória e não o envia ao Matomo.
wlv_analytics_download_id <- local({
  sequence <- 0
  function() {
    sequence <<- sequence + 1
    paste0("download-", Sys.getpid(), "-",
      gsub("[^0-9]", "", format(Sys.time(), "%Y%m%d%H%M%OS6", tz = "UTC")),
      "-", format(sequence, scientific = FALSE, trim = TRUE))
  }
})

wlv_analytics_download_events <- function(emit = wlv_analytics_download_emitter()) {
  event_id <- wlv_analytics_download_id()
  metadata <- list()
  started <- FALSE
  finished <- FALSE
  send <- function(status) {
    if (is.function(emit)) wlv_analytics_download_safe(emit(metadata, event_id, status))
    invisible(NULL)
  }
  requested <- function(request = NULL) {
    if (started) return(invisible(NULL))
    if (is.list(request)) {
      metadata <<- if (is.list(request$analytics)) request$analytics else list()
      metadata$filename <<- request$filename
      if (is.null(metadata$format) && is.character(request$filename)) {
        metadata$format <<- tolower(tools::file_ext(request$filename))
      }
    }
    started <<- TRUE
    send("requested")
  }
  finish <- function(status) {
    if (finished) return(invisible(NULL))
    requested()
    finished <<- TRUE
    send(status)
  }
  list(requested = requested, failed = function() finish("failed"),
    generated = function(file) {
      # Arquivo escrito com êxito; não comprova salvamento no dispositivo.
      info <- file.info(file)
      valid <- nrow(info) == 1L && !is.na(info$size) && !is.na(info$isdir) &&
        !info$isdir && info$size > 0
      finish(if (valid) "generated" else "failed")
    })
}
