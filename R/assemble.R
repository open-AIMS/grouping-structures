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

## c.bnecfit() takes every equation at once rather than being folded over them.
## Reduce() would run expand_manec() once per equation, drawing from the stream
## each time and doing the averaging work eighteen times to keep the last
## answer; one call does the averaging once, which is also what bnec() does.
assemble_models <- function(fits) {
  stopifnot(length(fits) > 0L)
  set.seed(ASSEMBLY_SEED)
  do.call(c, unname(fits))
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
