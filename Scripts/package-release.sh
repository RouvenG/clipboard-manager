#!/bin/bash
# Packages a built ClipShelf.app as a zip and a DMG with an Applications shortcut.
# Usage: Scripts/package-release.sh <path/to/ClipShelf.app> <version> <output dir>
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 <path/to/ClipShelf.app> <version> <output dir>" >&2
  exit 64
fi

app="$1"
version="$2"
out="$3"
name="$(basename "$app" .app)"

if [ ! -d "$app" ]; then
  echo "error: $app does not exist" >&2
  exit 66
fi

mkdir -p "$out"
zip_path="$out/$name-$version.zip"
dmg_path="$out/$name-$version.dmg"
rm -f "$zip_path" "$dmg_path"

# ditto keeps symlinks, permissions and the code signature intact.
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/$name.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "$name $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg_path" >/dev/null

echo "$zip_path"
echo "$dmg_path"
