"""v3.7: local gameplay + authoritative online results, exact shipped assets.
Chromium uses synthetic Location/History/storage adapters and a loopback fixture.
"""
import argparse,json,re,secrets
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request,urlopen
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('--url',default='http://127.0.0.1:8878');ap.add_argument('--output',default='test-output/stats37');ap.add_argument('--browser',default='/usr/bin/chromium');args=ap.parse_args()
root=Path(__file__).resolve().parents[1];web=root/'web';out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
checks=[];errors=[]
def check(ok,label):
 if not ok:raise AssertionError(label)
 checks.append(label);print('PASS',label,flush=True)
def fixture(code,action,player=0):
 with urlopen(Request(args.url+'/_fixture/features32',data=json.dumps(dict(code=code,action=action,player=player)).encode(),headers={'Content-Type':'application/json'}),timeout=5) as r:return json.load(r)
def state(p):return p.evaluate('leqra.getState()')
with sync_playwright() as pw:
 browser=pw.chromium.launch(headless=True,executable_path=args.browser);contexts=[];pages=[]
 def load(name='HOST',size=(1365,950),code=None,watch=False):
  mobile=size[0]<760 or size[1]<620;context=browser.new_context(viewport={'width':size[0],'height':size[1]},is_mobile=mobile,has_touch=mobile,device_scale_factor=2 if mobile else 1);contexts.append(context);p=context.new_page();pages.append(p);p.set_default_timeout(8000);p.on('pageerror',lambda e:errors.append(str(e)));p.on('dialog',lambda d:d.accept())
  html=re.sub(r'<link[^>]*>','',web.joinpath('index.html').read_text());html=re.sub(r'<script src="[^"]+" defer></script>','',html);html=html.replace('</head>','<style>'+web.joinpath('style.css').read_text()+'</style></head>');p.set_content(html)
  url='http://game.test/tanks/?test=1'+('&'+urlencode({'room':code,**({'spectate':1} if watch else {})}) if code else '')
  p.evaluate(r'''([url,ws,name])=>{window.__location=new URL(url);window.__messages=[];window.__sockets=[];window.__sent=[];const WS=WebSocket;window.WebSocket=class extends WS{constructor(){super(ws);__sockets.push(this);this.addEventListener('message',e=>__messages.push(JSON.parse(e.data)))}send(v){__sent.push(JSON.parse(v));return super.send(v)}};const store=data=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});window.__store={'leqra.name':name,'leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:store(__store)});Object.defineProperty(window,'sessionStorage',{value:store({})});history.replaceState=(s,t,u)=>{__location.href=String(u)};Object.defineProperty(navigator,'clipboard',{value:{writeText:async v=>{}}});}''',[url,args.url.replace('http:','ws:')+'/ws',name])
  js=web.joinpath('game.js').read_text().replace('(() => {','((location) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location);'+js[i+5:]
  p.add_script_tag(content=web.joinpath('netcode.js').read_text());p.add_script_tag(content=js);p.wait_for_function('window.leqra');return p
 def setup(p,mode='elimination',count=8,ff=False):
  p.evaluate('''({mode,count,ff})=>{__test.closeVictory();const T=__test,rules={...T.defaultRoomRules(),mode,teamMode:mode==='elimination'?'ffa':'teams',scoreTarget:mode==='koth'?60:1,timeLimit:600,pickupRate:'off',friendlyFire:ff,teamNames:['Aurora 🌟','Red Foxes','Tidal & Co','Violet Guard']};const roster=Array.from({length:count},(_,i)=>({name:i===0?'PILOT ONE':i===1?'PLAYER TWO':['RUST','VAPOR','EMBER','PIXEL','NOVA','COMET'][i-2],kind:i===0?'human':i===1?'local':'bot',team:rules.teamMode==='ffa'?0:i<2?1:2,...(i>1?{difficulty:'normal'}:{})}));T.applyLocalPreset({rules,roster});}''',dict(mode=mode,count=count,ff=ff))
 def start(p):
  p.locator('#startRoomBtn').click()
  p.evaluate('''()=>{const T=__test;T.setPhase('playing');T.setWorld({width:1008,height:840,cols:12,rows:10,walls:[]});T.clearBullets();T.tanks.forEach((t,i)=>{t.human=true;t.invulnerable=0;t.x=100+i*90;t.y=300;t.cooldown=999;});}''')
 def local_finish(p,mode):
  return p.evaluate('''mode=>{const T=__test,t=T.tanks;T.setPhase('playing');T.clearBullets();const kill=(victim,owner)=>{t[victim].alive=true;t[victim].shield=0;t[victim].invulnerable=0;T.hurt(t[victim],{owner,kind:'grenade'});};kill(2,0);kill(3,0);kill(4,1);kill(5,5);kill(6,0);t[7].shield=2;T.hurt(t[7],{owner:0});
   if(mode==='ctf'){const o=T.localObjectives,own=o.flags[0],enemy=o.flags[1];t[1].x=250;t[1].y=200;Object.assign(own,{home:false,carrier:-1,x:250,y:200,returnIn:12});T.stepLocalObjectives(1/60);t[0].x=own.homeX;t[0].y=own.homeY;Object.assign(enemy,{home:false,carrier:0,x:t[0].x,y:t[0].y,returnIn:0});T.stepLocalObjectives(1/60);}
   else if(mode==='koth'){const o=T.localObjectives;t[0].x=o.hillX-10;t[0].y=o.hillY;t[1].x=o.hillX+10;t[1].y=o.hillY;for(let n=0;n<135;n++)T.stepLocalObjectives(1/60);T.finishMatch(0);}
   else T.finishMatch(0);
   return leqra.getState().matchStats;
  }''',mode)
 def bounds(p):return p.evaluate('''()=>{const d=document.querySelector('#victoryDialog'),r=d.getBoundingClientRect(),footer=document.querySelector('#victoryCloseBtn').getBoundingClientRect();return {ok:r.left>=0&&r.right<=innerWidth+1&&r.top>=0&&r.bottom<=innerHeight+1,overflow:d.scrollWidth>d.clientWidth+1,scroll:d.scrollTop,focus:document.activeElement.id,button:footer.bottom<=innerHeight+1&&footer.top>=0,bodyOverflow:document.documentElement.scrollWidth>innerWidth};}''')
 try:
  for size in [(1365,950),(390,844),(320,568),(844,390)]:
   for mode in ['elimination','ctf','koth']:
    p=load(size=size);setup(p,mode);start(p);report=local_finish(p,mode);suffix=mode+' '+str(size)
    p.wait_for_function('document.querySelector("#victoryDialog").open')
    check(len(report['players'])==8,'Eight individual results '+suffix)
    a=report['players'];check(a[0]['eliminations']==3 and a[1]['eliminations']==1,'Eliminations attributed to both local players '+suffix)
    check(a[5]['selfDestructs']==1 and a[5]['deaths']==1 and a[5]['eliminations']==0,'Self-destruct separate from eliminations '+suffix)
    check(a[7]['deaths']==0,'Shield absorption not a death '+suffix)
    check(p.locator('#victoryStats tbody tr').count()==8,'Eight rendered result rows '+suffix)
    if mode=='ctf':check(a[0]['captures']==1 and a[1]['captures']==0 and a[1]['flagReturns']==1,'Winning capture and manual return credited personally '+suffix)
    if mode=='koth':check(a[0]['hillSeconds']==2.25 and a[1]['hillSeconds']==2.25,'Each ally gets uncontested hill time '+suffix)
    check(p.locator('[data-metric="captures"]').count()==(8 if mode=='ctf' else 0) and p.locator('[data-metric="hillSeconds"]').count()==(8 if mode=='koth' else 0),'Mode-specific columns '+suffix)
    b=bounds(p);check(b['ok'] and not b['overflow'] and not b['bodyOverflow'],'Popup and page stay within viewport '+suffix)
    check(b['scroll']==0 and b['focus']=='victoryTitle','Congratulations shown first, not scrolled to footer '+suffix)
    check(b['button'],'Back to room action visible '+suffix)
    p.screenshot(path=str(out/f'{mode}-{size[0]}x{size[1]}.png'))
    if size[0]<641:
     check(p.locator('#victoryStats tbody tr').first.evaluate('(e)=>getComputedStyle(e).display')=='grid','Mobile result cards '+suffix)
     p.locator('#victoryDialog').evaluate('(e)=>e.scrollTop=e.scrollHeight');p.screenshot(path=str(out/f'{mode}-lower-{size[0]}x{size[1]}.png'));check(p.locator('#victoryCloseBtn').is_visible(),'Dismissal remains reachable while scrolling '+suffix)
    saved=json.dumps(report,sort_keys=True);p.evaluate('__test.localRoom.players[0].name="LATER NAME";__test.hurt(__test.tanks[7],{owner:0});')
    check(json.dumps(state(p)['matchStats'],sort_keys=True)==saved,'Report frozen after end '+suffix)
    p.locator('#victoryCloseBtn').click();check(not p.locator('#victoryDialog').is_visible(),'Dismisses without starting another match '+suffix)
    p.locator('#startRoomBtn').click();check(state(p)['matchStats'] is None and p.evaluate('__test.matchStats.rows.every(p=>p.eliminations===0&&p.deaths===0&&p.hillSeconds===0)'),'New match clears all totals '+suffix)
    p.context.close();contexts.remove(p.context)
  # Accumulation through normal elimination rounds, self/FF distinction, active
  # spectators' personal history and duplicate names sharing different seats.
  p=load();setup(p,'elimination',4);start(p)
  v=p.evaluate('''()=>{const T=__test;T.setPhase('playing');T.hurt(T.tanks[2],{owner:0});const row=T.tanks[0].statsRow;T.startRound();T.setPhase('playing');for(const t of T.tanks){t.invulnerable=0;t.human=true;}T.hurt(T.tanks[2],{owner:0});const kept=T.tanks[0].statsRow===row;const member=T.localRoom.players.find(p=>p.id===0);T.setPlayerSpectating(member,true);const deaths=row.deaths;T.setPlayerSpectating(member,false);const restored=T.tanks.find(t=>t.id===member.id).statsRow===row;T.setPhase('playing');T.finishMatch(1);return{kept,restored,deaths,report:T.matchReport};}''')
  check(v['kept'] and v['restored'] and v['deaths']==0 and v['report']['players'][0]['eliminations']==2,'Local totals survive rounds and spectator toggles, not counted as deaths')
  setup(p,'ctf',4,True);start(p)
  v=p.evaluate('''()=>{const T=__test;T.hurt(T.tanks[1],{owner:0});T.finishMatch(0);return T.matchReport;}''')
  check(v['players'][0]['teamKills']==1 and v['players'][0]['eliminations']==0 and p.locator('[data-metric=teamKills]').count()==4,'Friendly-fire kills have their own column')
  # Plain text safety, long custom names, and historical-participant labels.
  p.evaluate('''()=>{const r=JSON.parse(JSON.stringify(__test.matchReport));r.players[0].name='<img src=x onerror=alert(1)>';r.players[0].mixedTeams=true;r.players[1].active=false;__test.renderMatchStats(r);}''')
  check(p.locator('#victoryStats img').count()==0 and '<img' in p.locator('.stat-pilot-name').first.inner_text(),'Statistics render names as plain text')
  check('CHANGED TEAMS' in p.locator('#victoryStats').inner_text() and 'PLAYED EARLIER' in p.locator('#victoryStats').inner_text(),'Changed-team and earlier-participant notes visible')
  # Real Go-backed report delivered to primary, secondary controller, guest and watcher.
  host=load();setup(host,'ctf',4);code='stats-'+secrets.token_hex(4);host.locator('#localRoomName').fill(code);host.evaluate('__test.shareLocalRoom()');host.wait_for_function('leqra.getState().online?.connected')
  guest=load('GUEST',code=code);guest.wait_for_function('leqra.getState().online?.connected')
  viewer=load('VIEWER',(320,568),code,True)
  check(not state(viewer).get('online'),'Watch link still waits for callsign confirmation')
  viewer.locator('#pilotName').fill('VIEWER');viewer.locator('#joinRoomBtn').click();viewer.wait_for_function('leqra.getState().online?.connected')
  guest.locator('#readyBtn').click();host.wait_for_function('!document.querySelector("#startRoomBtn").disabled');host.locator('#startRoomBtn').click();host.wait_for_function('leqra.getState().phase==="playing"')
  check(host.evaluate('__messages.filter(m=>m.type==="state"&&m.phase==="playing").every(s=>!("matchStats" in s))'),'Live network snapshots exclude the results ledger')
  fixture(code,'enemyKill37',2);fixture(code,'flagReturn37',1);fixture(code,'captureWin37',0)
  for page in [host,guest,viewer]:page.wait_for_function('document.querySelector("#victoryDialog").open')
  expected=state(host)['matchStats'];check(expected['players'][0]['eliminations']==1 and expected['players'][0]['captures']==1 and expected['players'][1]['flagReturns']==1,'Go report carries actual enemy death, winning capture and local-P2 return')
  check(all(state(pg)['matchStats']==expected for pg in [guest,viewer]),'Players and spectators receive identical authoritative results')
  check(len(expected['players'])==5 and all(x['name']!='VIEWER' for x in expected['players']),'Watching alone does not invent a combat row')
  viewer.screenshot(path=str(out/'online-spectator-320.png'));host.screenshot(path=str(out/'online-report-desktop.png'))
  before=host.evaluate('__messages.filter(m=>m.type==="state"&&m.matchStats).at(-1).matchStats');host.locator('#victoryCloseBtn').click();host.wait_for_timeout(200)
  check(not host.locator('#victoryDialog').is_visible() and state(host)['matchStats']==before,'Repeated end snapshots neither reopen popup nor change results')
  late=load('LATE VIEWER',(390,844),code,True);late.locator('#pilotName').fill('LATE VIEWER');late.locator('#joinRoomBtn').click();late.wait_for_function('document.querySelector("#victoryDialog").open')
  check(state(late)['matchStats']==expected,'Late spectator receives the frozen completed-match report')
  # A reconnect sees the same server report; it never derives counts from missed events.
  sockets=guest.evaluate('__sockets.length');guest.evaluate('__sockets.at(-1).close()');guest.wait_for_function('(n)=>__sockets.length>n&&leqra.getState().online?.connected',arg=sockets,timeout=10000);guest.wait_for_function('__messages.filter(m=>m.type==="welcome").at(-1)?.resumed===true');guest.wait_for_timeout(100)
  check(state(guest)['matchStats']==expected,'Reconnect retains the completed report')
  check(not errors,'No JavaScript page errors')
  report=dict(version='3.7.1',passed=len(checks),checks=checks,errors=errors,limits='Chromium emulation, exact assets injected with Location/History/storage adapters, local Go fixture; not physical phones or public hosting.')
  (out/'results.json').write_text(json.dumps(report,indent=2));print('TOTAL',len(checks),flush=True)
 except Exception:
  for i,page in enumerate(pages):
   if not page.is_closed():
    try:page.screenshot(path=str(out/f'failure-{i}.png'))
    except Exception:pass
  (out/'failure.json').write_text(json.dumps({'checks':checks,'errors':errors},indent=2));raise
 finally:
  for c in contexts:
   try:c.close()
   except Exception:pass
  browser.close()
