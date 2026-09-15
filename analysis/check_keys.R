## Check that the shim asks for exactly the keys the store will hold.
##
##   Rscript analysis/check_keys.R
##
## The agreement between the compendium and the render is the one thing this
## design rests on, and it costs nothing to test: the keys are computed from the
## call and the data, and neither needs a fit. A store of empty placeholder files
## is stood up under the manifest's keys, the shim is installed against it, and
## the vignette's code is run. Every fit call must resolve, and it must resolve to
## the key the manifest planned units for.
##
## Run this after every change to the vignette, before the array is submitted.
## Twenty seconds here is the alternative to discovering at the render that the
## store was built against a different draft.

suppressPackageStartupMessages({
  library(bayesnec)
  library(digest)
})
for (f in list.files("R", full.names = TRUE)) source(f)

mf <- readRDS("manifest.rds")
fake <- file.path(tempdir(), "fake-store")
unlink(fake, recursive = TRUE)
dir.create(fake, recursive = TRUE)
for (key in names(mf$calls)) file.create(file.path(fake, paste0(key, ".rds")))
write.csv(data.frame(key = names(mf$calls),
                     target = vapply(mf$calls, `[[`, character(1L), "target"),
                     n_units = vapply(mf$calls, `[[`, integer(1L), "n_units")),
          file.path(fake, "index.csv"), row.names = FALSE)

## The shim as bayesnec will carry it, loaded from the generated file rather than
## from the sources it was generated from, so that a stale copy is caught here.
source("shim/fit_store.R")

asked <- character(0)
# The placeholders are empty, so the shim's readRDS would fail on the value it
# never uses here. Intercepted to record the key and hand back a marker.
assign("readRDS", function(file, ...) {
  key <- sub("\\.rds$", "", basename(file))
  asked <<- c(asked, key)
  structure(list(key = key), class = c("bayesmanecfit", "bnecfit"))
}, envir = globalenv())

fit_store_install(fake)

items <- vignette_exprs(mf$vignette)
env <- prefix_env()
errs <- 0L
for (i in seq_along(items)) {
  e <- items[[i]]$expr
  err <- tryCatch({
    withCallingHandlers(eval(e, env),
                        warning = function(w) invokeRestart("muffleWarning"),
                        message = function(m) invokeRestart("muffleMessage"))
    NULL
  }, error = function(e) conditionMessage(e))
  if (!is.null(err) && !is.null(fit_call_of(e))) {
    cat("FIT CALL FAILED at expression ", i, ":\n  ", err, "\n", sep = "")
    errs <- errs + 1L
  }
}

planned <- names(mf$calls)
cat("\nfit calls in the manifest: ", length(planned), "\n", sep = "")
cat("keys the vignette asked for: ", length(asked), "\n", sep = "")
missing <- setdiff(planned, asked)
extra <- setdiff(asked, planned)
if (length(missing)) cat("NOT ASKED FOR: ", paste(missing, collapse = ", "), "\n", sep = "")
if (length(extra)) cat("ASKED FOR, NOT PLANNED: ", paste(extra, collapse = ", "), "\n", sep = "")

ok <- errs == 0L && !length(missing) && !length(extra)
cat(if (ok) "\nkeys agree\n" else "\nKEYS DO NOT AGREE\n")
quit(save = "no", status = if (ok) 0L else 1L)
