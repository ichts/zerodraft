// With --dmg-file <path> the given real file is served instead of random bytes.
// Local pre-deploy server for the journey gate.
// Serves a writeitdown site tree (--root) and, with --fixture-dmg, a generated
// 2 MB FIXTURE DMG at /download/Write-It-Down-1.0.dmg. With the fixture, the
// pending SHA-256 line of download/index.html is rewritten in memory to the
// fixture's real hash (proves the sha logic only; it is NOT the real release).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i < 0 ? d : (process.argv[i + 1] ?? true); };
const root = path.resolve(arg('root', '.'));
const port = Number(arg('port', 8016));
const fixture = process.argv.includes('--fixture-dmg');
const dmgFile = arg('dmg-file', null);
const dmg = dmgFile ? fs.readFileSync(path.resolve(dmgFile)) : fixture ? crypto.randomBytes(2 * 1024 * 1024) : null;
const sha = dmg && crypto.createHash('sha256').update(dmg).digest('hex');
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript', '.woff2': 'font/woff2', '.png': 'image/png', '.txt': 'text/plain', '.xml': 'application/xml' };

http.createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (dmg && p === '/download/Write-It-Down-1.0.dmg') {
    res.writeHead(200, { 'content-type': 'application/x-apple-diskimage', 'content-length': dmg.length });
    return res.end(req.method === 'HEAD' ? undefined : dmg);
  }
  let f = path.join(root, p);
  if (!f.startsWith(root)) { res.writeHead(403); return res.end(); }
  if (fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, 'index.html');
  if (!fs.existsSync(f)) { res.writeHead(404); return res.end('not found'); }
  let body = fs.readFileSync(f);
  if (sha && p === '/download/') {
    body = Buffer.from(body.toString().replace(/<p class="report" id="sha256" data-launch-pending[^>]*>.*?<\/p>/,
      `<p class="report" id="sha256">SHA-256: <code data-launch="sha256">${sha}</code></p>`));
  }
  res.writeHead(200, { 'content-type': types[path.extname(f)] || 'application/octet-stream' });
  res.end(req.method === 'HEAD' ? undefined : body);
}).listen(port, '127.0.0.1', () => console.log(`serving ${root} on http://127.0.0.1:${port}${dmg ? ` (served dmg ${dmgFile || 'FIXTURE'} sha ${sha})` : ''}`));
