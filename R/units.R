## Splitting a fit call into the smallest pieces that can be run on their own,
## and running one of them.
##
## A unit is one equation of one model set, on one level where the call is a
## bnec_group() one. That is the finest grain bayesnec supports being reassembled
## at: c.bnecfit() builds a bayesmanecfit out of separately fitted equations, and
## a bayesnecgroupfit is a plain list of per-level fits. The wall clock of the
## whole vignette then becomes the wall clock of its slowest single equation
## rather than the sum of all 189.
##
## A call this cannot decompose -- anything that is not bnec() or bnec_group() --
## becomes one unit holding the whole call. It is still run in parallel with
## every other call; it simply does not divide any further.

## The candidate set as bnec() will actually fit it.
##
## get_priors() is the oracle rather than models() or a copy of the filtering
## rules, because it runs check_models() on the same formula, family and model
## frame that bnec() runs it on, and returns one element per surviving equation.
## It is exported, so this does not depend on an internal staying where it is.
## Reimplementing the filter here would be a second copy of a decision that
## belongs to the package, and it would be wrong the moment the package changed.
expand_model_set <- function(formula_expr, data, family_expr, prior_type_expr, env) {
  gp <- as.call(list(quote(bayesnec::get_priors), formula_expr, quote(.set_data)))
  names(gp)[2:3] <- c("object", "data")
  if (!is.null(family_expr)) gp$family <- family_expr
  if (!is.null(prior_type_expr)) gp$prior_type <- prior_type_expr
  senv <- new.env(parent = env)
  assign(".set_data", data, envir = senv)
  names(eval(gp, senv))
}

## Rewrite crf()'s model argument to a single equation, wherever crf() sits in
## the formula. The model set is read off the formula by
## get_model_from_formula(), not off a `model =` argument -- that one is
## deprecated -- so this is the only place a single-equation fit can be asked
## for.
set_crf_model <- function(e, model) {
  if (!is.call(e)) return(e)
  if (identical(as.character(e[[1L]])[1L], "crf")) {
    nms <- names(e)
    if (!is.null(nms) && "model" %in% nms) {
      e[["model"]] <- model
    } else {
      # crf(x, model, arg_to_retrieve): the model is the second argument, and
      # every call in the vignette gives it positionally.
      e[[3L]] <- model
    }
    return(e)
  }
  for (i in seq_along(e)) {
    if (!is.null(e[[i]]) && is.call(e[[i]])) e[[i]] <- set_crf_model(e[[i]], model)
  }
  e
}

## The family bnec_group() settles on for every level, and the level sizes.
##
## bnec_group() chooses the family once from the whole response and hands the
## same one to every level, so a per-level task that let bnec() choose again
## could get a different family on a level whose response happens to look
## different. These three lines mirror R/bnec_group.R on dev, through the same
## internals it uses. ::: is used deliberately: this is a compendium and not a
## package, R CMD check never reads it, and a parallel implementation of
## set_distribution() would be the wrong answer the moment the package changed.
group_plan <- function(cl, data, env) {
  form <- bayesnec::bayesnecformula(eval(cl$formula, env))
  group_var <- eval(cl$group_var, env)
  grp <- factor(data[[group_var]])
  mod_dat <- stats::model.frame(form, data = data)
  link_source <- bayesnec:::family_link_source(cl$family, env = env)
  fam <- if (is.null(cl$family)) NULL else eval(cl$family, env)
  if (is.null(fam)) {
    y <- bayesnec:::retrieve_var(mod_dat, "y_var", error = TRUE)
    tr <- bayesnec:::retrieve_var(mod_dat, "trials_var")
    fam <- bayesnec:::set_distribution(y, support_integer = TRUE, trials = tr)
  }
  # Two forms of the same family are kept. bnec_group() hands the marked one to
  # every bnec() call -- the mark is what keeps validate_family() idempotent, so
  # passing it is what stops the link being reassigned per level -- and stores
  # the unmarked one on the object it returns. A unit that fitted with the
  # unmarked form would be validated a second time and could differ.
  marked <- bayesnec:::validate_family(fam, link_source = link_source)
  counts <- table(grp)
  list(group_var = group_var, levels = levels(grp),
       family = marked, family_stored = bayesnec:::unmark_family(marked),
       n = as.integer(counts[levels(grp)]), grp = grp,
       weights_method = group_weights_method(cl, env))
}

