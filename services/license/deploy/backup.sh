#!/bin/sh
set -eu
umask 077
database=${LICENSE_DB:-/var/lib/writeitdown-license/licenses.db}
state=$(dirname "$database")
name=$(basename "$database" .db)
# Retention patterns must remain literal apart from the dated suffix.
case "$name" in ''|*[!a-zA-Z0-9_.-]*) exit 1 ;; esac
backup="$state/backups"
mkdir -p "$backup"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
target="$backup/$name-$stamp.db"
# SQLite's online backup captures WAL changes consistently.
sqlite3 "$database" ".timeout 5000" ".backup '$target'"
result=$(sqlite3 "$target" 'PRAGMA integrity_check;')
[ "$result" = ok ] || exit 1
# Only this script's dated backup files are eligible for local retention pruning.
find "$backup" -type f -name "$name-????????T??????Z.db" -mtime +14 -delete
