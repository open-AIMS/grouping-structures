
## ---------------------------------------------------------------------------
## The shim
## ---------------------------------------------------------------------------
##
## Replaces bnec(), bnec_group() and bnec_hurdle() for the duration of a
## precompile with functions that load a fit from the store instead of running
## one. Installed only when BAYESNEC_FIT_STORE names a directory, so an ordinary
## precompile is untouched.
##
## What the reader sees is unaffected: knitr echoes the chunk's source, so the
## vignette still shows the bnec() call the analysis was actually run from. What
## changes is only that the call is answered from a file rather than by sampling
## for the twenty minutes it took on the cluster.
##
## A key that is not in the store stops the render. That is the design and not a
## limitation. The alternative -- falling back to fitting -- would turn a
## vignette edit that nobody noticed into a twenty-two hour render, or worse,
## into a render where one chunk was fitted fresh and the rest came from a store
## built against a different draft.

fit_store_install <- function(store = Sys.getenv("BAYESNEC_FIT_STORE"),
                              envir = globalenv()) {
  if (!nzchar(store)) return(invisible(FALSE))
  if (!dir.exists(store)) {
    stop("BAYESNEC_FIT_STORE is set to \"", store, "\", which is not a ",
         "directory.", call. = FALSE)
  }
  manifest <- file.path(store, "MANIFEST")
  message("Fit store: ", normalizePath(store))
  if (file.exists(manifest)) {
    message(paste0("  ", readLines(manifest, warn = FALSE), collapse = "\n"))
  }
  for (nm in FIT_FUNS) {
    assign(nm, fit_store_shim(nm, store), envir = envir)
  }
  invisible(TRUE)
}

fit_store_shim <- function(fn_name, store) {
  force(fn_name); force(store)
  function(...) {
    cl <- sys.call()
    caller <- parent.frame()
    def <- get(fn_name, envir = asNamespace("bayesnec"))
    mcl <- match.call(def, cl, expand.dots = TRUE)
    if (is.null(mcl$data)) {
      stop("the fit store needs `data` named or matched in the call to ",
           fn_name, "().", call. = FALSE)
    }
    data <- eval(mcl$data, caller)
    key <- fit_key(cl, data, fn_name)
    path <- file.path(store, paste0(key, ".rds"))
    if (!file.exists(path)) {
      fit_store_miss(key, cl, fn_name, store)
    }
    message("fit store: ", key, " <- ", basename(path))
    readRDS(path)
  }
}

## A miss is reported with everything needed to find the cause: the key, the
## normalised form of the call the key was computed from, and what the store does
## hold. Without the normalised form the only information is that two hashes
## differ, which says nothing about which argument moved.
fit_store_miss <- function(key, cl, fn_name, store) {
  idx <- file.path(store, "index.csv")
  held <- if (file.exists(idx)) {
    d <- utils::read.csv(idx, stringsAsFactors = FALSE)
    paste0("  ", d$key, "  ", d$target, "  (", d$n_units, " units)",
           collapse = "\n")
  } else {
    "  (no index.csv in the store)"
  }
  stop("no stored fit under key ", key, "\n",
       "  call: ", paste(deparse(cl, width.cutoff = 500L), collapse = " "), "\n",
       "  normalised: ", normalise_fit_call(cl, fn_name), "\n",
       "  the store holds:\n", held, "\n",
       "  This call has changed since the store was built. Rebuild it in the\n",
       "  grouping-structures compendium: analysis/build_manifest.R, then the\n",
       "  array, then analysis/assemble_store.R.", call. = FALSE)
}
