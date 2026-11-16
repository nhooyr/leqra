'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),{readFileSync}=require('node:fs'),{webcrypto}=require('node:crypto'),{assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
function declaration(name){let start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);if(source.slice(start-6,start)==='async ')start-=6;const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
const old='p_'+'A'.repeat(43),saved='p_'+'B'.repeat(43),flush=()=>new Promise(setImmediate);
function boot(existing){
 const storage=existing||new Map([['leqra.publicToken',old],['leqra.name','Alpha']]),requests=[],player={id:0,name:'Alpha'},elements=new Map();
 const s={URL,AbortController,Uint8Array,crypto:webcrypto,btoa,Array,MAX_TANKS:8,mode:'online',phase:'playing',gameStarted:true,scores:[17],online:{connected:true},localRoom:{self:0,players:[player]},navigator:{onLine:true},window:{leqraInfinity:{close(){s.closed=true;}}},location:{protocol:'https:',href:'https://game.test/'},accountImportAllowed:()=>s.mode==='room'&&!s.online.connected,accountSeat:()=>0,syncAccountImport(){},accountNotice(id,text){s.notice=text;},pendingAccountKeys:()=>[],renderSavedCallsignAccounts(){},confirmGameAction:async options=>{s.confirmation=options;return s.confirm!==false;},
  localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},setTimeout,clearTimeout,fetch(url,options){requests.push({url:String(url),body:JSON.parse(options.body)});return new Promise((resolve,reject)=>Object.assign(requests.at(-1),{resolve,reject}));},
  cleanPilotName:n=>n.trim(),generatedCallsign:()=>player.name,secondaryMember:()=>null,rememberCallsign:name=>{player.name=name;storage.set('leqra.name',name);},rememberLocalCallsign(){},persistLocalRoomRules(){},readyRoom(){s.phase='menu';},syncCallsignEditors(){},renderOnlineRoom(){},updateHUD(){},leaveOnline(){s.left=true;s.mode='room';s.online.connected=false;},$:id=>{if(!elements.has(id))elements.set(id,{replaceChildren(){},classList:{toggle(){}}});return elements.get(id);}};
 vm.createContext(s);for(const name of ['publicIdentityToken','rememberPublicIdentity','localAccountRegistrationPending','accountKeyValid','fetchAccountInfo','accountNameKey','savedCallsignAccounts','saveCallsignAccount','forgetSavedCallsignAccount','boundCallsignName','rememberCurrentCallsignAccount','newCallsignAccount','claimCallsignAccount','adoptCallsignAccount','selectCallsignAccount','ensureSelectedCallsignAccounts','clearReleasedAccountReferences','freshReleasedSeat','releaseCallsignAccount'])vm.runInContext(declaration(name),s);
 const answer=(request,status,names,score=0)=>request.resolve({ok:status===200,status,json:async()=>({names,publicProfile:{name:names[0],score},message:'Callsign unavailable'})});return{s,storage,requests,player,answer};
}
test('new names stage a durable fresh key and only replace the old account after successful claim',async()=>{
 const h=boot(),p=h.s.selectCallsignAccount(0,'Bravo');await flush();const r=h.requests[0];assert.equal(new URL(r.url).pathname,'/api/account/create');assert.notEqual(r.body.publicToken,old);assert.equal(JSON.parse(h.storage.get('leqra.accountSwitch.0')).token,r.body.publicToken);assert.equal(h.s.publicIdentityToken(),old);assert.equal(h.s.left,undefined);
 h.answer(r,200,['Bravo']);await p;assert.equal(h.s.publicIdentityToken(),r.body.publicToken);assert.equal(h.player.name,'Bravo');assert.equal(h.s.left,true);assert.deepEqual([...h.s.scores],Array(8).fill(0));assert.equal(h.s.savedCallsignAccounts().find(a=>a.name==='Alpha').token,old);
});
test('denied new name and stale success keep the prior key, name and live match',async()=>{
 for(const stale of [false,true]){const h=boot();let current=true;const p=h.s.selectCallsignAccount(0,'Bravo','Alpha',()=>current);await flush();current=!stale;h.answer(h.requests[0],stale?200:409,['Bravo']);await assert.rejects(p);assert.equal(h.s.publicIdentityToken(),old);assert.equal(h.player.name,'Alpha');assert.equal(h.s.left,undefined);}
});
test('typing a saved callsign signs in with its stored key and keeps its own score',async()=>{
 const h=boot();h.s.saveCallsignAccount('Bravo',saved);const p=h.s.selectCallsignAccount(0,'Bravo');await flush();assert.deepEqual(h.requests[0].body,{publicToken:saved,signIn:true});h.answer(h.requests[0],200,['Bravo'],29);await p;assert.equal(h.s.publicIdentityToken(),saved);assert.equal(h.requests.length,1);assert.equal(h.s.savedCallsignAccounts().find(a=>a.name==='Alpha').token,old);
});
test('expired saved account uses a new key only after the callsign is successfully reclaimed',async()=>{
 const h=boot();h.s.saveCallsignAccount('Bravo',saved);const p=h.s.selectCallsignAccount(0,'Bravo');await flush();h.answer(h.requests[0],401,['Bravo']);await flush();assert.equal(h.requests.length,2);assert.notEqual(h.requests[1].body.publicToken,saved);h.answer(h.requests[1],200,['Bravo']);await p;assert.equal(h.s.publicIdentityToken(),h.requests[1].body.publicToken);
});
test('same callsign is a no-op and offline new names retain a pending fresh account for later claim',async()=>{
 const h=boot();await h.s.selectCallsignAccount(0,'ALPHA');assert.equal(h.requests.length,0);assert.equal(h.s.publicIdentityToken(),old);h.s.navigator.onLine=false;await h.s.selectCallsignAccount(0,'Bravo');assert.notEqual(h.s.publicIdentityToken(),old);assert.equal(h.s.savedCallsignAccounts().find(a=>a.name==='Bravo').pending,true);h.s.navigator.onLine=true;const p=h.s.ensureSelectedCallsignAccounts([0]);await flush();h.answer(h.requests[0],200,['Bravo']);await p;assert.equal(h.s.savedCallsignAccounts().find(a=>a.name==='Bravo').pending,false);
});

