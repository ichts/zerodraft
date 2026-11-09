#!/bin/sh
# Host cache-policy gate for writeitdown.app.
#
# Serves the exact production file set (the list `install.sh` owns) from a disposable root with the
# site block documented in `README.md`, on loopback, using the real Caddy binary, then asserts:
#   - every path answers the Cache-Control the policy names, and nothing else;
#   - every revalidating path also carries an ETag and Last-Modified, so a browser can revalidate;
#   - a cached file revalidates to 304 instead of downloading again;
#   - changed bytes come back as 200 with a new ETag, so a deploy shows on an ordinary reload;
#   - the policy neither adds nor replaces an /api/ response header (a fixture directive, because
#     the waitlist handler sets none today).
# It never writes the site: the served root is a copy under $TMPDIR, removed on exit.
#
# Usage: npm run cache-headers, or sh qa/cache-headers.sh     (CADDY_BIN overrides where caddy is
# found). A manual pre-host-change check, not a CI gate: CI does not install caddy.
# Exit: 0 every assertion held; 1 on drift, on a missing caddy/python3, or when the documented
# block could not be read. A pass proves the documented policy, not the deployed host.
set -eu

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
SITE=$(dirname "$HERE")
REPO=$(dirname "$SITE")

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); printf 'PASS  %s\n' "$*"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL  %s\n' "$*"; }
die() { printf 'FAIL  %s\n' "$*"; exit 1; }

CADDY=${CADDY_BIN:-}
if [ -z "$CADDY" ]; then
	if command -v caddy >/dev/null 2>&1; then
		CADDY=$(command -v caddy)
	elif [ -x /opt/homebrew/bin/caddy ]; then
		CADDY=/opt/homebrew/bin/caddy
	else
		die 'caddy not found (install it or set CADDY_BIN)'
	fi
fi
command -v python3 >/dev/null 2>&1 || die 'python3 not found'
command -v curl >/dev/null 2>&1 || die 'curl not found'

WORK=$(mktemp -d "${TMPDIR:-/tmp}/wid-cache-headers.XXXXXX")
WEBROOT=$WORK/www
CADDY_PID=
API_PID=
cleanup() {
	[ -z "$CADDY_PID" ] || kill "$CADDY_PID" 2>/dev/null || true
	[ -z "$API_PID" ] || kill "$API_PID" 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

# --- Assemble the site root: exactly what install.sh deploys, plus the artifacts it does not own ---

files=$(sed -n "s/^FILES='\(.*\)'$/\1/p" "$SITE/install.sh")
[ -n "$files" ] || die 'could not read the FILES list from install.sh'
mkdir -p "$WEBROOT/download/updates"
for file in $files; do
	[ -f "$SITE/$file" ] || die "missing production file: $file"
	mkdir -p "$WEBROOT/$(dirname "$file")"
	cp "$SITE/$file" "$WEBROOT/$file"
done
# The DMG, the Sparkle feed and its payloads are placed on the host separately, never committed.
printf 'dmg fixture\n' > "$WEBROOT/download/Write-It-Down-1.1.dmg"
printf '<?xml version="1.0" encoding="utf-8"?>\n<rss version="2.0"><channel><title>fixture</title></channel></rss>\n' \
	> "$WEBROOT/download/appcast.xml"
printf 'payload fixture\n' > "$WEBROOT/download/updates/WriteItDown-1.1-2.zip"

# --- Assemble the Caddyfile: README's site block, the real waitlist handler, loopback address ---

free_port() {
	python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}
PORT=$(free_port)
API_PORT=$(free_port)

awk '
	/^```caddyfile$/ { fenced = 1; next }
	fenced {
		if ($0 ~ /^writeitdown\.app \{$/) { capture = 1; print; fenced = 0; next }
		fenced = 0
	}
	capture {
		if ($0 ~ /^```$/) { captured = 1; exit }
		print
	}
	END { if (!captured) exit 1 }
' "$SITE/README.md" > "$WORK/site-block.caddyfile" ||
	die 'could not read the site Caddyfile block from README.md'
grep -Fq 'root * /var/www/writeitdown.app' "$WORK/site-block.caddyfile" ||
	die 'the README.md site block does not declare the production root'

sed -e "1s|^writeitdown\.app {$|http://127.0.0.1:$PORT {|" \
	-e "s|root \* /var/www/writeitdown.app$|root * $WEBROOT|" \
	"$WORK/site-block.caddyfile" > "$WORK/site.local"
grep -Fxq "http://127.0.0.1:$PORT {" "$WORK/site.local" ||
	die 'could not point the site block at loopback'
grep -Fq "root * $WEBROOT" "$WORK/site.local" ||
	die 'could not point the site block at the disposable root'
[ "$(tail -1 "$WORK/site.local")" = '}' ] || die 'the site block does not end with a closing brace'

# The waitlist handler is a real member of that site block, so the policy has to leave it alone.
awk '/^[[:space:]]*#/ { next } /^[[:space:]]*$/ { next } { print }' \
	"$REPO/services/waitlist/deploy/Caddyfile.snippet" |
	sed "s|127\.0\.0\.1:8091|127.0.0.1:$API_PORT|" > "$WORK/api-handle.caddyfile"
