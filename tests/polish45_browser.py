"""v4.5 focused browser regression: dark-only theme, callsigns, paint ownership, teams and speed stacks."""
import argparse,json,re,time
from pathlib import Path
from urllib.parse import urlencode
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:8455');ap.add_argument('--output',default='test-output/polish45');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[];contexts=[]
def check(ok,label): assert ok,label; checks.append(label); print('PASS',label,flush=True)
def wait(p,s,**kwargs): return p.wait_for_function(s,polling=30,**kwargs)
def load(b,size=(1365,950),live=False,code=None,name='ALPHA'):
 w,h=size;mobile=w<760 or h<620;c=b.new_context(viewport={'width':w,'height':h},has_touch=mobile,is_mobile=mobile,device_scale_factor=2 if mobile else 1,color_scheme='dark');contexts.append(c);p=c.new_page();p.set_default_timeout(9000);p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 q={'test':'1'}
 if code:q['room']=code
 p.evaluate('''a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(s,t,u){this.state=s;window.__updatedURL=String(u)}};const d={'leqra.name':a.name,'leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});if(!a.live)window.requestAnimationFrame=()=>0;}''',dict(url=a.url+'/?'+urlencode(q),live=live,name=name))
 for f in ['theme.js','netcode.js']:p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);wait(p,'window.__test&&leqra.version==="4.5.0"');p.evaluate('__test.render()');return p
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium')
 try:
  p=load(b)
  check(p.evaluate('leqraTheme.resolved')=='dark' and p.evaluate('leqraTheme.palette.accent')=='#00c8ff','dark-only neon-blue theme')
  check('APPEARANCE' not in p.locator('#controlsDialog').inner_text(),'appearance/light-mode controls removed')
  check(p.locator('[data-tank-color]').count()==4,'FFA host can paint own tank and local bots')
  # Remove one bot without a confirmation and add/name P2.
  p.locator('[data-kick-target="3"]').first.click();check(not p.locator('#kickDialog').get_attribute('open'),'bot removal has no confirmation dialog')
  p.locator('#addLocalBtn').click();wait(p,'__test.localRoom.players.some(p=>p.kind==="local")')
  p.locator('#roomP2Callsign').fill('BRAVO');p.locator('#roomP2CallsignForm button').click();wait(p,'__test.localRoom.players.find(p=>p.kind==="local").name==="BRAVO"')
  p2=p.evaluate('__test.localRoom.players.find(p=>p.kind==="local").id')
  labels=p.evaluate('''ids=>{const c=document.getElementById('arena').getContext('2d'),old=c.fillText,seen=[];c.fillText=function(s,...a){seen.push(String(s));return old.call(this,s,...a)};try{for(const id of ids)__test.drawTank(__test.tanks.find(t=>t.id===id));}finally{c.fillText=old}return seen;}''',[0,p2])
  check('ALPHA' in labels and 'BRAVO' in labels,'both local tank labels use callsigns')
  check(not any(x in ('P1','P2') or '· T' in x for x in labels),'tank labels contain no P1/P2 or team suffix')
  # Five speed pickups stack and the sixth caps.
  speed=p.evaluate('''()=>{const t=__test.tanks[0];t.speedTime=0;t.speedStacks=0;for(let i=0;i<6;i++)__test.grantPower(t,'speed');__test.updateHUD(true);return{stacks:t.speedStacks,time:t.speedTime,buff:document.querySelector('#buffLabel').textContent}}''')
  check(speed['stacks']==5 and speed['time']==6 and 'SPD×5' in speed['buff'],'Super Speed stacks to five and refreshes one timer')
  # Team format clears FFA paint and forces all tank paint to team choices.
  p.locator('[data-tank-color="0"]').select_option('7');check(p.evaluate('__test.localRoom.players.find(p=>p.id===0).colorIndex')==7,'FFA tank paint can be customized')
  p.locator('#roomRulesBtn').click();p.locator('#rule-teamMode').select_option('teams');p.locator('#rule-teamColor1').select_option('4');p.locator('#rule-teamColor2').select_option('6');p.locator('#applyRulesBtn').click()
  check(p.locator('[data-tank-color]').count()==0,'individual tank color controls disappear in Teams')
  state=p.evaluate('''()=>({rules:__test.currentRules(),players:__test.localRoom.players.map(p=>({id:p.id,team:p.team,colorIndex:p.colorIndex,color:__test.localRoom.players.find(x=>x.id===p.id)&&document.querySelector(`[data-seat="${p.id}"]`)?.style.getPropertyValue('--player')}))})''')
  check(all(x.get('colorIndex') is None for x in state['players']),'switching to Teams clears hidden FFA paint overrides')
  p.evaluate('__test.resetPreview()')
  teamcheck=p.evaluate('''()=>__test.tanks.every(t=>t.color===__test.localRoom.players.find(p=>p.id===t.id)?.color || t.color===(['#d2f65a','#ff9679','#73cee4','#c5a2ff','#ffc46b','#ff83bd','#75f0cb','#b7c6ee'][__test.currentRules().teamColors[t.team-1]]))''')
  check(teamcheck,'team tank colors are authoritative')
  p.screenshot(path=str(out/'teams-dark.png'))
  p.close()
  # Online FFA paint ownership: remote human owns their own paint, host cannot edit it.
  code='v45-'+str(int(time.time()*1000))
  host=load(b,live=True,code=code,name='HOST');wait(host,'__test.online.connected&&__test.online.roomData?.host===__test.online.id')
  guest=load(b,(390,844),True,code,'GUEST');wait(guest,'__test.online.connected&&!__test.online.spectating')
  gid=guest.evaluate('__test.online.id');hid=host.evaluate('__test.online.id')
  wait(host,f'__test.online.roomData.players.some(p=>p.id==={gid})')
  check(host.locator(f'[data-tank-color="{gid}"]').count()==0,'host cannot repaint a remote online human in FFA')
  check(guest.locator(f'[data-tank-color="{gid}"]').count()==1,'online FFA player can edit own tank color')
  guest.locator(f'[data-tank-color="{gid}"]').select_option('6');wait(host,f'__test.online.roomData.players.find(p=>p.id==={gid}).colorIndex===6')
  check(host.evaluate(f'__test.online.roomData.players.find(p=>p.id==={gid}).color')=='#75f0cb','self-selected FFA color replicates to room')
  # Convert to teams and verify both clients lose personal color controls and server clears override.
  host.locator('#roomRulesBtn').click();host.locator('#rule-teamMode').select_option('teams');host.locator('#rule-teamColor1').select_option('0');host.locator('#rule-teamColor2').select_option('1');host.locator('#applyRulesBtn').click();wait(guest,'__test.online.roomData.rules.teamMode==="teams"')
  wait(host,"document.querySelectorAll('[data-tank-color]').length===0");wait(guest,"document.querySelectorAll('[data-tank-color]').length===0");check(True,'Teams lock individual paint for host and guest')
  check(guest.evaluate(f'__test.online.roomData.players.find(p=>p.id==={gid}).colorIndex==null'),'server clears former FFA paint when Teams begins')
  check(guest.evaluate(f'__test.online.roomData.players.find(p=>p.id==={gid}).color')=='#ff9679','remote team tank matches host-selected Team 2 color')
  guest.screenshot(path=str(out/'online-teams-390x844.png'))
  check(not errors,'no uncaught browser errors: '+str(errors))
 finally:
  for c in contexts:
   try:c.close()
   except:pass
  b.close()
(out/'results.json').write_text(json.dumps({'version':'4.5.0','passed':len(checks),'checks':checks,'errors':errors},indent=2));print('TOTAL',len(checks))
