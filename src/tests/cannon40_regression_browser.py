"""Cannon v3.9: exact shipped browser assets, deterministic local stepping.
No network mocks alter collision, damage, bots, guides, or rendering.
"""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--output',default='test-output/cannon39');ap.add_argument('--browser',default='/usr/bin/chromium');args=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(ok,label):
 assert ok,label
 checks.append(label);print('PASS',label,flush=True)
html=re.sub(r'<link[^>]*>','',(web/'index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html);html=html.replace('</head>','<style>'+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location);'+js[i+5:]
def load(c,data=None):
 p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate('''data=>{window.__location=new URL('http://game.test/?test=1');window.__store=data;
 const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});
 Object.defineProperty(window,'localStorage',{value:store(data)});Object.defineProperty(window,'sessionStorage',{value:store({})});window.requestAnimationFrame=()=>0;}''',data or {'leqra.muted':'1'})
 p.add_script_tag(content=(web/'netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.__test')
 p.evaluate('''()=>{window.arena39=(n=3,wall=true)=>{const T=__test;T.setPhase('menu');
 T.applyLocalPreset({rules:{...T.defaultRoomRules(),teamMode:'ffa',pickupRate:'off'},roster:Array.from({length:n},(_,i)=>({kind:i===0?'human':i===1?'local':'bot',name:'P'+i,team:0,difficulty:'normal'}))});T.startRound();T.setPhase('playing');T.clearInput();T.clearBullets();
 T.setWorld({width:1008,height:840,cols:12,rows:10,walls:[{x:-4,y:-4,w:1016,h:8,axis:'h',line:0},{x:-4,y:836,w:1016,h:8,axis:'h',line:840},{x:-4,y:-4,w:8,h:848,axis:'v',line:0},{x:1004,y:-4,w:8,h:848,axis:'v',line:1008},...(wall?[{x:142,y:-4,w:8,h:848,axis:'v',line:146},{x:230,y:-4,w:32,h:848,axis:'v',line:246}]:[])]});
 T.tanks.forEach((t,i)=>Object.assign(t,{human:true,x:80+i*120,y:210+i*70,angle:0,alive:true,invulnerable:0,cooldown:0,power:null,powerTime:0,charges:0,shield:0,speedTime:0,scopeTime:0,team:0}));return T;};}''')
 return p
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path=args.browser)
 try:
  c=b.new_context(viewport={'width':1365,'height':950});p=load(c)
  check(p.evaluate('leqra.version')=='4.0.0','Version 4.0.0 loads')
  check(p.evaluate("leqra.getState().rules.weapons.length===9 && leqra.getState().rules.weapons.includes('cannon')"),'Cannon included among nine default pickups')
  p.locator('#roomRulesBtn').click();check(p.locator('[data-weapon-toggle="cannon"]').is_checked(),'Cannon host rule toggle starts enabled')
  p.locator('[data-weapon-toggle="cannon"]').uncheck();p.locator('#applyRulesBtn').click()
  check(p.evaluate("!leqra.getState().rules.weapons.includes('cannon')"),'Host can disable Cannon')
  p.locator('#roomPresetsBtn').click();p.locator('#presetName').fill('No Cannon');p.locator('#savePresetBtn').click();stored=p.evaluate('__store');p.locator('[data-close-dialog="presetsDialog"]').click()
  q=load(c,stored);q.locator('#roomPresetsBtn').click();q.locator('#presetSelect').select_option('saved:0');q.locator('#loadPresetBtn').click()
  check(q.evaluate("!leqra.getState().rules.weapons.includes('cannon')"),'Saved explicit weapon list stays unchanged after reload');q.close()
  r=p.evaluate('''()=>{const T=arena39(),p=T.tanks[0];const a=T.projectileSpec(null),s=T.projectileSpec('cannon');T.grantPower(p,'scope');T.grantPower(p,'speed');T.grantPower(p,'shield');T.grantPower(p,'cannon');
   const grants={power:p.power,charges:p.charges,time:p.powerTime,scope:p.scopeTime,speed:p.speedTime,shield:p.shield};T.fire(p);const b=T.bullets[0],first={r:b.r,vx:b.vx,kind:b.kind,x:b.x,cooldown:p.cooldown,charges:p.charges};const repeated=T.fire(p);T.updateBullets(.4);return{a,s,grants,first,repeated,after:{x:b.x,vx:b.vx,bounces:b.bounces,dead:b.dead}};}''')
  check(r['s']['r']==3*r['a']['r'] and r['s']['speed']==3*r['a']['speed'],'Cannon diameter and speed exactly three times a standard shot')
  check(r['grants']=={'power':'cannon','charges':3,'time':10,'scope':10,'speed':6,'shield':10},'Cannon grants three shots/ten seconds and preserves independent buffs')
  check(not r['repeated'] and r['first']['cooldown']==.85 and r['first']['charges']==2,'Cannon cooldown prevents duplicate held-frame firing')
  check(abs(r['after']['x']-r['first']['x']-.4*846)<1e-6 and r['after']['vx']==846 and r['after']['bounces']==0 and not r['after']['dead'],'Actual local shot crosses two walls without speed loss or bouncing')
  r=p.evaluate('''()=>{const T=arena39(),p=T.tanks[0];p.x=117;T.grantPower(p,'cannon');const b=T.muzzleProjectile(p,0);return{x:b.x,vx:b.vx,bounces:b.bounces,inside:b.x>=142&&b.x<=150};}''')
  check(r['inside'] and r['x']==145 and r['vx']==846 and r['bounces']==0,'Wall-overlapping muzzle does not reflect or relocate Cannon shot')
  for dt in [1/120,1/60,.05,.5]:
   r=p.evaluate('''dt=>{const T=arena39(),p=T.tanks[0],a=T.tanks[1],b=T.tanks[2];a.x=320;a.y=210;b.x=420;b.y=210;T.grantPower(p,'cannon');T.fire(p);const shot=T.bullets[0];for(let time=0;time<.5-1e-9;){const s=Math.min(dt,.5-time);T.updateBullets(s);time+=s;}return{target:a.alive,behind:b.alive,x:shot.x,dead:shot.dead,count:T.bullets.length};}''',dt)
   check(not r['target'] and r['behind'] and r['dead'] and r['count']==0 and abs(r['x']-292.5)<1e-6,f'Swept first-tank hit at timestep {dt}; no tank piercing')
  r=p.evaluate('''()=>{const T=arena39(),p=T.tanks[0],a=T.tanks[1],b=T.tanks[2];a.x=320;a.y=210;a.shield=10;b.x=325;b.y=245;T.grantPower(p,'cannon');T.fire(p);T.updateBullets(.5);return{alive:a.alive,shield:a.shield,other:b.alive,count:T.bullets.length};}''')
  check(r=={'alive':True,'shield':0,'other':True,'count':0},'Shield absorbs one Cannon hit; no area damage')
  for ff in [False,True]:
   r=p.evaluate('''ff=>{const T=arena39();T.localRoom.rules.teamMode='teams';T.localRoom.rules.friendlyFire=ff;const p=T.tanks[0],a=T.tanks[1],b=T.tanks[2];p.team=a.team=2;b.team=3;a.x=220;a.y=210;a.shield=10;b.x=370;b.y=210;T.grantPower(p,'cannon');T.fire(p);T.updateBullets(.5);return{a:a.alive,shield:a.shield,b:b.alive};}''',ff)
   check(r['a'] and r['shield']==(0 if ff else 10) and r['b']==ff,f'Friendly fire {ff}: correct ally shield and downstream enemy handling')
  r=p.evaluate('''()=>{const T=arena39(),p=T.tanks[0];T.grantPower(p,'cannon');const fired=[];for(let i=0;i<3;i++){p.cooldown=0;fired.push(T.fire(p));}const out={fired,power:p.power,charges:p.charges,time:p.powerTime,kinds:T.bullets.map(b=>b.kind)};T.clearBullets();p.power='cannon';p.charges=0;p.cooldown=0;out.empty=T.fire(p);T.grantPower(p,'cannon');p.powerTime=.001;T.update(1/120);out.expired=!p.power;return out;}''')
  check(all(r['fired']) and r['power'] is None and r['charges']==0 and r['time']==0 and r['kinds']==['cannon']*3,'Final charge resets weapon, not existing Cannon shots')
  check(not r['empty'] and r['expired'],'Zero-charge shots refused; equip timer expires')
  r=p.evaluate('''()=>{const T=arena39(),p=T.tanks[0];for(const e of T.tanks.slice(1))e.alive=false;T.grantPower(p,'cannon');T.fire(p);const b=T.bullets[0];for(let i=0;i<600;i++)T.updateBullets(1/60);const exited=b.dead&&T.bullets.length===0&&b.bounces===0;T.grantPower(p,'cannon');p.cooldown=0;T.fire(p);const short=T.bullets[0],x=short.x;short.life=.002;T.updateBullets(.1);return{exited,expired:short.dead,dx:short.x-x};}''')
  check(r['exited'] and r['expired'] and abs(r['dx']-.002*846)<1e-6,'Arena exit and fractional lifetime bound Cannon shots')
  r=p.evaluate('''()=>{const T=arena39(),p=T.tanks[0];T.tanks.slice(1).forEach(t=>t.alive=false);T.grantPower(p,'cannon');const b=T.muzzleProjectile(p,0),before=JSON.stringify(b),visual=T.projectOnlineBullet(b,.12),unchanged=JSON.stringify(b)===before;T.bullets.push({...b,id:1,trail:[]});T.updateBullets(.12);return{dx:visual.x-b.x,local:T.bullets[0].x,visual:visual.x,vx:visual.vx,bounces:visual.bounces,unchanged};}''')
  check(abs(r['dx']-.12*846)<1e-6 and abs(r['local']-r['visual'])<1e-6 and r['vx']==846 and r['bounces']==0 and r['unchanged'],'Online visual extrapolation crosses walls and matches simulation without mutating snapshots')
  r=p.evaluate('''()=>{const T=arena39(),p=T.tanks[0],e=T.tanks[1];T.tanks[2].alive=false;e.x=320;e.y=210;T.grantPower(p,'cannon');const d={lead:1};const aim=T.evaluateBotShot(p,0,e,d,0);T.fire(p);const threats=T.forecastThreats(e,.65);return{hit:aim?.target,flight:aim?.flight,bounces:aim?.bounces,threats:threats.map(t=>({r:t.r,x:t.x,dx:t.vx*(t.end-t.start)}))};}''')
  check(r['hit']==1 and r['flight']<.3 and r['bounces']==0,'Local bots aim through walls with Cannon intercept timing')
  check(len(r['threats'])==1 and r['threats'][0]['r']==10.5 and r['threats'][0]['dx']>400,'Bot dodge forecast treats Cannon as a large, fast wall-piercing threat')
  r=p.evaluate('''()=>{const T=arena39(),p=T.tanks[0];T.tanks.slice(1).forEach(t=>t.alive=false);T.grantPower(p,'cannon');const short=T.aimingGuide(p);p.scopeTime=10;const long=T.aimingGuide(p);const e=T.tanks[1];e.x=320;e.y=210;e.alive=true;const stop=T.aimingGuide(p);p.power=null;p.scopeTime=0;const regular=T.aimingGuide(p);return{short,long,end:stop.points.at(-1),target:stop.tank?.id,regular:regular.points};}''')
  check(len(r['short']['points'])==2 and r['short']['points'][-1]['x']==192,'Normal Cannon guide crosses nearby wall instead of suggesting a bounce')
  check(len(r['long']['points'])==2 and r['long']['points'][-1]['x']==1008,'Scoped Cannon guide stays straight, ends at arena edge, and remains range-bounded')
  check(r['target']==1 and abs(r['end']['x']-292.5)<1e-6,'Cannon guide uses enlarged projectile contact radius')
  check(len(r['regular'])>2,'Ordinary short guide still reflects from walls')
  r=p.evaluate("""()=>{const T=arena39();T.pickups.length=0;const p=T.tanks[0];T.pickups.push({x:p.x,y:p.y,type:'cannon',age:0,life:19});T.update(1/120);return{power:p.power,charges:p.charges,time:p.powerTime,pickups:T.pickups.length};}""")
  check(r=={'power':'cannon','charges':3,'time':10,'pickups':0},'Driving over a real Cannon pickup collects it and removes it from the maze')
  # Press the actual default keys, including Player 2's Space binding.
  p.evaluate('''()=>{const T=arena39();T.tanks.slice(2).forEach(t=>t.alive=false);for(const t of T.tanks.slice(0,2)){t.invulnerable=999;T.grantPower(t,'cannon');}}''')
  p.keyboard.down('f');p.evaluate('__test.update(1/120)');p.keyboard.up('f');p.keyboard.down('Space');p.evaluate('__test.update(1/120)');p.keyboard.up('Space')
  check(p.evaluate("__test.bullets.filter(b=>b.kind==='cannon').map(b=>b.owner).sort().join(',')==='0,1'"),'F and Space independently fire primary and secondary Cannons')
  for w,h in [(1365,950),(390,844),(320,568),(844,390)]:
   mobile=w<760 or h<620;ctx=b.new_context(viewport={'width':w,'height':h},has_touch=mobile,is_mobile=mobile,device_scale_factor=2 if mobile else 1);page=load(ctx)
   icons=page.evaluate('''()=>{__test.renderPowerLegend();return [...document.querySelectorAll('.power-list canvas[data-power-icon]')].map(e=>{const f=document.createElement('canvas');f.width=e.width;f.height=e.height;const c=f.getContext('2d');c.setTransform(f.width/26,0,0,f.height/26,f.width/2,f.height/2);__test.powerIcon(e.dataset.powerIcon,c);return{kind:e.dataset.powerIcon,equal:e.toDataURL()===f.toDataURL()};});}''')
   check(len(icons)==9 and all(x['equal'] for x in icons),f'{w}x{h}: all nine legend icons pixel-match the pickup renderer')
   page.locator('#roomRulesBtn').click();check(page.locator('[data-weapon-toggle="cannon"]').is_checked(),f'{w}x{h}: Cannon available in rules');page.screenshot(path=str(out/f'rules-{w}x{h}.png'));page.locator('#applyRulesBtn').click()
   page.evaluate("__test.addRoomSeat('local')");page.locator('#startRoomBtn').click()
   result=page.evaluate('''()=>{const T=__test;T.setPhase('playing');T.tanks.forEach(t=>{t.human=true;t.invulnerable=999});T.clearBullets();T.updateHUD(true);T.updateCombatFeedback(true);const rect=()=>{const r=document.querySelector('#arenaWrap').getBoundingClientRect();return[r.width,r.height]};const before=rect();
    const p=T.tanks.find(t=>t.id===T.localRoom.self),two=T.tanks.find(t=>t.localIndex===1);for(const t of [p,two]){T.grantPower(t,'cannon');T.grantPower(t,'scope');T.grantPower(t,'speed');T.grantPower(t,'shield');t.cooldown=0;T.fire(t);}T.updateBullets(.03);T.updateHUD(true);T.updateCombatFeedback(true);T.render();return{before,after:rect(),one:document.querySelector('#weaponLabel').textContent,two:document.querySelector('#weaponLabel2').textContent,body:document.body.scrollWidth,width:innerWidth};}''')
   check(result['before']==result['after'] and result['body']<=result['width']+1,f'{w}x{h}: Cannon/buffs do not resize maze or overflow horizontally')
   check('CANNON' in result['one'] and '×2' in result['one'] and 'CANNON' in result['two'] and '×2' in result['two'],f'{w}x{h}: independent named Cannon charge/cooldown HUDs')
   page.screenshot(path=str(out/f'cannon-{w}x{h}.png'));ctx.close()
  check(not errors,'No uncaught browser errors')
  report={'version':'4.0.0','passed':len(checks),'checks':checks,'errors':errors,'limits':'Chromium desktop/mobile emulation; real assets, synthetic URL/storage and deterministic stepping. No physical phones.'}
  (out/'results.json').write_text(json.dumps(report,indent=2));print('TOTAL',len(checks))
 finally:b.close()
