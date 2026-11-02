## Loading precompiled fits from a store, instead of fitting them.
##
## GENERATED FILE -- do not edit here.
## Source: grouping-structures/R/keys.R + shim/fit_store_body.R
## Regenerate with: Rscript analysis/build_shim.R <path to this file>
##
## example8 fits 189 models. Run in sequence at the cluster's four cores that
## is the better part of a day, which is longer than the walltime and far
## longer than a vignette should take to rebuild after a prose edit. The
## compendium at open-AIMS/grouping-structures runs every one of those models
## as its own array task and writes the assembled fits to a store; this file
## is how the store reaches the render. It also answers the vignette's
## post-fit calls, such as screen_models() and summary(), from the results
## the compendium stored in <store>/post/.
##
## Set BAYESNEC_FIT_STORE to the directory. Leave it unset and nothing here
## does anything, so an ordinary precompile is unaffected.
## keys_sha256: 5cfe4831b8f8e6ee

## The key a stored fit is filed under.
##
## The same key is computed in two places that never see each other's code: here,
## from the call this compendium extracted out of the vignette source, and in
## bayesnec's shim/fit_store.R, from the call the vignette actually makes while
## it is being knitted. Agreement between the two is what makes the store
## trustworthy, so the key is derived from the call and the data rather than from
## a name either side chooses. A vignette edit that changes a fit call changes
## its key, the render finds nothing under it, and the render stops -- which is
## the whole point. Keying by name instead would have loaded the old fit under
## the new code and said nothing.
##
## Kept free of every dependency but digest, because this file is copied verbatim
## into bayesnec and has to behave identically there.

FIT_FUNS <- c("bnec", "bnec_group", "bnec_hurdle", "bnec_joint")

## The fitting functions whose first argument is a fitted object rather than a
## data frame. bnec_joint() refits a bayesnecgroupfit or a bayesnechurdlefit as
## one model, so what it is handed is the result of an earlier call in the same
## vignette. There is no `data` to digest, and keying on the call alone would
## file two joint refits of two different grouped fits under one key.
FIT_FUNS_ON_FIT <- c("bnec_joint")

## bayesnec::bnec -> "bnec"; bnec -> "bnec"; anything else -> NA.
fit_fun_name <- function(e) {
  if (!is.call(e)) return(NA_character_)
  nm <- e[[1L]]
  if (is.call(nm) && as.character(nm[[1L]]) %in% c("::", ":::")) {
    nm <- nm[[3L]]
  }
  if (!is.name(nm)) return(NA_character_)
  nm <- as.character(nm)
  if (nm %in% FIT_FUNS) nm else NA_character_
}

## A call reduced to text that does not depend on how it was written.
##
## match.call() against the real definition names every argument and puts them in
## the formals' order, so `bnec(f, d)` and `bnec(data = d, formula = f)` normalise
## to the same string. The arguments are then sorted by name, which the formals'
## order already almost gives but which `...` arguments do not follow. `data` is
## dropped and digested separately: it is a whole data frame, and deparsing one
## would be both enormous and dependent on print width.
##
## `object` is dropped for the same reason and on the same terms, but only for
## the functions that take one: it names the fit being refitted, and what
## identifies that fit is its own key rather than the symbol the vignette
## happened to bind it to. joint_key() digests the key in its place.
##
## bnec_joint() is a generic, and the definition matched against here is the
## generic rather than the method, so only `object` is named by match.call() and
## everything else keeps whatever name the call gave it. Matching against the
## method would normalise `model` and `formula` as well, but it would mean the
## two sides choosing a method -- by class during the render and from the
## prerequisite's own function here -- and the whole value of this file is that
## both sides reach the same string without consulting each other.
##
## deparse() with a wide cutoff rather than deparse1(), because the file has to
## run under the R in the container as well as here.
normalise_fit_call <- function(cl, fn_name = fit_fun_name(cl)) {
  if (is.na(fn_name)) {
    stop("not a bayesnec fitting call: ", paste(deparse(cl), collapse = " "))
  }
  def <- get(fn_name, envir = asNamespace("bayesnec"))
  cl <- match.call(def, cl, expand.dots = TRUE)
  cl$data <- NULL
  if (fn_name %in% FIT_FUNS_ON_FIT) {
    cl$object <- NULL
  }
  args <- as.list(cl)[-1L]
  if (length(args)) {
    args <- args[order(names(args))]
  }
  parts <- vapply(seq_along(args), function(i) {
    paste0(names(args)[[i]], "=",
           paste(deparse(args[[i]], width.cutoff = 500L), collapse = " "))
  }, character(1L))
  paste(c(fn_name, parts), collapse = ";")
}

