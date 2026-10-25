// Uses mock school records and the real MTT workspace bridge script.
const { chromium } = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');
(async () => {
 const origin = process.env.LG_TEST_ORIGIN || 'http://127.0.0.1:8766';
 const mtt = 'https://mtt.thelittlegraduates.in';
 const bridge = process.env.LG_WORKSPACE_JS
   ? fs.readFileSync(process.env.LG_WORKSPACE_JS, 'utf8')
   : await (await fetch(mtt + '/assets/js/app-workspace.js')).text();
 const script = bridge.replaceAll('https://app.thelittlegraduates.in', origin);
 const browser = await chromium.launch({executablePath: process.env.CHROME_BIN, headless: true});
 try {
  const context = await browser.newContext({viewport: {width: 1280, height: 900}});
  const errors = [], posts = [];
  let blocked = false;
  const modules = ['students','montessori','tasks','crm','fees','expenses','logbook','inventory','plans','daycare','recruitment'].map(key => ({key, label: ({crm:'Admissions', montessori:'Assessment'})[key] || key[0].toUpperCase()+key.slice(1), native:false, web_url:mtt+'/'+(key==='montessori'?'assessment':key)+'/index.php'}));
  await context.route('**/api/v1/**', async route => {
   const path = new URL(route.request().url()).pathname;
   const headers = {'content-type':'application/json','access-control-allow-origin':origin,'access-control-allow-methods':'GET, POST, OPTIONS','access-control-allow-headers':'authorization,content-type,accept'};
   if(route.request().method()==='OPTIONS') return route.fulfill({status:204,headers});
   const data = path.endsWith('login_users.php') ? {school:'Test school',users:[{id:1,name:'Workspace Test',role:'admin'}]} : path.endsWith('login.php') ? {token:'a'.repeat(64), user:{id:1,name:'Workspace Test',role:'admin'},modules} : path.endsWith('me.php') ? {school:'Test school',user:{id:1,name:'Workspace Test',role:'admin'},modules} : {};
   await route.fulfill({status:200,headers,body:JSON.stringify({ok:true,...data})});
  });
  await context.route(mtt+'/app/open.php', async route => {
   const req=route.request();
   assert.equal(req.method(),'POST');
   assert(!req.url().includes('token='));
   const data=new URLSearchParams(req.postData());
   assert.equal(data.get('token'),'a'.repeat(64));
   posts.push(data.get('path'));
   await route.fulfill({status:200,contentType:'text/html',body:'<script>location.replace('+JSON.stringify(mtt+data.get('path'))+')</script>'});
  });
  await context.route(mtt+'/assets/js/app-workspace.js', route => route.fulfill({contentType:'application/javascript',body:script}));
  for (const prefix of [...modules.map(m=>new URL(m.web_url).pathname.split('/')[1]),'duties']) {
   await context.route(mtt+'/'+prefix+'/**', async route => {
    if(blocked) return route.abort('internetdisconnected');
    const path = new URL(route.request().url()).pathname;
    const detail=path.endsWith('detail.php');
    const body='<!doctype html><html><meta name="viewport" content="width=device-width,initial-scale=1"><script src="/assets/js/app-workspace.js" defer data-user="1"></script><body><h1>'+prefix+(detail?' details':' workspace')+'</h1>'+(detail?'<form><label>Notes <input name="notes"></label><button>Save</button></form>':'<a href="/'+prefix+'/detail.php" target="_blank">Open record</a>')+'</body></html>';
    await route.fulfill({status:200,contentType:'text/html',body});
   });
  }
  const page = await context.newPage();
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(origin);
  await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
  await page.getByRole('button',{name:'WT Workspace Test Admin'}).click();
  for(const digit of ['1','2','3','4']) await page.getByRole('button',{name:digit,exact:true}).click();
  await page.getByRole('button',{name:'OK',exact:true}).click();
  await page.getByRole('button',{name:/School Tab/}).click();
  await page.waitForTimeout(700);
  for(const module of modules) {
   console.log('Checking '+module.label);
   await page.getByRole('textbox',{name:'Search school tools'}).fill(module.label);
   await page.getByRole('button',{name:new RegExp('^'+module.label+' ')}).click();
   await page.waitForTimeout(800);
   const frame=page.frameLocator('iframe[title="School tool"]');
   await frame.getByRole('heading').waitFor();
   await page.getByRole('progressbar').waitFor({state:'hidden'});
   assert.equal(context.pages().length,1,'school module opened another tab');
   await frame.getByRole('link',{name:'Open record'}).click();
   await frame.getByRole('heading',{name:/details/}).waitFor();
   await page.getByRole('button',{name:'Previous page',exact:true}).click();
   await frame.getByRole('heading',{name:/workspace/}).waitFor();
   await page.getByRole('button',{name:'Close tool',exact:true}).click();
  }
  assert.equal(posts.length,11);
  // Narrow layout and a failed connection must leave a usable Close/Retry screen.
  await page.setViewportSize({width:375,height:812});
  await page.getByRole('textbox',{name:'Search school tools'}).fill('Fees');
  await page.getByRole('button',{name:/^Fees Fee records/}).click();
  await page.frameLocator('iframe[title="School tool"]').getByRole('heading').waitFor();
  await page.getByRole('progressbar').waitFor({state:'hidden'});
  await page.screenshot({path:'build/workspace-phone.png'});
  blocked=true;
  await page.getByRole('button',{name:'Reopen tool',exact:true}).click();
  await page.getByRole('button',{name:'Try again',exact:true}).waitFor({timeout:35000});
  await page.getByRole('button',{name:'Close tool',exact:true}).click();
  assert.equal(context.pages().length,1);
  assert.deepEqual(errors,[]);
  console.log('PASS: all 11 embedded modules; POST-only sign-in; internal target=_blank stays in app; Previous page and Close; phone layout; failed connection recovery. Fixtures only.');
 } finally { await browser.close(); }
})();
