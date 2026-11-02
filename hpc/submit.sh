#!/bin/bash
# Submit the study: install and gate, the fitting array, the assembly, the
# joint refits, the post-fit array and the render.
#
#   ./hpc/submit.sh [MAX_RESIDENT]
#
# Five jobs chained here, and the post-fit array and the render submitted by
# the last of them. The array waits on the install because nothing should sample
# until bayesnec is installed, the manifest is built against the deployed
# vignette, and the keys have been checked against it. The assembly waits on the
# array because a store assembled from part of a model set would be a different
# model average with nothing to say so. The joint refits wait on the assembly
# because bnec_joint() is handed the assembled object, not the units it was
# assembled from.
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

# afterany, not afterok. An equation that cannot be fitted is now recorded by
# run_unit.R and the task exits zero, so a non-zero task is a task that did not
# finish -- a timeout, a node failure, an out-of-memory kill. Under afterok one
# of those would leave the assembly cancelled as DependencyNeverSatisfied, which
# is the wrong gate: assemble_store.R already refuses to write a call that is
# short a unit, and reports which. Let it run and say so.
ASSEMBLE=$(sbatch --parsable --dependency=afterany:"$UNITS" hpc/run.assemble)
echo "assemble:       $ASSEMBLE"

# afterok here, not afterany. A joint refit reads its prerequisite out of the
# store, so an assembly that did not finish leaves nothing to read; run_joint.R
# would stop on the missing file, and a job that cannot start is the clearer
# report. Submitted unconditionally: the manifest is built inside run.install, so
# this script cannot yet know whether the vignette has a joint refit in it, and
# run_joint.R exits zero saying so when it has none.
JOINT=$(sbatch --parsable --dependency=afterok:"$ASSEMBLE" hpc/run.joint)
echo "joint refits:   $JOINT"

# run.post sizes the post-fit array from the assembled store, so it submits the
# array and the render itself.
POST=$(sbatch --parsable --dependency=afterok:"$JOINT" hpc/run.post)
echo "post-fit plan:  $POST  (submits the post-fit array and the render)"

cat <<TXT

watch:    squeue -u \$USER
progress: ls units/*.rds | wc -l          # of $N
store:    ls store/*.rds
post:     ls store/post/*.rds | wc -l
TXT
