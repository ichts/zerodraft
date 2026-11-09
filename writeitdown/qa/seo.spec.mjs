import { test, expect } from '@playwright/test';
import { readdirSync, readFileSync } from 'node:fs';
import { openPage, sweepTimeout } from './page-sweep.mjs';

// Indexed pages, in sitemap order. mac.html ships and is linked, but stays out of the sitemap until sales open.
const answers = [
  '/what-is-write-it-down.html',
  '/write-it-down-mac-vs-web.html',
  '/write-it-down-free-trial.html',
  '/write-it-down-price.html',
  '/delete-a-draft.html',
  '/is-my-writing-saved.html',
];
const pages = ['/', '/download/', '/support.html', ...answers, '/privacy.html', '/terms.html', '/impressum.html'];
const shipped = [...pages, '/mac.html'];
const origin = 'https://writeitdown.app';
const crawlers = ['OAI-SearchBot', 'ChatGPT-User', 'GPTBot', 'PerplexityBot', 'ClaudeBot'];

const servedPath = path => '/writeitdown' + (path.endsWith('/') ? path + 'index.html' : path);
const localPath = path => (path === '/' ? 'index.html' : path.slice(1));

async function faqData(page, path) {
  await openPage(page, localPath(path));
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
    const answerPage = [
      ...(document.querySelector('#faq > h2 + p')
        ? [{ question: document.querySelector('#faq > h2').textContent.trim(), answer: document.querySelector('#faq > p').textContent.trim() }]
        : []),
      ...[...document.querySelectorAll('#faq .qa')].map(item => ({
        question: item.querySelector('h3').textContent.trim(),
        answer: item.querySelector('p').textContent.trim(),
      })),
    ];
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
  // Thirteen page fetches in one body: budget the walk, not the harness's flat 30 s (#146).
  test.setTimeout(sweepTimeout(shipped.length));
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
  // Purchase and refund details live on the Mac page; this public file points readers there.
  for (const fact of [
    '3 free writing sessions',
    'See the Mac page for current purchase details and license delivery.',
    'The price and refund terms are on that page.',
  ])
    expect(text).toContain(fact);
  expect(text).not.toMatch(/\b(openai|chatgpt|anthropic|claude|perplexity|gemini|gpt-?\d|google|cloudflare)\b/i);
  // Only the Mac app ships, so this public summary names no Windows app until a Store listing is live (C3).
  expect(text).not.toMatch(/windows/i);
  for (const path of [...pages, '/mac.html'])
    expect(text, path).toContain(origin + path);
});

test('every JSON-LD block parses and every FAQPage matches the visible FAQ word for word', async ({ page }) => {
  // Thirteen shipped pages, then the landing and its six answer pages: twenty navigations in one body.
  test.setTimeout(sweepTimeout(shipped.length + 1 + answers.length));
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
      const firstParagraph = document.querySelector('main h1 + p')?.innerText.trim();
      const firstSentence = [...new Intl.Segmenter('en', { granularity: 'sentence' }).segment(firstParagraph || '')][0]?.segment.trim();
      return {
        title: document.title,
        h1: document.querySelector('main h1')?.textContent.trim(),
        firstParagraph,
        firstSentence,
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
    expect(data.firstSentence, `${path}: first sentence names the product`).toContain('Write It Down');
    expect(data.words, `${path}: visible body copy`).toBeGreaterThanOrEqual(120);
    expect(data.article, `${path}: Article schema`).toEqual({ headline: data.h1, description: data.firstParagraph });
    expect(data.crumbNames[0], `${path}: breadcrumb starts at home`).toBe('Home');
    expect(data.schemaCrumbs, `${path}: BreadcrumbList matches the visible breadcrumb`).toEqual(data.crumbNames);
    // The five answer-first pages answer their question directly, so only the older page still
    // carries the tool-directed self-description.
    expect(data.selfMention, `${path}: tool-directed self-description`).toBe(path === '/write-it-down-mac-vs-web.html');
  }
});

