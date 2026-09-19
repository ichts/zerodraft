# Supporting static pages

**What it is:** the self-contained vanilla static pages that carry support, legal, and release content: `download.html`, `checkout-success.html`, `help.html`, `privacy.html`, `refund.html`, `terms.html`, `release-notes.html`. No framework, no build; each ships its own inline CSS/JS on the same bone canvas with Newsreader + IBM Plex Mono.

**How to reach it:** served from the repo root like `index.html` (see Launch in `../SKILL.md`); linked from the landing footer and each other.

**How to drive it:** HTTP status + per-page marker, plus one Playwright pass if a visual change is under review:

```bash
for p in download checkout-success help privacy refund terms release-notes; do
  printf '%s: ' "$p"; curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:8000/$p.html"
done
```

Marker examples (verify against current markup if one rots): `download.html` -> download/copy action; `help.html` -> support content; `privacy.html` -> the one-line privacy promise; `terms.html` / `refund.html` -> legal text; `release-notes.html` -> version entries; `checkout-success.html` -> post-purchase confirmation.

**Observable end state that proves it works:** every page returns 200, renders its marker content with the bone canvas (`#f1f0eb`) and the Newsreader/Plex Mono faces, and produces zero console errors and zero failed asset requests in a Playwright pass. Navigation links between the pages and back to `/index.html` resolve (no 404s in the request log).
