# WRITE_IT_DOWN

A static browser writing room. Open `index.html#trial` over HTTP to enter directly, or use the landing CTA.

```sh
python3 -m http.server 8000
# http://localhost:8000/writeitdown/
node --test writeitdown/session.test.mjs
```

The first input starts sixty seconds. Five seconds of silence warns; eight wipes the draft. The earlier deadline wins, and a tie wipes. Kept text remains available to copy until the user leaves. No draft is stored or sent anywhere.

The watch-only preview has its own clock. It shows typed keys, a surviving typo and a blocked Backspace before the silence and wipe. `feedback.js` shares the brief deny shake and tone with the trial. Sound needs a prior browser gesture; the preview is silent before one. Reduced motion replaces the loop with a static explanation and disables the shake.

`session.mjs` owns the real deadline rules and the count: Unicode words, with Han characters counted individually. Punctuation, emoji and whitespace do not count. This is a writing-unit count, not a linguistic Chinese word count. The room counter's tooltip and accessible description explain it. `room.js` connects the session to the browser editor. `theme.js` stores only the appearance preference. The default follows the system.

## Deploy

Transfer and extract the phase-two bundle on the target host, then run `sh writeitdown/install.sh` as root. It writes only the ten production files under `/var/www/writeitdown.app/`, preserves an existing `index.html.dc-bak2`, and creates that backup from the current index if absent. It does not touch server configuration or remove other files.

The legal pages disclose Google Fonts requests and possible hosting access logs. A public support/privacy contact is deliberately marked as not configured, not replaced with an invented address.

See `QA.md` for validation evidence and limits.
