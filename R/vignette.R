## Reading the fit calls out of the vignette, and re-creating the objects they
## are given.
##
## Nothing here restates any of the vignette's code. The calls are extracted from
## the source, and the data each one is handed is built by running the vignette's
## own preparation code up to that point. A copy of the data preparation kept in
## this repository would be a second thing to maintain and a silent way for the
## store to be built on data the vignette does not use; the key would then agree
## with itself and disagree with the render.

## Chunks are read from the .Rmd.orig directly rather than through knitr::purl(),
## for one reason: purl() emits the code of a chunk marked `eval = FALSE` along
## with everything else. example8 shows one bnec() call it deliberately does not
## run -- the hurdle fit that does not converge -- and fitting it here would spend
## a task on a fit nothing reads and put a key in the store the render never asks
## for. Reading the headers is what lets that chunk be dropped.
read_chunks <- function(path) {
  ln <- readLines(path, warn = FALSE)
  fence <- grep("^```", ln)
  if (length(fence) %% 2L != 0L) {
    stop("unbalanced code fences in ", path)
  }
  opens <- fence[seq(1L, length(fence), by = 2L)]
  closes <- fence[seq(2L, length(fence), by = 2L)]
  keep <- grepl("^```\\{r[ ,}]", ln[opens])
  opens <- opens[keep]
  closes <- closes[keep]
  lapply(seq_along(opens), function(i) {
    header <- sub("^```\\{r *", "", sub("\\} *$", "", ln[opens[i]]))
    body <- if (closes[i] > opens[i] + 1L) ln[(opens[i] + 1L):(closes[i] - 1L)] else character(0)
    list(options = parse_chunk_options(header), code = body)
  })
}

## The header of a chunk, as a list. The label is the one item that may arrive
## without a name, so it is taken off the front before the rest is parsed as an
## argument list. A header this cannot parse stops the run rather than being
## skipped: a chunk silently dropped here is a fit missing from the store, and
## that is discovered hours later at the render.
parse_chunk_options <- function(header) {
  header <- trimws(header)
  label <- ""
  if (nzchar(header) && !grepl("^[A-Za-z.][A-Za-z0-9._]*\\s*=", header)) {
    label <- trimws(sub(",.*$", "", header))
    header <- sub("^[^,]*,?", "", header)
  }
  opts <- tryCatch(eval(parse(text = paste0("list(", header, ")"))),
                   error = function(e) {
                     stop("cannot parse chunk header {r ", header, "}: ",
                          conditionMessage(e), call. = FALSE)
                   })
  opts$label <- label
  opts
}

## Every expression the vignette evaluates, in order, with the chunk it came from
## recorded against it. Chunks marked `eval = FALSE` are left out entirely, so an
## expression's position here is its position in the run.
vignette_exprs <- function(path) {
  chunks <- read_chunks(path)
  runnable <- Filter(function(ch) !identical(ch$options$eval, FALSE), chunks)
  out <- list()
  for (ch in runnable) {
    if (!length(ch$code)) next
    exprs <- tryCatch(parse(text = ch$code),
                      error = function(e) {
                        stop("chunk \"", ch$options$label, "\" does not parse: ",
                             conditionMessage(e), call. = FALSE)
                      })
    for (e in exprs) {
      out[[length(out) + 1L]] <- list(expr = e, chunk = ch$options$label)
    }
  }
  out
}

## The fitting call inside an expression, or NULL. An assignment is unwrapped
## first, because every fit in the vignette is assigned to something.
fit_call_of <- function(e) {
  if (is.call(e) && as.character(e[[1L]])[1L] %in% c("<-", "=", "<<-")) {
    e <- e[[3L]]
  }
  if (!is.na(fit_fun_name(e))) e else NULL
}

assign_target <- function(e) {
  if (is.call(e) && as.character(e[[1L]])[1L] %in% c("<-", "=", "<<-")) {
    paste(deparse(e[[2L]]), collapse = "")
  } else {
    NA_character_
  }
}

## Run everything the vignette does before expression `upto`, so that the objects
## the fit at `upto` is handed exist and are the ones the render will hand it.
##
## Two kinds of expression are passed over. A fitting call is skipped outright:
## fits are what this pipeline exists to avoid running in sequence, and no fit in
## example8 feeds the data of a later one. Anything else that fails is reported
## and skipped, because the prefix necessarily includes the chunks that summarise
## and plot the fits that were just skipped, and those cannot run. That tolerance
## is the one risk in this design -- a genuine data-preparation failure would be
## swallowed the same way -- so every failure is returned and the caller logs it,
## and the key check downstream catches the case where it mattered.
run_prefix <- function(items, upto, env) {
  failures <- list()
  for (i in seq_len(upto - 1L)) {
    e <- items[[i]]$expr
    if (!is.null(fit_call_of(e))) next
    err <- tryCatch({
      withCallingHandlers(eval(e, env),
                          warning = function(w) invokeRestart("muffleWarning"),
                          message = function(m) invokeRestart("muffleMessage"))
      NULL
    }, error = function(e) conditionMessage(e))
    if (!is.null(err)) {
      failures[[length(failures) + 1L]] <- list(
        i = i, chunk = items[[i]]$chunk,
        code = paste(deparse(e, width.cutoff = 100L), collapse = " "),
        error = err)
    }
  }
  failures
}

## A fresh environment whose parent is the global one, so that library() calls in
## the vignette's own setup reach it and nothing this repository happens to have
## defined is visible to the vignette's code.
prefix_env <- function() new.env(parent = globalenv())
