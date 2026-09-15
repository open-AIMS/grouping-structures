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

FIT_FUNS <- c("bnec", "bnec_group", "bnec_hurdle")

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
## deparse() with a wide cutoff rather than deparse1(), because the file has to
## run under the R in the container as well as here.
normalise_fit_call <- function(cl, fn_name = fit_fun_name(cl)) {
  if (is.na(fn_name)) {
    stop("not a bayesnec fitting call: ", paste(deparse(cl), collapse = " "))
  }
  def <- get(fn_name, envir = asNamespace("bayesnec"))
  cl <- match.call(def, cl, expand.dots = TRUE)
  cl$data <- NULL
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
