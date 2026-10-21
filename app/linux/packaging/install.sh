#!/bin/sh
# Installs nearby for the current user: the build goes to ~/.local/lib/nearby, plus a launcher entry and icon.
#
#   linux/packaging/install.sh [bundle]
#
# [bundle] defaults to the directory above this script when it ships inside a release bundle,
# otherwise to the local release build (flutter build linux --release).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
if [ $# -gt 0 ]; then
  bundle=$1
elif [ -x "$here/../nearby" ]; then
  bundle=$here/..
else
  bundle=$here/../../build/linux/x64/release/bundle
fi
if [ ! -x "$bundle/nearby" ]; then
  echo "No build at $bundle. Run: flutter build linux --release" >&2
  exit 1
fi

id=io.github.fingerskier.nearby
data=${XDG_DATA_HOME:-$HOME/.local/share}
target=$HOME/.local/lib/nearby

rm -rf "$target"
mkdir -p "$target" "$data/applications" "$data/icons/hicolor/scalable/apps"
cp -R "$bundle"/. "$target"/
cp "$here/$id.svg" "$data/icons/hicolor/scalable/apps/$id.svg"
sed "s|@EXEC@|$target/nearby|" "$here/$id.desktop" > "$data/applications/$id.desktop"
command -v update-desktop-database > /dev/null && update-desktop-database "$data/applications" || true

echo "Installed to $target; launch \"nearby\" from your app launcher."
echo "To uninstall: rm -r $target $data/applications/$id.desktop $data/icons/hicolor/scalable/apps/$id.svg"
