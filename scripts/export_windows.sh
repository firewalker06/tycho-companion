#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
project_dir="$repo_dir/godot"
output_path="${1:-$repo_dir/dist/windows-x86_64/TychoCompanion.exe}"
engine="${GODOT_BIN:-godot}"

mkdir -p "$(dirname "$output_path")"

# A fresh checkout has no .godot cache. Force the import scan before export so
# image preloads cannot resolve to missing .ctex files in the packaged build.
"$engine" --headless --editor --path "$project_dir" --quit-after 10

test -f "$project_dir/.godot/imported/coastal-workshop.png-72a4813e775541bb3ad03944b80a2a7c.ctex"
test -f "$project_dir/.godot/imported/caretaker-poses.png-c9b8d7ebae61f7567440b788922e60d0.ctex"

"$engine" --headless --path "$project_dir" --export-release "Windows Desktop" "$output_path"
