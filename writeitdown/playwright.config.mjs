import { defineConfig } from '@playwright/test';

const origin = 'http://127.0.0.1:8015';
const viewport = width => ({ width, height: width === 1440 ? 900 : 844 });
// Light is the site default; dark projects choose dark the way a visitor does, via the stored toggle.
const storage = colorScheme => ({ cookies: [], origins: [{ origin, localStorage: [{ name: 'writeitdown-theme', value: colorScheme }] }] });
const project = (width, colorScheme, reducedMotion) => ({
  name: `${width}-${colorScheme}-${reducedMotion}`,
  use: { viewport: viewport(width), colorScheme, reducedMotion, storageState: storage(colorScheme) },
});

// The default run, and the required PR check, is two projects: the desktop width and the phone width, both in the
// default light theme with no motion preference (the pair the full matrix repeats ten more ways). Every spec that is
// not gated to one project runs on both. The project names are the ones the specs gate on.
const defaultProjects = () => [1440, 390].map(width => project(width, 'light', 'no-preference'));

// The full matrix, `npm run test:full`, for the nightly run and before a release: every spec in both themes at both
// widths with and without Reduce Motion.
const fullMatrix = () => [1440, 390].flatMap(width => ['dark', 'light'].flatMap(colorScheme =>
  ['no-preference', 'reduce'].map(reducedMotion => project(width, colorScheme, reducedMotion))));

export default defineConfig({
  testDir: './qa',
  testMatch: '**/*.spec.mjs',
  outputDir: process.env.WID_QA_OUTPUT || './test-results',
  reporter: [['list']],
  workers: 2,
  use: {
    baseURL: `${origin}/writeitdown/`,
    channel: 'chrome',
    trace: 'retain-on-failure',
  },
  projects: process.env.WID_MATRIX === 'full' ? fullMatrix() : defaultProjects(),
  webServer: {
    command: 'python3 -m http.server 8015 --bind 127.0.0.1 --directory ..',
    url: `${origin}/writeitdown/`,
    reuseExistingServer: false,
  },
});
