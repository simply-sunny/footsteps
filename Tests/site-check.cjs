// Run: NODE_PATH=<directory containing playwright> node Tests/site-check.cjs
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
(async () => {
  assert(fs.existsSync('docs/style.css'), 'Site stylesheet must exist');
  const browser = await chromium.launch({channel:'chrome',headless:true});
  const page = await browser.newPage();
  const errors = [], requests = [];
  page.on('pageerror', error=>errors.push(error.message));
  page.on('request', request=>requests.push(request.url()));
  page.on('response', response=>{if(response.status()>=400) errors.push(`${response.status()} ${response.url()}`);});
  await page.goto(process.env.SITE_URL || 'http://127.0.0.1:8765/', {waitUntil:'networkidle'});
  assert.equal(await page.locator('.card').count(),4);
  assert(await page.locator('#reader').innerText().then(text=>text.includes('Footsteps')));
  const count=requests.length;
  const readerBox=()=>page.locator('#reader').evaluate(el=>({height:el.offsetHeight,top:el.offsetTop}));
  const before=await readerBox();
  await page.getByRole('tab',{name:'PRIVACY.md',exact:true}).click();
  assert((await page.locator('#reader').innerText()).includes('What stays on your device'));
  await page.getByRole('tab',{name:'PRIVACY.md',exact:true}).press('ArrowRight');
  assert.equal(await page.locator('#tab-architecture').getAttribute('aria-selected'),'true');
  const after=await readerBox();
  assert.deepEqual(before,after);
  assert.equal(requests.length,count,'Switching documents must not fetch');
  await page.getByRole('button',{name:'Time',exact:true}).click();
  assert.equal(await page.locator('#heat-nodes').getAttribute('hidden'),null);
  assert.equal(await page.locator('#routes').evaluate(el=>el.style.opacity),'0');
  await page.getByRole('button',{name:'Path',exact:true}).click();
  assert.equal(await page.locator('#heat-nodes').getAttribute('hidden'),'');
  await page.getByRole('tab',{name:'README.md',exact:true}).click();
  fs.mkdirSync('.impeccable/review',{recursive:true});
  for(const [name,width] of [['desktop',1440],['mobile',390]]) {
    await page.setViewportSize({width,height:1000});
    await page.evaluate(()=>window.scrollTo(0,0));
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'No horizontal page overflow');
    await page.screenshot({path:`.impeccable/review/${name}.png`,fullPage:true});
  }
  assert.deepEqual(errors,[]);
  assert(requests.every(url=>new URL(url).origin===new URL(page.url()).origin),'No third-party requests');
  await browser.close();
  console.log('PASS: docs, keyboard tabs, no-fetch switching, stable reader, modes, responsive overflow, no console/HTTP errors.');
})().catch(error=>{console.error(error);process.exit(1);});
