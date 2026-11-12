'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const end=source.indexOf('\n',start),line=source.slice(start,end);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);
}
function boot(p2=false,stored=null){
 const storage=new Map(stored?[['leqra.bindings.v1',JSON.stringify(stored)]]:[]);
 const pilots=[{name:'Lead',color:'#32c5ff'},{name:'Wing',color:'#ff83bd'}];
 const sandbox={phase:'playing',mode:'room',combatPrefs:{mouseAim:true,mouseFire:true},window:{},pilots,COLORS:pilots.map(p=>p.color),tanks:[],paintColor:c=>c,roomMember:id=>pilots[id],secondaryMember:()=>p2?pilots[1]:null,localPlayerID:()=>0,secondaryID:()=>1,savedLocalCallsign:()=>pilots[1].name,teamColor:id=>pilots[id].color,infinityPlayMode:()=>'',keys:new Set(),hasLocalP2:()=>p2,modeLabel:()=> 'ELIMINATION',modeInstructions:()=> 'Play',localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)}};vm.createContext(sandbox);
 vm.runInContext(source.match(/^const escapeHTML=.*$/m)[0],sandbox);
 for(const name of ['pilotIdentity','pilotIdentityHTML','localPilotIdentity','localPilotIdentityHTML','defaultBindings','validBinding','validateBindings','loadBindings','aliasesActive','keyForAction','heldAction','isWeaponKey','isControlKey','fireAliasLabels','keyLabel','movementKeySummary','controlKeyMap','controlPairActive','controlSummary','pilotControlHint','controlKeycapsHTML','controlMouseKeyHTML','controlKeyHTML','controlHintHTML','fieldManualHTML','syncIntroTourControls','syncControlIdentities'])vm.runInContext(declaration(name),sandbox);
 sandbox.bindings=sandbox.loadBindings();sandbox.storage=storage;return sandbox;
}
function assign(s,player,action,code){s.bindings[player][action]=code;assert.ok(s.validateBindings(s.bindings),'the controls editor accepts this remap');}
function owner(s,action,code,expected){
 s.keys.clear();s.keys.add(code);
 for(let player=0;player<2;player++){
  assert.equal(s.keyForAction(player,action,code),player===expected,code+' key owner');
  assert.equal(s.heldAction(player,action),player===expected,code+' held owner');
 }
}
function tour(s){
 const nodes=new Map();s.$=id=>{if(!nodes.has(id))nodes.set(id,{hidden:false,previousElementSibling:{hidden:false},setAttribute(k,v){this[k]=v;}});return nodes.get(id);};
 s.$('bindingGrid').querySelectorAll=()=>[];s.window.matchMedia=()=>({matches:true});s.syncControlIdentities();s.syncIntroTourControls();return s.$;
}
const keycaps=html=>[...html.matchAll(/<kbd(?:\s[^>]*)?>(.*?)<\/kbd>/g)].map(match=>match[1]);

test('tour keyboard hints use themed keycaps and current aliases without advertising the active co-pilot keys',()=>{
 for(const paired of [false,true]){
  const s=boot(paired),$=tour(s),movement=$('introTourMoveKeys').innerHTML,fire=$('introTourFireKeys').innerHTML;
  assert.deepEqual(keycaps(movement),paired?['W','A','S','D']:['W','↑','A','←','S','↓','D','→']);
  assert.deepEqual(keycaps(fire),paired?['Q','C']:['Q','C','SPACE','ENTER']);
  assert.equal((movement.match(/class="control-keycaps"/g)||[]).length,4,'movement aliases stay grouped by direction');
  assert.equal((movement.match(/class="control-alias"/g)||[]).length,paired?0:4);
  assert.equal((fire.match(/class="control-alias"/g)||[]).length,paired?1:3);
 }
 const s=boot();for(const [action,code]of Object.entries({forward:'KeyI',left:'KeyJ',reverse:'KeyK',right:'KeyL',fire:'KeyZ',fireAlt:'KeyX'}))assign(s,0,action,code);
 for(const [action,code]of Object.entries({forward:'KeyU',left:'KeyH',reverse:'KeyN',right:'KeyO'}))assign(s,1,action,code);
 const $=tour(s);assert.deepEqual(keycaps($('introTourMoveKeys').innerHTML),['I','U','J','H','K','N','L','O']);assert.deepEqual(keycaps($('introTourFireKeys').innerHTML),['Z','X','SPACE','ENTER']);
 for(const key of ['W','A','S','D','Q','C','↑','←','↓','→'])assert.equal([...keycaps($('introTourMoveKeys').innerHTML),...keycaps($('introTourFireKeys').innerHTML)].includes(key),false,'retired binding '+key+' is absent');
});

