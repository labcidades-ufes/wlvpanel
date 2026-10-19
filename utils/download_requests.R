# Build one workbook from the canonical arrays only after a download is requested.
# A valid selection no longer depends on thousands of pre-generated XLSX files.
wlv_download_label <- function(language, key, fallback = key, lang = "en") {
  column <- wlv_language_column(lang)
  if (!key %in% rownames(language) || !column %in% colnames(language)) return(fallback)
  value <- as.character(language[key, column])
  if (length(value) == 1L && !is.na(value) && nzchar(value)) value else fallback
}

wlv_download_header <- function(method, language, selected = list(), lang = "en") {
  rows <- lapply(names(selected), function(label) c(paste0(wlv_tr(switch(label, Country = "País", Indicator = "Indicador", Sector = "Setor", Partner = "Parceiro", label), label, lang), ":"), selected[[label]]))
  rows <- c(rows, list(c(wlv_tr("Método de cálculo:", "Computation method:", lang), method$name[[1L]]),
    c(wlv_tr("Fonte principal:", "Main source:", lang), method$source[[1L]])))
  result <- matrix(NA_character_, nrow = 6L, ncol = 2L)
  result[seq_along(rows), ] <- do.call(rbind, rows)
  result[6L, ] <- c(wlv_tr("Nome", "Name", lang), wlv_tr("Código", "Code", lang))
  result
}

# A plan is an immutable selection snapshot. Availability checks need neither a
# transposed export matrix nor translated workbook labels and metadata.
wlv_aggregated_download_plan <- function(method, country = NULL, indicator = NULL,
    sector = NULL, countries, sectors, metadata, methods, contracts) {
  nonempty <- wlv_nonempty_selection
  if (!nonempty(method) || !method %in% dimnames(countries)[[1L]] ||
      !method %in% methods$code) return(NULL)
  sector_countries <- if (method %in% names(sectors)) wlv_sector_country_codes(sectors, method) else character()
  href <- wlv_aggregated_download_href(method, country, indicator, sector, sector_countries)
  if (!nzchar(href)) return(NULL)
  method_row <- methods[methods$code == method, , drop = FALSE]
  public <- intersect(metadata$value, dimnames(countries)[[3L]])
  if (nonempty(indicator) && !indicator %in% public) return(NULL)
  if (nonempty(country) && !country %in% dimnames(countries)[[4L]]) return(NULL)
  selected <- list()
  if (nonempty(country)) selected$Country <- list(key = paste0("ISO3.", country), fallback = country)
  if (nonempty(indicator)) selected$Indicator <- list(key = indicator, fallback = indicator)
  if (nonempty(sector)) selected$Sector <- list(key = paste0(method_row$source[[1L]], ".", sector), fallback = sector)

  if (nonempty(sector) || (nonempty(country) && nonempty(indicator))) {
    if (!method %in% names(sectors)) return(NULL)
    values <- sectors[[method]]
    axes <- dimnames(values)
    if (nonempty(indicator) && !indicator %in% axes[[2L]]) return(NULL)
    if (nonempty(sector) && !sector %in% axes[[3L]]) return(NULL)
    indicators <- if (nonempty(indicator)) indicator else intersect(public, axes[[2L]])
    if (!length(indicators)) return(NULL)
    values <- values[, indicators, if (nonempty(sector)) sector else axes[[3L]],
      if (nonempty(country)) country else axes[[4L]], drop = FALSE]
    row_axis <- if (!nonempty(indicator)) 2L else if (!nonempty(sector)) 3L else 4L
    year_axis <- 1L
    row_prefix <- if (row_axis == 2L) "" else if (row_axis == 3L)
      paste0(method_row$source[[1L]], ".") else "ISO3."
  } else {
    indicators <- if (nonempty(indicator)) indicator else public
    if (!length(indicators)) return(NULL)
    values <- countries[method, , indicators,
      if (nonempty(country)) country else dimnames(countries)[[4L]], drop = FALSE]
    row_axis <- if (nonempty(country)) 3L else 4L
    year_axis <- 2L
    row_prefix <- if (row_axis == 3L) "" else "ISO3."
  }
  if (!wlv_has_observations(values)) return(NULL)
  list(filename = basename(href), values = values, row_axis = row_axis,
    year_axis = year_axis, row_prefix = row_prefix, selected = selected,
    specs = method_row, method = method, indicator = indicator, contracts = contracts)
}