test('pending account retries reuse the durable key after failure and reload',async()=>{
 const h=boot();let attempt=h.s.selectCallsignAccount(0,'Bravo');await flush();const candidate=h.requests[0].body.publicToken;h.requests[0].reject(Error('Lost response'));await assert.rejects(attempt);
 const reloaded=boot(h.storage);attempt=reloaded.s.selectCallsignAccount(0,'Bravo');await flush();assert.equal(reloaded.requests[0].body.publicToken,candidate);reloaded.answer(reloaded.requests[0],200,['Bravo']);await attempt;assert.equal(reloaded.s.publicIdentityToken(),candidate);assert.equal(reloaded.s.savedCallsignAccounts().find(a=>a.name==='Alpha').token,old);
 const anotherOrigin=boot();assert.equal(anotherOrigin.s.savedCallsignAccounts().some(a=>a.name==='Bravo'),false,'browser-origin storage isolates the account history');
});
test('an offline pending saved account is claimed using its same key before selection',async()=>{
 const h=boot();h.s.saveCallsignAccount('Bravo',saved,true);const p=h.s.selectCallsignAccount(0,'Bravo');await flush();assert.equal(new URL(h.requests[0].url).pathname,'/api/account/create');assert.equal(h.requests[0].body.publicToken,saved);h.answer(h.requests[0],200,['Bravo']);await p;assert.equal(h.s.publicIdentityToken(),saved);
});

test('starting online checks only the participating saved accounts and replaces expired keys',async()=>{
 const h=boot();h.s.saveCallsignAccount('Alpha',old);h.s.saveCallsignAccount('Bravo',saved);h.storage.set('leqra.localPublicToken',saved);const p=h.s.ensureSelectedCallsignAccounts([0]);await flush();assert.deepEqual(h.requests[0].body,{publicToken:old,signIn:true});h.answer(h.requests[0],401,['Alpha']);await flush();assert.equal(h.requests.length,2);assert.notEqual(h.requests[1].body.publicToken,old);h.answer(h.requests[1],200,['Alpha']);await p;assert.equal(h.s.publicIdentityToken(),h.requests[1].body.publicToken);assert.equal(h.s.savedCallsignAccounts().some(a=>a.token===old),false);assert.equal(h.s.publicIdentityToken(1),saved);
});