test('tour names and key labels escape HTML while sharing the control keycap renderer',()=>{
 const s=boot();s.pilots[0].name='<Lead & co>';const $=tour(s);
 assert.ok($('introTourPilot').innerHTML.includes('&lt;Lead &amp; co&gt; (P1)'));assert.equal($('introTourPilot').innerHTML.includes('<Lead'),false);
 const key=s.controlKeyHTML(['Key<script>','Key&']);assert.deepEqual(keycaps(key),['&lt;SCRIPT&gt;','&amp;']);assert.equal(key.includes('<SCRIPT>'),false);assert.ok(key.includes('class="control-alias">/</span>'));
 assert.equal(s.controlKeyHTML(['KeyQ','KeyC']),s.controlKeycapsHTML(['<kbd>Q</kbd>','<kbd>C</kbd>']));
});

test('tour mouse hints share distinct aim and fire SVG keycaps and honor independent preferences',()=>{
 const s=boot(),$=tour(s),aim=$('introTourMouseAimKey').innerHTML,fire=$('introTourMouseFireKey').innerHTML;
 assert.ok(aim.includes(s.controlMouseKeyHTML(false)));assert.ok(fire.includes(s.controlMouseKeyHTML(true)));
 assert.equal(aim.includes('mouse-button-fill'),false);assert.ok(fire.includes('mouse-button-fill'));
 const html=readFileSync(require('node:path').join(__dirname,'../web/index.html'),'utf8');assert.match(html,/<dd id="introTourMouseAim">[\s\S]*?Point over the maze\.[\s\S]*?<\/dd>/);assert.match(html,/<dd id="introTourMouseFire">[\s\S]*?Left-click to fire[\s\S]*?<\/dd>/);
 for(const [mouseAim,mouseFire]of [[true,false],[false,true],[false,false],[true,true]]){
  Object.assign(s.combatPrefs,{mouseAim,mouseFire});s.syncControlIdentities();s.syncIntroTourControls();assert.equal($('introTourMouseAim').hidden,!mouseAim);assert.equal($('introTourMouseFire').hidden,!mouseFire);assert.equal($('introTourDesktop').hidden,!mouseAim&&!mouseFire);
  assert.equal(($('introTourMouseAimKey').innerHTML.match(/class="control-mouse-key"/g)||[]).length,1);assert.equal(($('introTourMouseFireKey').innerHTML.match(/class="control-mouse-key"/g)||[]).length,1,'reopening or refreshing the tour never duplicates a mouse icon');
 }
});

