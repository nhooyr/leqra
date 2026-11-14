'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{webcrypto}=require('node:crypto'),{assetPath}=require('./web_assets.cjs');
function boot(storage=new Map(),protocol='https:'){
 class Element{
  children=[];hidden=false;attributes={};dataset={};value='';isConnected=true;events={};
  classList={toggle(){}};
  append(...children){this.children.push(...children);}replaceChildren(...children){this.children=children;this.textContent='';}
  setAttribute(k,v){this.attributes[k]=v;}addEventListener(k,f){this.events[k]=f;}
 }
 const status=new Element(),field=new Element(),form={dataset:{member:'1'},querySelector:()=>status},pending=[],applied=[],remembered=[],models=[];
 const window={addEventListener(){}},localStorage={getItem:k=>storage.get(k)??null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)};
 const context=vm.createContext({window,localStorage,crypto:webcrypto,Uint8Array,Map,URL,Promise,AbortController,setTimeout,clearTimeout,
  location:{origin:protocol==='file:'?'null':'https://example.test',href:protocol==='file:'?'file:///game/index.html':'https://example.test/',protocol},navigator:{onLine:true},
  btoa:s=>Buffer.from(s,'binary').toString('base64'),document:{getElementById:()=>status,createElement:()=>new Element(),createTextNode:text=>({textContent:text})},
  fetch(url,options){const body=JSON.parse(options.body);assert.ok(storage.get('leqra.publicToken')||body.accounts[0].seat===1,'key saved before fetch');return new Promise((resolve,reject)=>pending.push({body,resolve,reject}));}
 });
 vm.runInContext(readFileSync(assetPath('callsigns.js'),'utf8'),context);
 const api=window.leqraCallsigns;models.push(api.initial(0),api.initial(1));field.value=models[0];
 const token=seat=>seat===0?storage.get('leqra.publicToken')||'':storage.get('leqra.localPublicToken')||JSON.parse(storage.get('leqra.localAccountRegistration')||'null')?.token||'';
 const hooks={token,prepareLocal(){let value=token(1);if(!value){value='p_'+Buffer.from(webcrypto.getRandomValues(new Uint8Array(32))).toString('base64url');storage.set('leqra.localAccountRegistration',JSON.stringify({token:value}));}return{localPublicToken:value};},
  remember(value,expected,seat){remembered.push(seat);storage.set(seat?'leqra.localPublicToken':'leqra.publicToken',value);},openAccount(){},
  canApply(seat,draft,ctx){return ctx?ctx.field.value===ctx.draft:models[seat]===draft;},
  apply(seat,name,ctx){models[seat]=name;applied.push({seat,name});if(ctx)ctx.field.value=name;else if(seat===0)field.value=name;}
 };
 const answer=(request,name)=>request.resolve({ok:true,json:async()=>({names:[{seat:request.body.accounts[0].seat,name}]})});
 return {api,storage,field,form,status,pending,applied,remembered,models,hooks,answer,context};
}
const flush=()=>new Promise(resolve=>setImmediate(resolve));
test('fresh P1/P2 defaults are distinct, durable random names and saved choices survive reload',()=>{
 const h=boot();for(const name of h.models)assert.match(name,/^pilot#[A-HJ-NP-Z2-9]{6}$/);assert.notEqual(h.models[0],h.models[1]);
 assert.deepEqual(boot(h.storage).models,h.models);
 assert.deepEqual(boot(new Map([['leqra.name','RUST'],['leqra.local2Name','Godlike Bot 7']])).models,['RUST','Godlike Bot 7']);
 assert.deepEqual(boot(new Map([['ricochet.name','OLD FOX'],['ricochet.local2Name','OLD WING']])).models,['OLD FOX','OLD WING']);
});
test('offline repair handles transport failure without hiding credential or auth errors',async()=>{
 const h=boot(new Map([['leqra.name','Bot RUST'],['leqra.local2Name','WING']]));h.hooks.offline=()=>true;h.api.init(h.hooks);await flush();
 const request=h.api.generate(h.field,h.form);await flush();h.pending[0].reject(Error('Network unavailable'));await request;
 assert.match(h.field.value,/^pilot#[A-HJ-NP-Z2-9]{6}$/);assert.equal(h.api.isPending(0),true);
 const other=boot(new Map([['leqra.name','RUST'],['leqra.local2Name','Bot WING']]));other.hooks.offline=()=>true;other.hooks.prepareLocal=()=>{throw Error('Saved account registration is invalid');};other.api.init(other.hooks);await flush();
 other.form.dataset.pilot='secondary';other.field.value='Bot WING';await other.api.generate(other.field,other.form);
 assert.equal(other.field.value,'Bot WING');assert.match(other.status.children[0].textContent,/registration is invalid/);
});
test('only Bot-word prefixes are reserved, and public bot formats remain unchanged',()=>{
 const {api}=boot();for(const name of ['Bot RUST','bOt 7','Bot 7 - Godlike','B\u0301ot RUST','  BOT  0001  ','Bot'])assert.equal(api.reserved(name),true,name);
 for(const name of ['Botanist','RUST','Godlike Bot 7','GODLIKE 7','godlike-7','BOT\tPILOT'])assert.equal(api.reserved(name),false,name);
 assert.equal(api.botName('RUST',true),'Bot Rust');assert.equal(api.botName('RUST',false),'RUST');
 assert.equal(api.botName('Bot 7',true),'Bot 7');assert.equal(api.botName('Bot 7 - Godlike',true),'Bot 7 - Godlike');
 assert.equal(api.botName('Godlike Bot 7',true),'Bot Godlike Bot 7');assert.equal(api.botName('Godlike Bot 7',false),'Godlike Bot 7');
 assert.equal(api.botName('BOT RUST VAPOR',true),'Bot Rust Vapor');
});
test('startup claims independent names with saved keys and retains P2 first-game migration intent',async()=>{
 const h=boot();h.api.init(h.hooks);await flush();assert.equal(h.pending.length,2);
 const [p1,p2]=h.pending;assert.notEqual(p1.body.accounts[0].publicToken,p2.body.accounts[0].publicToken);
 const first=h.api.ensure();h.answer(p1,'pilot#AAAAAA');h.answer(p2,'pilot#BBBBBB');await first;
 assert.deepEqual(h.models,['pilot#AAAAAA','pilot#BBBBBB']);assert.deepEqual(h.remembered,[0]);
 assert.ok(h.storage.get('leqra.localAccountRegistration'));assert.equal(h.api.isPending(1),false);
});
test('legacy generated-name retries and saved choices remain readable beside room-code formatted names',async()=>{
 const h=boot();h.api.init(h.hooks);await flush();
 h.answer(h.pending[0],'pilot-aaaaaaaaaa');h.answer(h.pending[1],'pilot#BDF3XZ');await h.api.ensure();
 assert.deepEqual(h.models,['pilot-aaaaaaaaaa','pilot#BDF3XZ']);assert.deepEqual(boot(h.storage).models,h.models);
});
test('late auto replies cannot overwrite edits or an imported account, including after reopen',async()=>{
 const h=boot();h.api.init(h.hooks);await flush();h.api.cancelAuto(0);h.models[0]='Chosen';
 h.storage.set('leqra.localPublicToken','p_'+Buffer.alloc(32,7).toString('base64url'));h.models[1]='Imported';
 h.answer(h.pending[0],'pilot#AAAAAA');h.answer(h.pending[1],'pilot#BBBBBB');await flush();await flush();
 assert.deepEqual(h.models,['Chosen','Imported']);assert.equal(h.applied.length,0);
 const reloaded=boot(h.storage);reloaded.api.init(reloaded.hooks);await flush();assert.equal(reloaded.pending.length,0,'old pending owner cannot generate for the imported key');
});
test('failed request retries retain UUID and bearer; a manual generation uses a fresh UUID',async()=>{
 const h=boot();h.api.init(h.hooks);await flush();const first=h.pending[0],second=h.pending[1];
 first.reject(Error('Offline'));h.answer(second,'pilot#BBBBBB');await flush();await flush();
 const retry=h.api.ensure();await flush();const repeated=h.pending[2];assert.equal(repeated.body.requestId,first.body.requestId);assert.equal(repeated.body.accounts[0].publicToken,first.body.accounts[0].publicToken);
 h.answer(repeated,'pilot#AAAAAA');await retry;
 h.field.value='Taken';const manual=h.api.generate(h.field,h.form);await flush();const fresh=h.pending[3];assert.notEqual(fresh.body.requestId,first.body.requestId);
 h.answer(fresh,'pilot#CCCCCC');await manual;assert.equal(h.field.value,'pilot#CCCCCC');
});
test('taken feedback has three stable lines, reserved feedback has no misleading import action, offline generation works',async()=>{
 const h=boot(new Map(),'file:');h.api.init(h.hooks);await flush();
 h.api.status(h.field,h.form,'Taken',true);assert.equal(h.status.children[0].textContent,'Used online; offline is OK.');
 assert.equal(h.status.children[1].children[1].textContent,'Import account key');assert.equal(h.status.children[2].textContent,'Generate random?');
 h.api.status(h.field,h.form,'The Bot prefix is reserved for bots.',true,'reserved');assert.equal(h.status.children.length,2);
 h.field.value='Bot RUST';await h.api.generate(h.field,h.form);assert.match(h.field.value,/^pilot#[A-HJ-NP-Z2-9]{6}$/);assert.equal(h.pending.length,0);
});