test('releasing a saved callsign confirms deletion, then removes only its key after server acknowledgement',async()=>{
 const h=boot();h.s.mode='room';h.s.online.connected=false;h.s.saveCallsignAccount('Bravo',saved);const p=h.s.releaseCallsignAccount(saved,'Bravo');await flush();assert.match(h.s.confirmation.message,/permanently deletes Bravo’s score/);assert.equal(new URL(h.requests[0].url).pathname,'/api/account/release');assert.deepEqual(h.requests[0].body,{publicToken:saved});assert.equal(h.s.savedCallsignAccounts().length,1);
 h.requests[0].resolve({ok:true,json:async()=>({released:true})});assert.equal(await p,true);assert.equal(h.s.savedCallsignAccounts().length,0);assert.equal(h.s.publicIdentityToken(),old);assert.equal(h.player.name,'Alpha');
});
test('release cancellation and backend failure preserve credentials and current identity',async()=>{
 const h=boot();h.s.mode='room';h.s.online.connected=false;h.s.saveCallsignAccount('Alpha',old);h.s.confirm=false;assert.equal(await h.s.releaseCallsignAccount(old,'Alpha'),false);assert.equal(h.requests.length,0);h.s.confirm=true;const p=h.s.releaseCallsignAccount(old,'Alpha');await flush();h.requests[0].resolve({ok:false,status:503,json:async()=>({})});assert.equal(await p,false);assert.equal(h.s.publicIdentityToken(),old);assert.equal(h.player.name,'Alpha');assert.equal(h.s.savedCallsignAccounts()[0].token,old);
});
test('releasing the current account gives only that seat a fresh local name and clears matching pending references',async()=>{
 const h=boot();h.s.mode='room';h.s.online.connected=false;h.storage.set('leqra.localPublicToken',saved);h.s.saveCallsignAccount('Alpha',old);h.s.saveCallsignAccount('Bravo',saved);h.storage.set('leqra.accountSwitch.0',JSON.stringify({token:old,previous:saved}));h.storage.set('leqra.autoCallsign.0',JSON.stringify({owner:old,name:'Alpha'}));const p=h.s.releaseCallsignAccount(old,'Alpha');await flush();h.requests[0].resolve({ok:true,json:async()=>({released:true})});assert.equal(await p,true);assert.equal(h.s.publicIdentityToken(),'');assert.match(h.player.name,/^pilot#/);assert.equal(h.s.publicIdentityToken(1),saved);assert.equal(h.s.savedCallsignAccounts().length,1);assert.equal(h.storage.has('leqra.accountSwitch.0'),false);assert.equal(h.storage.has('leqra.autoCallsign.0'),false);
});

test('released current account can play again with a new durable key, while other recovery candidates survive',async()=>{
 const h=boot();h.s.mode='room';h.s.online.connected=false;h.s.saveCallsignAccount('Alpha',old);h.storage.set('leqra.accountSwitch.0',JSON.stringify({token:saved,previous:old,name:'Bravo'}));
 const p=h.s.releaseCallsignAccount(old,'Alpha');await flush();h.requests[0].resolve({ok:true,json:async()=>({released:true})});await p;assert.equal(h.s.savedCallsignAccounts().find(a=>a.name==='Bravo').token,saved);
 const play=h.s.ensureSelectedCallsignAccounts([0]);await flush();const request=h.requests[1];assert.equal(new URL(request.url).pathname,'/api/account/create');assert.notEqual(request.body.publicToken,old);assert.equal(JSON.parse(h.storage.get('leqra.accountSwitch.0')).token,request.body.publicToken);h.answer(request,200,[request.body.name]);await play;assert.equal(h.s.publicIdentityToken(),request.body.publicToken);
});
