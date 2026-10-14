// Render a page to PNG: node render.cjs page.html out.png WIDTH HEIGHT
const { chromium } = require('playwright');
const path = require('node:path');
(async () => {
  const [,, page, out, w, h] = process.argv;
  const browser = await chromium.launch();
  const p = await browser.newPage({ viewport: { width: +w, height: +h } });
  await p.goto('file://' + path.resolve(page));
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(400);
  await p.screenshot({ path: out });
  await browser.close();
  console.log('wrote', out);
})();
