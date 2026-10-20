
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

## The oldest bayesnec a store may have been fitted with.
##
## The key covers the call and the data, not the code that answers the call, so
## a store fitted before a change to what bayesnec fits still resolves every key
## and loads without complaint. PR #409 changed the default priors and left
## Version at 2.1.3.39, which is what the store assembled on 2026-09-18 records;
## 2.1.3.40 is the first version that can only be a build after it (#413).
## 2.1.3.42 (#468) computes a disp() variance function from the curve before
## an ogl() deviation rather than from the fitted mean, which changes every
## example8 fit that has both terms, so the minimum was raised to it.
##
## A minimum rather than equality with the installed version, because most
## version bumps change nothing example8 fits: 2.1.3.41 (#397) changes the
## disp() centring of negbinomial and beta_binomial fits, and example8 fits
## Gamma and Beta. Equality would turn every such bump into a refit of 189
## models with no number changed. In exchange the value has to be raised by
## hand, by the change that does alter what example8 fits.
##
## First added to the copy in bayesnec (PR #432, #413), then to
## shim/fit_store_body.R in the compendium, so that regenerating the copy
## keeps it.
FIT_STORE_MIN_BAYESNEC <- "2.1.3.42"

## Refuse a store whose MANIFEST records a bayesnec older than the minimum.
##
## The version is read from the MANIFEST that analysis/assemble_store.R writes.
## Its `bayesnec:` line is the version the manifest was built against, and the
## assembly refuses a set whose units were fitted by any other, so it is also
## the version the units of the last assembly were fitted with. It certifies
## that assembly, not every file in the directory: notes/example8_fit_store.md
## gives the cases where an older fit survives it. Compared with
## numeric_version() rather than as a string, under which "2.1.3.100" sorts
## before "2.1.3.40".
##
## A store with no MANIFEST, or with none recording a version, is not refused:
## the compendium's key check creates a store of empty files with no MANIFEST
## and installs this shim against it, and that gate has to keep working. It is
## reported instead, so that an unchecked store does not read as a checked one.
## Leading space before `bayesnec:` is allowed, so that a padded line is checked
## rather than taken for a missing one.
fit_store_check_version <- function(manifest,
                                    minimum = FIT_STORE_MIN_BAYESNEC) {
  lines <- if (file.exists(manifest)) readLines(manifest, warn = FALSE)
  version_line <- "^[[:space:]]*bayesnec:"
  recorded <- trimws(sub(version_line, "",
                         grep(version_line, lines, value = TRUE)))
  if (!length(recorded)) {
    message("  The store records no bayesnec version, so it was not checked ",
            "against the minimum of ", minimum, ".")
    return(invisible(NA_character_))
  }
  # assemble_store.R writes one `bayesnec:` line. The first is read so that a
  # hand-edited MANIFEST cannot turn one version into a vector of them.
  recorded <- recorded[[1L]]
  have <- numeric_version(recorded, strict = FALSE)
  if (is.na(have)) {
    stop("the fit store's MANIFEST records bayesnec \"", recorded, "\", which ",
         "is not a version number.\n  MANIFEST: ", manifest, call. = FALSE)
  }
  if (have < numeric_version(minimum)) {
    stop("the fit store was fitted with bayesnec ", recorded, ", and example8 ",
         "needs a store fitted with ", minimum, " or later.\n",
         "  MANIFEST: ", manifest, "\n",
         "  Fits from an older bayesnec were made by code that has since\n",
         "  changed what example8 fits, so they are not what this render\n",
         "  would produce. Refit the store in the grouping-structures\n",
         "  compendium. First rename the cluster's old units/ and store/\n",
         "  directories: the units and joint jobs skip a file that exists,\n",
         "  and their keys do not include the version, so old fits would be\n",
         "  reused. Then run ./hpc/deploy.sh --ref <bayesnec commit>, fetch the\n",
         "  store with ./hpc/fetch-store.sh, and point BAYESNEC_FIT_STORE at\n",
         "  it. notes/example8_fit_store.md in bayesnec gives the steps.",
         call. = FALSE)
  }
  invisible(recorded)
}

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
  # Checked before any shim is assigned, so a refused store leaves bnec() and
  # the other fitting functions as they were.
  fit_store_check_version(manifest)
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
    key <- if (fn_name %in% FIT_FUNS_ON_FIT) {
      joint_key(cl, fit_store_prereq_key(mcl, fn_name, caller), fn_name)
    } else {
      if (is.null(mcl$data)) {
        stop("the fit store needs `data` named or matched in the call to ",
             fn_name, "().", call. = FALSE)
      }
      fit_key(cl, eval(mcl$data, caller), fn_name)
    }
    path <- file.path(store, paste0(key, ".rds"))
    if (!file.exists(path)) {
      fit_store_miss(key, cl, fn_name, store)
    }
    message("fit store: ", key, " <- ", basename(path))
    # Every object the store hands back is stamped with the key it came from, so
    # that a later call which refits it can name its prerequisite without being
    # told. The compendium reaches the same key by following the variable back to
    # the earlier fit call in the vignette source, which is a different route to
    # the same string -- and two routes that agree is the property the whole
    # store rests on.
    obj <- readRDS(path)
    attr(obj, "fit_store_key") <- key
    obj
  }
}

## The key of the fit a joint refit was handed.
##
## Read off the object rather than off the symbol, because the symbol is not
## evidence: a variable rebound between the grouped fit and the joint refit would
## still be called `fits_herb`. The stamp is only on an object this shim
## returned, so a missing one means the fit reaching bnec_joint() is not the one
## the compendium planned against, and that is reported rather than guessed
## around.
fit_store_prereq_key <- function(mcl, fn_name, caller) {
  if (is.null(mcl$object)) {
    stop("the fit store needs `object` named or matched in the call to ",
         fn_name, "().", call. = FALSE)
  }
  obj <- eval(mcl$object, caller)
  dep <- attr(obj, "fit_store_key")
  if (is.null(dep)) {
    stop("the fit handed to ", fn_name, "() did not come from the fit store.\n",
         "  object: ", paste(deparse(mcl$object, width.cutoff = 500L),
                             collapse = " "), "\n",
         "  A joint refit is keyed on the key of the fit it refits, so that fit\n",
         "  has to be one the store answered. It is not, which means something\n",
         "  between the two calls returned a new object -- screen_models() and\n",
         "  amend() both do. Refit jointly from the object the fitting call\n",
         "  returned, or teach the compendium about the step in between.",
         call. = FALSE)
  }
  dep
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
