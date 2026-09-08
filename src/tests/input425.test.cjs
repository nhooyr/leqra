'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const end=source.indexOf('\n',start),line=source.slice(start,end);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);
}
function boot(p2=false,stored=null){
 const storage=new Map(stored?[['leqra.bindings.v1',JSON.stringify(stored)]]:[]);
 const sandbox={keys:new Set(),hasLocalP2:()=>p2,escapeHTML:s=>String(s),modeLabel:()=> 'ELIMINATION',modeInstructions:()=> 'Play',localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)}};vm.createContext(sandbox);
 for(const name of ['defaultBindings','validBinding','validateBindings','loadBindings','aliasesActive','keyForAction','heldAction','isWeaponKey','isControlKey','fireAliasLabels','keyLabel','controlSummary','manualKeyRow','fieldManualHTML'])vm.runInContext(declaration(name),sandbox);
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
 assert.ok(html.includes('<span>Fire</span>'));assert.equal(html.includes('Fire / detonate'),false);
 assert.ok(s.controlSummary(0).includes('(or T'));
});
test('two-player field manual labels each player without advertising solo fallbacks',()=>{
 const s=boot(true);assert.ok(s.fieldManualHTML().includes('Player 2'));assert.equal(s.controlSummary(0).includes('SPACE'),false);
 assert.equal(s.controlSummary(1).includes('Q'),false);
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