## The data frame is digested rather than deparsed. Both sides build it by
## running the vignette's own preparation code, so the objects are identical
## rather than merely equivalent, and digest() on the object itself is then both
## exact and cheap. It is exact about the things that decide a fit and are easy
## to change by accident: row order, factor levels and their order, and the
## numeric values to full precision.
fit_key <- function(cl, data, fn_name = fit_fun_name(cl)) {
  substr(digest::digest(list(call = normalise_fit_call(cl, fn_name),
                             data = data),
                        algo = "sha256"), 1L, 16L)
}

## A joint refit is keyed on its call and on the key of the fit it refits.
##
## The dependency is part of the identity rather than beside it: change the
## bnec_group() call and its key changes, so the joint refit's key changes with
## it and the render stops at the joint chunk instead of loading a refit of the
## previous draft. That is the same contract the data digest keeps for every
## other call in the store, reached the only way it can be reached for a call
## that is handed a fit rather than data.
##
## The list element is named `depends_on` rather than `data`, which keeps a
## joint refit's key out of the space fit_key() addresses even where a
## prerequisite key and a data frame happened to digest alike.
joint_key <- function(cl, depends_on, fn_name = fit_fun_name(cl)) {
  substr(digest::digest(list(call = normalise_fit_call(cl, fn_name),
                             depends_on = depends_on),
                        algo = "sha256"), 1L, 16L)
}

## The key a stored post-fit result is filed under.
##
## A post-fit call such as `summary(fit)` is identified by the key of the object
## it is handed, a fingerprint of that object, the function, and the values of
## its other arguments. Values rather than expressions, because a helper in the
## vignette passes `model = m` for each `m` in turn.
##
## The fingerprint catches an object changed in place after the store stamped
## it, which the key attribute alone would not. The bayesnec version is part of
## the key, so a result stored by another version is not replayed; it is left
## out of the seed, so the same call draws the same numbers under a new version.
post_identity <- function(input_key, fingerprint, fn_name, args) {
  digest::digest(list(input = input_key, fingerprint = fingerprint,
                      fn = fn_name, args = post_args_normalise(args)),
                 algo = "sha256")
}

post_key <- function(identity, version) {
  substr(digest::digest(list(identity = identity, version = version),
                        algo = "sha256"), 1L, 16L)
}

## The seed a post-fit call is evaluated under. Seven hex digits stay below
## .Machine$integer.max.
post_seed <- function(identity) {
  strtoi(substr(identity, 1L, 7L), 16L)
}

## Arguments sorted by name in C collation, which does not depend on the locale.
## Positional arguments keep their order among themselves.
post_args_normalise <- function(args) {
  if (!length(args)) return(list())
  nm <- names(args)
  if (is.null(nm)) nm <- rep("", length(args))
  ord <- order(nm, method = "radix")
  out <- lapply(args[ord], post_arg_value)
  names(out) <- nm[ord]
  out
}

## A function or formula is keyed by its text, since serialising it would
## serialise its environment. A closure whose result depends on that
## environment therefore keys by text alone. A fitted object is keyed by the
## key it carries.
post_arg_value <- function(v) {
  if (inherits(v, "bnecfit")) {
    k <- post_object_key(v)
    if (is.null(k)) stop("an argument is a fitted object the store did not answer")
    return(list(post_object_key = k))
  }
  if (is.function(v) || is.language(v) || inherits(v, "formula")) {
    return(paste(deparse(v, width.cutoff = 500L), collapse = " "))
  }
  if (is.environment(v)) stop("an argument is an environment")
  if (is.list(v) && !is.data.frame(v)) {
    out <- lapply(v, post_arg_value)
    names(out) <- names(v)
    return(out)
  }
  v
}

## The key an object carries: the key of the post-fit call that returned it,
## or else the key of the stored fit it is. NULL for anything else.
post_object_key <- function(x) {
  k <- attr(x, "post_store_key", exact = TRUE)
  if (is.null(k)) k <- attr(x, "fit_store_key", exact = TRUE)
  k
}

