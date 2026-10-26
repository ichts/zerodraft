#!/bin/sh
set -eu

TARGET=/var/www/writeitdown.app
SOURCE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
FILES='download/index.html site.css tokens.css reenie-beanie.woff2 OFL-ReenieBeanie.txt theme.js paper.js demo.js demo-timeline.mjs feedback.js status-slot.js session.mjs room.js buy.js privacy.html terms.html support.html mac.html what-is-write-it-down.html write-it-down-mac-vs-web.html write-it-down-free-trial.html write-it-down-price.html delete-a-draft.html is-my-writing-saved.html index.html og.png robots.txt sitemap.xml llms.txt BingSiteAuth.xml google7787e5a0693832e8.html 1bcb6b66144003eb070fe87774217f86.txt logo/write-it-down-lockup.svg logo/write-it-down-lockup-plate.svg favicon.svg favicon-16.png favicon-32.png favicon-dark.svg favicon-dark-16.png favicon-dark-32.png apple-touch-icon.png'

[ "$(id -u)" -eq 0 ] || { echo 'Run this installer as root.' >&2; exit 1; }
[ -d /var/www ] || { echo '/var/www must already exist.' >&2; exit 1; }
[ ! -L "$TARGET" ] || { echo 'Refusing a symlink deployment directory.' >&2; exit 1; }
for file in $FILES; do
  [ -f "$SOURCE/$file" ] || { echo "Missing source: $file" >&2; exit 1; }
  [ ! -L "$TARGET/$file" ] || { echo "Refusing symlink: $file" >&2; exit 1; }
done
[ ! -L "$TARGET/download" ] || { echo 'Refusing a symlink download directory.' >&2; exit 1; }
[ ! -L "$TARGET/logo" ] || { echo 'Refusing a symlink logo directory.' >&2; exit 1; }
[ ! -L "$TARGET/index.html.dc-bak2" ] || { echo 'Refusing a symlink backup.' >&2; exit 1; }
mkdir -p "$TARGET"
# download/ also holds the DMG, uploaded separately; only its index.html comes from here.
install -d -m 0755 "$TARGET/download"
install -d -m 0755 "$TARGET/logo"
if [ -f "$TARGET/index.html" ] && [ ! -e "$TARGET/index.html.dc-bak2" ]; then
  cp -p "$TARGET/index.html" "$TARGET/index.html.dc-bak2"
fi
for file in $FILES; do
  install -m 0644 "$SOURCE/$file" "$TARGET/$file"
done
printf '%s\n' 'Installed writeitdown.app. Existing index backup: index.html.dc-bak2 (if an old index existed).'
