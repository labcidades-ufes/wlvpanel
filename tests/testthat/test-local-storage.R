local_storage_env <- new.env(parent = baseenv())
sys.source(file.path(wlvpanel_test_root, "utils", "local_storage.R"), envir = local_storage_env)

test_that("normal panel sessions preserve the operational directory layout", {
  root <- tempfile("panel-storage-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  cache <- local_storage_env$wlvpanel_generated_directory("cache", root, "")
  downloads <- local_storage_env$wlvpanel_generated_directory("downloads", root, "")
  expect_identical(cache, normalizePath(file.path(root, "data/labourvaluesdatapanel-cache"), winslash = "/"))
  expect_identical(downloads, normalizePath(file.path(root, "data/download"), winslash = "/"))
})

test_that("campaign output stays isolated and closed campaigns reject writes", {
  root <- tempfile("panel-campaign-")
  campaign <- file.path(root, "temp", "example")
  dir.create(campaign, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  manifest <- file.path(campaign, ".campaign.json")
  record <- list(schema = "wlv-campaign/1", id = "example", status = "active", preserve = FALSE)
  jsonlite::write_json(record, manifest, auto_unbox = TRUE)
  cache <- local_storage_env$wlvpanel_generated_directory("cache", root, campaign)
  downloads <- local_storage_env$wlvpanel_generated_directory("downloads", root, campaign)
  expect_identical(cache, normalizePath(file.path(campaign, "scratch/cache"), winslash = "/"))
  expect_identical(downloads, normalizePath(file.path(campaign, "results/download"), winslash = "/"))
  expect_false(dir.exists(file.path(root, "data")))
  record$status <- "completed"
  jsonlite::write_json(record, manifest, auto_unbox = TRUE)
  expect_error(local_storage_env$wlvpanel_generated_directory("cache", root, campaign), "active campaign")
  expect_error(local_storage_env$wlvpanel_generated_directory("cache", root, root), "inside this project's temp")
  expect_error(
    local_storage_env$wlvpanel_generated_directory("cache", root, campaign, storage_root = root),
    "must not be combined")
})

test_that("dedicated storage root hosts generated directories", {
  root <- tempfile("panel-storage-root-")
  storage <- file.path(root, "ramdisk")
  dir.create(storage, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  cache <- local_storage_env$wlvpanel_generated_directory("cache", root, "", storage_root = storage)
  downloads <- local_storage_env$wlvpanel_generated_directory("downloads", root, "", storage_root = storage)
  expect_identical(cache, normalizePath(file.path(storage, "labourvaluesdatapanel-cache"), winslash = "/"))
  expect_identical(downloads, normalizePath(file.path(storage, "download"), winslash = "/"))
  expect_false(dir.exists(file.path(root, "data")))
})

test_that("dedicated storage root rejects linked ancestors escaping it", {
  skip_on_os("windows")
  root <- tempfile("panel-storage-escape-")
  storage <- file.path(root, "ramdisk")
  dir.create(storage, recursive = TRUE)
  dir.create(file.path(root, "outside"))
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  file.symlink(file.path(root, "outside"), file.path(storage, "download"))
  expect_error(
    local_storage_env$wlvpanel_generated_directory("downloads", root, "", storage_root = storage),
    "escapes the selected panel storage root")
})
