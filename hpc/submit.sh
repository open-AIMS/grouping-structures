#!/bin/bash
# Submit the study: install and gate, then the fitting array, then the assembly.
#
#   ./hpc/submit.sh [MAX_RESIDENT]
#
# Three jobs chained on afterok. The array waits on the install because nothing
# should sample until bayesnec is installed, the manifest is built against the
# deployed vignette, and the keys have been checked against it. The assembly
# waits on the array because a store assembled from part of a model set would be
# a different model average with nothing to say so.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# sbatch is not on PATH in a non-interactive shell on this cluster; it comes from
# a module, so a plain `ssh host ./hpc/submit.sh` otherwise submits nothing.
command -v sbatch > /dev/null 2>&1 || module load slurm 2>/dev/null || true
command -v sbatch > /dev/null 2>&1 || {
  echo "sbatch not on PATH even after 'module load slurm'" >&2; exit 1; }

MAX_RESIDENT="${1:-60}"
mkdir -p logs

# The array width is read from the manifest where one exists, and otherwise from
# the count example8 currently has. The install job rebuilds the manifest against
# the deployed vignette, so on a first run the manifest is not there yet; a width
# that is too small would silently leave units unfitted, so the default is the
# known count and the assembly reports anything missing.
if [ -f manifest.csv ]; then
  N=$(tail -n +2 manifest.csv | wc -l)
else
  N="${GRP_UNITS_N:-189}"
fi

INSTALL=$(sbatch --parsable hpc/run.install)
echo "install + gate: $INSTALL"

UNITS=$(sbatch --parsable --dependency=afterok:"$INSTALL" \
        --array=1-"$N"%"$MAX_RESIDENT" hpc/run.units)
echo "units:          $UNITS  ($N tasks, $MAX_RESIDENT resident)"

ASSEMBLE=$(sbatch --parsable --dependency=afterok:"$UNITS" hpc/run.assemble)
echo "assemble:       $ASSEMBLE"

cat <<TXT

watch:    squeue -u \$USER
progress: ls units/*.rds | wc -l          # of $N
store:    ls store/*.rds
TXT
