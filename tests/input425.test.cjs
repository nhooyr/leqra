'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const end=source.indexOf('\n',start),line=source.slice(start,end);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);
}
function boot(p2=false){
 const sandbox={keys:new Set(),hasLocalP2:()=>p2,escapeHTML:s=>String(s),modeLabel:()=> 'ELIMINATION',modeInstructions:()=> 'Play'};vm.createContext(sandbox);
 for(const name of ['defaultBindings','validBinding','validateBindings','defaultPrimary','aliasesActive','supplementalFireKey','keyForAction','heldAction','isWeaponKey','isControlKey','fireAliasLabels','keyLabel','controlSummary','manualKeyRow','fieldManualHTML'])vm.runInContext(declaration(name),sandbox);
 sandbox.bindings=sandbox.defaultBindings();return sandbox;
}
function assign(s,player,action,code){s.bindings[player][action]=code;assert.ok(s.validateBindings(s.bindings),'the controls editor accepts this remap');}

test('default supplemental keys still fire the correct local pilot',()=>{
 for(const p2 of [false,true]){
  const s=boot(p2);
  for(const [code,owner] of [['KeyC',0],['Enter',p2?1:0]]){
   s.keys.clear();s.keys.add(code);
   for(let player=0;player<2;player++){
    assert.equal(s.keyForAction(player,'fire',code),player===owner);
    assert.equal(s.heldAction(player,'fire'),player===owner);
   }
  }
 }
});
test('remapped C movement does not also fire either tank',()=>{
 for(const p2 of [false,true])for(const owner of [0,1]){
  const s=boot(p2);assign(s,owner,'forward','KeyC');s.keys.add('KeyC');
  assert.equal(s.heldAction(owner,'forward'),true);
  for(let player=0;player<2;player++){
   assert.equal(s.keyForAction(player,'fire','KeyC'),false);
   assert.equal(s.heldAction(player,'fire'),false);
  }
  assert.equal(s.fireAliasLabels(0).includes('C'),false);
 }
});
test('remapped Enter movement does not also fire either tank',()=>{
 for(const p2 of [false,true])for(const owner of [0,1]){
  const s=boot(p2);assign(s,owner,'right','Enter');s.keys.add('Enter');
  assert.equal(s.heldAction(owner,'right'),true);
  for(let player=0;player<2;player++){
   assert.equal(s.keyForAction(player,'fire','Enter'),false);
   assert.equal(s.heldAction(player,'fire'),false);
   assert.equal(s.fireAliasLabels(player).includes('ENTER'),false);
  }
 }
});
test('explicit fire mappings take priority over the other pilot supplemental key',()=>{
 for(const [code,owner] of [['KeyC',1],['Enter',0]]){
  const s=boot(true);assign(s,owner,'fire',code);s.keys.add(code);
  for(let player=0;player<2;player++){
   assert.equal(s.keyForAction(player,'fire',code),player===owner);
   assert.equal(s.heldAction(player,'fire'),player===owner);
  }
 }
});
test('configured fire keys are not repeated in the displayed alias summary',()=>{
 for(const [p2,player,code,label] of [[false,0,'KeyC','C'],[false,0,'Enter','ENTER'],[true,1,'Enter','ENTER']]){
  const s=boot(p2);assign(s,player,'fire',code);
  assert.equal(s.fireAliasLabels(player).includes(label),false);
  const fire=s.controlSummary(player,false).split(' + ')[1].split(' / ');
  assert.equal(fire.filter(item=>item===label).length,1);
 }
});
test('solo field manual only advertises supplemental keys still available to P1',()=>{
 for(const [code,label] of [['KeyC','C'],['Enter','ENTER']]){
  const s=boot(false);assign(s,1,'forward',code);
  assert.equal(s.fieldManualHTML().includes('<kbd>'+label+'</kbd>'),false);
  assert.equal(s.fieldManualHTML().includes('<kbd>SPACE</kbd>'),true);
 }
});
