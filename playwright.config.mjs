import { defineConfig } from '@playwright/test';

// Root-surface harness: serves the repository root over HTTP and drives the
// landing + browser trial in index.html. This is separate from the
// writeitdown/ harness, which covers the writeitdown site.
export default defineConfig({
  testDir: './tests',
  timeout: 30000,
  retries: 0,
  workers: 1,
  reporter: [['list']],
  use: {
    baseURL: 'http://127.0.0.1:8017',
    viewport: { width: 1440, height: 900 },
  },
  webServer: {
    command: 'python3 -m http.server 8017 --bind 127.0.0.1',
    url: 'http://127.0.0.1:8017/index.html',
    reuseExistingServer: !process.env.CI,
  },
});
