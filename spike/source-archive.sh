#!/usr/bin/env bash
#
# Build the canonical 42Hz source archive for a tag.
#
#     ./spike/source-archive.sh v1.0.0-rc1 [outdir]
#
# Writes 42hz-<ver>.tar.gz into outdir (default: packaging/, where makepkg
# picks it up before trying to download it). The archive is git archive of the
# tag: tracked files only, mtimes from the commit, and gzip -n so no name or
# timestamp of its own. The same tag therefore gives the same bytes, and the
# SHA-256 published in SHA256SUMS can be checked by rebuilding it.
#
set -euo pipefail

tag=${1:?usage: $0 <tag> [outdir]}
root="$(dirname "$(realpath "$0")")/.."
out=${2:-$root/packaging}
ver=${tag#v}
name=42hz-$ver

# An annotated tag only: a lightweight one carries no record of who cut the
# release or when.
if [[ $(git -C "$root" cat-file -t "$tag") != tag ]]; then
  echo "error: $tag is not an annotated tag" >&2
  exit 1
fi

git -C "$root" archive --format=tar --prefix="$name/" "$tag" | gzip -n -9 > "$out/$name.tar.gz"
echo "$out/$name.tar.gz"
