source("global.R", encoding = "UTF-8")
campaign <- Sys.getenv("WLV_CAMPAIGN_ROOT", "")
stopifnot(nzchar(campaign), startsWith(normalizePath(campaign, winslash = "/"), paste0(normalizePath(".", winslash = "/"), "/temp/")))
keys <- names(jsonlite::fromJSON("config/analytics-translations.json", simplifyVector = FALSE))
languages <- wlv_languages()$value
for (language in languages) {
  labels <- wlv_language_messages(language)$labels
  stopifnot(all(keys %in% names(labels)), all(nzchar(unlist(labels[keys]))), !any(unlist(labels[keys]) %in% keys))
}
ui <- source("ui.R", encoding = "UTF-8")$value
rendered <- htmltools::renderTags(ui(list(HTTP_ACCEPT_LANGUAGE = "pt-BR")))
html <- paste(rendered$head, rendered$html)
stopifnot(grepl('id="wlv-privacy-dialog"', html, fixed = TRUE),
  grepl('aria-labelledby="wlv-privacy-title"', html, fixed = TRUE),
  grepl('id="wlv-analytics-config"', html, fixed = TRUE),
  grepl('wlv-analytics-download', html, fixed = TRUE),
  grepl('analytics.retention', html, fixed = TRUE))
document <- xml2::read_html(html)
stopifnot(length(xml2::xml_find_all(document, '//*[@id="wlv-privacy-dialog"]')) == 1L,
  length(xml2::xml_find_all(document, '//*[@id="wlv-privacy-dialog"]/ancestor::footer')) == 0L,
  length(xml2::xml_find_all(document, '//footer//*[@id="wlv-privacy-open"]')) == 1L,
  length(xml2::xml_find_all(document, '//*[@id="wlv-settings"]//*[@id="wlv-privacy-open-settings"]')) == 1L,
  length(xml2::xml_find_all(document, '//*[@aria-controls="wlv-privacy-dialog"]')) == 2L)
jsonlite::write_json(list(languages = length(languages), labels = length(keys), html_checks = 10, passed = TRUE),
  file.path(campaign, "results", "analytics-ui-tests.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("Interface com %d idiomas, %d rótulos e 10 contratos HTML validada.\n", length(languages), length(keys)))
