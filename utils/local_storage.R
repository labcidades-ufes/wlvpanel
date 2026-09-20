# Generated cache and downloads belong to the active campaign during experiments.
# Normal panel sessions retain the existing operational data/ layout.
wlvpanel_generated_directory <- function(
    kind = c("cache", "downloads"),
    root = ".",
    campaign_root = Sys.getenv("WLV_CAMPAIGN_ROOT", unset = ""),
    storage_root = Sys.getenv("WLV_STORAGE_ROOT", unset = "")) {
  kind <- match.arg(kind)
  compare_path <- function(path) {
    if (.Platform$OS.type == "windows") tolower(path) else path
  }
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (nzchar(campaign_root)) {
    if (nzchar(storage_root)) {
      stop("WLV_STORAGE_ROOT must not be combined with WLV_CAMPAIGN_ROOT.", call. = FALSE)
    }
    campaign <- normalizePath(campaign_root, winslash = "/", mustWork = TRUE)
    temporary <- normalizePath(file.path(root, "temp"), winslash = "/", mustWork = TRUE)
    if (!identical(compare_path(dirname(campaign)), compare_path(temporary))) {
      stop("Panel experiments must use a campaign inside this project's temp/.", call. = FALSE)
    }
    manifest <- file.path(campaign, ".campaign.json")
    record <- jsonlite::fromJSON(manifest)
    if (!identical(record$schema, "wlv-campaign/1") ||
        !identical(record$id, basename(campaign)) ||
        !identical(record$status, "active")) {
      stop("Generated panel files require an active campaign.", call. = FALSE)
    }
    base <- campaign
    path <- file.path(base, if (kind == "cache") "scratch/cache" else "results/download")
  } else if (nzchar(storage_root)) {
    base <- normalizePath(storage_root, winslash = "/", mustWork = TRUE)
    path <- file.path(base, if (kind == "cache") "labourvaluesdatapanel-cache" else "download")
  } else {
    base <- root
    path <- file.path(root, "data", if (kind == "cache") "labourvaluesdatapanel-cache" else "download")
  }
  # Resolve existing ancestors before creating directories; a linked ancestor
  # cannot redirect writes outside the selected root.
  ancestor <- path
  while (!dir.exists(ancestor)) ancestor <- dirname(ancestor)
  resolved <- normalizePath(ancestor, winslash = "/", mustWork = TRUE)
  if (!identical(compare_path(resolved), compare_path(base)) &&
      !startsWith(compare_path(resolved), paste0(compare_path(base), "/"))) {
    stop("Generated directory escapes the selected panel storage root.", call. = FALSE)
  }
  if (!dir.exists(path) && !dir.create(path, recursive = TRUE)) {
    stop("Cannot create the panel generated directory.", call. = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}
