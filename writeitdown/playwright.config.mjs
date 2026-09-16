import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './qa',
  testMatch: '**/*.spec.mjs',
  outputDir: process.env.WID_QA_OUTPUT || './test-results',
  reporter: [['list']],
  workers: 2,
  use: {
    baseURL: 'http://127.0.0.1:8015/writeitdown/',
    channel: 'chrome',
    trace: 'retain-on-failure',
  },
  projects: [1440, 390].flatMap(width => ['dark', 'light'].flatMap(colorScheme =>
    ['no-preference', 'reduce'].map(reducedMotion => ({
      name: `${width}-${colorScheme}-${reducedMotion}`,
      use: { viewport: { width, height: width === 1440 ? 900 : 844 }, colorScheme, reducedMotion },
    })))),
  webServer: {
    command: 'python3 -m http.server 8015 --bind 127.0.0.1 --directory ..',
    url: 'http://127.0.0.1:8015/writeitdown/',
    reuseExistingServer: false,
  },
});
