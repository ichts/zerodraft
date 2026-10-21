#!/bin/sh
set -eu
umask 077
state=/var/lib/writeitdown-license
backup="$state/backups"
mkdir -p "$backup"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
target="$backup/licenses-$stamp.db"
# SQLite's online backup captures WAL changes consistently.
sqlite3 "$state/licenses.db" ".timeout 5000" ".backup '$target'"
result=$(sqlite3 "$target" 'PRAGMA integrity_check;')
[ "$result" = ok ] || exit 1
# Only this script's dated backup files are eligible for local retention pruning.
find "$backup" -type f -name 'licenses-????????T??????Z.db' -mtime +14 -delete
