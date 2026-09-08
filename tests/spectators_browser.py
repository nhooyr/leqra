"""v3.3 spectator roles, links, swaps, persistence and mobile browser checks.
Uses shipped assets with Location/History/storage adapters because navigation is
blocked in the execution environment. The fixture server is opt-in and loopback-only.
"""
import argparse,json,re,time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:8878');ap.add_argument('--browser',default='/usr/bin/chromium');ap.add_argument('--output',default='test-output/spectators33');args=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def dismissVictory(p):
 if p.locator('#victoryDialog').count() and p.locator('#victoryDialog').is_visible():p.locator('#victoryCloseBtn').click()
def check(v,label):
 if not v:raise AssertionError(label)
 checks.append(label);print('PASS',label,flush=True)
def state(p):return p.evaluate('leqra.getState()')
def fixture(code,action,player=0):
 with urlopen(Request(args.url+'/_fixture/features32',data=json.dumps(dict(code=code,action=action,player=player)).encode(),headers={'Content-Type':'application/json'}),timeout=5) as r:return json.load(r)
def lane(p):
 p.evaluate('''()=>{const T=__test,w=leqra.getState().world;T.walls.splice(0,T.walls.length,{x:-4,y:-4,w:w.width+8,h:8},{x:-4,y:w.height-4,w:w.width+8,h:8},{x:-4,y:-4,w:8,h:w.height+8},{x:w.width-4,y:-4,w:8,h:w.height+8});T.clearBullets();T.tanks.forEach((t,i)=>Object.assign(t,{x:150,y:90+i*110,angle:0,invulnerable:100,cooldown:99,alive:true}));T.clearInput();}''')
