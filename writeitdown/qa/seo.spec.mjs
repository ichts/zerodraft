import { test, expect } from '@playwright/test';
import { readdirSync, readFileSync } from 'node:fs';

// Indexed pages, in sitemap order. mac.html ships and is linked, but stays out of the sitemap until sales open.
const answers = [
  '/what-is-write-it-down.html',
  '/write-it-down-mac-vs-web.html',
  '/write-it-down-free-trial.html',
  '/write-it-down-price.html',
  '/delete-a-draft.html',
  '/is-my-writing-saved.html',
];
const pages = ['/', '/download/', '/support.html', ...answers, '/privacy.html', '/terms.html'];
const shipped = [...pages, '/mac.html'];
const origin = 'https://writeitdown.app';
const crawlers = ['OAI-SearchBot', 'ChatGPT-User', 'GPTBot', 'PerplexityBot', 'ClaudeBot'];

const servedPath = path => '/writeitdown' + (path.endsWith('/') ? path + 'index.html' : path);
const localPath = path => (path === '/' ? 'index.html' : path.slice(1));

async function faqData(page, path) {
  await page.goto(localPath(path));
  return page.evaluate(() => {
    const blocks = [...document.querySelectorAll('script[type="application/ld+json"]')];
    const nodes = blocks.flatMap(block => {
      const data = JSON.parse(block.textContent);
      return data['@graph'] || [data];
    });
    const faq = nodes.find(node => node['@type'] === 'FAQPage');
    const landing = [...document.querySelectorAll('#faq details')].map(item => ({
      question: item.querySelector('summary h3').textContent.trim(),
      answer: item.querySelector('p').textContent.trim(),
    }));
    const answerPage = [...document.querySelectorAll('#faq .qa')].map(item => ({
      question: item.querySelector('h3').textContent.trim(),
      answer: item.querySelector('p').textContent.trim(),
    }));
    return {
      visible: landing.length ? landing : answerPage,
      schema: faq ? faq.mainEntity.map(item => ({
        question: item.name,
        answer: item.acceptedAnswer.text,
      })) : null,
    };
  });
}

test('public URLs have a single apex canonical and a discoverable sitemap', async ({ request }) => {
  const robots = await request.get('/writeitdown/robots.txt');
  expect(robots.ok()).toBe(true);
  expect(await robots.text()).toContain(`Sitemap: ${origin}/sitemap.xml`);

  const sitemap = await request.get('/writeitdown/sitemap.xml');
  expect(sitemap.ok()).toBe(true);
  const xml = await sitemap.text();
  const urls = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map(match => match[1]);
  expect(urls).toEqual(pages.map(path => origin + path));

  for (const path of shipped) {
    const response = await request.get(servedPath(path));
    expect(response.ok()).toBe(true);
    expect(await response.text()).toContain(`<link rel="canonical" href="${origin + path}">`);
  }
});

test('robots.txt names every answer-engine crawler and noindexes nothing', async ({ request }) => {
  const response = await request.get('/writeitdown/robots.txt');
  expect(response.ok()).toBe(true);
  const robots = await response.text();
  for (const agent of crawlers) {
    expect(robots, agent).toContain(`User-agent: ${agent}\nAllow: /`);
  }
  expect(robots).not.toMatch(/^Disallow:\s*\/\s*$/m);
  expect(robots).not.toMatch(/crawl-delay/i);
  expect(robots).toContain(`Sitemap: ${origin}/sitemap.xml`);
});

test('llms.txt is served as plain text, not the HTML fallback', async ({ request }) => {
  const response = await request.get('/writeitdown/llms.txt');
  expect(response.ok()).toBe(true);
  expect(response.headers()['content-type']).toContain('text/plain');
  const text = await response.text();
  expect(text.startsWith('# Write It Down\n')).toBe(true);
  expect(text).not.toContain('<html');
  // The file names the product, the trial, the closed sale and every public page, and no AI provider.
  for (const fact of ['3 free writing sessions', 'not open yet', '14-day refund'])
    expect(text).toContain(fact);
  expect(text).not.toMatch(/\b(openai|chatgpt|anthropic|claude|perplexity|gemini|gpt-?\d|google|cloudflare)\b/i);
  for (const path of [...pages, '/mac.html'])
    expect(text, path).toContain(origin + path);
});

