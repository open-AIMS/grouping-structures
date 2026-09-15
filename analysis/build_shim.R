## Write the single file bayesnec carries, from R/keys.R and shim/fit_store_body.R.
##
##   Rscript analysis/build_shim.R [path/to/bayesnec/vignettes/fit_store.R]
##
## One file rather than two, because it is copied into another repository and a
## pair of files that have to be copied together is a pair that will one day be
## copied apart. The digest of R/keys.R is written into it so that a copy which
## has fallen behind can be detected rather than inferred.

args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args)) args[[1L]] else "shim/fit_store.R"

keys <- readLines("R/keys.R", warn = FALSE)
body <- readLines("shim/fit_store_body.R", warn = FALSE)
sha <- substr(digest::digest(paste(keys, collapse = "\n"), algo = "sha256"),
              1L, 16L)

header <- c(
  "## Loading precompiled fits from a store, instead of fitting them.",
  "##",
  "## GENERATED FILE -- do not edit here.",
  "## Source: grouping-structures/R/keys.R + shim/fit_store_body.R",
  "## Regenerate with: Rscript analysis/build_shim.R <path to this file>",
  "##",
  "## example8 fits 189 models. Run in sequence at the cluster's four cores that",
  "## is the better part of a day, which is longer than the walltime and far",
  "## longer than a vignette should take to rebuild after a prose edit. The",
  "## compendium at open-AIMS/grouping-structures runs every one of those models",
  "## as its own array task and writes the assembled fits to a store; this file",
  "## is how the store reaches the render.",
  "##",
  "## Set BAYESNEC_FIT_STORE to the directory. Leave it unset and nothing here",
  "## does anything, so an ordinary precompile is unaffected.",
  paste0("## keys_sha256: ", sha),
  "")

writeLines(c(header, keys, body), out)
cat("written:", out, "\n  keys_sha256:", sha, "\n")
