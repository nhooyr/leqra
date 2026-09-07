"""v3.8 map density, Scope geometry/HUD, icons and settings regression.
Uses exact assets with synthetic URL/storage and deterministic simulation stepping.
"""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
pa=argparse.ArgumentParser();pa.add_argument('--output',default='test-output/scope38');pa.add_argument('--browser',default='/usr/bin/chromium');args=pa.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(x,s):
 assert x,s
 checks.append(s);print('PASS',s,flush=True)
html=re.sub(r'<link[^>]*>','',(web/'index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html);html=html.replace('</head>','<style>'+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location);'+js[i+5:]
def load(c,data=None):
 p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate('''data=>{window.__location=new URL('http://game.test/?test=1');window.__store=data;
 const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});
 Object.defineProperty(window,'localStorage',{value:store(data)});Object.defineProperty(window,'sessionStorage',{value:store({})});window.requestAnimationFrame=()=>0;
 }''',data or {'leqra.muted':'1'})
 p.add_script_tag(content=(web/'netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra && window.__test');return p
sizes=[('compact',7,7,2,5),('standard',9,8,3,7),('large',12,10,4,12),('huge',14,12,5,17),('giant',16,14,6,23)]
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path=args.browser)
 try:
  c=b.new_context(viewport={'width':1365,'height':950});p=load(c)
  check(p.evaluate('leqra.version')=='3.9.0','Version 3.9.0 starts without errors')
  check(p.evaluate("leqra.getState().rules.mapSize==='large' && leqra.getState().rules.pickupRate==='superfast'"),'12x10 and Super fast defaults retained')
  check(p.evaluate("leqra.getState().rules.weapons.includes('scope') && leqra.getState().rules.weapons.length===9"),'Scope remains included with all nine default pickups')
  p.locator('#roomRulesBtn').click();check(p.locator('#rule-mapSize option').count()==5,'All five map choices visible');check(p.locator('[data-weapon-toggle="scope"]').is_checked(),'Host can enable/disable Scope in rules')
  for name,w,h,start,cap in sizes:
   p.locator('#rule-mapSize').select_option(name)
   check(p.locator('#rule-pickup-density').inner_text().startswith(f'{start} starting pickups · {cap} maximum'),f'{name} live density explanation')
   p.locator('#applyRulesBtn').click();s=p.evaluate('leqra.getState()')
   check((s['world']['cols'],s['world']['rows'],s['pickupCount'])==(w,h,start),f'{name} local preview dimensions and starts')
   p.locator('#roomRulesBtn').click()
  p.screenshot(path=str(out/'rules-1365x950.png'));p.locator('[data-close-dialog="rulesDialog"]').click()
  p.locator('#roomPresetsBtn').click();p.locator('#presetName').fill('Giant scope game');p.locator('#savePresetBtn').click();stored=p.evaluate('__store')
  p2=load(c,stored);p2.locator('#roomPresetsBtn').click();p2.locator('#presetSelect').select_option('saved:0');p2.locator('#loadPresetBtn').click()
  check(p2.evaluate("leqra.getState().rules.mapSize==='giant' && leqra.getState().rules.weapons.includes('scope')"),'16x14 + Scope survive saved preset reload');p2.close();p.locator('[data-close-dialog="presetsDialog"]').click()
  # Game code creates eight real tanks; manual stepping holds controllers still.
  for mode in ['elimination','ctf','koth']:
   for name,w,h,start,cap in sizes:
    result=p.evaluate('''({mode,name})=>{const T=__test;T.setPhase('menu');
     T.applyLocalPreset({rules:{...T.defaultRoomRules(),mode,teamMode:'teams',mapSize:name,weapons:['scope'],timeLimit:600},roster:Array.from({length:8},(_,i)=>({kind:i===0?'human':i===1?'local':'bot',name:'P'+i,difficulty:'normal',team:1+i%2}))});T.startRound();
     const initial=T.pickups.length;T.setPhase('playing');for(const t of T.tanks){t.human=true;t.invulnerable=999;t.cooldown=999;}
     for(let i=0;i<119;i++)T.update(1/120);const before=T.pickups.length;for(let i=0;i<2;i++)T.update(1/120);const after=T.pickups.length;
     for(let i=0;i<300;i++)T.spawnPower();const cap=T.pickups.length;
     const safe=T.pickups.every((p,i)=>T.pickups.every((q,j)=>i===j||Math.hypot(p.x-q.x,p.y-q.y)>84*1.1)&&T.tanks.every(t=>!t.alive||Math.hypot(p.x-t.x,p.y-t.y)>84*.85));
     const onlyScope=T.pickups.every(p=>p.type==='scope');T.setPhase('menu');return{initial,before,after,cap,safe,onlyScope};}''',{'mode':mode,'name':name})
    check(result['initial']==start and result['before']==start and result['after']==start+1,f'{mode}/{name}: initial supply and first-second boundary')
    check(result['cap']==cap and result['safe'] and result['onlyScope'],f'{mode}/{name}: exact cap, safe separation, scope-only filter')
  for weapons,rate in [([], 'superfast'),(['scope'],'off')]:
   n=p.evaluate('''({weapons,rate})=>{const T=__test;T.setPhase('menu');T.setLocalRules({...T.defaultRoomRules(),mapSize:'giant',weapons,pickupRate:rate});T.startRound();for(let i=0;i<100;i++)T.spawnPower();return T.pickups.length;}''',{'weapons':weapons,'rate':rate})
   check(n==0,f'Disabled pickup rule respected: {rate}/{weapons}')
  result=p.evaluate('''()=>{const T=__test;T.setPhase('menu');T.setLocalRules({...T.defaultRoomRules(),mapSize:'giant'});T.startRound();T.setPhase('playing');T.clearBullets();T.pickups.length=0;for(const t of T.tanks){t.human=true;t.invulnerable=99;}
   const t=T.tanks[0];T.grantPower(t,'laser');T.grantPower(t,'speed');T.grantPower(t,'shield');T.pickups.push({x:t.x,y:t.y,type:'scope',life:19,age:0});T.update(1/120);
   const acquired={scope:t.scopeTime,power:t.power,charges:t.charges,shield:t.shield,speed:t.speedTime};t.scopeTime=1;T.grantPower(t,'scope');const refreshed=t.scopeTime;t.scopeTime=.001;T.update(1/120);const expired=t.scopeTime;T.grantPower(t,'scope');T.respawnLocalTank(t);return{acquired,refreshed,expired,respawn:t.scopeTime};}''')
  check(result['acquired']['scope']==10 and result['acquired']['power']=='laser' and result['acquired']['charges']==3 and result['acquired']['shield']>9 and result['acquired']['speed']>5,'Actual Scope collection preserves laser, charges, shield and boost')
  check(result['refreshed']==10 and result['expired']==0 and result['respawn']==0,'Scope refreshes without stacking, expires and resets on respawn')
  # Exact path budget and reflections, not pixel-length guesses.
  geometry=p.evaluate('''()=>{const T=__test;T.setPhase('playing');T.clearBullets();for(const t of T.tanks)t.alive=false;const t=T.tanks[0];Object.assign(t,{alive:true,invulnerable:99,x:300,y:210,angle:.41,scopeTime:10,power:null});
   const width=1344,height=1176;T.setWorld({cols:16,rows:14,width,height,walls:[{x:-4,y:-4,w:width+8,h:8},{x:-4,y:height-4,w:width+8,h:8},{x:-4,y:-4,w:8,h:height+8},{x:width-4,y:-4,w:8,h:height+8}]});
   const before=JSON.stringify({t,bullets:T.bullets,stats:T.matchReport});const g=T.aimingGuide(t);const total=g.points.reduce((sum,p,i)=>sum+(i?Math.hypot(p.x-g.points[i-1].x,p.y-g.points[i-1].y):0),0);const bounded=g.points.every(p=>p.x>=7.499&&p.x<=width-7.499&&p.y>=7.499&&p.y<=height-7.499);
   const unchanged=before===JSON.stringify({t,bullets:T.bullets,stats:T.matchReport});t.scopeTime=0;const normal=T.aimingGuide(t);const short=normal.points.reduce((s,p,i)=>s+(i?Math.hypot(p.x-normal.points[i-1].x,p.y-normal.points[i-1].y):0),0);
   const other=T.tanks[1];Object.assign(t,{scopeTime:10,angle:0,invulnerable:0,team:1});Object.assign(other,{alive:true,x:450,y:210,r:17,invulnerable:0,team:2});const stopped=T.aimingGuide(t);
   other.team=1;const friendly=T.aimingGuide(t);return{total,bounded,segments:g.points.length,unchanged,short,target:stopped.tank?.id,friend: friendly.tank?.id??null};}''')
  check(abs(geometry['total']-2520)<.002 and geometry['bounded'] and geometry['segments']>2,'Scope reflects at walls with exact 2520-unit half-perimeter budget')
  check(geometry['unchanged'] and abs(geometry['short']-112)<.001,'Guide is cosmetic and returns to original 112-unit length')
  check(geometry['target']==1 and geometry['friend']!=1,'Guide stops at opposing tank and respects friendly-fire protection')
  c.close()
  for w,h in [(1365,950),(390,844),(320,568),(844,390)]:
   mobile=w<760 or h<620;c=b.new_context(viewport={'width':w,'height':h},has_touch=mobile,is_mobile=mobile,device_scale_factor=2 if mobile else 1);p=load(c)
   pixels=p.evaluate('''()=>{const T=__test;T.renderPowerLegend();return [...document.querySelectorAll('.power-list canvas[data-power-icon]')].map(e=>{const fresh=document.createElement('canvas');fresh.width=e.width;fresh.height=e.height;const c=fresh.getContext('2d');c.setTransform(e.width/26,0,0,e.height/26,e.width/2,e.height/2);T.powerIcon(e.dataset.powerIcon,c);return{name:e.dataset.powerIcon,match:e.toDataURL()===fresh.toDataURL()};});}''')
   check(len(pixels)==9 and all(e['match'] for e in pixels),f'{w}x{h}: all nine legend icons pixel-match shared maze routine')
   p.locator('#roomRulesBtn').click();p.locator('#rule-mapSize').select_option('giant');p.screenshot(path=str(out/f'rules-{w}x{h}.png'));p.locator('#applyRulesBtn').click()
   p.evaluate("__test.addRoomSeat('local')");p.locator('#startRoomBtn').click()
   result=p.evaluate('''()=>{const T=__test;T.setPhase('playing');T.clearBullets();for(const t of T.tanks){t.human=true;t.invulnerable=999;t.cooldown=0;}
    const rect=()=>{const b=document.querySelector('#arenaWrap').getBoundingClientRect();return [b.width,b.height]};T.updateHUD(true);const before=rect();
    const one=T.tanks[0],two=T.tanks.find(t=>t.localIndex===1);for(const t of [one,two])for(const k of ['scope','speed','shield','laser'])T.grantPower(t,k);T.updateHUD(true);T.render();
    const after=rect(),labels=[document.querySelector('#buffLabel').textContent,document.querySelector('#buffLabel2').textContent];const active=[T.aimingGuide(one).points.length,T.aimingGuide(two).points.length];
    for(const t of [one,two]){t.scopeTime=0;t.speedTime=0;t.shield=0;}T.updateHUD(true);const expired=rect();for(const t of [one,two])for(const k of ['scope','speed','shield','laser'])T.grantPower(t,k);T.updateHUD(true);T.render();
    return {before,after,expired,labels,active};}''')
   check(result['before']==result['after']==result['expired'],f'{w}x{h}: pickup collection/expiry does not resize arena')
   check(all('SCP 10s' in s and 'SPD 6s' in s and 'SHD 10s' in s for s in result['labels']),f'{w}x{h}: both pilots get independent stacked buff timers')
   check(all(n>=2 for n in result['active']),f'{w}x{h}: both local pilots have extended guides')
   check(p.evaluate('document.documentElement.scrollWidth<=innerWidth+1'),f'{w}x{h}: no horizontal page overflow')
   p.screenshot(path=str(out/f'scope-{w}x{h}.png'));c.close()
  check(not errors,'No uncaught browser errors')
  (out/'results.json').write_text(json.dumps({'version':'3.9.0','passed':len(checks),'checks':checks,'errors':errors,'limits':'Chromium emulation, synthetic URL/storage, manual simulation stepping; no physical devices.'},indent=2));print('TOTAL',len(checks))
 finally:b.close()
