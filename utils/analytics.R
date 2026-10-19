# Configuração pública e opcional. Credenciais do Matomo nunca entram no HTML.
wlv_read_analytics_config <- function(path = Sys.getenv("WLV_ANALYTICS_CONFIG", "")) {
  disabled <- list(enabled = FALSE)
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) return(disabled)
  tryCatch({
    info <- file.info(path)
    if (is.na(info$size) || info$isdir || info$size > 16384) stop("arquivo inválido")
    value <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    if (!is.list(value) || !isTRUE(value$enabled)) return(disabled)
    scalar_id <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x) &&
      x == floor(x) && x >= 1 && x <= 1000000
    endpoint <- function(x, basename) is.character(x) && length(x) == 1L &&
      !is.na(x) && identical(x, paste0("/estatisticas/", basename))
    if (!scalar_id(value$site_id) || !endpoint(value$tracker_url, "matomo.php") ||
        !endpoint(value$script_url, "matomo.js")) stop("site ou endereço inválido")
    dimensions <- value$dimensions
    if (is.null(dimensions)) dimensions <- list()
    allowed <- c("kind", "format", "method", "country", "partner", "indicator", "years", "sector", "release", "filename")
    if (!is.list(dimensions) || length(setdiff(names(dimensions), allowed)) ||
        (length(dimensions) && (is.null(names(dimensions)) || anyDuplicated(names(dimensions)) ||
          !all(vapply(dimensions, scalar_id, logical(1L))) || anyDuplicated(unlist(dimensions))))) {
      stop("dimensões inválidas")
    }
    release <- value$release
    if (is.null(release)) release <- ""
    if (!is.character(release) || length(release) != 1L || is.na(release) ||
        !grepl("^[A-Za-z0-9._-]{0,128}$", release)) stop("versão inválida")
    list(enabled = TRUE, site_id = as.integer(value$site_id), release = release,
         tracker_url = value$tracker_url, script_url = value$script_url,
         dimensions = dimensions)
  }, error = function(e) {
    warning("Estatísticas desativadas: a configuração pública é inválida ou não pode ser lida.", call. = FALSE)
    disabled
  })
}

wlv_analytics_head <- function(config) {
  json <- jsonlite::toJSON(config, auto_unbox = TRUE, null = "null")
  json <- gsub("<", "\\u003c", json, fixed = TRUE)
  shiny::tags$script(id = "wlv-analytics-config", type = "application/json", shiny::HTML(json))
}

wlv_analytics_privacy_button <- function(id = "wlv-privacy-open", class = "wlv-privacy-link") {
  shiny::tags$button(id = id, class = class, type = "button", `aria-haspopup` = "dialog",
    `aria-controls` = "wlv-privacy-dialog",
    shiny::tags$span(`data-wlv-label` = "analytics.link", lb("analytics.link")))
}

wlv_analytics_privacy_ui <- function() {
  label <- function(key) shiny::tags$span(`data-wlv-label` = paste0("analytics.", key), lb(paste0("analytics.", key)))
  shiny::tags$dialog(id = "wlv-privacy-dialog", class = "wlv-privacy-dialog",
      `aria-labelledby` = "wlv-privacy-title", `aria-describedby` = "wlv-privacy-summary",
      shiny::tags$h2(id = "wlv-privacy-title", label("link")),
      shiny::tags$p(id = "wlv-privacy-summary", label("summary")),
      shiny::tags$p(label("timing")),
      shiny::tags$p(label("retention")),
      shiny::tags$p(label("choice")),
      shiny::tags$p(class = "wlv-privacy-status", role = "status", `aria-live` = "polite",
        shiny::tags$span(`data-analytics-status` = "enabled", hidden = NA, label("enabled")),
        shiny::tags$span(`data-analytics-status` = "optout", hidden = NA, label("optout")),
        shiny::tags$span(`data-analytics-status` = "browser", hidden = NA, label("browser")),
        shiny::tags$span(`data-analytics-status` = "unavailable", label("unavailable"))),
      shiny::tags$p(label("technical")),
      shiny::tags$div(class = "wlv-privacy-actions",
        shiny::tags$button(id = "wlv-privacy-toggle", type = "button", class = "btn btn-default",
          shiny::tags$span(`data-analytics-choice` = "disable", label("disable")),
          shiny::tags$span(`data-analytics-choice` = "enable", hidden = NA, label("enable"))),
        shiny::tags$button(id = "wlv-privacy-close", type = "button", class = "btn btn-primary", label("close")))
  )
}
