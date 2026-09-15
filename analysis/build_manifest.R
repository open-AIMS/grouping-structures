## Build the manifest: every fit call in the vignette, split into units.
##
##   Rscript analysis/build_manifest.R [path/to/example8.Rmd.orig]
##
## Writes manifest.rds and manifest.csv. One row of manifest.csv is one array
## task. Nothing is fitted here: the prefix is run so that the data each call is
## handed exists, and get_priors() expands each model set, both of which are
## seconds rather than hours.
##
## Re-run this whenever the vignette changes. The keys move when a fit call
## moves, and a manifest built against an older draft of the vignette produces a
## store the render cannot read -- loudly, at the first chunk, rather than
## quietly.

suppressPackageStartupMessages({
  library(bayesnec)
  library(digest)
})
for (f in list.files("R", full.names = TRUE)) source(f)

args <- commandArgs(trailingOnly = TRUE)
vig <- if (length(args)) args[[1L]] else Sys.getenv("GRP_VIGNETTE", "")
if (!nzchar(vig) || !file.exists(vig)) {
  stop("give the path to example8.Rmd.orig, or set GRP_VIGNETTE", call. = FALSE)
}
message("vignette: ", normalizePath(vig))
message("bayesnec: ", as.character(packageVersion("bayesnec")), " from ",
        dirname(find.package("bayesnec")))

items <- vignette_exprs(vig)
fit_at <- which(vapply(items, function(it) !is.null(fit_call_of(it$expr)), logical(1L)))
message("fit calls found: ", length(fit_at))

calls <- list()
units <- list()

for (k in fit_at) {
  e <- items[[k]]$expr
  cl <- fit_call_of(e)
  fn <- fit_fun_name(cl)
  target <- assign_target(e)
  message("\n--- ", k, "  ", target, " <- ", fn, "()  [chunk \"",
          items[[k]]$chunk, "\"]")

  env <- prefix_env()
  fails <- run_prefix(items, k, env)
  if (length(fails)) {
    # Expected: the prefix includes the chunks that summarise and plot the fits
    # this run skipped. Reported in full so that a failure which is not one of
    # those is visible rather than buried.
    message("  prefix expressions that did not run (", length(fails), "):")
    for (f in fails) message("    [", f$chunk, "] ", substr(f$code, 1L, 90L),
                             "  ->  ", substr(f$error, 1L, 90L))
  }

  mcl <- match.call(get(fn, envir = asNamespace("bayesnec")), cl,
                    expand.dots = TRUE)
  data <- eval(mcl$data, env)
  key <- fit_key(cl, data, fn)
  message("  key ", key, "  data ", nrow(data), " rows")

  u <- plan_units(mcl, fn, data, env)
  message("  units: ", nrow(u),
          if (fn == "bnec_group") paste0(" (", length(unique(u$level)), " levels)") else "")

  calls[[key]] <- list(key = key, target = target, fn = fn, expr_index = k,
                       chunk = items[[k]]$chunk,
                       call_text = paste(deparse(cl, width.cutoff = 500L),
                                         collapse = " "),
                       normalised = normalise_fit_call(cl, fn),
                       n_units = nrow(u))
  units[[key]] <- data.frame(key = key, target = target, fn = fn,
                             expr_index = k, level = u$level, model = u$model,
                             stringsAsFactors = FALSE)
}

manifest <- do.call(rbind, unname(units))
rownames(manifest) <- NULL
manifest$task <- seq_len(nrow(manifest))
manifest <- manifest[, c("task", "key", "target", "fn", "expr_index",
                         "level", "model")]

saveRDS(list(vignette = normalizePath(vig), calls = calls, units = manifest,
             bayesnec = as.character(packageVersion("bayesnec")),
             built = Sys.time()),
        "manifest.rds")
write.csv(manifest, "manifest.csv", row.names = FALSE)

message("\n", nrow(manifest), " units across ", length(calls), " fit calls")
message("written: manifest.rds, manifest.csv")
