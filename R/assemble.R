## Putting the units back together into the objects the vignette expects.
##
## A model set assembled from separately fitted equations is not bit-identical to
## one fitted by a single bnec() call, and the difference is worth stating
## plainly because it is the price of the parallelism.
##
## Each equation is identical: a unit passes the vignette's own `seed` through to
## brm(), so the equation samples from the same stream whether it was fitted
## alone or eighteenth in a set. What differs is the model-averaged layer.
## expand_manec() draws from the session's random number stream to build the
## averaged prediction grid, and a session that has just fitted seventeen other
## equations is at a different point in that stream than one that has fitted
## none. ASSEMBLY_SEED is set immediately before the combination for that reason:
## it does not make the result equal to a monolithic run, it makes this run
## repeatable. The same point is documented in bnec()'s own "Fitting a model set
## in parallel" section, which says that the averaged quantities are not
## reproduced between a sequential and a parallel run even with a seed.
ASSEMBLY_SEED <- 228L

## The equations are combined through expand_manec(), which is the call bnec()
## itself makes, rather than through the exported c.bnecfit().
##
## c.bnecfit() was the obvious route and it does not work here. It runs
## check_data_equality(), which compares `as.matrix(fit$data)` between fits with
## identical(). brms orders the columns of `fit$data` by the model formula, and
## the hormesis equations put the predictor before the grouping factor where the
## others put it after: on fit_pam the five hormesis equations came back with
## `yield, diuron, chamber` against the others' `yield, chamber, diuron`. Every
## value is the same and every column is the same; only the order differs, and
## identical() is order-sensitive, so the combination was refused. A monolithic
## bnec() never meets that check, because it hands its prebayesnecfit list
## straight to expand_manec(). Reported as a bayesnec issue; doing the same here
## is both the fix and the closer reproduction of what bnec() does.
##
## Folding with Reduce() would be wrong for a second reason: it would run
## expand_manec() once per equation, drawing from the stream each time and doing
## the averaging work eighteen times to keep the last answer. One call does the
## averaging once, which is what bnec() does.
assemble_models <- function(fits, call_args = list()) {
  stopifnot(length(fits) > 0L)
  mod_fits <- unlist(lapply(unname(fits), bayesnec:::recover_prebayesnecfit),
                     recursive = FALSE)
  mod_fits <- mod_fits[!duplicated(names(mod_fits))]
  formulas <- lapply(mod_fits, bayesnec:::extract_formula)
  args <- list(object = mod_fits, formula = formulas)
  # Forwarded from the vignette's own call where it set them, and left to
  # expand_manec()'s defaults where it did not -- which is what bnec() passes
  # when its own defaults are untouched.
  for (a in c("x_range", "resolution", "sig_val", "loo_controls")) {
    if (!is.null(call_args[[a]])) args[[a]] <- call_args[[a]]
  }
  set.seed(ASSEMBLY_SEED)
  out <- do.call(bayesnec:::expand_manec, args)
  if (length(out) == 1L) {
    # bnec() takes this branch too: a set that came down to one equation is a
    # bayesnecfit, expanded through expand_nec() rather than left as a
    # one-element model average.
    nec_args <- list(object = out[[1L]], formula = formulas[[1L]],
                     model = names(out))
    for (a in c("x_range", "resolution", "sig_val", "loo_controls")) {
      if (!is.null(call_args[[a]])) nec_args[[a]] <- call_args[[a]]
    }
    out <- do.call(bayesnec:::expand_nec, nec_args)
    class(out) <- c("bayesnecfit", "bnecfit")
  } else {
    class(out) <- c("bayesmanecfit", "bnecfit")
  }
  # expand_manec() does not carry retained_data: bnec() attaches it to the
  # completed object afterwards, so a set reassembled here loses the columns
  # that autoplot() colours by when the variable is not in the fitted formula.
  # The rule is the one c.bnecfit() uses -- carry them where every input agrees,
  # and drop them where they do not, because a set whose members saw different
  # data has no single frame to align observations against.
  retained <- Filter(Negate(is.null),
                     lapply(unname(fits), function(f) f[["retained_data"]]))
  if (length(retained) > 0L &&
      all(vapply(retained[-1], identical, logical(1), retained[[1]]))) {
    out$retained_data <- retained[[1]]
  }
  out
}

## The order is the order bnec() would have fitted in, which is the order
## check_models() returned and the manifest recorded. It decides the row order of
## mod_stats and so the order weights are reported in, and a table in the
## vignette that named its rows by position would otherwise be silently wrong.
assemble_group <- function(level_fits, plan, formula_expr, data, env) {
  out <- list(fits = level_fits,
              group_var = plan$group_var,
              levels = plan$levels,
              formula = bayesnec::bayesnecformula(eval(formula_expr, env)),
              data = data,
              family = plan$family_stored,
              n = plan$n,
              weights_method = plan$weights_method)
  class(out) <- c("bayesnecgroupfit", "bnecfit")
  out
}

unit_path <- function(root, key, level, model) {
  bits <- c(key, if (!is.na(level)) gsub("[^A-Za-z0-9]+", "-", level) else NULL,
            if (!is.na(model)) model else NULL)
  file.path(root, paste0(paste(bits, collapse = "__"), ".rds"))
}

store_path <- function(root, key) file.path(root, paste0(key, ".rds"))
