#!/usr/bin/env bash
# Emit the release metadata strix-build-ai consumes:
#
#   checksums.txt             sha256 of every release asset
#   archs.txt                 model architectures this build supports
#   strixbuild-manifest.json  runtime_tag + archs + assets keyed <os>/<arch>/<backend>
#
# strix-build-ai embeds the manifest at ITS build time, pins the tag, and
# verifies the sha256 before extracting — so these three files are the contract
# between this repo's CI and that tool. A key it cannot parse is a runtime the
# user cannot download.
#
# Usage: make-strixbuild-manifest.sh <release-dir> <tag> <llama-arch.cpp>
set -euo pipefail

dir="${1:?release directory}"
tag="${2:?release tag}"
archsrc="${3:-src/llama-arch.cpp}"

cd "$dir"

# ---- checksums -------------------------------------------------------------
: > checksums.txt
shopt -s nullglob
for f in *.tar.gz *.zip; do
  sha256sum "$f" >> checksums.txt
done
if [ ! -s checksums.txt ]; then
  echo "make-strixbuild-manifest: no release assets in $dir" >&2
  exit 1
fi

# ---- archs -----------------------------------------------------------------
# The arch table is `{ LLM_ARCH_NAME, "name" },`. Generated rather than
# hand-listed so a new architecture cannot drift out of the manifest silently.
sed -n 's/^[[:space:]]*{[[:space:]]*LLM_ARCH_[A-Z0-9_]*,[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$OLDPWD/$archsrc" | grep -v '^unknown$' | sort -u > archs.txt
if [ ! -s archs.txt ]; then
  echo "make-strixbuild-manifest: parsed no architectures from $archsrc" >&2
  exit 1
fi

# ---- manifest --------------------------------------------------------------
# Classify each asset into <os>/<arch>/<backend>. An asset that does not
# classify is a hard error: silently dropping it ships a manifest that is
# quietly missing a platform, and the user discovers it as "no runtime for your
# machine" long after the release went out.
classify() {
  local f="$1" os arch backend
  case "$f" in
    *-bin-ubuntu-*) os=linux ;;
    *-bin-win-*)    os=windows ;;
    *-bin-macos-*)  os=darwin ;;
    *)              return 1 ;;
  esac
  case "$f" in
    *-arm64.*|*-arm64-*) arch=arm64 ;;
    *-x64.*|*-x64-*)     arch=amd64 ;;
    *)                   return 1 ;;
  esac
  case "$f" in
    *vulkan*) backend=vulkan ;;
    *rocm*|*hip*) backend=hip ;;
    *cpu*) backend=cpu ;;
    *) return 1 ;;
  esac
  printf '%s/%s/%s' "$os" "$arch" "$backend"
}

{
  printf '{\n  "runtime_tag": "%s",\n  "archs": [' "$tag"
  paste -sd, - < <(sed 's/.*/"&"/' archs.txt)
  printf '],\n  "assets": {\n'
  first=1
  for f in *.tar.gz *.zip; do
    key="$(classify "$f")" || {
      echo "make-strixbuild-manifest: cannot classify asset '$f' into <os>/<arch>/<backend>" >&2
      exit 1
    }
    sum="$(sha256sum "$f" | cut -d' ' -f1)"
    size="$(stat -c%s "$f")"
    [ $first -eq 1 ] || printf ',\n'
    first=0
    printf '    "%s": {"name": "%s", "sha256": "%s", "size": %s}' "$key" "$f" "$sum" "$size"
  done
  printf '\n  }\n}\n'
} > strixbuild-manifest.json

python3 -c "import json,sys; json.load(open('strixbuild-manifest.json'))" \
  || { echo "make-strixbuild-manifest: emitted invalid JSON" >&2; exit 1; }

echo "wrote checksums.txt ($(wc -l < checksums.txt) assets), archs.txt ($(wc -l < archs.txt) archs), strixbuild-manifest.json"
