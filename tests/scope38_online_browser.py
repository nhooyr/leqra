"""v3.8 Scope integration through real local Go WebSockets and exact browser assets.
Uses the opt-in _test.go fixture for deterministic grants only. No production cheats.
"""
import argparse,json,re,urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright
pa=argparse.ArgumentParser();pa.add_argument('url');pa.add_argument('--output',default='test-output/scope38-online');args=pa.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(ok,s):
 assert ok,s
 checks.append(s);print('PASS',s,flush=True)
html=re.sub(r'<link[^>]*>','',(web/'index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html);html=html.replace('</head>','<style>'+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+f'}})(new URL({json.dumps(args.url+"/?test=1")}));'+js[i+5:]
def load(c):
 p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate('''()=>{const store=d=>({getItem:k=>Object.hasOwn(d,k)?d[k]:null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});Object.defineProperty(window,'localStorage',{value:store({'leqra.muted':'1'})});Object.defineProperty(window,'sessionStorage',{value:store({})});}''')
 p.add_script_tag(content=(web/'netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra');p.locator('#joinOtherBtn').click();return p
with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium')
 try:
  ctx=b.new_context(viewport={'width':1365,'height':950});host=load(ctx);host.locator('#pilotName').fill('SCOPE HOST');host.locator('#createRoomBtn').click();host.wait_for_function('leqra.getState().online?.connected');code=host.evaluate('leqra.getState().online.code')
  host.locator('#addLocalBtn').click();host.wait_for_function('leqra.getState().room.players.length===2');host.locator('[data-room-mode="koth"]').click();host.wait_for_function("leqra.getState().rules.mode==='koth'");host.locator('#roomMapSize').select_option('giant');host.wait_for_function('(value)=>leqra.getState().rules.mapSize===value',arg='giant');host.locator('#roomRulesBtn').click();host.locator('#rule-timeLimit').fill('600');host.locator('#rule-scoreTarget').fill('300');host.locator('#rule-pickupRate').select_option('off');host.locator('#applyRulesBtn').click();host.wait_for_function('leqra.getState().rules.mapSize==="giant"')
  guest=load(ctx);guest.locator('#pilotName').fill('GUEST');guest.locator('#joinCode').fill(code);guest.locator('#joinRoomBtn').click();guest.wait_for_function('leqra.getState().online?.connected');guest.locator('#readyBtn').click()
  viewer=load(ctx);viewer.locator('#pilotName').fill('WATCHER');viewer.locator('#joinCode').fill(code);viewer.locator('#joinRoomBtn').click();viewer.wait_for_function('leqra.getState().online?.connected');viewer.evaluate('''()=>{const s=leqra.getState();__test.setPlayerSpectating(s.room.players.find(p=>p.id===s.online.id),true);}''');viewer.wait_for_function('leqra.getState().online.spectating')
  # Roster changes clear guest ready; explicitly consent again only if needed.
  if guest.locator('#readyBtn').get_attribute('aria-pressed')!='true':
   state=guest.evaluate('leqra.getState()');me=next(p for p in state['room']['players'] if p['id']==state['online']['id'])
   if not me.get('ready'):guest.locator('#readyBtn').click()
  host.wait_for_function('!document.querySelector("#startRoomBtn").disabled');host.locator('#startRoomBtn').click()
  for p in [host,guest,viewer]:p.wait_for_function('leqra.getState().phase==="playing"')
  check(all(p.evaluate('leqra.getState().world.cols===16 && leqra.getState().world.rows===14') for p in [host,guest,viewer]),'All live clients render authoritative 16x14 world')
  def grant(expire=False):
   req=urllib.request.Request(args.url+'/_fixture/scope38',data=json.dumps({'code':code,'expire':expire}).encode(),headers={'Content-Type':'application/json'})
   with urllib.request.urlopen(req,timeout=3) as r:assert r.status==204
  grant()
  for p in [host,guest,viewer]:p.wait_for_function('leqra.getState().tanks.every(t=>t.scopeTime>7)')
  check(True,'Scope grant and timer delivered to players and spectator through snapshots')
  host.wait_for_function("document.querySelector('#buffLabel').textContent.includes('SCP') && document.querySelector('#buffLabel2').textContent.includes('SCP')")
  check('SCP' in host.locator('#buffLabel').inner_text() and 'SCP' in host.locator('#buffLabel2').inner_text(),'Online primary and secondary HUDs both show Scope timers')
  def guides(p):return p.evaluate('''()=>{const T=__test,c=document.querySelector('#arena').getContext('2d'),old=c.moveTo;let count=0;c.moveTo=function(...args){count++;return old.apply(this,args)};try{T.drawAimingGuides();return count;}finally{c.moveTo=old;}}''')
  check(guides(host)==2,'Online host draws two owned Scope guides')
  check(guides(guest)==1,'Guest draws only their own guide, not opponents\' scopes')
  check(guides(viewer)==0,'Spectator has no controllable tank and no personal guide')
  check(viewer.evaluate('leqra.getState().online.spectating'),'Grant never turns spectator into a player')
  # Observe actual render code shortening from the server timer without changing core prediction.
  old=host.evaluate('leqra.getState().online.id');host.evaluate('__test.online.socket.close(4000,"scope reconnect test")');host.wait_for_function('!leqra.getState().online.connected');host.wait_for_function('leqra.getState().online.connected',timeout=12000)
  host.wait_for_function('leqra.getState().tanks.some(t=>t.scopeTime>0)')
  check(host.evaluate('leqra.getState().online.id')==old and host.evaluate('leqra.getState().tanks[0].scopeTime')>0,'Reconnection preserves ownership and an active Scope buff')
  host.screenshot(path=str(out/'online-scopes.png'))
  grant(expire=True)
  for p in [host,guest,viewer]:p.wait_for_function('leqra.getState().tanks.every(t=>t.scopeTime===0)')
  host.wait_for_function("!document.querySelector('#buffLabel').textContent.includes('SCP') && !document.querySelector('#buffLabel2').textContent.includes('SCP')")
  check('SCP' not in host.locator('#buffLabel').inner_text() and 'SCP' not in host.locator('#buffLabel2').inner_text(),'Authoritative expiry clears both online Scope HUD indicators')
  check(guides(host)==1,'Expiry restores original primary-only short aiming guide')
  check(not errors,'No uncaught live browser errors')
  (out/'results.json').write_text(json.dumps({'version':'3.8.0','passed':len(checks),'checks':checks,'errors':errors,'limits':'Real loopback Go sockets; injected assets/URL/storage; _test.go grant endpoint only; no physical devices.'},indent=2));print('TOTAL',len(checks))
 finally:b.close()
