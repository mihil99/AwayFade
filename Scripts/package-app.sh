#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
workspace_dir="$(cd "$project_dir/../.." && pwd)"
build_dir="$workspace_dir/work/AwayFadeBuild"
app_dir="$project_dir/AwayFade.app"

swift build \
    --package-path "$project_dir" \
    --scratch-path "$build_dir" \
    --configuration release

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/release/AwayFade" "$app_dir/Contents/MacOS/AwayFade"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

codesign --force --deep --sign - \
    --entitlements "$project_dir/Resources/AwayFade.entitlements" \
    "$app_dir"

echo "$app_dir"