wlv_aggregated_download_data <- function(plan) {
  if (is.null(plan)) return(NULL)
  matrix <- wlv_xlsx_export_matrix(plan$values, plan$row_axis, plan$year_axis)
  observed_rows <- apply(matrix, 1L, wlv_has_observations)
  observed_years <- apply(matrix, 2L, wlv_has_observations)
  if (!any(observed_rows) || !any(observed_years)) return(NULL)
  matrix <- matrix[observed_rows, observed_years, drop = FALSE]
  list(filename = plan$filename, data = matrix,
    row_keys = paste0(plan$row_prefix, rownames(matrix)), selected = plan$selected,
    specs = plan$specs, method = plan$method,
    indicators = if (wlv_nonempty_selection(plan$indicator)) plan$indicator else rownames(matrix),
    contracts = plan$contracts)
}

wlv_aggregated_download_localize <- function(data, language, lang = "en") {
  if (is.null(data)) return(NULL)
  label <- function(code, fallback = code) wlv_download_label(language, code, fallback, lang)
  selected <- lapply(data$selected, function(item) label(item[["key"]], item[["fallback"]]))
  indicators <- data$indicators
  meta <- data.frame(Code = indicators,
    Name = vapply(indicators, label, character(1L)),
    Description = vapply(paste0("desc.", indicators), label, character(1L)),
    Observations = vapply(paste0("obs.", data$method, ".", indicators), label, character(1L)),
    row.names = NULL, stringsAsFactors = FALSE)
  list(filename = data$filename, data = data$data,
    labels = unname(vapply(data$row_keys, label, character(1L))), metadata = meta,
    header = wlv_download_header(data$specs, language, selected, lang), specs = data$specs,
    lang = wlv_language_code(lang), method = data$method,
    indicators = indicators, contracts = data$contracts,
    analytics = list(kind = "aggregate", format = "xlsx", method = data$method,
      country = data$selected$Country$fallback, sector = data$selected$Sector$fallback,
      indicator = data$selected$Indicator$fallback, years = colnames(data$data)))
}

# Preserve the public request API for batch callers and existing integrations.
wlv_aggregated_download_request <- function(method, country = NULL, indicator = NULL,
    sector = NULL, countries, sectors, metadata, methods, language, contracts, lang = "en") {
  plan <- wlv_aggregated_download_plan(method, country, indicator, sector,
    countries, sectors, metadata, methods, contracts)
  wlv_aggregated_download_localize(wlv_aggregated_download_data(plan), language, lang)
}

wlv_multilateral_indicator_codes <- function() {
  combinations <- expand.grid(category = c("CX", "CM", "CN", "TS", "TR", "TT"),
    scope = c("T", "P", "U"), unit = c("MP", "DP", "MV"), stringsAsFactors = FALSE)
  combinations <- combinations[!(startsWith(combinations$category, "T") & combinations$unit == "MP"), ]
  sort(apply(combinations, 1L, paste, collapse = "."))
}

wlv_multilateral_indicator_label <- function(code, lang = "en") {
  parts <- strsplit(code, ".", fixed = TRUE)[[1L]]
  category_en <- c(CX = "Exports", CM = "Imports", CN = "Net trade", TS = "Value transfers from exports", TR = "Value transfers from imports", TT = "Net value transfers")[[parts[[1L]]]]
  category_pt <- c(CX = "Exportações", CM = "Importações", CN = "Comércio líquido", TS = "Transferências de valor nas exportações", TR = "Transferências de valor nas importações", TT = "Transferências líquidas de valor")[[parts[[1L]]]]
  category <- wlv_tr(category_pt, category_en, lang)
  scope <- switch(parts[[2L]], T = "", P = wlv_tr(" dos setores produtivos", " of productive sectors", lang), U = wlv_tr(" dos setores improdutivos", " of unproductive sectors", lang))
  unit <- switch(parts[[3L]], MP = wlv_tr(" a preços de mercado (USD)", " at market prices (USD)", lang), DP = wlv_tr(" a preços diretos (USD)", " at direct prices (USD)", lang), MV = wlv_tr(" em magnitude de valor", " in magnitude of value", lang))
  paste0(category, scope, unit)
}

