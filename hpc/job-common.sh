#!/bin/bash
# Shared setup for every job in this study. Sourced, not executed.
#
# Adapted from open-AIMS/negative-response-conventions, which is the compendium
# behind example7, so that one set of habits covers both. The differences are
# noted where they occur; the main one is the Stan program cache, which is
# per-task here rather than shared.

set -euo pipefail

# `module` returns non-zero where these are already loaded, which under `set -e`
# would end the job before it started.
module load slurm || true
module load singularity || true
command -v singularity > /dev/null || {
  echo "singularity not on PATH after 'module load singularity'" >&2; exit 1; }

STUDY="${GRP_STUDY:-/export/scratch/$USER/grouping-structures}"
cd "$STUDY"
mkdir -p logs units store

SIF="$STUDY/bayesnec-precompile.sif"
LIB="$STUDY/lib"
SRC="$STUDY/bayesnec-src"

# The image is half of what determines the stored fits, so a job refuses to run
# against one the branch does not record. The same refusal as bayesnec's
# hpc/run.precompile, and for the same reason: rebuilding the image is a change
# that can alter published numbers and has to be made deliberately.
[ -f "$SIF" ] || { echo "no container at $SIF" >&2; exit 1; }
lock_sha=$(sed -n 's/^sif_sha256: //p' hpc/image.lock)
have_sha=$(sha256sum "$SIF" | cut -d' ' -f1)
if [ "$lock_sha" != "$have_sha" ]; then
  echo "image does not match hpc/image.lock" >&2
  echo "  hpc/image.lock: $lock_sha" >&2
  echo "  $SIF: $have_sha" >&2
  echo "Copy the image this branch records, or rebuild it in the bayesnec" >&2
  echo "repository and update both hpc/image.lock files." >&2
  exit 1
fi

# apptainer bind-mounts $HOME, so without this the container's R reads the
# account's own library and startup files from the host and can load a bayesnec
# that is not the one installed here. Verified on 2026-09-10 in bayesnec #308:
# an image built with no bayesnec in it reported bayesnec as available.
RENV=(--env R_LIBS="$LIB" --env R_LIBS_USER="$LIB" --env R_LIBS_SITE=
      --env R_ENVIRON_USER=/dev/null --env R_PROFILE_USER=/dev/null)

# One Stan program cache per array task, not one shared between them.
#
# This is the one place this study departs from the example7 compendium, and the
# reason is a property of the fits rather than a preference. bayesnec derives its
# priors from the response and brms writes them into the Stan source as literals,
# so two units differ in their Stan source wherever their data differ -- and
# every unit here is a different equation, a different level or a different
# dataset. There is almost nothing for a shared cache to reuse. What a shared
# cache would still do is let two tasks write the same file and run make on the
# same executable path at the same time, which is the collision the example7
# compendium spends a warm-up array avoiding. Per-task directories remove the
# collision instead of ordering around it, and they keep a re-run of a single
# timed-out unit warm, which is the reuse that actually happens here.
CACHE="${GRP_STAN_CACHE:-$STUDY/stan-cache/task-${SLURM_ARRAY_TASK_ID:-single}}"
mkdir -p "$CACHE"

# Run one Rscript inside the container with the study bound and the host's R
# libraries kept out.
grp_r() {
  singularity exec -B "$STUDY":"$STUDY" --pwd "$STUDY" \
    "${RENV[@]}" --env GRP_STAN_CACHE="$CACHE" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK:-4}" \
    "$SIF" Rscript "$@"
}

# Assert that the bayesnec about to be loaded is the one the study pins, and that
# it resolved to the job library rather than to something the host bound in.
grp_check_bayesnec() {
  local want_version
  want_version=$(sed -n 's/^version: //p' hpc/bayesnec.lock)
  singularity exec -B "$STUDY":"$STUDY" --pwd "$STUDY" "${RENV[@]}" \
    --env GRP_JOB_LIB="$LIB" --env GRP_WANT_VERSION="$want_version" "$SIF" \
    Rscript -e '
      lib <- normalizePath(Sys.getenv("GRP_JOB_LIB"))
      p <- find.package("bayesnec")
      if (!identical(normalizePath(dirname(p)), lib))
        stop("bayesnec resolved to ", p, ", not the job library ", lib)
      v <- as.character(packageVersion("bayesnec"))
      if (!identical(v, Sys.getenv("GRP_WANT_VERSION")))
        stop("bayesnec ", v, " installed, but hpc/bayesnec.lock pins ",
             Sys.getenv("GRP_WANT_VERSION"))
      cat("bayesnec", v, "from", p, "\n")'
}
