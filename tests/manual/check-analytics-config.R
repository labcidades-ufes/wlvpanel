# Execute no checkout com WLV_CAMPAIGN_ROOT e TEMP/TMP/TMPDIR dentro da campanha.
source("utils/analytics.R", encoding = "UTF-8")
campaign <- Sys.getenv("WLV_CAMPAIGN_ROOT", "")
root <- normalizePath(".", winslash = "/")
stopifnot(nzchar(campaign), startsWith(normalizePath(campaign, winslash = "/"), paste0(root, "/temp/")))
scratch <- file.path(campaign, "scratch", "analytics-config-tests")
dir.create(scratch, recursive = TRUE, showWarnings = FALSE)
config_path <- file.path(scratch, "public.json")
write_config <- function(value) jsonlite::write_json(value, config_path, auto_unbox = TRUE)
read_config <- function() suppressWarnings(wlv_read_analytics_config(config_path))
config <- list(enabled = TRUE, site_id = 2L, tracker_url = "/estatisticas/matomo.php", script_url = "/estatisticas/matomo.js",
  release = "release-20260913", dimensions = list(kind = 1L, filename = 10L), secret = "NEVER_PUBLIC")
checks <- 0L
check <- function(value) { stopifnot(isTRUE(value)); checks <<- checks + 1L }
check(identical(wlv_read_analytics_config(""), list(enabled = FALSE)))
check(identical(suppressWarnings(wlv_read_analytics_config(file.path(scratch, "missing.json"))), list(enabled = FALSE)))
write_config(config)
valid <- read_config()
check(isTRUE(valid$enabled))
check(identical(valid$site_id, 2L))
check(identical(valid$release, config$release))
check(is.null(valid$secret))
for (site in list(-1, 0, 1.5, "2", NULL, TRUE)) {
  broken <- config; broken$site_id <- site; write_config(broken); check(!read_config()$enabled)
}
for (url in c("https://outside.example/matomo.php", "//outside.example/matomo.php", "/estatisticas/matomo.php?secret=1", "/estatisticas/../matomo.php")) {
  broken <- config; broken$tracker_url <- url; write_config(broken); check(!read_config()$enabled)
}
for (dimensions in list(list(secret = 1), list(kind = -1), list(kind = 1, filename = 1), list(kind = "1"))) {
  broken <- config; broken$dimensions <- dimensions; write_config(broken); check(!read_config()$enabled)
}
broken <- config; broken$release <- "</script><script>alert(1)</script>"; write_config(broken); check(!read_config()$enabled)
writeLines("{invalid", config_path); check(!read_config()$enabled)
html <- as.character(wlv_analytics_head(valid))
check(!grepl("NEVER_PUBLIC", html, fixed = TRUE))
check(grepl('application/json', html, fixed = TRUE))
jsonlite::write_json(list(passed = checks, failed = 0L), file.path(campaign, "results", "analytics-config-tests.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("%d verificações de configuração passaram.\n", checks))
