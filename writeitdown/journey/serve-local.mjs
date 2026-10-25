// Local pre-deploy server for the journey gate, using the real release DMG.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i < 0 ? d : process.argv[i + 1]; };
const root = path.resolve(arg('root', '.'));
const port = Number(arg('port', 8016));
const dmgFile = arg('dmg-file', null);
const dmg = dmgFile ? fs.readFileSync(path.resolve(dmgFile)) : null;
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript', '.woff2': 'font/woff2', '.png': 'image/png', '.svg': 'image/svg+xml', '.txt': 'text/plain', '.xml': 'application/xml', '.dmg': 'application/x-apple-diskimage' };

http.createServer((req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (dmg && p === '/download/Write-It-Down-1.0.dmg') {
    res.writeHead(200, { 'content-type': types['.dmg'], 'content-length': dmg.length });
    return res.end(req.method === 'HEAD' ? undefined : dmg);
  }
  let f = path.join(root, p);
  if (!f.startsWith(root + path.sep) && f !== root) { res.writeHead(403); return res.end(); }
  if (fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, 'index.html');
  if (!fs.existsSync(f)) {
    // A missing page is a 404, never the landing page with a 200: a soft 404 makes every broken
    // link, stale DMG and mistyped URL look like the home page to a browser and to a crawler.
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    return res.end(req.method === 'HEAD' ? undefined : 'not found');
  }
  const body = fs.readFileSync(f);
  res.writeHead(200, { 'content-type': types[path.extname(f)] || 'application/octet-stream' });
  res.end(req.method === 'HEAD' ? undefined : body);
}).listen(port, '127.0.0.1', () => console.log(`serving ${root} on http://127.0.0.1:${port}${dmg ? ` (served dmg ${dmgFile})` : ''}`));