## The parts of a fitted object that identify it cheaply. Digesting the whole
## object would serialise every draw.
post_fingerprint <- function(x) {
  pick <- c("success_models", "mod_stats", "sample_size", "w_draw_seed",
            "w_ne", "model", "ne", "levels", "ne_type")
  parts <- unclass(x)[intersect(pick, names(x))]
  nested <- lapply(unclass(x), function(el) {
    if (inherits(el, "bnecfit")) {
      post_fingerprint(el)
    } else if (is.list(el) && length(el) &&
                 all(vapply(el, inherits, logical(1L), "bnecfit"))) {
      vapply(el, post_fingerprint, character(1L))
    }
  })
  nested <- Filter(Negate(is.null), nested)
  digest::digest(list(class = class(x), names = names(x), parts = parts,
                      nested = nested), algo = "sha256")
}

## The key of a component of a stored object, such as one level of a
## bayesnecgroupfit, derived from the key of the object that holds it.
post_part_key <- function(key, part, name) {
  substr(digest::digest(list(parent = key, part = part, name = name),
                        algo = "sha256"), 1L, 16L)
}

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
FIT_STORE_MIN_BAYESNEC <- "2.1.3.44"

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
  post_store_install(store, envir)
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
    fit_store_stamp(readRDS(path), key)
  }
}