grep -Fq "reverse_proxy 127.0.0.1:$API_PORT" "$WORK/api-handle.caddyfile" ||
	die 'could not read the waitlist handler from services/waitlist/deploy/Caddyfile.snippet'
awk -v api="$WORK/api-handle.caddyfile" '
	{ lines[NR] = $0 }
	END {
		for (i = 1; i < NR; i++) print lines[i]
		while ((getline line < api) > 0) print "\t" line
		close(api)
		print lines[NR]
	}
' "$WORK/site.local" > "$WORK/Caddyfile"

"$CADDY" validate --config "$WORK/Caddyfile" --adapter caddyfile > "$WORK/validate.log" 2>&1 ||
	{ cat "$WORK/validate.log"; die 'caddy rejected the assembled site block'; }

# --- Serve: the /api/ stub sends a fixture Cache-Control the real waitlist handler does not set
# today, so the gate can prove the policy neither adds nor replaces a service-level header.

cat > "$WORK/api-stub.py" <<'PY'
import http.server, sys

class Handler(http.server.BaseHTTPRequestHandler):
    def respond(self):
        body = b'{"ok":true}\n'
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        # Fixture: the live handler sets no Cache-Control, so any site-level header that added to
        # or replaced this value would change it here.
        self.send_header('Cache-Control', 'private, max-age=30')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = respond
    do_POST = respond

    def log_message(self, *args):
        pass

http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
PY
python3 "$WORK/api-stub.py" "$API_PORT" > "$WORK/api.log" 2>&1 &
API_PID=$!

"$CADDY" run --config "$WORK/Caddyfile" --adapter caddyfile > "$WORK/caddy.log" 2>&1 &
CADDY_PID=$!

ready=0
for _ in $(seq 1 100); do
	if curl -sS -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/" 2>/dev/null; then
		ready=1
		break
	fi
	kill -0 "$CADDY_PID" 2>/dev/null || break
	sleep 0.1
done
[ "$ready" -eq 1 ] || { cat "$WORK/caddy.log"; die "the site did not answer on 127.0.0.1:$PORT"; }

# --- Assertions ----------------------------------------------------------------------------

field() { # header block, field name -> value or empty
	printf '%s\n' "$1" | tr -d '\r' | awk -v want="$2" '
		tolower($1) == tolower(want ":") { sub(/^[^:]*: ?/, ""); print; exit }
	'
}
status_of() { printf '%s\n' "$1" | head -1 | tr -d '\r' | awk '{ print $2 }'; }
fetch() { curl -sS -D - -o /dev/null --max-time 10 "http://127.0.0.1:$PORT$1"; }

check() { # path, expected Cache-Control ("-" = none), expected status, content type prefix, revalidator
	path=$1
	want_cc=$2
	want_status=$3
	want_type=${4:-}
	want_revalidator=${5:-auto}
	raw=$(fetch "$path")
	got_cc=$(field "$raw" 'Cache-Control')
	got_status=$(status_of "$raw")
	got_type=$(field "$raw" 'Content-Type')
	ok=1

	[ "$got_status" = "$want_status" ] || ok=0
	if [ "$want_cc" = '-' ]; then
		[ -z "$got_cc" ] || ok=0
		want_cc='(none)'
	else
		[ "$got_cc" = "$want_cc" ] || ok=0
	fi
	if [ -n "$want_type" ]; then
		case "$got_type" in
		"$want_type"*) ;;
		*) ok=0 ;;
		esac
	fi

	# A 200 that a browser may hold has to be revalidatable, or `no-cache` would force a refetch.
	has_revalidator=skip
	if [ "$want_status" = 200 ] && [ "$want_revalidator" != no ]; then
		has_revalidator=yes
		if [ -z "$(field "$raw" 'ETag')" ] || [ -z "$(field "$raw" 'Last-Modified')" ]; then
			has_revalidator=missing
			ok=0
		fi
	fi

	if [ "$ok" -eq 1 ]; then
		pass "$path -> $got_status cache-control: $want_cc$( [ "$has_revalidator" = skip ] || printf ' (ETag + Last-Modified present)')"
	else
		fail "$path -> $got_status cache-control: ${got_cc:-(none)} content-type: ${got_type:-none} revalidators: $has_revalidator (want $want_status / $want_cc${want_type:+ / $want_type*})"
	fi
}

STABLE='no-cache'
IMMUTABLE='public, max-age=31536000, immutable'

