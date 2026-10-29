#!/usr/bin/env node
// Frames a raw crop of the approval prompt the way the landing page shows it: a rounded dark
// card with padding and a soft purple glow on a near-black background (colours sampled from the
// original Slack-era image). Output is a PNG at 2x.
//
// Library: import { frame } from './frame-approval.mjs'; await frame(browser, rawPath, outPath, { bg })
// CLI:     node frame-approval.mjs raw.png out.png [cardBackgroundCss]
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';

export async function frame(browser, rawPath, outPath, { cardBg = '#1f1f1f', dsf = 2 } = {}) {
  const b64 = readFileSync(rawPath).toString('base64');
  const ctx = await browser.newContext({ deviceScaleFactor: dsf, viewport: { width: 1400, height: 900 } });
  const page = await ctx.newPage();
  await page.setContent(`<!doctype html><meta charset="utf-8"><style>
    html,body{margin:0;background:#0f1117}
    #stage{display:inline-block;padding:20px;background:#0f1117}
    #card{border-radius:20px;overflow:hidden;background:${cardBg};padding:12px 16px 14px;
      box-shadow:0 0 0 1px rgba(124,58,237,.16),0 0 28px 4px rgba(112,64,230,.42)}
    img{display:block}
  </style><div id="stage"><div id="card"><img id="shot" src="data:image/png;base64,${b64}"></div></div>`);
  await page.waitForFunction(() => document.getElementById('shot').complete);
  // Show the raw capture at its CSS size (it was taken at the same scale factor).
  await page.evaluate(d => { const i = document.getElementById('shot'); i.style.width = (i.naturalWidth / d) + 'px'; }, dsf);
  await page.locator('#stage').screenshot({ path: outPath });
  await ctx.close();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { chromium } = await import('playwright');
  const browser = await chromium.launch();
  await frame(browser, process.argv[2], process.argv[3], process.argv[4] ? { cardBg: process.argv[4] } : {});
  await browser.close();
}
