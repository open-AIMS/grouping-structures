## Fit the vignette's joint refits, after the store has been assembled.
##
##   Rscript analysis/run_joint.R [key ...]
##
## bnec_joint() refits a bayesnecgroupfit as one model with each curve parameter
## dummy-coded by level. What it is handed is the fit an earlier call in the
## vignette produced, so it cannot be an array task: the array's tasks are
## independent by construction, and this one needs its prerequisite fitted and
## then reassembled. It runs here instead, in a job chained behind the assembly,
## with the prerequisite read out of the store.
##
## Idempotent in the same way the array is: a refit whose store file exists is
## skipped, so a timed-out run is recovered by resubmitting the same job. Given
## keys on the command line, only those are run.

suppressPackageStartupMessages({
  library(bayesnec)
  library(digest)
})
for (f in list.files("R", full.names = TRUE)) source(f)

args <- commandArgs(trailingOnly = TRUE)
mf <- readRDS("manifest.rds")
store <- Sys.getenv("GRP_STORE", "store")
dir.create(store, showWarnings = FALSE, recursive = TRUE)

jt <- mf$joint
if (is.null(jt) || !nrow(jt)) {
  message("no joint refits in the manifest")
  quit(save = "no", status = 0L)
}
if (length(args)) {
  jt <- jt[jt$key %in% args, , drop = FALSE]
  if (!nrow(jt)) stop("none of those keys is a joint refit", call. = FALSE)
}

# Same backend as the array, and for the same reason: a store that mixed rstan
# and cmdstanr fits would be a set of fits from a different sampler than the one
# the vignette names. See analysis/run_unit.R.
options(brms.backend = Sys.getenv("BAYESNEC_BACKEND", "cmdstanr"))
cache <- Sys.getenv("GRP_STAN_CACHE", "")
if (nzchar(cache)) {
  dir.create(cache, showWarnings = FALSE, recursive = TRUE)
  options(cmdstanr_write_stan_file_dir = cache)
}
options(mc.cores = as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "4")))

items <- vignette_exprs(mf$vignette)
rows <- list()

# In vignette order, so that a joint refit of a joint refit would find its own
# prerequisite already written. Nothing in example8 does that; ordering by
# expression index removes the case from the list of things to remember.
for (i in order(jt$expr_index)) {
  info <- mf$calls[[jt$key[i]]]
  key <- info$key
  out <- store_path(store, key)
  message("\n--- ", info$target, " (", key, ") refits ",
          mf$calls[[info$depends_on]]$target, " (", info$depends_on, ")")
  if (file.exists(out)) {
    message("    already fitted: ", out)
    # Recorded all the same: a resumed assembly rewrites index.csv without it.
    rows[[length(rows) + 1L]] <- data.frame(
      key = key, target = info$target, fn = info$fn, chunk = info$chunk,
      n_units = 1L, class = class(readRDS(out))[1L],
      mb = round(file.size(out) / 1e6, 1L),
      call = info$call_text, stringsAsFactors = FALSE)
    next
  }

  dep_path <- store_path(store, info$depends_on)
  if (!file.exists(dep_path)) {
    stop("the fit ", info$target, " refits is not in the store: ", dep_path,
         "\n  Run analysis/assemble_store.R first; a joint refit takes the",
         "\n  assembled object, not the units it was assembled from.",
         call. = FALSE)
  }
  prereq <- readRDS(dep_path)

  # The stored fit is bound under the name its own call assigned, before the
  # prefix runs rather than after. What sits between the two calls then runs on
  # it here exactly as it will at the render: example8 screens every grouped fit
  # with screen_models(), which rebinds the same variable and can change which
  # equation holds the most weight -- and so which equation bnec_joint() picks.
  # Substituting the stored object straight into the joint call instead would
  # refit the unscreened fit while the vignette's visible code said otherwise,
  # and the key would agree either way, because neither the joint call nor the
  # prerequisite's key changes when a step between them does.
  dep_target <- mf$calls[[info$depends_on]]$target
  env <- prefix_env()
  assign(dep_target, prereq, envir = env)
  fails <- run_prefix(items, info$expr_index, env)
  if (length(fails)) {
    message("    ", length(fails), " prefix expressions did not run (expected:",
            " the chunks that read the fits this pipeline skips)")
  }
  # An expression that assigns to the prerequisite's own name and did not run is
  # the one prefix failure that cannot be tolerated here: it is a step the
  # vignette applies to the fit before refitting it, and skipping it changes the
  # object without changing the key.
  rebind <- Filter(function(f) grepl(paste0("^", dep_target, "\\s*<-"), f$code),
                   fails)
  if (length(rebind)) {
    stop("an expression that rebinds `", dep_target, "` did not run, so the ",
         "fit\n  handed to ", info$target, " is not the one the vignette ",
         "refits.\n",
         paste0("  [", vapply(rebind, `[[`, character(1L), "chunk"), "] ",
                vapply(rebind, `[[`, character(1L), "code"), "\n    -> ",
                vapply(rebind, `[[`, character(1L), "error"), collapse = "\n"),
         call. = FALSE)
  }

  cl <- fit_call_of(items[[info$expr_index]]$expr)
  fn <- fit_fun_name(cl)
  mcl <- match.call(get(fn, envir = asNamespace("bayesnec")), cl,
                    expand.dots = TRUE)

  # Recomputed rather than trusted, as run_unit.R does for a unit. Here it also
  # checks the prerequisite: the key is derived from this call and from the key
  # of the fit it refits, so a mismatch means one of the two has moved since the
  # manifest was built.
  key2 <- joint_key(cl, info$depends_on, fn)
  if (!identical(key2, key)) {
    stop("key mismatch: manifest has ", key, ", this run computes ", key2,
         "\n  The vignette has changed since the manifest was built.",
         "\n  Re-run analysis/build_manifest.R.", call. = FALSE)
  }

  # Taken out of the environment the prefix left, not from the file, so that a
  # rebinding between the two calls is what gets refitted.
  t0 <- Sys.time()
  fit <- run_unit(mcl, fn, data = NULL, env = env,
                  prereq = get(prereq_var(cl, fn), envir = env))
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  saveRDS(fit, out)
  message(sprintf("    done in %.1f min -> %s  (%s, %.1f MB)", elapsed, out,
                  class(fit)[1L], file.size(out) / 1e6))
  rows[[length(rows) + 1L]] <- data.frame(
    key = key, target = info$target, fn = fn, chunk = info$chunk,
    n_units = 1L, class = class(fit)[1L],
    mb = round(file.size(out) / 1e6, 1L),
    call = info$call_text, stringsAsFactors = FALSE)
}

# The index is amended rather than rewritten. assemble_store.R writes it from
# the calls it assembled, which are every call but these, so a joint refit's row
# has to be added here -- and replaced rather than appended, or a second run of
# this script would file the same key twice.
idx_path <- file.path(store, "index.csv")
if (length(rows) && file.exists(idx_path)) {
  idx <- utils::read.csv(idx_path, stringsAsFactors = FALSE)
  add <- do.call(rbind, rows)
  idx <- idx[!idx$key %in% add$key, , drop = FALSE]
  write.csv(rbind(idx, add), idx_path, row.names = FALSE)
  message("\nindex.csv: ", nrow(add), " joint refit row(s) recorded")
} else if (length(rows)) {
  write.csv(do.call(rbind, rows), idx_path, row.names = FALSE)
}

message("\njoint refits complete: ", nrow(jt), " in ", store, "/")
