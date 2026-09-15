#!/bin/bash
# Bring the assembled store back from the cluster.
#
#   ./hpc/fetch-store.sh              # the whole store
#   ./hpc/fetch-store.sh --units      # the individual units as well
#
# The store is what the render reads, and it is a few hundred megabytes of
# brmsfit objects. It is not tracked: nine model-averaged fits over up to
# eighteen equations each is not something to put in a repository, and every one
# of them is reproducible from this code, the manifest and hpc/bayesnec.lock.
# What fetching saves is the fitting, not the record.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=/dev/null
[ -f hpc/local.conf ] && . ./hpc/local.conf
HOST="${HOST:?set HOST in hpc/local.conf}"
DEST="${DEST:-/export/scratch/${HOST%%@*}/grouping-structures}"

mkdir -p store
rsync -a --progress "$HOST:$DEST/store/" store/
rsync -a "$HOST:$DEST/manifest.rds" "$HOST:$DEST/manifest.csv" .

if [ "${1:-}" = "--units" ]; then
  mkdir -p units
  rsync -a --progress "$HOST:$DEST/units/" units/
fi

echo
echo "store:"
ls -la store/
echo
echo "Point the render at it:"
echo "  export BAYESNEC_FIT_STORE=$(pwd)/store"
