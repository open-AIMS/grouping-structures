## Fit one unit.
##
##   Rscript analysis/run_unit.R <task>
##
## The task number is a row of manifest.csv. Idempotent: a unit whose file
## already exists is skipped, so a failed or timed-out subset is recovered by
## resubmitting the same array.

suppressPackageStartupMessages({
  library(bayesnec)
  library(digest)
})
for (f in list.files("R", full.names = TRUE)) source(f)

args <- commandArgs(trailingOnly = TRUE)
task <- as.integer(args[[1L]])
mf <- readRDS("manifest.rds")
row <- mf$units[mf$units$task == task, , drop = FALSE]
if (nrow(row) != 1L) stop("no task ", task, " in manifest.rds", call. = FALSE)

unit_dir <- Sys.getenv("GRP_UNITS", "units")
dir.create(unit_dir, showWarnings = FALSE, recursive = TRUE)
out <- unit_path(unit_dir, row$key, row$level, row$model)
if (file.exists(out)) {
  message("already fitted: ", out)
  quit(save = "no", status = 0L)
}

# cmdstanr, not brms's rstan default, because that is what vignettes/precompile.R
# sets and therefore what the vignette's output is understood to have come from.
# A store built under rstan would be a set of fits from a different sampler than
# the one the vignette names. BAYESNEC_BACKEND is honoured under the same name
# precompile.R uses, for a machine that has rstan and not cmdstan.
options(brms.backend = Sys.getenv("BAYESNEC_BACKEND", "cmdstanr"))

cache <- Sys.getenv("GRP_STAN_CACHE", "")
if (nzchar(cache)) {
  dir.create(cache, showWarnings = FALSE, recursive = TRUE)
  options(cmdstanr_write_stan_file_dir = cache)
}
# One equation on one dedicated core means the four chains are the only
# parallelism there is, and they are what the task is sized for.
options(mc.cores = as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "4")))

message("task ", task, ": ", row$target, " [", row$fn, "] ",
        if (!is.na(row$level)) paste0("level \"", row$level, "\" ") else "",
        if (!is.na(row$model)) row$model else "(whole call)")

items <- vignette_exprs(mf$vignette)
env <- prefix_env()
fails <- run_prefix(items, row$expr_index, env)
if (length(fails)) {
  message("  ", length(fails), " prefix expressions did not run (expected: the",
          " chunks that read the fits this pipeline skips)")
  for (f in fails) message("    [", f$chunk, "] ", substr(f$code, 1L, 80L))
}

cl <- fit_call_of(items[[row$expr_index]]$expr)
fn <- fit_fun_name(cl)
mcl <- match.call(get(fn, envir = asNamespace("bayesnec")), cl, expand.dots = TRUE)
data <- eval(mcl$data, env)

# The key is recomputed rather than trusted. It is the one check that the data
# this task built is the data the manifest was planned against, and a mismatch
# here means the vignette changed under the manifest -- which would otherwise
# surface as a store the render cannot read, hours later.
key <- fit_key(cl, data, fn)
if (!identical(key, row$key)) {
  stop("key mismatch: manifest has ", row$key, ", this run computes ", key,
       "\n  The vignette has changed since the manifest was built.",
       "\n  Re-run analysis/build_manifest.R.", call. = FALSE)
}

plan <- if (identical(fn, "bnec_group")) group_plan(mcl, data, env) else NULL
t0 <- Sys.time()
fit <- run_unit(mcl, fn, data, env, level = row$level, model = row$model,
                plan = plan)
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))

saveRDS(list(fit = fit, task = task, key = row$key, level = row$level,
             model = row$model, minutes = elapsed,
             bayesnec = as.character(packageVersion("bayesnec"))),
        out)
message(sprintf("  done in %.1f min -> %s", elapsed, out))