## Stamp a stored fit with its key, and stamp each component that a post-fit
## call may be handed on its own, such as `fits$fits[[i]]`.
fit_store_stamp <- function(obj, key) {
  attr(obj, "fit_store_key") <- key
  post_store_stamp_parts(obj, key)
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

## ---------------------------------------------------------------------------
## Stored post-fit results
## ---------------------------------------------------------------------------
##
## Even with every fit read from the store, the vignette's own calls on those
## fits took about six hours. The compendium computes them once per stored set,
## in parallel, and files each result under post_key() in <store>/post/. The
## functions below answer the vignette's calls from there.
##
## Each call is evaluated under a seed derived from its key, and the render's
## random number stream is restored afterwards. A stored result is therefore
## the result this render would compute, whichever session computed it.
##
## BAYESNEC_POST_STORE is "replay" (the default: read a stored result, compute a
## missing one), "compute" (compute every call) or "off" (answer nothing).
## BAYESNEC_POST_STORE_RECORD=true writes each computed result to the store.
## BAYESNEC_POST_STORE_LOG names a file that receives one line per call.

## Loaded at install, before any call is answered. A post-fit call that
## loaded one of these itself would load it at a different point in a render
## that reads the call from the store.
POST_NAMESPACES <- c("rstan", "loo", "posterior")

## The functions answered, and the namespace that holds each real one.
POST_FUNS <- c(screen_models = "bayesnec", summary = "base",
               check_sampling = "bayesnec", pull_out = "bayesnec",
               ecx = "bayesnec", nsec = "bayesnec", nec = "bayesnec",
               rhat = "bayesnec", compare_posterior = "bayesnec",
               autoplot = "ggplot2")

post_store_install <- function(store, envir) {
  mode <- Sys.getenv("BAYESNEC_POST_STORE", "replay")
  if (identical(mode, "off")) {
    message("Post-fit store: off")
    return(invisible(FALSE))
  }
  if (!mode %in% c("replay", "compute")) {
    stop("BAYESNEC_POST_STORE must be \"replay\", \"compute\" or \"off\", not \"",
         mode, "\".", call. = FALSE)
  }
  dir <- file.path(store, "post")
  record <- identical(Sys.getenv("BAYESNEC_POST_STORE_RECORD"), "true")
  version <- as.character(utils::packageVersion("bayesnec"))
  log <- Sys.getenv("BAYESNEC_POST_STORE_LOG")
  for (ns in POST_NAMESPACES) requireNamespace(ns, quietly = TRUE)
  message("Post-fit store: ", dir, " (",
          length(list.files(dir, pattern = "\\.rds$")), " results, ", mode,
          if (record) ", recording", ")")
  pm <- file.path(dir, "MANIFEST")
  planned <- if (file.exists(pm)) {
    sub("^bayesnec: *", "", grep("^bayesnec:", readLines(pm), value = TRUE))
  }
  if (length(planned) && !identical(planned[[1L]], version)) {
    message("  The results were computed with bayesnec ", planned[[1L]],
            " and this is ", version, ", so none will be read and every\n",
            "  post-fit call will be computed. Rerun hpc/run.post with this ",
            "version to store them.")
  }
  for (nm in names(POST_FUNS)) {
    assign(nm, post_store_shim(nm, POST_FUNS[[nm]], dir, mode, record,
                               version, log), envir = envir)
  }
  invisible(TRUE)
}

post_store_shim <- function(fn_name, pkg, dir, mode, record, version, log) {
  force(fn_name); force(pkg); force(dir); force(mode); force(record)
  force(version); force(log)
  function(...) {
    real <- get(fn_name, envir = asNamespace(pkg))
    # list(...) forces the promises, so real(...) below does not evaluate the
    # arguments a second time.
    args <- post_store_args(real, list(...))
    key_in <- if (length(args)) post_object_key(args[[1L]])
    if (is.null(key_in)) return(real(...))
    x <- args[[1L]]
    identity <- tryCatch(
      post_identity(key_in, post_fingerprint(x), fn_name, args[-1L]),
      error = function(e) NULL)
    if (is.null(identity)) return(real(...))
    key <- post_key(identity, version)
    path <- file.path(dir, paste0(key, ".rds"))
    t0 <- proc.time()[["elapsed"]]
    hit <- identical(mode, "replay") && file.exists(path)
    if (hit) {
      rec <- readRDS(path)
      value <- if (isTRUE(rec$same_as_input)) x else rec$value
    } else {
      rec <- post_store_compute(function() real(...), post_seed(identity), x)
      value <- rec$value
      if (record) {
        rec$fn <- fn_name
        rec$call <- paste(deparse(sys.call(), width.cutoff = 500L),
                          collapse = " ")
        rec$input <- key_in
        rec$bayesnec <- version
        rec$recorded <- format(Sys.time())
        if (isTRUE(rec$same_as_input)) rec$value <- NULL
        post_store_write(rec, path)
      }
    }
    secs <- round(proc.time()[["elapsed"]] - t0, 1L)
    cat("post store: ", fn_name, "() on ", key_in, " -> ", key, ", ",
        if (hit) "read" else paste0("computed in ", secs, " s"),
        if (!hit && record) ", recorded", "\n", sep = "", file = stderr())
    if (nzchar(log)) {
      cat(fn_name, key_in, key, if (hit) "read" else "computed", secs,
          substr(paste(deparse(sys.call(), width.cutoff = 500L),
                       collapse = " "), 1L, 200L),
          sep = "\t", file = log, append = TRUE)
      cat("\n", file = log, append = TRUE)
    }
    post_store_emit(rec)
    value <- post_store_stamp(value, key)
    if (isTRUE(rec$visible)) value else invisible(value)
  }
}

## The arguments of a call, named as match.call() names them against the real
## function, with the object it is handed first. NULL where they cannot be
## matched, and the call is then run as written.
post_store_args <- function(real, vals) {
  if (!length(vals)) return(NULL)
  nm <- names(vals)
  if (is.null(nm)) nm <- rep("", length(vals))
  ph <- lapply(seq_along(vals), function(i) as.name(paste0("post_arg_", i)))
  names(ph) <- nm
  m <- tryCatch(match.call(real, as.call(c(list(quote(f)), ph)),
                           expand.dots = TRUE),
                error = function(e) NULL)
  if (is.null(m) || length(m) < 2L) return(NULL)
  margs <- as.list(m)[-1L]
  if (!identical(names(margs)[1L], names(formals(real))[1L])) return(NULL)
  idx <- as.integer(sub("^post_arg_", "",
                        vapply(margs, deparse, character(1L))))
  out <- vals[idx]
  names(out) <- names(margs)
  out
}

## Evaluate a call under `seed`, recording what it prints and signals rather
## than letting it through, so that a computed and a stored result reach the
## render by the same route: post_store_emit().
post_store_compute <- function(thunk, seed, x) {
  ns0 <- loadedNamespaces()
  opts0 <- options()
  events <- list()
  post_out <- NULL
  con <- textConnection("post_out", "w", local = TRUE)
  taken <- 0L
  take_output <- function(lines) {
    if (length(lines) > taken) {
      events[[length(events) + 1L]] <<-
        paste0(lines[(taken + 1L):length(lines)], "\n", collapse = "")
      taken <<- length(lines)
    }
  }
  # A condition's call is dropped: one raised under do.call() holds its
  # arguments' values, which can be a whole model set.
  keep <- function(cond) {
    take_output(textConnectionValue(con))
    cond$call <- NULL
    events[[length(events) + 1L]] <<- cond
  }
  sink(con)
  sunk <- TRUE
  on.exit(if (sunk) { sink(); close(con) }, add = TRUE)
  t0 <- proc.time()[["elapsed"]]
  # A namespace's load message depends on what the session has already loaded,
  # so it is dropped rather than replayed into a session where it is untrue.
  res <- withCallingHandlers(
    post_store_isolated(seed, withVisible(thunk())),
    packageStartupMessage = function(m) invokeRestart("muffleMessage"),
    message = function(m) { keep(m); invokeRestart("muffleMessage") },
    warning = function(w) { keep(w); invokeRestart("muffleWarning") })
  secs <- proc.time()[["elapsed"]] - t0
  sink()
  close(con)
  sunk <- FALSE
  take_output(post_out)
  list(value = res$value, visible = res$visible,
       same_as_input = identical(res$value, x), events = events,
       namespaces = setdiff(loadedNamespaces(), ns0),
       options = post_store_options_diff(opts0, options()),
       seconds = secs)
}

## Evaluate `expr` and restore the session's random number state afterwards,
## having first set `seed` unless it is NULL. The kind is restored before the
## seed, because .Random.seed[1] encodes it.
post_store_isolated <- function(seed, expr) {
  kind <- RNGkind()
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  old <- if (had) get(".Random.seed", envir = globalenv(), inherits = FALSE)
  on.exit({
    suppressWarnings(RNGkind(kind[1L], kind[2L], kind[3L]))
    if (had) {
      assign(".Random.seed", old, envir = globalenv())
    } else {
      suppressWarnings(rm(".Random.seed", envir = globalenv()))
    }
  }, add = TRUE)
  if (!is.null(seed)) {
    set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion",
             sample.kind = "Rejection")
  }
  expr
}

