## Assemble the units into the store the vignette reads.
##
##   Rscript analysis/assemble_store.R
##
## One file per fit call, named by the key. A call with units missing is reported
## and skipped rather than assembled from part of its set: a model set short an
## equation is a different model average, and it would be published without
## anything to say so.

suppressPackageStartupMessages({
  library(bayesnec)
  library(digest)
})
for (f in list.files("R", full.names = TRUE)) source(f)

mf <- readRDS("manifest.rds")
unit_dir <- Sys.getenv("GRP_UNITS", "units")
store <- Sys.getenv("GRP_STORE", "store")
dir.create(store, showWarnings = FALSE, recursive = TRUE)

items <- vignette_exprs(mf$vignette)
index <- list()
incomplete <- character(0)

for (key in names(mf$calls)) {
  info <- mf$calls[[key]]
  rows <- mf$units[mf$units$key == key, , drop = FALSE]
  paths <- mapply(unit_path, MoreArgs = list(root = unit_dir),
                  key = rows$key, level = rows$level, model = rows$model)
  have <- file.exists(paths)
  message("\n--- ", info$target, " (", key, ") ", sum(have), "/", length(have),
          " units")
  if (!all(have)) {
    for (p in paths[!have]) message("    missing: ", basename(p))
    incomplete <- c(incomplete, info$target)
    next
  }

  env <- prefix_env()
  run_prefix(items, info$expr_index, env)
  cl <- fit_call_of(items[[info$expr_index]]$expr)
  fn <- fit_fun_name(cl)
  mcl <- match.call(get(fn, envir = asNamespace("bayesnec")), cl,
                    expand.dots = TRUE)
  data <- eval(mcl$data, env)

  units <- lapply(paths, function(p) readRDS(p)$fit)

  fit <- if (identical(fn, "bnec")) {
    assemble_models(stats::setNames(units, rows$model))
  } else if (identical(fn, "bnec_group")) {
    plan <- group_plan(mcl, data, env)
    level_fits <- lapply(plan$levels, function(lev) {
      sel <- rows$level == lev
      assemble_models(stats::setNames(units[sel], rows$model[sel]))
    })
    names(level_fits) <- plan$levels
    assemble_group(level_fits, plan, mcl$formula, data, env)
  } else {
    units[[1L]]
  }

  p <- store_path(store, key)
  saveRDS(fit, p)
  message("    -> ", p, "  (", class(fit)[1L], ", ",
          round(file.size(p) / 1e6, 1L), " MB)")
  index[[length(index) + 1L]] <- data.frame(
    key = key, target = info$target, fn = fn, chunk = info$chunk,
    n_units = nrow(rows), class = class(fit)[1L],
    mb = round(file.size(p) / 1e6, 1L),
    call = info$call_text, stringsAsFactors = FALSE)
}

if (length(index)) {
  write.csv(do.call(rbind, index), file.path(store, "index.csv"),
            row.names = FALSE)
}
writeLines(c(paste("vignette:", mf$vignette),
             paste("bayesnec:", mf$bayesnec),
             paste("manifest built:", format(mf$built)),
             paste("assembled:", format(Sys.time())),
             paste("assembly seed:", ASSEMBLY_SEED)),
           file.path(store, "MANIFEST"))

if (length(incomplete)) {
  message("\nincomplete, not written: ", paste(incomplete, collapse = ", "))
  quit(save = "no", status = 1L)
}
message("\nstore complete: ", length(index), " fits in ", store, "/")
