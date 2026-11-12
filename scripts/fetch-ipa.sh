#!/usr/bin/env bash
set -euo pipefail
run_id="${1:-}"
if [[ ! "$run_id" =~ ^[0-9]+$ ]]; then printf 'Usage: %s <GitHub Actions run ID>\n' "$0" >&2; exit 2; fi
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="$repo_dir/releases"; mkdir -p "$release_dir"; cd "$repo_dir"
gh run watch "$run_id" --exit-status
staging="$(mktemp -d "$release_dir/.download.XXXXXXXX")"
gh run download "$run_id" --repo hdd290187-web/QingRead-iOS --name QingRead-ios-unsigned --dir "$staging"
ipa="$staging/QingRead.ipa"; info="$staging/build-info.txt"; sums="$staging/SHA256SUMS"
test -f "$ipa"; test -f "$info"; unzip -tqq "$ipa"; test -f "$sums"
version="$(sed -n 's/^version=//p' "$info")"; build="$(sed -n 's/^build=//p' "$info")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]] || { echo 'Invalid build metadata' >&2; exit 1; }
archive="$release_dir/QingRead-${version}-build${build}.ipa"
if [[ -e "$archive" ]]; then cmp -s "$ipa" "$archive" || { echo 'Archived build differs' >&2; exit 1; }; else install -m 600 "$ipa" "$archive"; fi
mkdir -p "$release_dir/latest"; install -m 600 "$archive" "$release_dir/latest/QingRead.ipa"; install -m 600 "$info" "$release_dir/latest/build-info.txt"; install -m 600 "$sums" "$release_dir/latest/SHA256SUMS"
rm -rf "$staging"; printf 'Archive: %s\nLatest: %s\n' "$archive" "$release_dir/latest/QingRead.ipa"