# Same identities as the original batch exporter, evaluated only for the requested
# country and partners. World totals are used only for the direct-price factor.
wlv_multilateral_matrix <- function(values, country, partners, indicator, factor = NULL) {
  parts <- strsplit(indicator, ".", fixed = TRUE)[[1L]]
  category <- parts[[1L]]; scope <- parts[[2L]]; unit <- parts[[3L]]
  if (unit == "DP" && is.null(factor)) {
    factor <- apply(values[, "exports_productive_mp", , , drop = FALSE], 1L, sum) /
      apply(values[, "exports_values", , , drop = FALSE], 1L, sum)
    factor[!is.finite(factor)] <- NA_real_
  }
  flow <- function(key, reverse) {
    if (reverse) wlv_xlsx_export_matrix(values[, key, partners, country, drop = FALSE], 3L, 1L)
    else wlv_xlsx_export_matrix(values[, key, country, partners, drop = FALSE], 4L, 1L)
  }
  component <- function(transfer, reverse) {
    if (transfer) {
      suffix <- if (unit == "MV") "values" else "dp"
      total <- flow(paste0("transfers_", suffix), reverse)
      productive <- flow(paste0("transfers_productive_", suffix), reverse)
    } else if (unit == "MP") {
      total <- flow("exports_mp", reverse)
      productive <- flow("exports_productive_mp", reverse)
    } else {
      total <- flow("exports_values", reverse)
      if (unit == "DP") total <- sweep(total, 2L, factor, "*")
      productive <- total
    }
    if (scope == "T") total else if (scope == "P") productive else total - productive
  }
  switch(category, CX = component(FALSE, FALSE), CM = component(FALSE, TRUE),
    CN = component(FALSE, FALSE) - component(FALSE, TRUE), TS = component(TRUE, FALSE),
    TR = component(TRUE, TRUE), TT = component(TRUE, TRUE) - component(TRUE, FALSE))
}

wlv_multilateral_download_plan <- function(method, country, partner = NULL,
    category = NULL, scope = NULL, unit = NULL, values, methods) {
  nonempty <- wlv_nonempty_selection
  if (!nonempty(method) || !method %in% names(values) || !method %in% methods$code ||
      !nonempty(country)) return(NULL)
  data <- values[[method]]
  countries <- dimnames(data)[[3L]]
  if (!country %in% countries) return(NULL)
  if (nonempty(partner)) {
    if (!partner %in% countries || partner == country) return(NULL)
    codes <- wlv_multilateral_indicator_codes()
    # Every primitive below has a direct, unscaled row among the 45 indicators.
    # Therefore a bilateral workbook exists exactly when either direction has
    # an observation; zeros and infinities remain observations, as before.
    keys <- c("exports_values", "exports_mp", "exports_productive_mp", "transfers_values",
      "transfers_dp", "transfers_productive_values", "transfers_productive_dp")
    if (!wlv_has_observations(data[, keys, country, partner, drop = FALSE]) &&
        !wlv_has_observations(data[, keys, partner, country, drop = FALSE])) return(NULL)
    matrix <- NULL
    filename <- paste(country, partner, method, "xlsx", sep = ".")
  } else {
    if (!nonempty(category) || !nonempty(scope) || !nonempty(unit)) return(NULL)
    codes <- paste0(category, scope, unit)
    if (!codes %in% wlv_multilateral_indicator_codes()) return(NULL)
    matrix <- wlv_multilateral_matrix(data, country, countries, codes)
    if (!wlv_has_observations(matrix)) return(NULL)
    filename <- paste(country, codes, method, "xlsx", sep = ".")
  }
  list(filename = filename, values = if (nonempty(partner)) data else NULL,
    data = matrix, codes = codes, country = country, partner = partner,
    countries = countries, specs = methods[methods$code == method, , drop = FALSE])
}

wlv_multilateral_download_data <- function(plan) {
  if (is.null(plan)) return(NULL)
  matrix <- plan$data
  codes <- plan$codes
  if (wlv_nonempty_selection(plan$partner)) {
    data <- plan$values
    factor <- apply(data[, "exports_productive_mp", , , drop = FALSE], 1L, sum) /
      apply(data[, "exports_values", , , drop = FALSE], 1L, sum)
    factor[!is.finite(factor)] <- NA_real_
    matrix <- do.call(rbind, lapply(codes, function(code)
      wlv_multilateral_matrix(data, plan$country, plan$partner, code, factor)))
    rownames(matrix) <- codes
  }
  rows <- apply(matrix, 1L, wlv_has_observations)
  years <- apply(matrix, 2L, wlv_has_observations)
  if (!any(rows) || !any(years)) return(NULL)
  matrix <- matrix[rows, years, drop = FALSE]
  if (wlv_nonempty_selection(plan$partner)) codes <- rownames(matrix)
  list(filename = plan$filename, data = matrix, codes = codes, country = plan$country,
    partner = plan$partner,
    row_countries = if (wlv_nonempty_selection(plan$partner)) NULL else plan$countries[rows],
    specs = plan$specs)
}

