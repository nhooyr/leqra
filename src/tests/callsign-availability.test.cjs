'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const {assetPath}=require('./web_assets.cjs');
const source=fs.readFileSync(assetPath('game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const status={hidden:true,textContent:'',classList:{toggle(name,value){this[name]=value;}}},field={value:'Taken',disabled:false,setAttribute(name,value){this[name]=value;}},form={dataset:{},querySelector:()=>status,elements:{callsign:field}};
 const storage=new Map(),pending=[],timers=new Map();let next=0;
 const context={AbortController,URL,location:{protocol:'https:',href:'https://example.test/'},localStorage:{getItem:key=>storage.get(key),setItem:(key,value)=>storage.set(key,value),removeItem:key=>storage.delete(key)},online:{},mode:'room',window:{},$:()=>status,cleanPilotName:value=>String(value).trim(),secondaryMember:()=>null,roomMember:()=>null,localPlayerID:()=>0,
  setTimeout(fn){timers.set(++next,fn);return next;},clearTimeout(id){timers.delete(id);},fetch(url,request){return new Promise(resolve=>pending.push({url,request,resolve}));}};
 vm.createContext(context);for(const name of ['publicIdentityToken','rememberPublicIdentity','localAccountRegistrationPending','callsignAvailabilityNames','scheduleCallsignAvailability','checkCallsignAvailability'])vm.runInContext((name==='checkCallsignAvailability'?'async ':'')+declaration(name),context);
 return{context,status,field,form,storage,pending,timers};
}
test('availability is advisory offline, authenticates ownership, and never sends a score',async()=>{
 const {context:s,status,field,form,pending,storage}=boot();s.rememberPublicIdentity('p_owner');field.callsignCheckRevision=1;
 const check=s.checkCallsignAvailability(field,form,1,field.value);
 const request=JSON.parse(pending[0].request.body);assert.deepEqual(request,{publicToken:'p_owner',independentAccounts:true,names:['Taken']});assert.equal(new URL(pending[0].url).pathname,'/api/callsigns');
 pending[0].resolve({ok:true,json:async()=>({names:[{seat:0,name:'Taken',available:false}]})});await check;
 assert.equal(status.textContent,'Used online; offline is OK. Yours?');assert.equal(field['aria-invalid'],'true');assert.equal(field.disabled,false,'offline editing and play remain unrestricted');
 s.rememberPublicIdentity('');assert.equal(storage.has('leqra.publicToken'),false);
});
test('stale availability replies cannot replace feedback for a newer draft',async()=>{
 const {context:s,status,field,form,pending}=boot();field.callsignCheckRevision=1;
 const old=s.checkCallsignAvailability(field,form,1,'Taken');field.value='Free';field.callsignCheckRevision=2;
 const current=s.checkCallsignAvailability(field,form,2,'Free');
 pending[1].resolve({ok:true,json:async()=>({names:[{seat:0,name:'Free',available:true}]})});await current;
 pending[0].resolve({ok:true,json:async()=>({names:[{seat:0,name:'Taken',available:false}]})});await old;
 assert.equal(status.textContent,'');assert.equal(status.hidden,true);assert.equal(field['aria-invalid'],'false');
});
test('a saved fresh P2 key checks its legacy callsign as an eligible migration without allocating another key',async()=>{
 const {context:s,status,field,form,pending,storage}=boot(),candidate='p_'+Buffer.alloc(32,9).toString('base64url');
 storage.set('leqra.publicToken','p_owner');storage.set('leqra.localAccountRegistration',JSON.stringify({token:candidate}));s.roomMember=()=>({name:'Primary'});form.dataset.pilot='secondary';field.callsignCheckRevision=1;
 const before=[...storage],check=s.checkCallsignAvailability(field,form,1,field.value),request=JSON.parse(pending[0].request.body);
 assert.deepEqual(request,{publicToken:'p_owner',localPublicToken:candidate,localNewAccount:true,independentAccounts:true,names:['Primary','Taken']});
 pending[0].resolve({ok:true,json:async()=>({names:[{seat:0,name:'Primary',available:true},{seat:1,name:'Taken',available:true}]})});await check;
 assert.equal(status.hidden,true);assert.equal(field['aria-invalid'],'false');assert.deepEqual([...storage],before,'advisory editing preserves the pre-saved registration without minting a key');
});
test('a duplicate local callsign warns the edited primary as well as the co-pilot',async()=>{
 const {context:s,status,field,form,pending}=boot();s.secondaryMember=()=>({name:'TAKEN'});s.mode='online';field.callsignCheckRevision=1;
 const check=s.checkCallsignAvailability(field,form,1,'Taken');
 pending[0].resolve({ok:true,json:async()=>({names:[{seat:0,name:'Taken',available:true},{seat:1,name:'TAKEN',available:false}]})});await check;
 assert.equal(status.textContent,'Taken online. Yours?');assert.equal(field['aria-invalid'],'true');assert.equal(status.classList.error,true);
});
test('typing cancels pending availability and debounces the next request',()=>{
 const {context:s,field,form,timers}=boot();const first=new AbortController();field.callsignCheckController=first;
 s.scheduleCallsignAvailability(field,form);const timer=field.callsignCheckTimer;
 s.scheduleCallsignAvailability(field,form);assert.equal(first.signal.aborted,true);assert.equal(timers.has(timer),false);assert.equal(timers.size,1);assert.equal(field.callsignCheckRevision,2);
});


test('availability failures cannot overwrite an in-flight primary or Infinity name save',async()=>{
 for(const infinity of [false,true]){
  const {context:s,status,field,form,pending}=boot();field.callsignCheckRevision=1;
  const check=s.checkCallsignAvailability(field,form,1,'Taken');status.textContent='Saving…';
  if(infinity)form.infinityRenamePending={};else s.online.renamePending={form};
  pending[0].resolve({ok:false});await check;assert.equal(status.textContent,'Saving…');
 }
});

test('availability responses using a previous bearer cannot mark the new owner unavailable',async()=>{
 const {context:s,status,field,form,pending}=boot();field.callsignCheckRevision=1;
 const check=s.checkCallsignAvailability(field,form,1,'Taken');s.rememberPublicIdentity('p_new_owner');
 pending[0].resolve({ok:true,json:async()=>({names:[{seat:0,name:'Taken',available:false}]})});await check;
 assert.ok(!status.textContent.includes('Used online')&&!status.textContent.includes('Taken online'));assert.notEqual(field['aria-invalid'],'true');
});

test('identity handover and clearing override readable stale storage when writes are denied',()=>{
 const {context:s,storage}=boot();storage.set('leqra.publicToken','p_old_owner');
 s.localStorage.setItem=()=>{throw Error('storage writes denied');};s.localStorage.removeItem=()=>{throw Error('storage removal denied');};
 s.rememberPublicIdentity('p_new_owner');assert.equal(s.publicIdentityToken(),'p_new_owner');
 s.rememberPublicIdentity('');assert.equal(s.publicIdentityToken(),'');
});