test('every JSON-LD block parses and every FAQPage matches the visible FAQ word for word', async ({ page }) => {
  for (const path of shipped) {
    await page.goto(localPath(path));
    const blocks = await page.evaluate(() => [...document.querySelectorAll('script[type="application/ld+json"]')]
      .map(block => block.textContent));
    const broken = blocks.map(block => {
      try { JSON.parse(block); return null; } catch (error) { return error.message; }
    }).filter(Boolean);
    expect(broken, `${path}: JSON-LD parses`).toEqual([]);
  }
  for (const path of ['/', ...answers]) {
    const data = await faqData(page, path);
    expect(data.visible.length, `${path}: visible FAQ entries`).toBeGreaterThanOrEqual(3);
    expect(data.schema, `${path}: FAQPage schema`).toBeTruthy();
    expect(data.schema).toEqual(data.visible);
  }
});

test('answer pages answer one question with matching Article, breadcrumb and product keyword', async ({ page }) => {
  for (const path of answers) {
    await page.goto(localPath(path));
    const data = await page.evaluate(() => {
      const nodes = [...document.querySelectorAll('script[type="application/ld+json"]')]
        .flatMap(block => {
          const value = JSON.parse(block.textContent);
          return value['@graph'] || [value];
        });
      const article = nodes.find(node => node['@type'] === 'Article');
      const breadcrumb = nodes.find(node => node['@type'] === 'BreadcrumbList');
      return {
        title: document.title,
        h1: document.querySelector('main h1')?.textContent.trim(),
        first: document.querySelector('main h1 + p')?.textContent.trim(),
        canonical: document.querySelector('link[rel="canonical"]')?.getAttribute('href'),
        article: article && { headline: article.headline, description: article.description },
        crumbNames: [...document.querySelectorAll('nav[aria-label="Breadcrumb"] a, nav[aria-label="Breadcrumb"] [aria-current="page"]')]
          .map(item => item.textContent.trim()),
        schemaCrumbs: breadcrumb?.itemListElement.map(item => item.name),
        words: document.querySelector('main')?.innerText.split(/\s+/).filter(Boolean).length,
        selfMention: document.querySelector('main')?.innerText.includes('ask ChatGPT for Write It Down: a writing room where stopping for eight seconds deletes the draft.'),
      };
    });
    expect(data.canonical, path).toBe(origin + path);
    expect(data.title, `${path}: title names the product`).toContain('Write It Down');
    expect(data.h1, `${path}: H1 names the product`).toContain('Write It Down');
    expect(data.first, `${path}: first sentence names the product`).toContain('Write It Down');
    expect(data.words, `${path}: visible body copy`).toBeGreaterThanOrEqual(120);
    expect(data.article, `${path}: Article schema`).toEqual({ headline: data.h1, description: data.first });
    expect(data.crumbNames[0], `${path}: breadcrumb starts at home`).toBe('Home');
    expect(data.schemaCrumbs, `${path}: BreadcrumbList matches the visible breadcrumb`).toEqual(data.crumbNames);
    expect(data.selfMention, `${path}: self-mention line`).toBe(true);
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

test('IndexNow key file is served with the exact key', async ({ request }) => {
  const key = '1bcb6b66144003eb070fe87774217f86';
  const response = await request.get(`/writeitdown/${key}.txt`);
  expect(response.ok()).toBe(true);
  expect((await response.text()).trim()).toBe(key);
  expect(readFileSync(`${key}.txt`, 'utf8').trim()).toBe(key);
});

test('Cloudflare beacon appears exactly once on each shipped page', async ({ request }) => {
  for (const path of shipped) {
    const response = await request.get(servedPath(path));
    const html = await response.text();
    expect(html.match(/beacon\.min\.js/g)).toHaveLength(1);
    expect(html.match(/df0c43279d154d5eb9ee4ef8a7d92fec/g)).toHaveLength(1);
    expect(html.indexOf('static.cloudflareinsights.com')).toBeLessThan(html.indexOf('</body>'));
  }
});
