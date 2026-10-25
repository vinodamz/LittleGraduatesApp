const { chromium } = require('playwright');
(async () => {
 const browser = await chromium.launch({executablePath:process.env.CHROME_BIN, headless:true});
 const testOrigin=process.env.LG_TEST_ORIGIN || 'http://127.0.0.1:8766';
 const context = await browser.newContext({viewport:{width:1280,height:900}});
 const page = await context.newPage();
 const errors=[];
 page.on('pageerror', e=>errors.push(e.message));
 const modules=[{key:'materials',label:'Materials',native:true,web_url:'https://mtt.thelittlegraduates.in/materials/index.php'}];
 let offline=false, markCount=0;
 const day={date:'2026-10-25',date_label:'Sunday, 25 October',summary:{checked:markCount,total:1,pending:1-markCount},conditions:[{code:'good',label:'Good',tone:'ok'},{code:'damaged',label:'Damaged',tone:'danger'}],locations:['Sensorial'],materials:[{id:4,name:'Pink Tower',location:'Sensorial',check:null,media:[]}],links:{}};
 await context.route('**/api/v1/**', async route=>{
  const req=route.request(),path=new URL(req.url()).pathname;
  const headers={'content-type':'application/json','access-control-allow-origin':testOrigin,'access-control-allow-methods':'GET, POST, OPTIONS','access-control-allow-headers':'authorization,content-type,accept'};
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers});
  if(path.endsWith('materials/mark.php')){if(offline)return route.abort('internetdisconnected');markCount++;}
  const data=path.endsWith('login_users.php')?{school:'Little Graduates',users:[{id:1,name:'Browser Test',role:'admin'}]}:
   path.endsWith('login.php')?{token:'a'.repeat(64),user:{id:1,name:'Browser Test',role:'admin'},modules}:
   path.endsWith('me.php')?{school:'Little Graduates',user:{id:1,name:'Browser Test',role:'admin'},modules}:
   path.endsWith('materials/today.php')?{day:{...day,summary:{checked:markCount,total:1,pending:1-markCount},materials:[{...day.materials[0],check:markCount?{id:1,condition_code:'good',label:'Good',tone:'ok'}:null}]}}:{};
  await route.fulfill({status:200,headers,body:JSON.stringify({ok:true,...data})});
 });
 await page.goto(testOrigin);
 await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
 await page.waitForTimeout(3000);
 await page.getByRole('button',{name:'BT Browser Test Admin'}).click();
 await page.waitForTimeout(300);
 for(const digit of ['1','2','3','4']) await page.getByRole('button',{name:digit,exact:true}).click();
 await page.getByRole('button',{name:'OK',exact:true}).click();
 await page.waitForTimeout(2000);
 await page.getByRole('button',{name:/Materials Tab/}).click();
 await page.waitForTimeout(500);
 offline=true;
 await page.getByRole('checkbox',{name:'Good',exact:true}).click();
 await page.waitForTimeout(500);
 let saved=JSON.parse(await page.evaluate(()=>window.lgStore.read('materials:1')));
 if(saved.pending.length!==1)throw new Error('Offline mark was not saved');
 await page.reload();
 await page.locator('flt-semantics-placeholder').evaluate(el=>el.click());
 await page.waitForTimeout(1500);
 await page.getByRole('button',{name:/Materials Tab/}).click();
 await page.waitForTimeout(500);
 if(!(await page.getByRole('checkbox',{name:'Good',exact:true}).isChecked()))throw new Error('Saved condition not restored after reload');
 offline=false;
 await page.getByRole('button',{name:'Refresh and retry saved checks',exact:true}).click();
 await page.waitForTimeout(500);
 saved=JSON.parse(await page.evaluate(()=>window.lgStore.read('materials:1')));
 if(saved.pending.length!==0 || markCount!==1)throw new Error('Retry did not upload exactly once');
 const second=await page.context().newPage();
 await second.goto(testOrigin);
 await second.locator('flt-semantics-placeholder').evaluate(el=>el.click());
 await second.waitForTimeout(1500);
 await second.getByRole('button',{name:/Materials Tab/}).click();
 if(!(await second.locator('body').innerText()).includes('another tab'))throw new Error('Concurrent-tab editing was not prevented');
 await second.close();
 await page.screenshot({path:process.cwd() + '/build/web-browser-preview.png'});
 console.log('PASS: browser sign-in, offline persistence, reload recovery, retry-once upload, concurrent-tab protection');
 await browser.close();
 if(errors.length)throw new Error(errors.join('\n'));
})();