# Stable names: HTML, CSS, JS, XML, text, images, fonts, the DMG and directory indexes.
check '/' "$STABLE" 200 'text/html'
check '/mac.html' "$STABLE" 200 'text/html'
check '/download/' "$STABLE" 200 'text/html'
check '/site.css' "$STABLE" 200 'text/css'
check '/tokens.css' "$STABLE" 200 'text/css'
check '/fonts.css' "$STABLE" 200 'text/css'
check '/fonts-cjk.css' "$STABLE" 200 'text/css'
check '/paper.js' "$STABLE" 200 'text/javascript'
check '/paper-render.js' "$STABLE" 200 'text/javascript'
check '/room.js' "$STABLE" 200 'text/javascript'
check '/demo.js' "$STABLE" 200 'text/javascript'
check '/theme.js' "$STABLE" 200 'text/javascript'
check '/buy.js' "$STABLE" 200 'text/javascript'
check '/session.mjs' "$STABLE" 200 'text/javascript'
check '/sitemap.xml' "$STABLE" 200
check '/robots.txt' "$STABLE" 200 'text/plain'
check '/llms.txt' "$STABLE" 200 'text/plain'
check '/favicon.svg' "$STABLE" 200 'image/svg+xml'
check '/og.png' "$STABLE" 200 'image/png'
check '/fonts/newsreader-latin.woff2' "$STABLE" 200 'font/woff2'
check '/fonts/zhuque-fangsong-gb2312.woff2' "$STABLE" 200 'font/woff2'
check '/fonts/OFL-Newsreader.txt' "$STABLE" 200 'text/plain'
# The DMG name carries the marketing version only, so a rebuild inside one version reuses the URL.
check '/download/Write-It-Down-1.1.dmg' "$STABLE" 200 'application/x-apple-diskimage'

# The Sparkle feed is never reused, and it is read as XML, not as the landing page.
check '/download/appcast.xml' "$STABLE" 200 'application/xml'

# Sparkle payloads carry version and build number in the name, so the year is honest.
check '/download/updates/WriteItDown-1.1-2.zip' "$IMMUTABLE" 200
# No fallback: a missing payload is a 404, never the landing page with a 200.
check '/download/updates/does-not-exist.zip' "$IMMUTABLE" 404
check '/download/absent.dmg' "$STABLE" 404

# /api/ responses stay out of the policy. The stub's directive is a fixture the live waitlist
# handler does not send, so this asserts non-interference only; the stub carries no ETag, so
# revalidators are not expected here.
check '/api/waitlist' 'private, max-age=30' 200 'application/json' no

# Revalidation: a held copy costs one conditional request, not another download.
css_etag=$(field "$(fetch '/site.css')" 'ETag')
css_modified=$(field "$(fetch '/site.css')" 'Last-Modified')
[ -n "$css_etag" ] || die '/site.css answered no ETag'
[ -n "$css_modified" ] || die '/site.css answered no Last-Modified'

raw=$(curl -sS -D - -o /dev/null --max-time 10 -H "If-None-Match: $css_etag" "http://127.0.0.1:$PORT/site.css")
if [ "$(status_of "$raw")" = 304 ] && [ "$(field "$raw" 'Cache-Control')" = "$STABLE" ]; then
	pass "If-None-Match on /site.css -> 304 with cache-control: $STABLE"
else
	fail "If-None-Match on /site.css -> $(status_of "$raw") (want 304 with cache-control: $STABLE)"
fi

raw=$(curl -sS -D - -o /dev/null --max-time 10 -H "If-Modified-Since: $css_modified" "http://127.0.0.1:$PORT/site.css")
if [ "$(status_of "$raw")" = 304 ]; then
	pass 'If-Modified-Since on /site.css -> 304'
else
	fail "If-Modified-Since on /site.css -> $(status_of "$raw") (want 304)"
fi

# A deploy: new bytes must surface as a new ETag, not as the pinned old file.
reveal_deploy() { # url, file under the webroot, marker
	url=$1
	file=$2
	marker=$3
	old_etag=$(field "$(fetch "$url")" 'ETag')
	if [ -z "$old_etag" ]; then
		fail "$url answered no ETag before the change"
		return
	fi
	printf '%s\n' "$marker" >> "$file"
	raw=$(curl -sS -D - -o "$WORK/body" --max-time 10 -H "If-None-Match: $old_etag" "http://127.0.0.1:$PORT$url")
	new_etag=$(field "$raw" 'ETag')
	if [ "$(status_of "$raw")" = 200 ] && [ -n "$new_etag" ] && [ "$new_etag" != "$old_etag" ] &&
		grep -Fq "$marker" "$WORK/body"; then
		pass "changed $url -> 200 with a new ETag ($new_etag), new bytes served"
	else
		fail "changed $url -> $(status_of "$raw") etag: ${new_etag:-none} (want 200, new ETag, new bytes)"
	fi
}
reveal_deploy '/site.css' "$WEBROOT/site.css" '/* cache-headers.sh deploy marker */'
reveal_deploy '/' "$WEBROOT/index.html" '<!-- cache-headers.sh deploy marker -->'

# --- Summary ------------------------------------------------------------------------------

total=$((PASSED + FAILED))
if [ "$FAILED" -ne 0 ]; then
	printf '\n%s of %s assertions drifted from the policy in README.md\n' "$FAILED" "$total"
	exit 1
fi
printf '\nall %s assertions match the policy in README.md\n' "$total"
