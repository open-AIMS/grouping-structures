## The evidence behind the plate-term comparison in example8 (#382).
##
##   Rscript analysis/plate_term_evidence.R
##
## Reads the assembled store by key and extracts what the vignette has to
## report: the stacking weights, the group-level standard deviations, the
## threshold estimates and the sampler and leave-one-out diagnostics, for the
## fits that differ only in their group-level term.
##
## Run on the cluster rather than after fetching. The store is 1.45 GB and the
## numbers wanted from it are a few kilobytes; ecx() and nsec() across a
## fourteen-equation set is the cost bayesnec #306 measured, and it is paid once
## here instead of once per local experiment.
##
## Nothing here restates a fit call. The fits are located by the key
## store/index.csv files them under, which is the same contract the render uses.

suppressPackageStartupMessages({
  library(bayesnec)
  library(brms)
})

store <- Sys.getenv("GRP_STORE", "store")
out   <- Sys.getenv("GRP_EVIDENCE_OUT", "plate_term_evidence")
idx   <- read.csv(file.path(store, "index.csv"), stringsAsFactors = FALSE)

## The seven fits the comparison is made over. fit_pooled and fit_plate are the
## two the vignette already fits; the other five were added for #382.
wanted <- c("fit_pooled", "fit_plate", "fit_pgl", "fit_batch", "fit_plate_batch",
            "fit_nec_ogl", "fit_nec_gl")
stopifnot(all(wanted %in% idx$target))

read_fit <- function(target) {
  key <- idx$key[match(target, idx$target)]
  readRDS(file.path(store, paste0(key, ".rds")))
}

fits <- lapply(wanted, read_fit)
names(fits) <- wanted

## ---- stacking weights ------------------------------------------------------
## Reported in full because a diagnostic is read against the weight the equation
## it was computed on carries, which is the rule bayesnec/CLAUDE.md records.
weights_of <- function(x, label) {
  w <- summary(x)$mod_weights
  data.frame(fit = label, model = rownames(w), w, row.names = NULL)
}
weights <- do.call(rbind, Map(weights_of, fits, names(fits)))

## ---- group-level standard deviations ---------------------------------------
## VarCorr() per equation, on the scale of the parameter the deviation applies
## to. The weight is carried alongside so that a large standard deviation on an
## equation holding no weight is not read as a property of the model average.
sds_of <- function(x, label) {
  w <- summary(x)$mod_weights
  mods <- rownames(w)
  do.call(rbind, lapply(mods, function(m) {
    f <- suppressWarnings(pull_out(x, model = m))
    vc <- try(brms::VarCorr(f$fit), silent = TRUE)
    if (inherits(vc, "try-error") || !length(vc)) return(NULL)
    do.call(rbind, lapply(names(vc), function(g) {
      sd <- vc[[g]]$sd
      if (is.null(sd)) return(NULL)
      data.frame(fit = label, model = m, wi = w[m, "wi"], grouping = g,
                 parameter = rownames(sd),
                 sd = sd[, "Estimate"], lower = sd[, "Q2.5"], upper = sd[, "Q97.5"],
                 row.names = NULL)
    }))
  }))
}
sds <- do.call(rbind, Map(sds_of, fits, names(fits)))

## ---- thresholds ------------------------------------------------------------
## xform = exp because the predictor is fitted as log(conc); without it the
## estimate is the logarithm of a concentration labelled as a concentration.
thr_of <- function(x, label) {
  e10 <- try(ecx(x, ecx_val = 10, xform = exp), silent = TRUE)
  ns  <- try(nsec(x, xform = exp), silent = TRUE)
  ne  <- try(nec(x, xform = exp), silent = TRUE)
  g <- function(v) if (inherits(v, "try-error")) rep(NA_real_, 3L) else as.numeric(v)[1:3]
  data.frame(fit = label,
             quantity = c("ec10", "nsec", "nec"),
             rbind(g(e10), g(ns), g(ne)), row.names = NULL)
}
thresholds <- do.call(rbind, Map(thr_of, fits, names(fits)))
names(thresholds)[3:5] <- c("estimate", "lower", "upper")

## ---- sampler and leave-one-out ---------------------------------------------
## check_sampling() reports the equations that did not sample; the Pareto-k
## count comes from the loo object each fit already holds, so nothing is refitted.
sampling <- do.call(rbind, Map(function(x, label) {
  cs <- try(check_sampling(x), silent = TRUE)
  if (inherits(cs, "try-error")) return(data.frame(fit = label, note = "check_sampling failed"))
  data.frame(fit = label, model = names(cs), flagged = unlist(cs), row.names = NULL)
}, fits, names(fits)))

pareto_of <- function(x, label) {
  w <- summary(x)$mod_weights
  do.call(rbind, lapply(rownames(w), function(m) {
    f <- suppressWarnings(pull_out(x, model = m))
    l <- try(f$fit$criteria$loo, silent = TRUE)
    if (inherits(l, "try-error") || is.null(l)) return(NULL)
    k <- try(l$diagnostics$pareto_k, silent = TRUE)
    if (inherits(k, "try-error") || is.null(k)) return(NULL)
    data.frame(fit = label, model = m, wi = w[m, "wi"], n = length(k),
               k_gt_0.7 = sum(k > 0.7), k_max = max(k), row.names = NULL)
  }))
}
pareto <- do.call(rbind, Map(pareto_of, fits, names(fits)))

## ---- dispersion ------------------------------------------------------------
## summary()$mod_weights already carries it for the families the test applies to,
## so it is taken from there rather than recomputed per equation.
disp <- weights[, intersect(names(weights),
                            c("fit", "model", "wi", "dispersion_Estimate",
                              "dispersion_Q2.5", "dispersion_Q97.5"))]

res <- list(weights = weights, sds = sds, thresholds = thresholds,
            sampling = sampling, pareto = pareto, dispersion = disp,
            store_manifest = readLines(file.path(store, "MANIFEST")),
            bayesnec = as.character(packageVersion("bayesnec")),
            extracted = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
saveRDS(res, paste0(out, ".rds"))

sink(paste0(out, ".txt"))
for (nm in c("store_manifest", "bayesnec", "extracted")) {
  cat("== ", nm, " ==\n"); print(res[[nm]]); cat("\n")
}
for (nm in c("thresholds", "sds", "weights", "sampling", "pareto")) {
  cat("== ", nm, " ==\n"); print(res[[nm]], digits = 4); cat("\n")
}
sink()
cat("written: ", out, ".rds and ", out, ".txt\n", sep = "")