## pseudobma unless the call asked for something else, which is the rule
## bnec_group() applies. Recorded rather than read back off the fits, because
## the attribute expand_manec() stamps on the weight vector does not survive
## row-subsetting and is absent altogether from a level that fitted one equation.
group_weights_method <- function(cl, env) {
  lc <- if (is.null(cl$loo_controls)) NULL else eval(cl$loo_controls, env)
  if (!is.null(lc$weights$method)) lc$weights$method else "pseudobma"
}

## The units one fit call divides into. Returned as a data frame so the manifest
## is one table and an array task is one row of it.
plan_units <- function(cl, fn_name, data, env) {
  if (identical(fn_name, "bnec")) {
    models <- expand_model_set(cl$formula, data, cl$family, cl$prior_type, env)
    data.frame(level = NA_character_, model = models, stringsAsFactors = FALSE)
  } else if (identical(fn_name, "bnec_group")) {
    plan <- group_plan(cl, data, env)
    # The family is referred to by symbol rather than spliced in as a value, so
    # that bayesnec sees the same kind of expression bnec_group() gives bnec()
    # and resolves the link the same way. See family_link_source() and #256.
    penv <- new.env(parent = env)
    assign(".plan_family", plan$family, envir = penv)
    do.call(rbind, lapply(plan$levels, function(lev) {
      sub <- data[plan$grp == lev, , drop = FALSE]
      data.frame(level = lev,
                 model = expand_model_set(cl$formula, sub, quote(.plan_family),
                                          cl$prior_type, penv),
                 stringsAsFactors = FALSE)
    }))
  } else {
    # Not decomposable: bnec_hurdle() fits two model sets of its own and has no
    # published route back from their parts. It runs whole, as one task.
    data.frame(level = NA_character_, model = NA_character_,
               stringsAsFactors = FALSE)
  }
}

## Run one unit and return the fit.
##
## The call is the vignette's own, with two changes and no others: the formula's
## model set is narrowed to this unit's equation, and where the call was a
## bnec_group() one the data is narrowed to this unit's level and the family is
## passed explicitly. Everything else -- chains, iter, warmup, seed, adapt_delta,
## the priors bayesnec derives -- is left exactly as the vignette wrote it, which
## is what makes the stored fit the fit the vignette's visible code describes.
run_unit <- function(cl, fn_name, data, env, level = NA, model = NA, plan = NULL) {
  if (!identical(fn_name, "bnec") && !identical(fn_name, "bnec_group")) {
    return(eval(cl, env))
  }
  ucl <- cl
  ucl$formula <- set_crf_model(cl$formula, model)
  if (identical(fn_name, "bnec_group")) {
    if (is.null(plan)) plan <- group_plan(cl, data, env)
    data <- data[plan$grp == level, , drop = FALSE]
    ucl$family <- quote(.plan_family)
    ucl$group_var <- NULL
  }
  ucl[[1L]] <- quote(bayesnec::bnec)
  ucl$data <- quote(.unit_data)
  uenv <- new.env(parent = env)
  assign(".unit_data", data, envir = uenv)
  if (identical(fn_name, "bnec_group")) {
    assign(".plan_family", plan$family, envir = uenv)
  }
  eval(ucl, uenv)
}

## The candidate set as requested, as attempted, and what was dropped between.
##
## bnec() attaches this to every fit it returns, and bnec_record() is what a
## methods section reads to state the set as requested against the set as fitted.
## An assembled object would otherwise carry the record of whichever unit came
## first, whose request was one equation: a fit whose call said "all" would
## report `requested = "ecxll3"`, which is not approximately right but wrong.
##
## Four internals are used, and they are the ones bnec() itself runs in this
## order. A parallel implementation of check_models() would be the wrong answer
## the moment the package changed, and these fail loudly at assembly rather than
## silently: a rename stops the run.
model_set_record <- function(formula_expr, data, family_expr, env) {
  form <- bayesnec::bayesnecformula(eval(formula_expr, env))
  bdat <- stats::model.frame(form, data = data, run_par_checks = TRUE)
  link_source <- bayesnec:::family_link_source(family_expr, env = env)
  fam_args <- if (is.null(family_expr)) {
    list()
  } else {
    list(family = eval(family_expr, env))
  }
  family <- bayesnec:::retrieve_valid_family(fam_args, bdat,
                                             link_source = link_source)
  requested <- bayesnec:::get_model_from_formula(form)
  attempted <- suppressMessages(
    bayesnec:::check_models(requested, family, bdat, record = TRUE))
  list(requested = as.character(requested),
       attempted = as.character(attempted),
       excluded = attr(attempted, "excluded"))
}