post_store_options_diff <- function(before, after) {
  same <- vapply(names(after), function(n) identical(after[[n]], before[[n]]),
                 logical(1L))
  removed <- setdiff(names(before), names(after))
  c(after[!same], stats::setNames(vector("list", length(removed)), removed))
}

## Replay what a call left behind: the namespaces it loaded, the options it
## set, then its output and conditions in the order they occurred. A
## namespace's .onLoad may draw random numbers, so the stream is restored.
post_store_emit <- function(rec) {
  post_store_isolated(NULL, for (ns in rec$namespaces) {
    requireNamespace(ns, quietly = TRUE)
  })
  if (length(rec$options)) options(rec$options)
  for (ev in rec$events) {
    if (is.character(ev)) {
      cat(ev)
    } else if (inherits(ev, "warning")) {
      warning(ev)
    } else if (inherits(ev, "message")) {
      message(ev)
    }
  }
  invisible(NULL)
}

## Written under a temporary name and renamed, so that a task killed part-way
## leaves no file that later reads as a stored result.
post_store_write <- function(rec, path) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  tmp <- paste0(path, ".part", Sys.getpid())
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(rec, tmp)
  if (!file.rename(tmp, path)) stop("could not write ", path, call. = FALSE)
  invisible(path)
}

post_store_stamp <- function(value, key) {
  if (!inherits(value, "bnecfit")) return(value)
  attr(value, "post_store_key") <- key
  post_store_stamp_parts(value, key)
}

post_store_stamp_parts <- function(obj, key) {
  if (inherits(obj, "bayesnecgroupfit") && is.list(obj$fits)) {
    nm <- names(obj$fits)
    if (is.null(nm)) nm <- as.character(seq_along(obj$fits))
    for (i in seq_along(obj$fits)) {
      if (inherits(obj$fits[[i]], "bnecfit")) {
        attr(obj$fits[[i]], "post_store_key") <- post_part_key(key, "fits", nm[[i]])
      }
    }
  }
  for (part in c("growth", "survival")) {
    if (inherits(obj[[part]], "bnecfit")) {
      attr(obj[[part]], "post_store_key") <- post_part_key(key, part, part)
    }
  }
  obj
}