test('mouse binding controls keep native checkbox behavior inside the same sized column as key buttons',()=>{
 const s=boot(),nodes=new Map(),changes=[];
 const element=tag=>({tag,children:[],dataset:{},append(...children){this.children.push(...children);},replaceChildren(...children){this.children=children;},setAttribute(key,value){this[key]=value;}});
 s.document={createElement:element};s.$=id=>{if(!nodes.has(id))nodes.set(id,element('div'));return nodes.get(id);};
 s.syncControlIdentities=s.syncControlsPickupInfo=s.featureNotice=()=>{};
 s.setMouseControlEnabled=(kind,enabled)=>changes.push([kind,enabled]);
 vm.runInContext(declaration('renderBindings'),s);s.renderBindings();
 const sections=s.$('bindingGrid').children;assert.equal(sections.length,2);
 assert.equal(sections[0].children.length,8);assert.equal(sections[1].children.length,6,'mouse controls belong only to the primary tank');
 for(const [index,kind]of ['aim','fire'].entries()){
  const row=sections[0].children[index+6],[label,control]=row.children,[checkbox,state]=control.children;
  assert.equal(row.className,'binding-row binding-mouse-row');assert.equal(control.className,'binding-mouse-control');
  assert.equal(checkbox.type,'checkbox');assert.equal(checkbox.className,'binding-mouse-toggle');assert.equal(label.htmlFor,checkbox.id);
  assert.equal(checkbox.id,kind==='aim'?'p1MouseAimEnabled':'p1MouseFireEnabled');assert.equal(checkbox.checked,true);
  assert.equal(state['aria-hidden'],'true','decorative ON/OFF text does not rename the checkbox');
  checkbox.checked=false;checkbox.onchange();assert.deepEqual(changes.at(-1),[kind,false]);
  checkbox.checked=true;checkbox.onchange();assert.deepEqual(changes.at(-1),[kind,true]);
 }
 const css=readFileSync(assetPath('style.css'),'utf8');
 assert.match(css,/\.binding-key\.secondary,\.binding-mouse-control\{[^}]*width:var\(--binding-control-width\);[^}]*max-width:var\(--binding-control-width\)/);
 assert.match(css,/\.binding-key\.secondary\{[^}]*min-height:var\(--binding-control-height\)/);
 assert.match(css,/\.binding-mouse-toggle\{[^}]*appearance:none;[^}]*width:100%;[^}]*min-height:var\(--binding-control-height\)/);
 assert.match(css,/\.binding-mouse-toggle:focus-visible\{[^}]*outline:/);
 assert.match(css,/\.binding-mouse-state\{[^}]*pointer-events:none/);
 assert.match(css,/\.binding-mouse-state:after\{content:'OFF'\}/);assert.match(css,/\.binding-mouse-toggle:checked\+\.binding-mouse-state:after\{content:'ON'\}/);
});

test('hold-fire help follows the solo pilot or both pilots according to the active arena',()=>{
 const tip='Hold any fire key to rapid fire.';
 const html=readFileSync(require('node:path').join(__dirname,'../web/index.html'),'utf8');
 assert.ok(html.includes('<p class="intro-fire-tip">'+tip+'</p>'));
 assert.ok(html.indexOf('class="intro-fire-tip"')>html.indexOf('id="introTourFireKeys"'));
 assert.ok(html.indexOf('class="intro-fire-tip"')<html.indexOf('Rebind keys in Controls.'));
 assert.equal(source.includes('Both fire keys can also detonate your grenade.'),false);
 for(const [roomP2,infinityP2,paired]of [[false,null,false],[true,null,true],[true,false,false],[false,true,true]]){
  const s=boot(roomP2);if(infinityP2!==null)s.window.leqraInfinity={sidebarHelp:()=>({twoPilots:infinityP2,instructions:'Keep playing.'})};
  const manual=s.fieldManualHTML(),shared=manual.indexOf('<div class="manual-shared-controls">'),tipAt=manual.indexOf(tip);
  assert.equal(manual.split(tip).length-1,1);assert.equal(tipAt>shared,paired,'only a rendered pair shares the tip below the divider');
  assert.ok(manual.indexOf('Lead (P1)')<tipAt);if(paired)assert.ok(manual.indexOf('Wing (P2)')<tipAt);else assert.equal(manual.includes('Wing (P2)'),false);
  if(!paired)assert.ok(manual.includes('<p class="manual-fire-tip">'+tip+'</p></div><div class="manual-shared-controls">'),'solo tip ends the primary control section');
  assert.ok(tipAt<manual.indexOf('<span class="control-action">Menu</span>'));
  assert.ok(tipAt<manual.indexOf('<div class="warning">'),'the mode description remains after shared help');
 }
 const s=boot();let fired=0,detonated=0,activeGrenade=false;s.fire=()=>{fired++;};s.detonateOwned=()=>{if(!activeGrenade)return false;activeGrenade=false;detonated++;return true;};
 vm.runInContext(declaration('weaponControl'),s);
 const ordinary={alive:true,power:'homing'};s.weaponControl(ordinary,true,true);s.weaponControl(ordinary,true,false);s.weaponControl(ordinary,true,false);assert.equal(fired,3,'held fire keeps requesting shots at the weapon cadence');
 const grenade={alive:true,power:'grenade'};s.weaponControl(grenade,true,true);s.weaponControl(grenade,true,false);assert.equal(fired,4,'holding the launch press cannot repeatedly throw or detonate');
 activeGrenade=true;s.weaponControl(grenade,false,false);s.weaponControl(grenade,true,true);assert.equal(detonated,1);assert.equal(fired,4,'a separate press detonates the active grenade');
});

