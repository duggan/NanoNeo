// Renders scene.html into numbered PNG frames: node render.js <out dir> [fps]
// Needs Playwright and Google Chrome. `make demo` runs this and encodes docs/demo.gif.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  const [out, fps = 20] = [process.argv[2], +process.argv[3] || 20];
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ channel: 'chrome' });
  const page = await browser.newPage({ viewport: { width: 960, height: 540 }, deviceScaleFactor: 2 });
  await page.goto('file://' + path.join(__dirname, 'scene.html'));
  const loop = await page.evaluate(() => window.LOOP);
  for (let i = 0; i < Math.round(loop * fps); i++) {
    await page.evaluate(t => render(t), i / fps);
    await page.evaluate(() => Promise.all([...document.images].map(img =>
      img.complete ? 0 : new Promise(resolve => { img.onload = resolve; }))));
    await page.screenshot({ path: path.join(out, String(i).padStart(4, '0') + '.png') });
  }
  await browser.close();
})();
