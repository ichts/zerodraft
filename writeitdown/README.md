# WRITE_IT_DOWN

A static browser writing room. Open `index.html#trial` over HTTP to enter directly, or use the landing CTA.

```sh
python3 -m http.server 8000
# http://localhost:8000/writeitdown/
node --test writeitdown/session.test.mjs
```

The first input starts sixty seconds. Five seconds of silence warns; eight wipes the draft. The earlier deadline wins, and a tie wipes. Kept text remains available to copy until the user leaves. No draft is stored or sent anywhere.

The preview has its own clock and is labeled PREVIEW. `session.mjs` owns the real deadline rules; `room.js` connects them to the browser editor. `theme.js` stores only the appearance preference. The default follows the system.

## Deploy

Transfer and extract the phase-two bundle on the target host, then run `sh writeitdown/install.sh` as root. It writes only the nine production files under `/var/www/writeitdown.app/`, preserves an existing `index.html.dc-bak2`, and creates that backup from the current index if absent. It does not touch server configuration or remove other files.

The legal pages disclose Google Fonts requests and possible hosting access logs. A public support/privacy contact is deliberately marked as not configured, not replaced with an invented address.

See `QA.md` for validation evidence and limits.
