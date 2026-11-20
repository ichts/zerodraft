import { defineConfig } from '@playwright/test';

const origin = 'http://127.0.0.1:8015';
const viewport = width => ({ width, height: width === 1440 ? 900 : 844 });
const lampStorage = { cookies: [], origins: [] };

// The default run, and the required PR check, is two projects: the desktop width and the phone width, both Chromium in
// the Lamp default with no motion preference (the pair the full matrix repeats nine more ways). Every spec that is not
// gated to one project runs on both. The project names are the ones the specs gate on. The shipped-site journey gate
// (`journey/`, AGENTS.md "Testing gate") owns the WebKit iPhone profile: most of this suite probes Chromium (CDP,
// clipboard permissions, Tab order), so it is not run on WebKit here.
function defaultProjects() {
  return [1440, 390].map(width => ({
    name: `${width}-lamp-no-preference`,
    use: { channel: 'chrome', viewport: viewport(width), colorScheme: 'dark', reducedMotion: 'no-preference', storageState: lampStorage },
  }));
}

// The full matrix, `npm run test:full`, for the nightly run and before a release: every spec in each paper mode
// (D-119: one engine, one timing, three materials) at both widths with and without Reduce Motion, all on Chromium.
// Lamp is the default and its projects store nothing; Paper and Slate choose the mode the way a visitor does,
// through the stored switch.
function fullMatrix() {
  return [1440, 390].flatMap(width => ['lamp', 'paper', 'slate'].flatMap(mode =>
    ['no-preference', 'reduce'].map(reducedMotion => ({
      name: `${width}-${mode}-${reducedMotion}`,
      use: { channel: 'chrome', viewport: viewport(width), colorScheme: mode === 'paper' ? 'light' : 'dark', reducedMotion,
        storageState: { cookies: [], origins: mode === 'lamp' ? [] : [{ origin, localStorage: [{ name: 'writeitdown-theme', value: mode }] }] } },
    }))));
}

export default defineConfig({
  testDir: './qa',
  testMatch: '**/*.spec.mjs',
  outputDir: process.env.WID_QA_OUTPUT || './test-results',
  reporter: [['list']],
  workers: 2,
  use: {
    baseURL: 'http://127.0.0.1:8015/writeitdown/',
    trace: 'retain-on-failure',
  },
  projects: process.env.WID_MATRIX === 'full' ? fullMatrix() : defaultProjects(),
  webServer: {
    command: 'python3 -m http.server 8015 --bind 127.0.0.1 --directory ..',
    url: 'http://127.0.0.1:8015/writeitdown/',
    reuseExistingServer: false,
  },
});