test('answer-first pages open on the answer and keep the document grid', async ({ page }) => {
  const rewritten = answers.filter(path => path !== '/write-it-down-mac-vs-web.html');
  for (const path of rewritten) {
    await page.goto(localPath(path));
    await page.evaluate(() => document.fonts.ready);
    const measure = () => page.evaluate(() => {
      const main = document.querySelector('main');
      const bounds = main.getBoundingClientRect();
      const sentences = value => [...new Intl.Segmenter('en', { granularity: 'sentence' }).segment(value)]
        .map(part => part.segment.trim()).filter(Boolean);
      const grid = element => {
        const rect = element.getBoundingClientRect();
        const range = document.createRange();
        range.selectNodeContents(element);
        return {
          text: element.innerText,
          left: rect.left,
          right: rect.right,
          clipped: [...range.getClientRects()].some(line => line.left < rect.left - 1 || line.right > rect.right + 1),
        };
      };
      return {
        width: innerWidth,
        scrollWidth: document.documentElement.scrollWidth,
        text: main.innerText,
        lede: main.querySelector('.doc-lede').innerText,
        headings: [...main.querySelectorAll('h1, h2, h3')].map(heading => {
          const next = heading.nextElementSibling?.matches('p') ? heading.nextElementSibling.innerText : null;
          const parts = next ? sentences(next) : [];
          const firstAnswer = parts[0] && /^(No|Yes)\.$/.test(parts[0])
            ? parts.slice(0, 2).join(' ')
            : (parts[0] || '');
          return {
            ...grid(heading),
            tag: heading.tagName,
            answer: next,
            firstSentence: firstAnswer,
          };
        }),
        paragraphs: [...main.querySelectorAll('p')].map(paragraph => ({
          ...grid(paragraph),
          sentences: sentences(paragraph.innerText),
        })),
        column: { left: main.querySelector('h1').getBoundingClientRect().left, right: main.querySelector('h1').getBoundingClientRect().right },
      };
    });
    const before = await measure();
    expect(before.scrollWidth, `${path}: no horizontal scroll`).toBe(before.width);
    expect(before.text, `${path}: no tool-directed copy`).not.toMatch(/ChatGPT|ask an AI|language model/i);
    expect(before.text, `${path}: no em dash`).not.toContain('\u2014');
    expect(before.lede, `${path}: no introductory filler`).not.toMatch(/is simple:|for you:|keep typing:/);
    // Rule 18 item 5: every section opens with a question in the reader's words.
    // The title, H1, each H2 question and its first answer sentence name Write It Down.
    for (const heading of before.headings) {
      expect(heading.text, `${path}: ${heading.text} is a question`).toMatch(/\?$/);
      expect(heading.text, `${path}: ${heading.text} names the product`).toContain('Write It Down');
      expect(heading.answer, `${path}: ${heading.text} is answered by the next paragraph`).toBeTruthy();
      if (heading.tag === 'H1' || heading.tag === 'H2') {
        expect(heading.firstSentence, `${path}: first answer sentence under "${heading.text}" names the product`).toContain('Write It Down');
      }
    }
    // Each sentence carries one fact; later sentences use it/the room/the app with an unambiguous referent.
    for (const paragraph of before.paragraphs) {
      for (const sentence of paragraph.sentences) {
        expect(sentence.split(/\s+/).length, `${path}: ${sentence} carries one fact`).toBeLessThanOrEqual(32);
      }
    }
    // Every block sits on the one text column the H1 defines, and none of it is cut off.
    for (const block of [...before.headings, ...before.paragraphs]) {
      expect(Math.abs(block.left - before.column.left), `${path}: left grid ${block.text}`).toBeLessThanOrEqual(1);
      expect(block.right, `${path}: right edge ${block.text}`).toBeCloseTo(before.column.right, 0);
      expect(block.clipped, `${path}: text fits ${block.text}`).toBe(false);
    }
    await page.waitForTimeout(150);
    const after = await measure();
    expect(after.headings, `${path}: headings stay put`).toEqual(before.headings);
    expect(after.paragraphs, `${path}: paragraphs stay put`).toEqual(before.paragraphs);
  }
});

test('answer pages link each other', async ({ page }) => {
  for (const path of answers) {
    await page.goto(localPath(path));
    const links = await page.evaluate(() => [...document.querySelectorAll('main.doc a')]
      .map(link => link.getAttribute('href')));
    const siblings = answers.filter(other => other !== path && links.includes(other.slice(1)));
    expect(siblings.length, `${path}: links ${siblings.join(', ')}`).toBeGreaterThanOrEqual(2);
  }
});
