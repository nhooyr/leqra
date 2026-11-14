(() => {
'use strict';
const names=['leqra.name','leqra.local2Name'], pending=['leqra.autoCallsign.0','leqra.autoCallsign.1'];
const memory=new Map(), requests=new Map(),botLabels=new Map();
let hooks,editRevision=0;
function read(key){try{return localStorage.getItem(key)??memory.get(key)??null;}catch(_){return memory.get(key)??null;}}
function write(key,value){memory.set(key,value);try{localStorage.setItem(key,value);}catch(_){} }
function remove(key){memory.delete(key);try{localStorage.removeItem(key);}catch(_){} }
function uuid(){
 const b=crypto.getRandomValues(new Uint8Array(16));b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;
 const h=Array.from(b,n=>n.toString(16).padStart(2,'0')).join('');return h.slice(0,8)+'-'+h.slice(8,12)+'-'+h.slice(12,16)+'-'+h.slice(16,20)+'-'+h.slice(20);
}
function randomName(seat){const alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';let name;do{name='pilot#'+Array.from(crypto.getRandomValues(new Uint8Array(6)),n=>alphabet[n&31]).join('');}while(name===read(names[seat===1?0:1]));return name;}
function reserved(name){
 // Apply the same Unicode cleanup as the server before checking the namespace.
 const clean=[...String(name).trim()].filter(c=>/[\p{L}\p{Nd} #_-]/u.test(c)).slice(0,16).join('').replace(/ +/g,' ').trim();
 return /^bot(?: |$)/i.test(clean);
}
function botName(name,bot){
 if(!bot)return name;if(botLabels.has(name))return botLabels.get(name);
 const label=/^Bot [0-9]+(?: - Godlike)?$/.test(name)?name:'Bot'+String(name).replace(/^bot(?:\s+|$)/i,'').trim().toLowerCase().split(/\s+/u).filter(Boolean).map(word=>' '+[...word][0].toUpperCase()+[...word].slice(1).join('')).join('');
 botLabels.set(name,label);if(botLabels.size>128)botLabels.delete(botLabels.keys().next().value);return label;
}
function record(seat){try{const value=JSON.parse(read(pending[seat])||'null');return value&&typeof value.name==='string'&&typeof value.requestId==='string'&&/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value.requestId)&&(!value.owner||/^p_[A-Za-z0-9_-]{43}$/.test(value.owner))?value:null;}catch(_){return null;}}
function initial(seat){
 const saved=read(names[seat])?.trim();if(saved)return saved;
 const legacy=read(seat?'ricochet.local2Name':'ricochet.name')?.trim();if(legacy){write(names[seat],legacy);return legacy;}
 const name=randomName(seat);write(names[seat],name);write(pending[seat],JSON.stringify({name,requestId:uuid(),auto:true}));return name;
}
// Generate local names before game.js creates the ready room, including offline launches.
initial(0);initial(1);
function prepare(seat){
 if(seat===1)return hooks.prepareLocal().localPublicToken;
 let token=hooks.token(0);if(token)return token;
 const bytes=crypto.getRandomValues(new Uint8Array(32));token='p_'+btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
 // A credential must survive a failed response or a crash before it can own a name.
 localStorage.setItem('leqra.publicToken',token);
 if(localStorage.getItem('leqra.publicToken')!==token)throw Error('Enable browser storage before generating an online callsign.');
 return token;
}
function isPending(seat){return !!record(seat);}
async function request(seat,value,context){
 const old=requests.get(seat);if(old&&old.id===value.requestId)return old.promise;
 const selected=hooks.token(seat);
 if(value.owner&&value.owner!==selected){if(record(seat)?.requestId===value.requestId)remove(pending[seat]);return null;}
 const token=prepare(seat),origin=location.origin,controller=new AbortController();
 value={...value,owner:token};const saved=JSON.stringify(value);write(pending[seat],saved);
 if(localStorage.getItem(pending[seat])!==saved)throw Error('The name request could not be saved. Enable browser storage before going online.');
 const timeout=setTimeout(()=>controller.abort(),6000);
 const promise=(async()=>{
  const response=await fetch(new URL('/api/callsigns/generate',location.href),{
   method:'POST',headers:{'Content-Type':'application/json'},cache:'no-store',redirect:'error',signal:controller.signal,
   body:JSON.stringify({requestId:value.requestId,accounts:[{seat,publicToken:token}]})
  }).catch(error=>{error.generationNetworkFailure=true;throw error;});
  const data=await response.json();
  if(!response.ok){const error=Error(data.message||'Could not generate a callsign. Try again.');error.status=response.status;error.code=data.code;throw error;}
  const rows=data.names,name=rows?.[0]?.name;
  if(!Array.isArray(rows)||rows.length!==1||rows[0].seat!==seat||typeof name!=='string'||!/^pilot#[A-HJ-NP-Z2-9]{6}$/.test(name)&&!/^pilot-[a-z2-7]{10}$/.test(name))throw Error('Unexpected generated callsign. Try again.');
  const current=record(seat);
  if(location.origin!==origin||hooks.token(seat)!==token||current?.requestId!==value.requestId)return null;
  // P2 keeps its durable first-game migration intent until a welcome confirms it.
  if(seat===0)hooks.remember(token,token,seat);
  remove(pending[seat]);
  if(!current.suppressed&&hooks.canApply(seat,value.name,context)){
   write(names[seat],name);hooks.apply(seat,name,context);
  }
  return name;
 })();
 requests.set(seat,{id:value.requestId,promise});
 try{return await promise;}finally{clearTimeout(timeout);if(requests.get(seat)?.promise===promise)requests.delete(seat);}
}
async function ensure(){
 if(!hooks||!['http:','https:'].includes(location.protocol))return;
 await Promise.all([0,1].map(seat=>{const value=record(seat);return value?request(seat,value):null;}));
}
function cancelAuto(seat){editRevision++;const value=record(seat);if(value?.auto){value.suppressed=true;write(pending[seat],JSON.stringify(value));}}
async function generate(field,form){
 editRevision++;
 const seat=form?.dataset.pilot==='secondary'?1:0;
 const previous=record(seat),value=previous&&!previous.auto&&previous.name===field.value&&(!previous.owner||previous.owner===hooks.token(seat))?previous:{name:field.value,requestId:uuid(),auto:false};write(pending[seat],JSON.stringify(value));
 const context={field,form,draft:field.value,member:form?.dataset.member};status(field,form,'Generating a random callsign…');
 if(!['http:','https:'].includes(location.protocol)||typeof navigator!=='undefined'&&navigator.onLine===false){
  const name=randomName(seat);write(names[seat],name);write(pending[seat],JSON.stringify({name,requestId:value.requestId,auto:true}));
  if(hooks.canApply(seat,value.name,context))hooks.apply(seat,name,context);
  status(field,form,'Generated locally; checked when online.');return;
 }
 try{await request(seat,value,context);}catch(error){
  if(record(seat)?.requestId!==value.requestId||field.value!==context.draft)return;
  if(hooks.offline?.()&&(error.generationNetworkFailure||error.status>=500)){
   const name=randomName(seat);write(names[seat],name);write(pending[seat],JSON.stringify({...record(seat),name,auto:true}));
   if(hooks.canApply(seat,value.name,context))hooks.apply(seat,name,context);
   status(field,form,'Generated locally; checked when online.');
  }else status(field,form,error.name==='AbortError'?'Generation timed out. Try again.':error.message,true,'generate');
 }
}
function status(field,form,text,error=false,kind='taken'){
 const node=form?.querySelector('.callsign-status')||document.getElementById('pilotNameStatus');
 if(!node)return;node.replaceChildren();node.classList.toggle('error',error);field.setAttribute('aria-invalid',String(error));
 if(error&&kind==='taken'){
  const line=document.createElement('span');line.textContent='Used online; offline is OK.';node.append(line);
  const yours=document.createElement('span');yours.append(document.createTextNode('Yours? '));
  const action=document.createElement('button');action.type='button';action.className='callsign-account-action';action.textContent='Import account key';action.onclick=()=>hooks.openAccount(form?.dataset.pilot==='secondary'?1:0);yours.append(action);node.append(yours);
 }else if(text){const line=document.createElement('span');line.textContent=text;node.append(line);}
 if(error&&(kind==='taken'||kind==='reserved'||kind==='generate')){
  const action=document.createElement('button');action.type='button';action.className='callsign-account-action callsign-random-action';action.textContent='Generate random?';
  action.addEventListener('pointerdown',event=>event.preventDefault());action.onclick=()=>generate(field,form);node.append(action);
 }
 node.hidden=!text;
}
window.leqraCallsigns=Object.freeze({initial,reserved,botName,isPending,cancelAuto,ensure,generate,status,revision:()=>editRevision,
 init(value){hooks=value;Promise.resolve().then(ensure).catch(()=>{});window.addEventListener('online',()=>ensure().catch(()=>{}));}
});
})();
