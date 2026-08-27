#!/usr/bin/env bash
#
# Fetch and verify the pinned EasyEffects source tree.
#
#     ./spike/fetch.sh
#     ./spike/reduce-deps.py upstream/easyeffects-8.2.8
#     cmake -B upstream/easyeffects-8.2.8/build -S upstream/easyeffects-8.2.8 \
#           -G Ninja -DCMAKE_BUILD_TYPE=Release
#     ninja -C upstream/easyeffects-8.2.8/build
#
# 42Hz is a patch-on-tarball derivative: upstream source is fetched, never
# tracked, so that `spike/reduce-deps.py` remains legible as the entire set of
# modifications against a known base. That only holds if the base is genuinely
# pinned -- hence the checksums below.
#
set -euo pipefail

UPSTREAM_TAG=v8.2.8
UPSTREAM_VERSION=8.2.8

# The authoritative identity of the base revision. GitHub's auto-generated
# archives are a convenience; this commit is what `v8.2.8` means.
UPSTREAM_COMMIT=6d9b1220d3dcebb154ba759a05600662bc0af549

# Compressed bytes, as served on 2026-08-27.
TARBALL_SHA256=0e241ad32a0147d180f9dd35181c8eea11e7d32309dda9b4b70b6b472189e45e

# Digest of the extracted file tree (709 files), independent of how the archive
# happens to be compressed. GitHub does not guarantee byte-stable auto-generated
# tarballs -- their gzip settings have changed before and invalidated pinned
# checksums project-wide -- so this is the fallback that distinguishes "same
# source, recompressed" from "source actually changed".
TREE_SHA256=8f8e9ac21308a3e8d4c6a06df5a112f830592b04293477138899effd31f973a5

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dest="$repo_root/upstream"
tarball="$dest/easyeffects-$UPSTREAM_VERSION.tar.gz"
tree="$dest/easyeffects-$UPSTREAM_VERSION"
url="https://codeload.github.com/wwmm/easyeffects/tar.gz/refs/tags/$UPSTREAM_TAG"

# Order-independent digest of every file in a tree. NUL-delimited and
# LC_ALL=C-sorted so the result does not depend on locale or readdir order.
tree_digest() {
  (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
}

file_digest() { sha256sum "$1" | cut -d' ' -f1; }

# The extracted tree is disposable: re-fetching deletes it outright rather than
# trying to reconcile it. This is what keeps the patch inventory honest -- an
# edit that is not in reduce-deps.py does not survive the next fetch, so it
# cannot quietly become load-bearing.
#
# It takes any build directory inside the tree with it, which is correct rather
# than merely acceptable: a rebuilt source tree deserves a fresh build, and a
# build left over from a source state that no longer exists is exactly the kind
# of quiet inconsistency this arrangement exists to prevent.
handle_existing_tree() {
  echo "clean   $tree"
  rm -rf "$tree"
}

mkdir -p "$dest"

# ---- acquire ----
if [[ -f $tarball ]]; then
  echo "have    $tarball"
else
  echo "fetch   $url"
  curl -fL --retry 3 -o "$tarball.part" "$url"
  mv "$tarball.part" "$tarball"
fi

# ---- verify ----
got=$(file_digest "$tarball")
if [[ $got == "$TARBALL_SHA256" ]]; then
  echo "verify  tarball sha256 ok"
else
  echo "warn    tarball sha256 mismatch" >&2
  echo "          expected $TARBALL_SHA256" >&2
  echo "          got      $got" >&2
  echo "        checking whether the source itself changed..." >&2

  scratch=$(mktemp -d)
  trap 'rm -rf "$scratch"' EXIT
  tar -xzf "$tarball" -C "$scratch"
  got_tree=$(tree_digest "$scratch/easyeffects-$UPSTREAM_VERSION")

  if [[ $got_tree == "$TREE_SHA256" ]]; then
    echo "verify  tree sha256 ok -- same source, recompressed; continuing" >&2
    echo "        update TARBALL_SHA256 in $0 to silence this." >&2
  else
    echo "error   tree sha256 mismatch -- the source has changed, not just the archive" >&2
    echo "          expected $got_tree" >&2
    echo "          against  $TREE_SHA256" >&2
    echo "        refusing to build on an unverified base." >&2
    echo "        cross-check against commit $UPSTREAM_COMMIT before proceeding." >&2
    exit 1
  fi
fi

# ---- extract ----
[[ -e $tree ]] && handle_existing_tree

tar -xzf "$tarball" -C "$dest"
echo "extract $tree"

cat <<NEXT

base    EasyEffects $UPSTREAM_TAG ($UPSTREAM_COMMIT)
next    ./spike/reduce-deps.py upstream/easyeffects-$UPSTREAM_VERSION
NEXT
