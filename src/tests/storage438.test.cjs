'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
const startup=source.slice(source.indexOf("const STORAGE_PREFIX='leqra.';"),source.indexOf('const pilotFeedback='));
function declaration(name){const start=source.indexOf('function '+name+'('),end=source.indexOf('\n',start),line=source.slice(start,end);assert.ok(start>=0,name);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function storage(entries=[]){const values=new Map(entries);return{values,getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};}
function boot(blocked=[]){
 const local=storage([['ricochet.name','LEGACY PILOT'],['ricochet.volume','80'],['leqra.volume','25']]),session=storage([['ricochet.session','old-session'],['ricochet.kicked','old-room']]),s={storageHandles:{localStorage:local,sessionStorage:session},blockedStorage:blocked};
 vm.createContext(s);vm.runInContext("for(const key of ['localStorage','sessionStorage'])Object.defineProperty(globalThis,key,{get(){if(blockedStorage.includes(key)){const e=new Error(key+' access denied');e.name='SecurityError';throw e;}return storageHandles[key];}});",s);return{s,local,session};
}

test('startup reaches default initialization when either browser storage getter throws SecurityError',()=>{
 for(const blocked of [['localStorage'],['sessionStorage'],['localStorage','sessionStorage']]){
  const {s}=boot(blocked);assert.doesNotThrow(()=>vm.runInContext(startup+'\nglobalThis.startupContinued=true;',s),blocked.join(', '));assert.equal(s.startupContinued,true);
  for(const name of ['defaultBindings','loadBindings','readCombatPrefs','loadPresets','save','savedLocalCallsign','cleanPilotName'])vm.runInContext(declaration(name),s);
  if(blocked.includes('localStorage')){
   assert.deepEqual(JSON.parse(JSON.stringify(s.loadBindings())),JSON.parse(JSON.stringify(s.defaultBindings())));
   assert.deepEqual(JSON.parse(JSON.stringify(s.readCombatPrefs())),{visual:true,audio:true,fps:false,performance:false});assert.equal(s.loadPresets().length,0);assert.equal(s.savedLocalCallsign(),'PLAYER 2');assert.doesNotThrow(()=>s.save('name','PILOT'));
  }
 }
});

test('a denied local storage getter does not prevent accessible session migration, or vice versa',()=>{
 const first=boot(['localStorage']);assert.doesNotThrow(()=>vm.runInContext(startup,first.s));assert.equal(first.session.values.get('leqra.session'),'old-session');assert.equal(first.session.values.get('leqra.kicked'),'old-room');
 const second=boot(['sessionStorage']);assert.doesNotThrow(()=>vm.runInContext(startup,second.s));assert.equal(second.local.values.get('leqra.name'),'LEGACY PILOT');assert.equal(second.local.values.get('leqra.volume'),'25');
});

test('accessible legacy settings migrate once without replacing current preferences or credentials',()=>{
 const {s,local,session}=boot();session.values.set('leqra.session','current-session');vm.runInContext(startup,s);
 assert.equal(local.values.get('leqra.name'),'LEGACY PILOT');assert.equal(local.values.get('leqra.volume'),'25');assert.equal(session.values.get('leqra.session'),'current-session');assert.equal(session.values.get('leqra.kicked'),'old-room');
});
