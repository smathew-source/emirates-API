const { defineConfig } = require('@playwright/test');
module.exports = defineConfig({
  testDir: './ui-tests',
  timeout: 240000,
  expect: { timeout: 15000 },
  workers: 1,
  retries: 0,
  outputDir: './reports/ui-artifacts',
  reporter: [['list'], ['html', { outputFolder: './reports/ui-report', open: 'never' }]],
  use: {
    channel: 'chrome', headless: true,
    viewport: { width: 1440, height: 1000 },
    actionTimeout: 20000, navigationTimeout: 60000,
    screenshot: 'only-on-failure', trace: 'off', video: 'off'
  }
});