test('Controls shortcuts share themed keycaps and separate firing help from the shortcut line',()=>{
 const s=boot(),template=source.match(/<div id="controlsKeyboardHelp">[\s\S]*?<\/div>/)?.[0];assert.ok(template);
 const html=vm.runInContext('`'+template+'`',s),shortcuts=html.match(/<p class="mode-help controls-shortcuts">([\s\S]*?)<\/p>/)?.[1];assert.ok(shortcuts);
 assert.deepEqual(keycaps(shortcuts),['P','ESC','M','F']);
 assert.ok(shortcuts.includes(s.controlKeyHTML(['KeyP','ESC'])));assert.ok(shortcuts.includes(s.controlKeyHTML(['KeyM'])));assert.ok(shortcuts.includes(s.controlKeyHTML(['KeyF'])));
 const help='Hold any fire key to rapid fire.<br> With one local tank, both keyboard layouts control it.';
 assert.ok(html.includes('</p><p class="mode-help controls-firing-help">'+help+'</p>'),'firing guidance has its own block after all shortcut keys');
 assert.equal(shortcuts.includes('rapid fire'),false);assert.equal(html.split(help).length-1,1);
});

test('both default fire keys and solo fallback belong to exactly one pilot',()=>{
 for(const p2 of [false,true]){
  const s=boot(p2);
  for(const code of ['KeyQ','KeyC'])owner(s,'fire',code,0);
  for(const code of ['Space','Enter'])owner(s,'fire',code,p2?1:0);
 }
});
test('all configured P2 movement and fire bindings fall back after either player remaps',()=>{
 for(const p2 of [false,true]){
  const s=boot(p2);assign(s,0,'forward','KeyI');assign(s,0,'fire','KeyO');assign(s,0,'fireAlt','KeyU');
  const mappings={forward:'KeyT',reverse:'KeyG',left:'KeyR',right:'KeyY',fire:'KeyH',fireAlt:'KeyJ'};
  for(const [action,code] of Object.entries(mappings))assign(s,1,action,code);
  for(const [action,code] of Object.entries(mappings))owner(s,action==='fireAlt'?'fire':action,code,p2?1:0);
  for(const code of ['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Space','Enter','KeyQ','KeyC'])assert.equal(s.isControlKey(code),false,'old mappings are released');
  owner(s,'forward','KeyI',0);owner(s,'fire','KeyO',0);owner(s,'fire','KeyU',0);
 }
});
test('P1 remapping alone never disables configured P2 fallbacks',()=>{
 const s=boot();assign(s,0,'forward','KeyI');assign(s,0,'fireAlt','KeyJ');
 owner(s,'forward','ArrowUp',0);owner(s,'fire','Space',0);owner(s,'fire','Enter',0);
});
test('C and Enter can be reassigned to movement after freeing their fire binding',()=>{
 for(const p2 of [false,true])for(const [code,from] of [['KeyC',0],['Enter',1]])for(const target of [0,1]){
  const s=boot(p2);assign(s,from,'fireAlt','KeyJ');assign(s,target,'forward',code);
  owner(s,'forward',code,target===1&&!p2?0:target);
  assert.equal(s.isWeaponKey(code),false);
  assert.equal(s.heldAction(0,'fire'),false);assert.equal(s.heldAction(1,'fire'),false);
 }
});
test('secondary fire keys are included in cross-player conflict validation',()=>{
 for(const player of [0,1])for(const action of ['forward','reverse','left','right','fire','fireAlt']){
  const s=boot();s.bindings[player][action]=s.bindings[1-player].fireAlt;assert.equal(s.validateBindings(s.bindings),null);
 }
 const s=boot();s.bindings[0].fireAlt=s.bindings[0].fire;assert.equal(s.validateBindings(s.bindings),null);
});
test('remapped alternate fire is supported independently for both active players',()=>{
 const s=boot(true);assign(s,0,'fireAlt','KeyJ');assign(s,1,'fireAlt','KeyL');
 owner(s,'fire','KeyJ',0);owner(s,'fire','KeyL',1);
 assert.equal(s.isWeaponKey('KeyC'),false);assert.equal(s.isWeaponKey('Enter'),false);
});
test('simultaneously held fire keys keep firing until the last key is released',()=>{
 const s=boot();s.keys.add('KeyQ');s.keys.add('Enter');assert.equal(s.heldAction(0,'fire'),true);
 s.keys.delete('KeyQ');assert.equal(s.heldAction(0,'fire'),true);s.keys.delete('Enter');assert.equal(s.heldAction(0,'fire'),false);
});
test('solo field manual displays current movement and both fire bindings for both layouts',()=>{
 const s=boot();assign(s,0,'forward','KeyI');assign(s,0,'fireAlt','KeyJ');assign(s,1,'forward','KeyT');assign(s,1,'fireAlt','KeyL');
 const html=s.fieldManualHTML();
 for(const key of ['I','T','Q','J','SPACE','L'])assert.ok(html.includes('<kbd>'+key+'</kbd>'),key);
 for(const key of ['W','↑','C','ENTER'])assert.equal(html.includes('<kbd>'+key+'</kbd>'),false,key);
 assert.ok(html.includes('class="control-action">Fire</span>'));assert.equal(html.includes('Fire / detonate'),false);
 assert.ok(s.movementKeySummary(0).includes('(or T'));
});
test('two-player field manual labels each player without advertising solo fallbacks',()=>{
 const s=boot(true);assert.ok(s.fieldManualHTML().includes('Wing (P2)'));assert.equal(s.controlSummary(0).includes('SPACE'),false);
 assert.equal(s.controlSummary(1).includes('Q'),false);
});
test('control groups label directions and reserve slashes for current aliases',()=>{
 const solo=boot();
 assert.equal(solo.controlSummary(0),'Lead (P1): Forward W/↑, Reverse S/↓, Left A/←, Right D/→, Fire Q/C/SPACE/ENTER');
 assert.equal(solo.movementKeySummary(0),'W A S D (or ↑ ← ↓ →)');
 const pair=boot(true);
 assert.equal(pair.controlSummary(0),'Lead (P1): Forward W, Reverse S, Left A, Right D, Fire Q/C');
 assert.equal(pair.controlSummary(1),'Wing (P2): Forward ↑, Reverse ↓, Left ←, Right →, Fire SPACE/ENTER');
 assign(pair,0,'forward','KeyI');assign(pair,0,'fireAlt','KeyJ');assign(pair,1,'fireAlt','KeyL');
 assert.equal(pair.controlSummary(0,false),'Forward I, Reverse S, Left A, Right D, Fire Q/J');
 assert.equal(pair.controlSummary(1,false),'Forward ↑, Reverse ↓, Left ←, Right →, Fire SPACE/L');
 const html=pair.fieldManualHTML();
 assert.equal((html.match(/class="control-player"/g)||[]).length,2);
 for(const label of ['Forward','Reverse','Left','Right','Fire'])assert.ok(html.includes('class="control-action">'+label+'</span>'));
 assert.ok(html.includes('<span class="control-key-option"><span class="control-alias">/</span><kbd>J</kbd></span>'));
 assert.ok(html.includes('<span class="control-key-option"><span class="control-alias">/</span><kbd>L</kbd></span>'));
 assert.equal(html.includes('Move I, S'),false);
});
test('menu, mute and fullscreen are shared below both pilots and separated from the mode description',()=>{
 for(const infinity of [false,true]){
  const s=boot(true);
  if(infinity)s.window={leqraInfinity:{sidebarHelp:()=>({twoPilots:true,instructions:'Keep playing.'})}};
  const html=s.fieldManualHTML(),shared=html.indexOf('<div class="manual-shared-controls">');
  assert.ok(shared>html.indexOf('Wing (P2)'));
  assert.equal(html.slice(0,shared).includes('Fullscreen'),false);
  const controls=html.slice(shared,html.indexOf('<div class="warning">'));
  for(const label of ['Menu','Mute','Fullscreen'])assert.ok(controls.includes('<span class="control-action">'+label+'</span>'));
  for(const key of ['P','ESC','M','F'])assert.ok(controls.includes('<kbd>'+key+'</kbd>'));
  assert.ok(controls.includes('<span class="control-key-option"><span class="control-alias">/</span><kbd>ESC</kbd></span>'));
  assert.equal(controls.includes('Pause'),false);
  assert.ok(html.indexOf('<div class="warning">')>shared);
 }
});
test('control identities escape current callsigns and follow tank paint without changing aliases',()=>{
 const s=boot(true);s.pilots[0].name='<Lead & co>';s.pilots[0].color='#ffc46b';s.pilots[1].name='Wing renamed';
 const html=s.fieldManualHTML();
 assert.ok(html.includes('style="color:#ffc46b">&lt;Lead &amp; co&gt; (P1)</strong>'));
 assert.ok(html.includes('style="color:#ff83bd">Wing renamed (P2)</strong>'));
 assert.equal(html.includes('Player 1'),false);assert.equal(html.includes('Player 2'),false);
 assert.ok(html.includes('<kbd>Q</kbd>'));assert.ok(html.includes('<kbd>ENTER</kbd>'));
});
test('ready and manual control labels use the same theme paint mapping as callsign editors',()=>{
 const s=boot(true),mapped={'#d2f65a':'#32c5ff','#ff9679':'#ff758f'};
 s.pilots[0].color='#d2f65a';s.pilots[1].color='#ff9679';s.paintColor=color=>mapped[color]||color;
 const ready=s.pilotControlHint(0,'mouse',false,true)+s.pilotControlHint(1,'',false,true),manual=s.fieldManualHTML();
 for(const html of [ready,manual]){
  assert.ok(html.includes('style="color:#32c5ff">Lead (P1)</strong>'));
  assert.ok(html.includes('style="color:#ff758f">Wing (P2)</strong>'));
  assert.equal(html.includes('style="color:#d2f65a"'),false);
 }
});
test('mouse hints come after keyboard Fire and disappear without changing keyboard bindings when disabled',()=>{
 const s=boot(true),keys=s.controlKeyMap(0,false);
 const html=s.controlHintHTML(keys,'Lead (P1)','mouse','#32c5ff');
 assert.deepEqual([...html.matchAll(/class="control-action">([^<]+)/g)].map(match=>match[1]),['Forward','Reverse','Left','Right','Fire','Mouse Aim','Mouse Fire']);
 const fire=html.slice(html.indexOf('class="control-action">Fire'),html.indexOf('class="control-action">Mouse Aim'));
 assert.ok(fire.includes('<kbd>Q</kbd>'));assert.ok(fire.includes('<kbd>C</kbd>'));assert.equal(fire.includes('control-mouse-key'),false);
 s.combatPrefs.mouseAim=false;s.combatPrefs.mouseFire=false;
 const disabled=s.controlHintHTML(keys,'Lead (P1)','mouse','#32c5ff');
 assert.equal(disabled.includes('control-mouse-key'),false);assert.equal(disabled.includes('Mouse Aim'),false);
 assert.ok(disabled.includes('<kbd>Q</kbd>'));assert.ok(disabled.includes('<kbd>C</kbd>'));
 assert.equal(s.fieldManualHTML().includes('control-mouse-key'),false);
 assert.ok(s.controlHintHTML(keys,'Lead (P1)','touch').includes('Drag the stick'));
 for(const [aim,fire]of [[true,false],[false,true]]){
  Object.assign(s.combatPrefs,{mouseAim:aim,mouseFire:fire});
  const hint=s.controlHintHTML(keys,'Lead (P1)','mouse');
  assert.equal(hint.includes('Mouse Aim'),aim);assert.equal(hint.includes('Mouse Fire'),fire);
  assert.ok(hint.includes('<kbd>Q</kbd>'));assert.ok(hint.includes('<kbd>C</kbd>'));
 }
});
test('open controls and tour identities refresh without replacing an active binding capture',()=>{
 const s=boot(),nodes=new Map(),headings=[{},{}],buttons=[0,1].map(()=>({dataset:{actionLabel:'Forward'},textContent:'PRESS KEY',setAttribute(k,v){this[k]=v;}}));
 const sections=headings.map((heading,index)=>({querySelector:()=>heading,querySelectorAll:()=>[buttons[index]]}));
 s.$=id=>{if(!nodes.has(id))nodes.set(id,{setAttribute(k,v){this[k]=v;}});return nodes.get(id);};
 s.$('bindingGrid').querySelectorAll=()=>sections;
 s.syncControlIdentities();
 assert.ok(headings[0].innerHTML.includes('Lead (P1)'));assert.equal(headings[1].innerHTML,'Alternate keyboard');
 assert.equal(buttons[0]['aria-label'],'Rebind Lead (P1) Forward');assert.equal(buttons[1]['aria-label'],'Rebind alternate keyboard Forward');
 s.pilots[0].name='Renamed';s.pilots[0].color='#ffc46b';s.window.leqraInfinity={localPilots:()=>s.pilots};
 s.syncControlIdentities();
 assert.ok(headings[0].innerHTML.includes('color:#ffc46b'));assert.ok(headings[0].innerHTML.includes('Renamed (P1)'));
 assert.ok(headings[1].innerHTML.includes('Wing (P2)'));assert.equal(buttons[1]['aria-label'],'Rebind Wing (P2) Forward');
 assert.equal(buttons[0].textContent,'PRESS KEY');assert.equal(s.$('introTourKeyboard')['aria-label'],'Keyboard controls for Renamed (P1)');
 assert.ok(s.$('introTourPilot').innerHTML.includes('Renamed (P1)'));
 s.window.matchMedia=()=>({matches:true});s.syncControlIdentities();
 assert.equal(s.$('p1MouseAimEnabled').checked,true);assert.equal(s.$('p1MouseFireEnabled').checked,true);assert.equal(s.$('introTourDesktop').hidden,false);
 assert.equal(s.$('p1MouseAimEnabled')['aria-label'],'Mouse aim for Renamed (P1)');
 s.combatPrefs.mouseAim=false;s.combatPrefs.mouseFire=false;s.syncControlIdentities();
 assert.equal(s.$('p1MouseAimEnabled').checked,false);assert.equal(s.$('p1MouseFireEnabled').checked,false);assert.equal(s.$('introTourDesktop').hidden,true);
 assert.equal(s.$('pauseInstructions').innerHTML.includes('control-mouse-key'),false);
 s.combatPrefs.mouseFire=true;s.syncControlIdentities();
 assert.equal(s.$('introTourDesktop').hidden,false);assert.equal(s.$('introTourMouseAim').hidden,true);assert.equal(s.$('introTourMouseFire').hidden,false);
});
test('old saved bindings migrate both extra fire keys without losing remaps',()=>{
 const raw=boot().defaultBindings();delete raw[0].fireAlt;delete raw[1].fireAlt;raw[0].forward='KeyI';raw[1].fire='KeyL';
 const s=boot(false,{version:1,bindings:raw});
 assert.equal(s.bindings[0].forward,'KeyI');assert.equal(s.bindings[1].fire,'KeyL');
 assert.equal(s.bindings[0].fireAlt,'KeyC');assert.equal(s.bindings[1].fireAlt,'Enter');
 assert.equal(JSON.parse(s.storage.get('leqra.bindings.v1')).version,4);
});
test('legacy C and Enter remaps are preserved while missing fire keys get unused keys',()=>{
 const raw=boot().defaultBindings();delete raw[0].fireAlt;delete raw[1].fireAlt;raw[0].forward='KeyC';raw[1].right='Enter';
 const s=boot(false,{version:1,bindings:raw});
 assert.equal(s.bindings[0].forward,'KeyC');assert.equal(s.bindings[1].right,'Enter');
 assert.ok(s.validateBindings(s.bindings));assert.notEqual(s.bindings[0].fireAlt,'KeyC');assert.notEqual(s.bindings[1].fireAlt,'Enter');
});
test('legacy fullscreen key migration still avoids existing and secondary-fire bindings',()=>{
 const raw=boot().defaultBindings();delete raw[0].fireAlt;delete raw[1].fireAlt;raw[0].fire='KeyF';raw[1].forward='KeyQ';
 const s=boot(false,{version:1,bindings:raw});assert.ok(s.validateBindings(s.bindings));assert.equal(s.bindings[1].forward,'KeyQ');
 assert.notEqual(s.bindings[0].fire,'KeyF');assert.notEqual(s.bindings[0].fire,'KeyQ');
});
test('new alternate-fire remaps survive reload without another migration',()=>{
 const s=boot();assign(s,0,'fireAlt','KeyJ');assign(s,1,'fireAlt','KeyL');
 const r=boot(false,{version:4,bindings:s.bindings});assert.equal(r.bindings[0].fireAlt,'KeyJ');assert.equal(r.bindings[1].fireAlt,'KeyL');
});
test('invalid storage or unavailable storage restores valid safe defaults',()=>{
 for(const raw of [null,[null],[null,null],[{},{}]])assert.ok(boot(false,{bindings:raw}).validateBindings(boot(false,{bindings:raw}).bindings));
 const s=boot();s.localStorage.getItem=()=>{throw Error('unavailable')};assert.ok(s.validateBindings(s.loadBindings()));
});
test('a spectating secondary seat does not suppress the solo fallback',()=>{
 const line=source.match(/^const hasLocalP2=.*$/m)[0];
 const s={mode:'room',secondLocal:()=>undefined,secondaryMember:()=>({spectating:true})};vm.createContext(s);vm.runInContext(line+';globalThis.active=hasLocalP2;',s);
 assert.equal(s.active(),false);s.secondLocal=()=>({spectating:false});assert.equal(s.active(),true);
 s.secondLocal=()=>undefined;s.mode='duel';assert.equal(s.active(),true);
});


test('public Infinity preview explains FFA scoring instead of fixed round rules',()=>{
 const s=boot();s.phase='menu';s.infinityPlayMode=()=> 'online';
 const html=s.fieldManualHTML();assert.ok(html.includes('PUBLIC INFINITY'));
 assert.ok(html.includes('All pilots compete individually.'));assert.equal(html.includes('ELIMINATION'),false);
});
