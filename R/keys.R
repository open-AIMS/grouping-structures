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
