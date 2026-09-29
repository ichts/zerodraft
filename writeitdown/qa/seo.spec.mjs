import { test, expect } from '@playwright/test';
import { readdirSync, readFileSync } from 'node:fs';

const pages = ['/', '/support.html', '/privacy.html', '/terms.html'];
const origin = 'https://writeitdown.app';

test('public URLs have a single apex canonical and a discoverable sitemap', async ({ request }) => {
  const robots = await request.get('/writeitdown/robots.txt');
  expect(robots.ok()).toBe(true);
  expect(await robots.text()).toContain(`Sitemap: ${origin}/sitemap.xml`);

  const sitemap = await request.get('/writeitdown/sitemap.xml');
  expect(sitemap.ok()).toBe(true);
  const xml = await sitemap.text();
  const urls = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map(match => match[1]);
  expect(urls).toEqual(pages.map(path => origin + path));

  for (const path of pages) {
    const response = await request.get('/writeitdown' + (path === '/' ? '/index.html' : path));
    expect(response.ok()).toBe(true);
    expect(await response.text()).toContain(`<link rel="canonical" href="${origin + path}">`);
  }
});

test('verification files are served without HTML fallback', async ({ request }) => {
  const googleFile = readdirSync('.').find(name => /^google[a-zA-Z0-9_-]+\.html$/.test(name));
  expect(googleFile).toBeTruthy();
  for (const file of [googleFile, 'BingSiteAuth.xml']) {
    const response = await request.get('/writeitdown/' + file);
    expect(response.ok()).toBe(true);
    expect(await response.text()).toBe(readFileSync(file, 'utf8'));
  }
});

test('IndexNow key file is served, exact, and shipped by the installer', async ({ request }) => {
  const key = '1bcb6b66144003eb070fe87774217f86';
  const response = await request.get(`/writeitdown/${key}.txt`);
  expect(response.ok()).toBe(true);
  expect((await response.text()).trim()).toBe(key);
  expect(readFileSync(`${key}.txt`, 'utf8').trim()).toBe(key);
  expect(readFileSync('install.sh', 'utf8')).toContain(` ${key}.txt'`);
});
