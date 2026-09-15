#!/bin/bash
# Deploy this study to the cluster and submit it.
#
#   ./hpc/deploy.sh                  # export, copy, submit
#   ./hpc/deploy.sh --copy-only      # export and copy; submit yourself
#   ./hpc/deploy.sh --ref <ref>      # pin a different bayesnec ref
#
# What is copied: this repository's code, and an export of bayesnec at the ref
# hpc/bayesnec.lock names. The export is of a commit rather than of a working
# tree, so what ran can always be recovered -- which is the opposite of
# bayesnec's own precompile-hpc.sh, and deliberately so. That script exists to
# render an uncommitted vignette edit; this one exists to produce fits that will
# be quoted, and an uncommitted source is not something to quote.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# shellcheck source=/dev/null
[ -f hpc/local.conf ] && . ./hpc/local.conf

copy_only=0
for a in "$@"; do
  case "$a" in
    --copy-only) copy_only=1 ;;
    --ref) shift; BAYESNEC_REF="$1" ;;
    -*) echo "unknown option: $a" >&2; exit 2 ;;
  esac
  shift || true
done

HOST="${HOST:-}"
[ -n "$HOST" ] || {
  echo "HOST is not set. Copy hpc/local.conf.example to hpc/local.conf." >&2
  exit 1; }
DEST="${DEST:-/export/scratch/${HOST%%@*}/grouping-structures}"
BAYESNEC_REPO="${BAYESNEC_REPO:-../bayesnec}"
BAYESNEC_REF="${BAYESNEC_REF:-issue-6-33-grouping-vignette}"
SIF="${SIF:-}"
MAX_RESIDENT="${MAX_RESIDENT:-60}"

[ -d "$BAYESNEC_REPO/.git" ] || {
  echo "BAYESNEC_REPO=$BAYESNEC_REPO is not a git checkout" >&2; exit 1; }

echo "=== exporting bayesnec $BAYESNEC_REF from $BAYESNEC_REPO"
COMMIT=$(git -C "$BAYESNEC_REPO" rev-parse "$BAYESNEC_REF")
VERSION=$(git -C "$BAYESNEC_REPO" show "$COMMIT:DESCRIPTION" |
          sed -n 's/^Version: //p')
rm -rf .bayesnec-src; mkdir -p .bayesnec-src
git -C "$BAYESNEC_REPO" archive "$COMMIT" | tar -x -C .bayesnec-src
[ -f .bayesnec-src/vignettes/example8.Rmd.orig ] || {
  echo "$BAYESNEC_REF does not carry vignettes/example8.Rmd.orig" >&2; exit 1; }

{ echo "ref: $BAYESNEC_REF"
  echo "commit: $COMMIT"
  echo "version: $VERSION"
  echo "exported: $(date -Is)"; } > hpc/bayesnec.lock
echo "    $COMMIT  ($VERSION)"

echo "=== syncing to $HOST:$DEST"
ssh "$HOST" "mkdir -p '$DEST'"
rsync -a --delete \
  --exclude 'units/' --exclude 'store/' --exclude 'logs/' --exclude 'lib/' \
  --exclude 'stan-cache/' --exclude '.git/' --exclude 'hpc/local.conf' \
  R analysis hpc shim .Rprofile README.md CLAUDE.md "$HOST:$DEST/"
rsync -a --delete .bayesnec-src/ "$HOST:$DEST/bayesnec-src/"

# The image is copied only when the cluster does not already hold the one this
# branch records, which makes it a rare cost rather than a per-run one. Compared
# by digest, because a squashfs image is not bit-reproducible and a rebuild from
# an unchanged definition still produces a different file.
lock_sha=$(sed -n 's/^sif_sha256: //p' hpc/image.lock)
remote_sha=$(ssh "$HOST" "sha256sum '$DEST/bayesnec-precompile.sif' 2>/dev/null | cut -d' ' -f1" || true)
if [ "$remote_sha" != "$lock_sha" ]; then
  # Look for the same image already on the cluster before copying 700MB across
  # the network. bayesnec's precompile jobs and the example7 compendium deploy
  # the same file, and a cluster-side cp of a byte-identical image is seconds
  # against twenty minutes. Matched by digest, not by path, so an image that
  # happens to sit there under the right name is still checked.
  echo "=== looking for the image already on the cluster"
  found=$(ssh "$HOST" "for f in /export/scratch/\$USER/*/bayesnec-precompile.sif; do
            [ -f \"\$f\" ] || continue
            if [ \"\$(sha256sum \"\$f\" | cut -d' ' -f1)\" = '$lock_sha' ]; then
              echo \"\$f\"; break
            fi
          done" || true)
  if [ -n "$found" ]; then
    echo "    copying from $found"
    ssh "$HOST" "cp '$found' '$DEST/bayesnec-precompile.sif'"
    remote_sha="$lock_sha"
  fi
fi
if [ "$remote_sha" != "$lock_sha" ]; then
  [ -n "$SIF" ] || {
    echo "the cluster does not hold the image hpc/image.lock records, and SIF" >&2
    echo "is not set. Build it in the bayesnec repository (./hpc/build.sh) and" >&2
    echo "put its path in hpc/local.conf." >&2; exit 1; }
  have_sha=$(sha256sum "$SIF" | cut -d' ' -f1)
  [ "$have_sha" = "$lock_sha" ] || {
    echo "$SIF does not match hpc/image.lock" >&2; exit 1; }
  echo "=== copying the image (about 700MB, once)"
  rsync -a --progress "$SIF" "$HOST:$DEST/bayesnec-precompile.sif"
else
  echo "=== image already on the cluster"
fi

{ echo "deployed: $(date -Is)"
  echo "from: $(hostname):$(pwd)"
  echo "compendium commit: $(git rev-parse HEAD 2>/dev/null || echo uncommitted)"
  cat hpc/bayesnec.lock; } | ssh "$HOST" "cat > '$DEST/PROVENANCE'"

if [ "$copy_only" -eq 1 ]; then
  echo "=== copied. Submit with: ssh $HOST 'cd $DEST && ./hpc/submit.sh'"
  exit 0
fi
ssh "$HOST" "cd '$DEST' && GRP_STUDY='$DEST' ./hpc/submit.sh '$MAX_RESIDENT'"
