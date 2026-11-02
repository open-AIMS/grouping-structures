## Plan the post-fit array: one task per stored object, with memory and time
## sized to the object's file.
##
##   Rscript analysis/plan_post.R
##
## Writes <store>/post/tasks.csv, one row per task; <store>/post/classes.txt,
## one line per memory class, "<GB> <hours> <task ids>", from which
## hpc/run.post submits one array per line; and <store>/post/MANIFEST.

store <- Sys.getenv("GRP_STORE", "store")
idx <- utils::read.csv(file.path(store, "index.csv"), stringsAsFactors = FALSE)
paths <- file.path(store, paste0(idx$key, ".rds"))
if (!all(file.exists(paths))) {
  stop("index.csv names objects the store does not hold: ",
       paste(idx$target[!file.exists(paths)], collapse = ", "), call. = FALSE)
}
mb <- round(file.size(paths) / 1e6)

# Peak memory and time grow with the size of the set. The bounds are on the
# file size in MB; README.md gives the measurements they were set from.
classes <- data.frame(upto_mb = c(150, 400, 800, Inf),
                      mem_gb = c(8, 16, 24, 48),
                      hours = c(2, 3, 4, 6))
cls <- findInterval(mb, classes$upto_mb, left.open = TRUE) + 1L

tasks <- data.frame(key = idx$key, target = idx$target, mb = mb,
                    mem_gb = classes$mem_gb[cls], hours = classes$hours[cls],
                    stringsAsFactors = FALSE)
tasks <- tasks[order(-tasks$mb), , drop = FALSE]
tasks$task <- seq_len(nrow(tasks))
tasks <- tasks[, c("task", "key", "target", "mb", "mem_gb", "hours")]

dir.create(file.path(store, "post"), showWarnings = FALSE, recursive = TRUE)
utils::write.csv(tasks, file.path(store, "post", "tasks.csv"),
                 row.names = FALSE)
# The shim compares this version with its own and says so where they differ:
# the version is part of every post-fit key, so none would be read.
lock <- if (file.exists("hpc/bayesnec.lock")) readLines("hpc/bayesnec.lock")
writeLines(c(paste("bayesnec:", utils::packageVersion("bayesnec")),
             grep("^commit: ", lock, value = TRUE),
             paste("planned:", format(Sys.time()))),
           file.path(store, "post", "MANIFEST"))
lines <- vapply(split(tasks, tasks$mem_gb), function(t) {
  paste(t$mem_gb[1L], max(t$hours), paste(t$task, collapse = ","))
}, character(1L))
writeLines(lines, file.path(store, "post", "classes.txt"))

print(tasks, row.names = FALSE)
cat("\n", paste(lines, collapse = "\n"), "\n", sep = "")
