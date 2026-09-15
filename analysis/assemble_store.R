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
  # The arguments expand_manec() takes that the vignette may have set on the
  # call. Evaluated here rather than passed as expressions because
  # expand_manec() is reached by do.call().
  expand_args <- c("x_range", "resolution", "sig_val", "loo_controls")
  mcl_list <- as.list(mcl)
  call_args <- lapply(mcl_list[intersect(names(mcl_list), expand_args)],
                      eval, envir = env)

  records <- lapply(paths, readRDS)

  # Every unit of a set must have been fitted by the same backend and the same
  # bayesnec. Neither is in the key, so the skip in run_unit.R would otherwise
  # reuse a unit left by a run under different settings, and the set would mix
  # them with nothing to say so. Stop rather than warn: a mixed set is not a
  # model average of anything, and deleting the units named here and
  # resubmitting the array is the whole remedy.
  seen_backend <- unique(unlist(lapply(records, `[[`, "backend")))
  seen_version <- unique(unlist(lapply(records, `[[`, "bayesnec")))
  if (length(seen_backend) > 1L || length(seen_version) > 1L) {
    stop("units of ", info$target, " disagree:\n",
         "  backend: ", paste(seen_backend, collapse = ", "), "\n",
         "  bayesnec: ", paste(seen_version, collapse = ", "), "\n",
         "  Delete units/", key, "__* and resubmit the array.", call. = FALSE)
  }
  if (length(seen_version) && !identical(seen_version, mf$bayesnec)) {
    stop("units of ", info$target, " were fitted by bayesnec ", seen_version,
         ", but the manifest was built against ", mf$bayesnec, ".",
         "\n  Delete units/", key, "__* and resubmit the array.", call. = FALSE)
  }

  units <- lapply(records, `[[`, "fit")
  ok <- !vapply(units, is.null, logical(1L))
  if (any(!ok)) {
    # The same outcome bnec() reaches for a model it could not fit: the set is
    # averaged over the equations that did fit, and the failure is recorded on
    # the object rather than lost. attach_failed_models() is what summary()
    # and failed_models() read.
    message("    ", sum(!ok), " equation(s) failed and are recorded, not fitted: ",
            paste(unique(rows$model[!ok]), collapse = ", "))
  }
  if (!any(ok)) {
    message("    every equation failed; nothing to assemble")
    incomplete <- c(incomplete, info$target)
    next
  }
  failed <- stats::setNames(
    lapply(which(!ok), function(i) {
      bayesnec:::failure_record(rows$model[i], records[[i]]$condition)
    }), rows$model[!ok])

  # The substitutions are the unit's own: every unit is a real bnec() call on
  # the same data, so check_data() recorded the same substitution in each.
  subs <- Find(Negate(is.null),
               lapply(records[ok], function(r) attr(r$fit, "bnec_record")$substitutions))

  fit <- if (identical(fn, "bnec")) {
    rec <- model_set_record(mcl$formula, data, mcl$family, env)
    bayesnec:::attach_bnec_record(
      bayesnec:::attach_failed_models(
        assemble_models(stats::setNames(units[ok], rows$model[ok]), call_args),
        failed),
      rec$requested, rec$attempted, rec$excluded, subs)
  } else if (identical(fn, "bnec_group")) {
    plan <- group_plan(mcl, data, env)
    level_fits <- lapply(plan$levels, function(lev) {
      sel <- rows$level == lev & ok
      lf <- assemble_models(stats::setNames(units[sel], rows$model[sel]), call_args)
      lvl_failed <- failed[rows$model[rows$level == lev & !ok]]
      if (length(lvl_failed)) lf <- bayesnec:::attach_failed_models(lf, lvl_failed)
      # Per level, because bnec_group() fits each level with its own bnec()
      # call on its own subset, and check_models() can drop different
      # equations on different levels.
      sub_data <- data[plan$grp == lev, , drop = FALSE]
      penv <- new.env(parent = env)
      assign(".plan_family", plan$family, envir = penv)
      rec <- model_set_record(mcl$formula, sub_data, quote(.plan_family), penv)
      bayesnec:::attach_bnec_record(lf, rec$requested, rec$attempted,
                                    rec$excluded, subs)
    })
    names(level_fits) <- plan$levels
    assemble_group(level_fits, plan, mcl$formula, data, env)
  } else {
    units[ok][[1L]]
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
