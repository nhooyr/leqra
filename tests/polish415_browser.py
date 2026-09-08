"""v4.15 focused browser checks: stable lobby maze, ultra-wide tier, fixed-height per-pilot feedback, spectator wording."""
import argparse,json,re
from pathlib import Path
from playwright.sync_api import sync_playwright

ap=argparse.ArgumentParser();ap.add_argument('--output',default='tests/results/v4.15-browser');a=ap.parse_args()
r=Path(__file__).resolve().parents[1];web=r/'web';out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
html=re.sub(r'<link[^>]*>|<script[^>]*src=[^>]*></script>','',(web/'index.html').read_text()).replace('</head>','<style>'+(web/'theme.css').read_text()+(web/'style.css').read_text()+'</style></head>')
js=(web/'game.js').read_text().replace('(() => {','((location,history) => {',1);i=js.rfind('})();');js=js[:i]+'})(window.__location,window.__history);'+js[i+5:]
checks=[];errors=[]
def check(ok,label): assert ok,label;checks.append(label);print('PASS',label,flush=True)

with sync_playwright() as pw:
 b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium');c=b.new_context(viewport={'width':1365,'height':950},color_scheme='dark');p=c.new_page();p.on('pageerror',lambda e:errors.append(str(e)));p.set_content(html)
 p.evaluate("""()=>{window.__location=new URL('http://127.0.0.1/?test=1');window.__history={state:null,replaceState(){}};const d={'leqra.name':'ALPHA','leqra.muted':'1'};Object.defineProperty(window,'localStorage',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,'sessionStorage',{value:{getItem:()=>null,setItem(){},removeItem(){}}});window.requestAnimationFrame=()=>0;}""")
 for f in ['theme.js','netcode.js']: p.add_script_tag(content=(web/f).read_text())
 p.add_script_tag(content=js);p.wait_for_function("window.__test&&leqra.version==='4.29.0'")
 p.evaluate('__test.createLocalRoom()');p.wait_for_timeout(20)

 # New maze tier and exact pickup-density/lifetime rule.
 tiers=p.evaluate("""()=>({giant:{dim:__test.mapDimensions('giant'),cap:__test.pickupCap(16,14),start:__test.startingPickups(16,14),life:__test.pickupLifetime(16,14)},ultra:{dim:__test.mapDimensions('ultrawide'),cap:__test.pickupCap(24,14),start:__test.startingPickups(24,14),life:__test.pickupLifetime(24,14)}})""")
 check(tiers['giant']=={'dim':[16,14],'cap':23,'start':6,'life':61},'Giant keeps 23 max pickups and the requested 61-second expiry')
 check(tiers['ultra']=={'dim':[24,14],'cap':34,'start':7,'life':90},'Ultra Wide is 24×14 with 7 starting, 34 max and 90-second pickup expiry')

 # Roster edits must preserve the exact generated wall layout.
 stable=p.evaluate("""()=>{const before=JSON.stringify(__test.walls);const bot=__test.localRoom.players.find(x=>x.kind==='bot');__test.changeSeat(bot,{difficulty:'hard',name:'RUSTY'});const afterEdit=JSON.stringify(__test.walls);__test.addRoomSeat('local');const afterAdd=JSON.stringify(__test.walls);return{sameEdit:before===afterEdit,sameAdd:before===afterAdd,players:__test.localRoom.players.length};}""")
 check(stable['sameEdit'] and stable['sameAdd'] and stable['players']==5,'renaming/tuning roster and adding local P2 do not regenerate the lobby maze')

 # Non-size rule changes preserve the maze; a size change is the regeneration boundary.
 regen=p.evaluate("""()=>{const base=JSON.stringify(__test.walls),r=__test.currentRules();__test.setLocalRules({...r,teamMode:'teams'});const afterTeam=JSON.stringify(__test.walls);const teamSelects=document.querySelectorAll('#roomRoster select[data-team]').length;__test.setLocalRules({...__test.currentRules(),teamMode:'ffa'});const ffaWall=JSON.stringify(__test.walls),ffaSelects=document.querySelectorAll('#roomRoster select[data-team]').length;__test.setLocalRules({...__test.currentRules(),mapSize:'ultrawide'});return{sameTeam:base===afterTeam,sameFFA:base===ffaWall,teamSelects,ffaSelects,cols:leqra.getState().world.cols,rows:leqra.getState().world.rows,changed:base!==JSON.stringify(__test.walls)};}""")
 check(regen['sameTeam'] and regen['sameFFA'],'team/FFA rule edits preserve the lobby maze')
 check(regen['teamSelects']>0 and regen['ffaSelects']==0,'FFA removes tank team selectors instead of showing locked controls')
 check(regen['cols']==24 and regen['rows']==14 and regen['changed'],'changing maze size regenerates into the 24×14 Ultra Wide layout')
 maze_before_resize=p.evaluate('JSON.stringify(__test.walls)')
 p.set_viewport_size({'width':700,'height':950});p.wait_for_timeout(120);p.set_viewport_size({'width':1365,'height':950});p.wait_for_timeout(120)
 check(p.evaluate('JSON.stringify(__test.walls)')==maze_before_resize,'responsive layout changes resize the same lobby maze instead of regenerating it')

 # Controls menu describes the currently selected maze pickup budget and expiry.
 info=p.evaluate("""()=>{__test.syncControlsPickupInfo();return document.querySelector('#controlsPickupInfo').textContent;}""")
 check('7 starting pickups' in info and '34 maximum' in info and '90 seconds' in info,'Controls menu shows starting/max pickups and maze-dependent expiry')
 p.locator('#startRoomBtn').click();p.wait_for_timeout(30)

 # Per-player feedback occupies the existing reserved loadout line, keeping height invariant.
 p.evaluate("""()=>{__test.setPhase('playing');__test.updateHUD(true)}""");p.wait_for_timeout(20)
 feedback=p.evaluate("""()=>{const box=document.querySelector('#localLoadouts'),before=box.getBoundingClientRect().height;__test.showStartingControls();__test.updateHUD(true);const p1=document.querySelector('#buffLabel').textContent,p2=document.querySelector('#buffLabel2').textContent,afterControls=box.getBoundingClientRect().height;const t2=__test.tanks.find(t=>t.id===__test.localRoom.players.find(p=>p.kind==='local').id);__test.pickups.push({x:t2.x,y:t2.y,type:'laser',age:0,life:45});__test.update(1/60);__test.updateHUD(true);return{before,afterControls,afterPickup:box.getBoundingClientRect().height,p1,p2,p2Pickup:document.querySelector('#buffLabel2').textContent,p2Visible:!document.querySelector('#pilotLoadout2').hidden};}""")
 check(feedback['p2Visible'] and feedback['p1'].startswith('CONTROLS') and feedback['p2'].startswith('CONTROLS'),'P1 and local P2 each receive their own controls feedback beside ammo')
 check(abs(feedback['before']-feedback['afterControls'])<0.6 and abs(feedback['before']-feedback['afterPickup'])<0.6,'controls/pickup feedback does not change the player-status area height')
 check(feedback['p2Pickup'].startswith('LASER'),'a local P2 pickup replaces only P2’s reserved feedback line with pickup details')
 p.evaluate('__test.render()');p.screenshot(path=str(out/'v415-hud.png'))

 # Losing focus only clears inputs; explicit pause remains the only local pause trigger.
 focus=p.evaluate("""()=>{__test.setPhase('playing');window.dispatchEvent(new Event('blur'));return __test.phase;}""")
 check(focus=='playing','window focus loss does not pause local gameplay')

 # Pause copy and spectating terminology.
 p.locator('#pauseBtn').click();p.wait_for_timeout(20)
 check(p.locator('#menuControlsBtn').inner_text().strip()=='Controls','pause-menu action is labeled Controls')
 spectator=p.evaluate("""()=>{const body=document.body.innerText,matches=body.match(/NO TANK ASSIGNED|\\bWATCHING\\b|\\bWATCHERS?\\b/gi)||[];return{caption:document.querySelector('#watchingCaption').textContent,matches,sourceNoLegacy:!matches.length};}""")
 check('SPECTATING' in spectator['caption'] and 'NO TANK ASSIGNED' not in spectator['caption'] and spectator['sourceNoLegacy'],'spectator UI uses Spectators/Spectating and omits NO TANK ASSIGNED')
 p.locator('#onlineReturnBtn').click();p.wait_for_timeout(20)

 # Victory score numerals inherit each FFA tank color, not the primary interface accent.
 p.evaluate("""()=>{__test.setPhase('matchOver');__test.showVictory(__test.tanks[0].id)}""");p.wait_for_timeout(20)
 colors=p.locator('#victoryScores .match-result').evaluate_all("""rows=>rows.map(r=>({expected:r.style.getPropertyValue('--result-color'),actual:getComputedStyle(r.querySelector('strong')).color}))""")
 check(len(colors)>=2 and all(x['expected'] for x in colors) and len({x['actual'] for x in colors})>1,'victory score values use the tank/team result colors')
 check(not errors,'no uncaught browser errors: '+str(errors))
 p.screenshot(path=str(out/'v415-desktop.png'));c.close();b.close()

(out/'results.json').write_text(json.dumps({'version':'4.29.0','passed':len(checks),'checks':checks,'errors':errors,'tiers':tiers,'feedback':feedback,'controlsPickupInfo':info},indent=2));print('TOTAL',len(checks))
