const puppeteer = require('puppeteer');
(async () => {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  await page.goto('http://localhost:3000');
  
  // Try to find if .dark is active
  const isDark = await page.evaluate(() => document.documentElement.classList.contains('dark'));
  const themeValue = await page.evaluate(() => localStorage.getItem('onb_draft_theme'));
  console.log('Dark:', isDark, 'Draft theme:', themeValue);
  await browser.close();
})();