wlv_multilateral_download_localize <- function(data, language, lang = "en") {
  if (is.null(data)) return(NULL)
  codes <- data$codes
  selected <- list(Country = wlv_download_label(language, paste0("ISO3.", data$country), data$country, lang))
  if (wlv_nonempty_selection(data$partner)) {
    selected$Partner <- wlv_download_label(language, paste0("ISO3.", data$partner), data$partner, lang)
    labels <- vapply(codes, wlv_multilateral_indicator_label, character(1L), lang = lang)
  } else {
    selected$Indicator <- wlv_multilateral_indicator_label(codes, lang)
    labels <- vapply(paste0("ISO3.", data$row_countries), function(key)
      wlv_download_label(language, key, lang = lang), character(1L))
  }
  list(filename = data$filename, data = data$data, labels = unname(labels),
    metadata = data.frame(Code = codes, Name = vapply(codes, wlv_multilateral_indicator_label, character(1L), lang = lang), row.names = NULL),
    header = wlv_download_header(data$specs, language, selected, lang), specs = data$specs, lang = wlv_language_code(lang),
    analytics = list(kind = if (wlv_nonempty_selection(data$partner)) "bilateral" else "multilateral",
      format = "xlsx", method = data$specs$code, country = data$country,
      partner = data$partner, indicator = if (wlv_nonempty_selection(data$partner)) NULL else data$codes,
      years = colnames(data$data)))
}

wlv_multilateral_download_request <- function(method, country, partner = NULL,
    category = NULL, scope = NULL, unit = NULL, values, methods, language, lang = "en") {
  plan <- wlv_multilateral_download_plan(method, country, partner, category, scope, unit, values, methods)
  wlv_multilateral_download_localize(wlv_multilateral_download_data(plan), language, lang)
}

# Shiny asks for filename before content within the same download. Capture the
# full request once on that click so changing a selection cannot pair a filename
# from one snapshot with the contents or language of another.
wlv_download_callbacks <- function(request, writer = wlv_write_download_request) {
  pending <- NULL
  events <- NULL
  # A coleta é opcional também para ferramentas que carregam apenas este helper.
  safely <- function(expression) tryCatch(withCallingHandlers(expression,
    warning = function(warning) invokeRestart("muffleWarning")), error = function(error) NULL)
  begin <- function() {
    events <<- if (exists("wlv_analytics_download_events", mode = "function"))
      safely(wlv_analytics_download_events()) else NULL
    current <- tryCatch({
      value <- request()
      shiny::req(value)
      value
    }, error = function(error) {
      safely(events$failed())
      stop(error)
    })
    safely(events$requested(current))
    pending <<- current
    current
  }
  list(filename = function() {
    current <- if (is.null(pending)) begin() else pending
    current$filename
  }, content = function(file) {
    current <- if (is.null(pending)) begin() else pending
    current_events <- events
    pending <<- NULL
    events <<- NULL
    result <- tryCatch(withVisible(writer(current, file)), error = function(error) {
      safely(current_events$failed())
      stop(error)
    })
    safely(current_events$generated(file))
    if (result$visible) result$value else invisible(result$value)
  })
}

wlv_request_download_handler <- function(request) {
  callbacks <- wlv_download_callbacks(request)
  shiny::downloadHandler(filename = callbacks$filename, content = callbacks$content,
    contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
}

wlv_write_download_request <- function(request, file) {
  if (is.null(request)) stop("No observations are available for this download.", call. = FALSE)
  save_my_xlsx(file, request$header, request$labels, request$data,
    request$metadata, request$specs, list(seq_len(nrow(request$data)) + 6L),
    list("#,##0.00"), 35, 20, method_code = request$method,
    indicator_codes = request$indicators, display_contracts = request$contracts)
}
