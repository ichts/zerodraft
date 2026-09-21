#!/bin/sh
set -eu

TARGET=/var/www/writeitdown.app
SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
FILES='site.css theme.js demo.js demo-timeline.mjs feedback.js session.mjs room.js privacy.html terms.html support.html index.html'

[ "$(id -u)" -eq 0 ] || { echo 'Run this installer as root.' >&2; exit 1; }
[ -d /var/www ] || { echo '/var/www must already exist.' >&2; exit 1; }
[ ! -L "$TARGET" ] || { echo 'Refusing a symlink deployment directory.' >&2; exit 1; }
for file in $FILES; do
  [ -f "$SOURCE/$file" ] || { echo "Missing source: $file" >&2; exit 1; }
  [ ! -L "$TARGET/$file" ] || { echo "Refusing symlink: $file" >&2; exit 1; }
done
[ ! -L "$TARGET/index.html.dc-bak2" ] || { echo 'Refusing a symlink backup.' >&2; exit 1; }

mkdir -p "$TARGET"
if [ -f "$TARGET/index.html" ] && [ ! -e "$TARGET/index.html.dc-bak2" ]; then
  cp -p "$TARGET/index.html" "$TARGET/index.html.dc-bak2"
fi
for file in $FILES; do
  install -m 0644 "$SOURCE/$file" "$TARGET/$file"
done
printf '%s\n' 'Installed writeitdown.app. Existing index backup: index.html.dc-bak2 (if an old index existed).'
