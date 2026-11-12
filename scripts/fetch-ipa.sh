#!/usr/bin/env bash
set -euo pipefail
run_id="${1:-}"
if [[ ! "$run_id" =~ ^[0-9]+$ ]]; then
  printf 'Usage: %s <GitHub Actions run ID>\n' "$0" >&2
  exit 2
fi
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="$repo_dir/releases"
mkdir -p "$release_dir"
cd "$repo_dir"
gh run watch "$run_id" --repo hdd290187-web/QingRead-iOS --exit-status
staging="$(mktemp -d "$release_dir/.download.XXXXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
gh run download "$run_id" --repo hdd290187-web/QingRead-iOS --name QingRead-ios-unsigned --dir "$staging"
test -f "$staging/QingRead.ipa"
test -f "$staging/build-info.txt"
(cd "$staging" && sha256sum -c SHA256SUMS)
unzip -tqq "$staging/QingRead.ipa"
version="$(sed -n 's/^version=//p' "$staging/build-info.txt")"
build="$(sed -n 's/^build=//p' "$staging/build-info.txt")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]] || { echo 'Invalid build metadata' >&2; exit 1; }
archive="$release_dir/QingRead-${version}-build${build}-run${run_id}.ipa"
if [[ -e "$archive" ]]; then
  cmp -s "$staging/QingRead.ipa" "$archive" || { echo 'Archived build differs' >&2; exit 1; }
else
  install -m 600 "$staging/QingRead.ipa" "$archive"
fi
run_dir="$release_dir/run${run_id}"
mkdir -p "$run_dir" "$release_dir/latest"
cp -a "$staging/." "$run_dir/"
install -m 600 "$archive" "$release_dir/latest/QingRead.ipa"
install -m 600 "$staging/build-info.txt" "$release_dir/latest/build-info.txt"
install -m 600 "$staging/SHA256SUMS" "$release_dir/latest/SHA256SUMS"
printf 'Archive: %s\nLatest: %s\nEvidence: %s\n' "$archive" "$release_dir/latest/QingRead.ipa" "$run_dir"
