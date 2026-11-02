## Compute the vignette's post-fit calls on one stored set, and store them.
##
##   Rscript analysis/run_post.R <task | key>
##
## The vignette's code runs in order, as at the render, with the shim installed
## and recording. Only this task's set is read from the store. Every other fit
## call is bound to a placeholder, and a post-fit call handed a placeholder
## returns at once, so each task computes the calls on its own set and on the
## objects derived from it: `fit <- screen_models(fit)` and then `summary(fit)`
## run in that order here as they do in the vignette.
##
## An expression that reads another set before this one, such as an rbind() of
## two ecx() calls, can stop at the placeholder before reaching this set's call.
## hpc/run.render computes and records those calls, and the shim reports each.
##
## Idempotent: a result already in the store is read back rather than
## recomputed, so a resubmitted task computes only what an interrupted one left.

suppressPackageStartupMessages({
  library(bayesnec)
  library(digest)
})
for (f in list.files("R", full.names = TRUE)) source(f)
source("shim/fit_store.R")

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("give a task number or a key", call. = FALSE)
mf <- readRDS("manifest.rds")
store <- Sys.getenv("GRP_STORE", "store")
tasks <- utils::read.csv(file.path(store, "post", "tasks.csv"),
                         stringsAsFactors = FALSE)
row <- if (grepl("^[0-9]+$", args[[1L]])) {
  tasks[tasks$task == as.integer(args[[1L]]), , drop = FALSE]
} else {
  tasks[tasks$key == args[[1L]], , drop = FALSE]
}
if (nrow(row) != 1L) {
  stop("no single row of ", file.path(store, "post", "tasks.csv"), " for ",
       args[[1L]], call. = FALSE)
}
key <- row$key
message("--- ", row$target, " (", key, "), ", row$mb, " MB")

# The session settings precompile.R gives the render that can reach a computed
# value or a recorded message.
Sys.setenv(NOT_CRAN = "true")
options(width = 115,
        mc.cores = as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "1")))

log_path <- file.path(store, "post", paste0("log-", key, ".tsv"))
Sys.setenv(BAYESNEC_POST_STORE = "replay", BAYESNEC_POST_STORE_RECORD = "true",
           BAYESNEC_POST_STORE_LOG = log_path)
fit_store_install(store)

placeholder <- function(k) {
  structure(list(), class = "post_store_placeholder", fit_store_key = k)
}

# What a call on a placeholder returns: a value the surrounding expression can
# carry on with, so that it still reaches this set's own call where it can.
placeholder_value <- function(fn, x) {
  switch(fn,
         ecx = , nsec = , nec = c(Q50 = NA_real_, Q2.5 = NA_real_,
                                  Q97.5 = NA_real_),
         screen_models = , pull_out = x,
         NULL)
}

for (nm in names(POST_FUNS)) {
  assign(nm, local({
    fn <- nm
    shim <- get(nm, envir = globalenv())
    real <- get(nm, envir = asNamespace(POST_FUNS[[nm]]))
    function(...) {
      a <- post_store_args(real, list(...))
      if (length(a) && inherits(a[[1L]], "post_store_placeholder")) {
        return(placeholder_value(fn, a[[1L]]))
      }
      # The call is re-evaluated with the shim bound under the name it was
      # called by, so that the shim records the vignette's call text. An
      # argument that is itself a post-fit call is then read back from the store.
      cl <- sys.call()
      if (!is.name(cl[[1L]])) return(shim(...))
      env <- new.env(parent = parent.frame())
      assign(as.character(cl[[1L]]), shim, envir = env)
      eval(cl, env)
    }
  }), envir = globalenv())
}

by_expr <- list()
for (ci in mf$calls) by_expr[[as.character(ci$expr_index)]] <- ci

items <- vignette_exprs(mf$vignette)
env <- prefix_env()
failed <- 0L
started <- Sys.time()
for (i in seq_along(items)) {
  e <- items[[i]]$expr
  if (!is.null(fit_call_of(e))) {
    ci <- by_expr[[as.character(i)]]
    if (is.null(ci)) {
      stop("expression ", i, " is a fit call the manifest does not hold.\n",
           "  Re-run analysis/build_manifest.R against this vignette.",
           call. = FALSE)
    }
    obj <- if (identical(ci$key, key)) {
      fit_store_stamp(readRDS(store_path(store, key)), key)
    } else {
      placeholder(ci$key)
    }
    assign(ci$target, obj, envir = env)
    next
  }
  err <- tryCatch({
    utils::capture.output(withCallingHandlers(
      eval(e, env),
      warning = function(w) invokeRestart("muffleWarning"),
      message = function(m) invokeRestart("muffleMessage")))
    NULL
  }, error = function(err) conditionMessage(err))
  if (!is.null(err)) failed <- failed + 1L
}

calls <- if (file.exists(log_path)) {
  utils::read.delim(log_path, header = FALSE, quote = "",
                    col.names = c("fn", "input", "key", "how", "secs", "call"))
} else {
  data.frame(how = character(0), secs = numeric(0))
}
message(sprintf(paste0("\n%s: %d calls computed and stored, %d read back; ",
                       "%d expressions stopped (those reading other sets); ",
                       "%.1f min"),
                row$target, sum(calls$how == "computed"),
                sum(calls$how == "read"), failed,
                as.numeric(difftime(Sys.time(), started, units = "mins"))))
