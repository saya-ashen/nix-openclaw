#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: openclaw-plugin-install.sh <source> <target>" >&2
  exit 1
fi

src="$1"
target="$2"
parent="$(dirname "$target")"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-plugin.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$parent"
rm -rf "$tmp_dir/plugin"
cp -R --no-preserve=mode,ownership "$src" "$tmp_dir/plugin"
rm -rf "$target"
mv "$tmp_dir/plugin" "$target"