with sync_playwright() as pw:
 browser=pw.chromium.launch(headless=True,executable_path=args.browser);contexts=[]
 def load(name='HOST',code=None,size=(1365,950),storage=None,watch=False,session=None):
  mobile=size[0]<760 or size[1]<620;ctx=browser.new_context(viewport={'width':size[0],'height':size[1]},is_mobile=mobile,has_touch=mobile,device_scale_factor=2 if mobile else 1);contexts.append(ctx)
  p=ctx.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.on('dialog',lambda d:d.accept())
  html=re.sub(r'<link[^>]*>','',web.joinpath('index.html').read_text()).replace('<script src="game.js" defer></script>','').replace('<script src="netcode.js" defer></script>','').replace('</head>','<style>'+web.joinpath('style.css').read_text()+'</style></head>');p.set_content(html)
  url='http://game.test/tanks/?test=1'+('&'+urlencode({'room':code}) if code else '')+('&spectate=1' if watch else '')
  p.evaluate(r'''([url,ws,name,storage,session])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];window.__historyCalls=[];window.__copied='';const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener('message',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=(data)=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store=Object.assign({'leqra.name':name,'leqra.muted':'1'},storage||{});Object.defineProperty(window,'localStorage',{value:store(__store)});window.__session=Object.assign({},session||{});Object.defineProperty(window,'sessionStorage',{value:store(__session)});history.replaceState=(s,t,u)=>{__historyCalls.push(String(u));__location.href=String(u)};Object.defineProperty(navigator,'clipboard',{value:{writeText:async v=>{__copied=v}}});}''',[url,args.url.replace('http:','ws:')+'/ws',name,storage,session])
  js=web.joinpath('game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location);'+js[i+5:]
  p.add_script_tag(content=web.joinpath('netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra');return p
 def close(p,kind):p.locator('[data-close-dialog="'+kind+'Dialog"]').click()
 def preset(p,index):dismissVictory(p);p.locator('#roomPresetsBtn').click();p.locator('#presetSelect').select_option('builtin:'+str(index));p.locator('#loadPresetBtn').click();p.wait_for_function('!document.querySelector("#presetsDialog").open')
 def start(p):dismissVictory(p);p.locator('#startRoomBtn').click();p.wait_for_function('leqra.getState().phase==="playing"',timeout=9000)
 def room(p):dismissVictory(p);p.locator('#roomBtn').click();p.locator('#returnRoomBtn').click();p.wait_for_function('["menu","onlineLobby"].includes(leqra.getState().phase)')
 def press(p,key,ms=40):p.keyboard.down(key);p.wait_for_timeout(ms);p.keyboard.up(key)
 def rules(p,**values):
  dismissVictory(p)
  selected_mode=values.pop('mode',None)
  if selected_mode is not None:
   p.locator('[data-room-mode="'+selected_mode+'"]').click();p.wait_for_function('(mode)=>leqra.getState().rules.mode===mode',arg=selected_mode)
  p.locator('#roomRulesBtn').click()
  for key,val in values.items():
   loc=p.locator('#rule-'+key)
   if key in ['teamMode','mapSize','pickupRate']:
    if not loc.is_disabled():loc.select_option(str(val));p.wait_for_timeout(20)
    else:assert loc.input_value()==str(val)
   else:loc.fill(str(val))
  p.locator('#applyRulesBtn').click();p.wait_for_function('!document.querySelector("#rulesDialog").open')
 def screenshot(p,name):p.screenshot(path=str(out/(name+'.png')))
 def conn(p):p.wait_for_function('leqra.getState().online?.connected',timeout=9000)
 def wire(p,m):p.evaluate('m=>__sockets.at(-1).send(JSON.stringify(m))',m)
 def watchJoin(p,name):
  p.locator('#pilotName').fill(name);p.locator('#joinRoomBtn').click();conn(p);p.wait_for_function('leqra.getState().online.spectating')
 def role(p,watching):
  p.evaluate('v=>{const s=leqra.getState();const r=s.room;const id=s.online?.id??r.host;__test.setPlayerSpectating([...r.players,...r.spectators].find(x=>x.id===id),v)}',watching)
  p.wait_for_function('v=>!!leqra.getState().online?.spectating===v',arg=watching)
 def spectator(p,name):return next(x for x in state(p)['room']['spectators'] if x['name']==name)
 def member(p,name):return next(x for x in state(p)['room']['players']+state(p)['room']['spectators'] if x['name']==name)
 def membercount(p,n):p.wait_for_function('n=>leqra.getState().room.spectators.length===n',arg=n)
 def openGallery(p):
  if not p.locator('#spectatorsDialog').evaluate('(e)=>e.open'):p.locator('#spectatorsBtn').click()
 def closeGallery(p):
  if p.locator('#spectatorsDialog').evaluate('(e)=>e.open'):p.locator('#closeSpectatorsBtn').click()
 def swap(p,viewer,active):
  openGallery(p);v=spectator(p,viewer);a=member(p,active)
  p.locator('#spectatorList [data-swap-viewer="'+str(v['id'])+'"]').click()
  p.locator('#swapTarget').select_option(str(a['id'])+':'+str(a['member']));p.locator('#confirmSwapBtn').click()
  p.wait_for_function('!document.querySelector("#swapDialog").open');closeGallery(p)
 def screenshot(p,n):p.screenshot(path=str(out/(n+'.png')))
 # Local spectators persist across games, including independent P2 control.
 local=load('LOCAL HOST');local.locator('#addLocalBtn').click();local.locator('#toggleSpectateBtn').click()
 check(len(state(local)['room']['players'])==3 and len(state(local)['room']['spectators'])==1,'Local host can spectate without occupying a tank slot')
 check(state(local)['room']['host']>=4 and local.locator('#startRoomBtn').is_enabled(),'Spectating local host keeps Start and team controls')
 start(local);lane(local)
 check(not any(t['id']==state(local)['room']['host'] for t in state(local)['tanks']),'Local watching host has no tank in simulation')
 check(local.locator('#pilotLoadout1').is_hidden() if local.locator('#pilotLoadout1').count() else local.locator('#spectatorBanner').is_visible(),'Watching replaces primary ammo with spectator banner')
 check(local.locator('#pilotLoadout2').is_visible(),'Active local P2 keeps their ammo while P1 watches')
 local.evaluate('''()=>{const p=__test.tanks.find(t=>t.human);p.cooldown=0;__test.grantPower(p,'grenade');p.charges=1;}''');press(local,'Space')
 check(local.evaluate('__test.bullets.some(b=>b.kind==="grenade"&&b.owner===3)'),'Local P2 fires independently while primary spectates')
 room(local);start(local)
 check(len(state(local)['room']['spectators'])==1 and not any(t['id']>=4 for t in state(local)['tanks']),'Starting another local match retains spectator role')
 room(local);local.locator('#localRoomName').fill('Local spectators '+str(time.time_ns()));local.locator('#copyInviteBtn').click();conn(local)
 check(state(local)['online']['spectating'] and len(state(local)['room']['spectators'])==1 and len(state(local)['room']['players'])==3,'Sharing imports watching host with active local P2 and bots')
 check(next(p for p in state(local)['room']['players'] if p['kind']=='local')['owner']==state(local)['online']['id'],'Shared P2 remains owned by watching controller')
 lp=next(p for p in state(local)['room']['players'] if p['kind']=='local');swap(local,'LOCAL HOST',lp['name'])
 local.wait_for_function('!leqra.getState().online.spectating')
 swap(local,lp['name'],'LOCAL HOST');local.wait_for_function('leqra.getState().online.spectating')
 lp=next(p for p in state(local)['room']['players'] if p['kind']=='local');check(lp['owner']==state(local)['online']['id'],'Swapping own primary with own local P2 preserves keyboard ownership')
 start(local);press(local,'Space');local.wait_for_function('leqra.getState().online.serverTick>3')
 check(local.evaluate('id=>__sent.some(m=>m.type==="input"&&m.player===id&&m.fire)',lp['id']) and not local.evaluate('__messages.some(m=>m.type==="error"&&m.code==="not_owned")'),'Real server accepts P2 Fire after two self-local swaps')
 room(local);local.locator('#leaveRoomBtn').click();local.close()
 # A full arena accepts explicitly named viewers and normal-link overflow.
 host=load('HOST');host.locator('#addLocalBtn').click();code='Watch & play 💥 '+str(time.time_ns());host.locator('#localRoomName').fill(code);host.locator('#copyInviteBtn').click();conn(host)
 host.locator('#copySpectateBtn').click();copied=host.evaluate('__copied')
 check('spectate=1' in copied and host.evaluate('new URL(__copied).searchParams.get("room")')==code,'Spectator share link encodes full Unicode/punctuation room name')
 check('token' not in copied and host.evaluate('__test.online.token') not in copied,'Public watch link contains no private reconnect credential')
 host.evaluate('__location.hostname="localhost"');host.locator('#copySpectateBtn').click()
 check(host.evaluate('new URL(__copied).searchParams.get("spectate")==="1"') and 'localhost only' in host.locator('#roomStatus').inner_text().lower(),'Localhost spectator copy remains a watch link with cross-device warning')
 host.evaluate('__location.hostname="game.test"')
 watcher=load('SAVED NAME',code,watch=True)
 check(watcher.locator('#joinDialog').evaluate('(e)=>e.open') and watcher.locator('#joinTitle').inner_text()=='Watch this room.','Watch link opens callsign-first dialog')
 check(watcher.evaluate('__sockets.length===0') and not state(watcher)['online'],'Watch link does not connect or occupy membership before confirmation')
 watcher.locator('#pilotName').fill('');watcher.locator('#joinRoomBtn').click()
 check('callsign' in watcher.locator('#netStatus').inner_text().lower() and watcher.evaluate('__sockets.length===0'),'Empty callsign cannot enter spectator link')
 watchJoin(watcher,'VIEWER');membercount(host,1)
 check(state(watcher)['online']['id']>=4 and len(state(watcher)['room']['players'])==4,'Explicit viewer is outside all four tank slots')
 check(watcher.locator('#readyBtn').is_hidden() and watcher.locator('#toggleSpectateBtn').is_disabled(),'Spectator has no ready vote and cannot join full arena')
 fallback=load('OVERFLOW',code);conn(fallback);fallback.wait_for_function('leqra.getState().online.spectating');membercount(host,2)
 check(fallback.evaluate('__messages.some(m=>m.type==="welcome"&&m.full&&m.spectating)'),'Normal invite to full room automatically enters as spectator')
 check(not fallback.evaluate('__messages.some(m=>m.type==="error"&&m.code==="room_full")'),'Full arena does not decline visitor with room-full error')
 for page in [host,watcher,fallback]:
  membercount(page,2);openGallery(page)
  check(page.locator('#spectatorList').inner_text().count('VIEWER')==1 and 'OVERFLOW' in page.locator('#spectatorList').inner_text(),'Every room member can inspect spectator names')
  if page!=host:check(page.locator('#spectatorList [data-swap-viewer]').count()==0 and page.locator('#spectatorList [data-kick-target]').count()==0,'Spectator guest has no host moderation controls')
  closeGallery(page)
 check(host.locator('#startRoomBtn').is_enabled(),'Host can start full lineup without spectator readiness')
 start(host);watcher.wait_for_function('leqra.getState().phase==="playing"');fallback.wait_for_function('leqra.getState().phase==="playing"')
 check(len(state(watcher)['tanks'])==4 and not any(t['id']==state(watcher)['online']['id'] for t in state(watcher)['tanks']),'Viewer sees live four-tank world but owns no tank')
 check(watcher.locator('#overlay').is_hidden() and watcher.locator('#spectatorBanner').is_visible(),'Watcher automatically sees arena rather than blocking room overlay')
 t=state(watcher)['online']['serverTick'];watcher.wait_for_timeout(160);check(state(watcher)['online']['serverTick']>t,'Viewer receives continuing authoritative game snapshots')
 sent=watcher.evaluate('__sent.length');press(watcher,'KeyF');press(watcher,'Space');press(watcher,'KeyW')
 check(not watcher.evaluate('n=>__sent.slice(n).some(m=>m.type==="input")',sent),'Spectator keyboard cannot send gameplay controls')
 oldid=state(watcher)['online']['id'];token=watcher.evaluate('__test.online.token');watcher.evaluate('__sockets.at(-1).close(4000,"test reconnect")');watcher.wait_for_function('__messages.filter(m=>m.type==="welcome").length>=2',timeout=9000)
 check(state(watcher)['online']['spectating'] and state(watcher)['online']['id']==oldid and watcher.evaluate('__test.online.token')==token,'Automatic reconnect preserves watcher role, identity and session')
 # Kick UI and no retry from removed viewer.
 openGallery(host);v=spectator(host,'OVERFLOW');host.locator('#spectatorList [data-kick-target="'+str(v['id'])+'"]').click();host.locator('#confirmKickBtn').click();host.wait_for_function('!document.querySelector("#kickDialog").open');closeGallery(host)
 fallback.wait_for_function('!leqra.getState().online?.connected');membercount(host,1)
 check(fallback.evaluate('!__session["leqra.session"]') and fallback.evaluate('__messages.some(m=>m.type==="kicked")'),'Host kicking spectator clears reconnect credential and explains removal')
 nw=fallback.evaluate('__messages.filter(m=>m.type==="welcome").length');fallback.wait_for_timeout(900);check(fallback.evaluate('__messages.filter(m=>m.type==="welcome").length')==nw,'Kicked spectator does not automatically rejoin')
 fallback.close()
 # Swap active local P2 with viewer during round. Incoming player waits, no extra life.
 p2=next(p for p in state(host)['room']['players'] if p['kind']=='local');seq_before=host.evaluate('__test.online.seq');swap(host,'VIEWER',p2['name']);watcher.wait_for_function('!leqra.getState().online.spectating')
 check(state(watcher)['online']['id']==p2['id'] and member(host,p2['name'])['spectating'],'Host swap makes viewer active and former P2 a spectator')
 check(state(host)['room']['host']==0 and member(host,'VIEWER')['team']==p2['team'],'Swap keeps host authority and transfers selected seat team')
 check(watcher.evaluate('__test.online.token')==token,'Swap does not replace viewer reconnect identity')
 check(not next(t for t in state(watcher)['tanks'] if t['id']==p2['id'])['alive'],'Mid-round incoming elimination player does not receive an extra tank life')
 check(host.locator('#pilotLoadout2').is_hidden(),'Watching local P2 no longer shows a playable ammo panel')
 check(host.evaluate('__test.online.seq')>=seq_before,'Role notifications preserve input sequence chronology for unaffected pilots')
 # Switching oneself off and on frees a real seat but not the same-round life.
 role(watcher,True);check(len(state(watcher)['room']['players'])==3,'Active guest can voluntarily move to spectators')
 role(watcher,False);check(len(state(watcher)['room']['players'])==4,'Spectator can return to an available tank seat')
 watcher.wait_for_function('leqra.getState().tanks.some(t=>t.id===leqra.getState().online.id)');check(not next(t for t in state(watcher)['tanks'] if t['id']==state(watcher)['online']['id'])['alive'],'Role toggling cannot bypass elimination death')
 role(watcher,True);room(host);watcher.wait_for_function('leqra.getState().phase==="onlineLobby"');check(state(watcher)['online']['spectating'],'Host End match keeps spectators watching')
 start(host);watcher.wait_for_function('leqra.getState().phase==="playing"');check(state(watcher)['online']['spectating'] and len(state(watcher)['room']['spectators'])==2,'New online match does not auto-promote previous spectators')
 # Host may swap themselves; their moderation authority follows membership.
 swap(host,'VIEWER','HOST');watcher.wait_for_function('!leqra.getState().online.spectating');host.wait_for_function('leqra.getState().online.spectating')
 check(state(host)['room']['host']==state(host)['online']['id'] and host.locator('#spectatorBanner').is_visible(),'Host retains authority after moving themselves to spectators')
 check(state(watcher)['room']['host']!=state(watcher)['online']['id'],'Taking host former tank does not transfer host privileges')
 room(host);watcher.wait_for_function('leqra.getState().phase==="onlineLobby"');dismissVictory(watcher);watcher.locator('#readyBtn').click();host.wait_for_function('leqra.getState().room.canStart');start(host)
 check(state(host)['online']['spectating'],'Spectating host can start subsequent match')
 # Restore-role on simulated fresh page still respects watch link confirmation.
 oldid=state(host)['online']['id'];session=host.evaluate('__session');saved=host.evaluate('__store');host.context.close();watcher.wait_for_timeout(100)
 restored=load('HOST',code,watch=True,session=session,storage=saved)
 check(restored.evaluate('__sockets.length===0'),'Reloaded watch link still requires callsign confirmation before resume')
 watchJoin(restored,'HOST');check(state(restored)['online']['id']==oldid and restored.evaluate('__messages.some(m=>m.type==="welcome"&&m.resumed)'),'Confirmed watch refresh resumes existing spectator identity')
 # Reconnecting host handed authority to connected active guest; no takeover.
 check(state(restored)['room']['host']==state(watcher)['online']['id'],'Spectator reconnect does not steal host after handoff')
 dismissVictory(watcher);watcher.locator('#roomBtn').click();watcher.locator('#onlineLeaveBtn').click();watcher.close();dismissVictory(restored);restored.locator('#roomBtn').click();restored.locator('#onlineLeaveBtn').click();restored.close()
 # Empty watch link can create a spectator-host room; add bots, view without tanks.
 empty=load('WATCH HOST','New watch '+str(time.time_ns()),watch=True);watchJoin(empty,'WATCH HOST')
 check(len(state(empty)['room']['players'])==0 and state(empty)['room']['host']==state(empty)['online']['id'],'Missing watch room creates watching host, no hidden player')
 empty.locator('#addBotBtn').click();empty.wait_for_function('leqra.getState().room.players.length===1');empty.locator('#addBotBtn').click();empty.wait_for_function('leqra.getState().room.players.length===2')
 a=state(empty)['room']['players'][0];empty.locator('#roomRoster [data-team="'+str(a['id'])+'"]').select_option('1');empty.wait_for_function('leqra.getState().room.canStart');start(empty)
 check(state(empty)['online']['spectating'] and all(not p['kind']=='human' for p in state(empty)['room']['players']),'Spectating host can watch server bots play opposing teams')
 dismissVictory(empty);empty.locator('#roomBtn').click();empty.locator('#onlineLeaveBtn').click();empty.close()
 # Responsive watch prompt, spectators list, swaps and unobstructed spectator arena.
 for size in [(320,568),(390,844),(844,390),(1365,950)]:
  h=load('SCREEN HOST',size=size);h.locator('#addLocalBtn').click();code='Screen '+str(time.time_ns());h.locator('#localRoomName').fill(code);h.locator('#copyInviteBtn').click();conn(h)
  p=load('VIEW',code,size=size,watch=True);screenshot(p,f'watch-prompt-{size[0]}x{size[1]}');watchJoin(p,'SCREEN VIEWER');membercount(h,1)
  for control in ['toggleSpectateBtn','copySpectateBtn','startRoomBtn']:
   h.locator('#'+control).scroll_into_view_if_needed();hit=h.locator('#'+control).evaluate('(e)=>{const r=e.getBoundingClientRect(),t=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return e===t||e.contains(t)}');check(hit,f'{size}: {control} remains reachable')
  h.locator('#roomScreen').evaluate('(e)=>e.scrollTop=0');screenshot(h,f'room-{size[0]}x{size[1]}');openGallery(h);screenshot(h,f'gallery-{size[0]}x{size[1]}')
  v=spectator(h,'SCREEN VIEWER');h.locator('#spectatorList [data-swap-viewer="'+str(v['id'])+'"]').click();h.locator('#confirmSwapBtn').scroll_into_view_if_needed();check(h.locator('#confirmSwapBtn').is_visible(),f'{size}: host swap confirmation is reachable');screenshot(h,f'swap-{size[0]}x{size[1]}');h.locator('#cancelSwapBtn').click();closeGallery(h)
  start(h);p.wait_for_function('leqra.getState().phase==="playing"');screenshot(p,f'watching-{size[0]}x{size[1]}')
  check(p.locator('#spectatorBanner').is_visible() and p.locator('#touchControls').is_hidden(),f'{size}: spectator sees watch banner without inactive touch controls')
  check(p.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'{size}: spectator UI has no horizontal overflow')
  openGallery(p);check('SCREEN VIEWER' in p.locator('#spectatorList').inner_text(),f'{size}: watcher can view spectator names during match');closeGallery(p)
  p.close();h.close()
 check(not errors,'No JavaScript page errors across spectator scenarios')
 browser.close();report={'version':'3.3.0','checks_passed':len(checks),'checks':checks,'page_errors':errors,'limits':'Chromium emulation; exact assets, synthetic Location/History/storage, real loopback Go fixture. No physical devices/public internet/actual navigation.'};(out/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps({'passed':len(checks),'errors':errors}))
