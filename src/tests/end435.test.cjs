'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const identityFixture=require('./identity_fixture.cjs');
const source=readFileSync(assetPath('game.js'),'utf8'),css=readFileSync(assetPath('style.css'),'utf8');
function declaration(name){let start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);if(source.slice(start-6,start)==='async ')start-=6;const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const elements=new Map(),timers=new Map(),wire=[],events=[];let doc,serial=0;
 class Element{
  constructor(tag='div'){this.tagName=tag.toUpperCase();this.children=[];this.listeners=new Map();this.dataset={};this.attributes={};this.style={removeProperty(){}};this.classList={toggle(){},add(){},remove(){}};this.open=false;this.hidden=false;this.disabled=false;this.value='';this.textContent='';this.isConnected=true;}
  set id(v){this._id=v;elements.set(v,this);}get id(){return this._id;}
  append(...nodes){for(const node of nodes){node.parentElement=this;this.children.push(node);}}
  setAttribute(k,v){this.attributes[k]=v;}
  querySelector(selector){if(selector==='label')return this.label||null;if(selector==='button')return this.children.find(n=>n.tagName==='BUTTON')||null;if(selector==='.callsign-status')return this.status||null;return null;}
  addEventListener(name,handler){if(!this.listeners.has(name))this.listeners.set(name,[]);this.listeners.get(name).push(handler);}
  dispatch(name,properties={}){const e={type:name,target:this,preventDefault(){this.defaultPrevented=true;},...properties};for(const handler of this.listeners.get(name)||[])handler(e);return e;}
  showModal(){this.open=true;this.shows=(this.shows||0)+1;}
  close(){this.open=false;this.dispatch('close');}
  focus(){const prior=doc.activeElement;doc.activeElement=this;if(prior&&prior!==this)prior.dispatch('blur',{relatedTarget:this});}
  blur(){const prior=doc.activeElement;doc.activeElement=null;if(prior===this)this.dispatch('blur',{relatedTarget:null});}
  closest(){for(let n=this;n;n=n.parentElement)if(n.hidden)return n;return null;}
 }
 doc={body:new Element('body'),documentElement:new Element('html'),createElement:tag=>new Element(tag),activeElement:null,querySelectorAll:selector=>[...elements.values()].filter(e=>selector==='dialog[open]'&&e.tagName==='DIALOG'&&e.open),querySelector:selector=>doc.querySelectorAll(selector)[0]||null};
 const $=id=>elements.get(id)||null,add=(id,tag='div')=>{const e=new Element(tag);e.id=id;doc.body.append(e);return e;};
 for(const id of ['returnRoomBtn','endInfinityBtn','leaveMatchBtn','pilotName','roomBtn','bestInline','barHint','announcer','onlineMenuMessage','infiniteArena'])add(id,id.endsWith('Btn')?'button':'input');
 const players=[{id:0,member:101,name:'HOST',kind:'human'},{id:1,member:102,name:'PLAYER 2',kind:'local',owner:0}];
 for(const id of ['roomCallsignForm','menuCallsignForm','roomP2CallsignForm','menuP2CallsignForm','infiniteCallsignForm','infiniteP2CallsignForm']){
  const form=add(id,'form');if(id.includes('P2'))form.dataset.pilot='secondary';if(id.startsWith('infinite'))form.dataset.arena='infinity';form.elements={callsign:new Element('input')};form.label=new Element('label');form.append(form.label);form.status=new Element('p');form.status.hidden=true;form.append(form.elements.callsign,form.status);
 }
 const socket={readyState:1,bufferedAmount:0,send(data){if(s.sendFails)throw Error('closed');wire.push(JSON.parse(data));events.push('send:'+JSON.parse(data).type);},close(){events.push('close');this.readyState=3;}};
 const s={console,Promise,WebSocket:{OPEN:1},mode:'online',phase:'playing',pendingGameConfirmation:null,pendingMatchPresentation:null,localMatchReport:null,localObjectives:null,localMatchStats:{},localRoom:{self:0,players},
  online:{socket,code:'ROOM',member:101,id:0,generation:2,connected:true,menu:true,roomData:{host:0,phase:'playing',players},renamePending:null,endMatchPending:null},
  document:doc,window:{},$,setTimeout(fn){const id=++serial;timers.set(id,fn);return id;},clearTimeout(id){timers.delete(id);},
  roomData:()=>s.online.roomData,roomMember:id=>s.online.roomData?.players.find(p=>p.id===id),localPlayerID:()=>s.online.id,secondaryMember:()=>s.online.roomData?.players.find(p=>p.kind==='local'),cleanPilotName:n=>String(n).trim().replace(/[^\w -]/g,'').slice(0,16),
  rememberCallsign(name){$('pilotName').value=name;},rememberLocalCallsign(name){s.savedLocalName=name;},persistLocalRoomRules(){s.persistedNames=players.map(p=>p.name);},initAudio(){},updateHUD(){},syncPauseButton(){},renderOnlineRoom(){s.syncCallsignEditors();s.syncEndMatchAction();},
  clearInput(){},sendOnlineInput(){},toast(message){s.notice=message;},performance:{now:()=>1000},closeVictory(){s.pendingMatchPresentation=null;},setScreen(){},
  clearRestartWavePending(){},resetMatchmaking(){},closeChat(){},clearRoomChat(){},cancelSwap(){},resetWatchDialog(){},cancelKick(){},resetOnlineMotion(){},forgetOnlineSession(){},createLocalRoom(){s.createdLocal=(s.createdLocal||0)+1;},
  readyRoom(){s.ready=true;},leaveOnline(){s.left=(s.left||0)+1;s.mode='room';}
 };
 vm.createContext(s);identityFixture(s,source);
 for(const name of ['sendOnline','callsignForms','editorPilot','callsignStatus','syncCallsignEditors','cancelCallsignSave','submitCallsign','acceptCallsign','captureOnlineRoomActionScope','syncEndMatchAction','clearEndMatchPending','finishGameConfirmation','confirmGameAction','leaveOnlineMatch','returnToRoom','queueMatchPresentation','flushMatchPresentation'])vm.runInContext(declaration(name),s);
 // Execute the actual callsign event bindings, including the blur autosave.
 const bindings=source.split('\n').find(line=>line.includes("for(const form of callsignForms())")&&line.includes("field.addEventListener('blur'"));assert.ok(bindings);vm.runInContext(bindings,s);
 s.syncCallsignEditors();
 const accept=()=>{$('actionConfirmAccept').onclick();},begin=name=>{let pending;const button=$(name==='returnToRoom'?'returnRoomBtn':'leaveMatchBtn');button.addEventListener('click',()=>{pending=s[name]();});button.focus();button.dispatch('click');return pending;};
 return{s,$,timers,wire,events,socket,players,begin,accept,load:name=>vm.runInContext(declaration(name),s)};
}

test('callsign labels and inputs use actual room paint for an automatic P2 beyond the second seat',()=>{
 for(const mode of ['room','online']){
  const b=boot(),s=b.s,local=b.players[1];s.mode=mode;s.MAX_TANKS=8;s.online.roomData.rules={teamMode:'ffa'};s.currentRules=()=>s.online.roomData.rules;local.id=4;
  vm.runInContext(['COLORS','colorIndex','teamColor'].map(name=>source.match(new RegExp('^const '+name+'=.*$','m'))[0]).join('\n')+'\nthis.teamColor=teamColor;',s);
  for(const [patch,color]of [[{colorIndex:undefined},'#ffc46b'],[{colorIndex:6},'#75f0cb'],[{id:8,colorIndex:-1,spectating:true,spectatorColor:'#ffc46b'},'#ffc46b']]){
   Object.assign(local,patch);s.syncCallsignEditors();
   for(const id of ['roomP2CallsignForm','menuP2CallsignForm']){
    const form=b.$(id);assert.ok(form.label.innerHTML.includes('color:'+color),mode+' '+id+' '+JSON.stringify(patch)+' '+form.label.innerHTML);assert.equal(form.elements.callsign.style.color,color,mode+' '+id);
   }
  }
 }
});

test('callsign editors show colored names and local suffixes without modifying fields or saved identities',()=>{
 const b=boot();b.players[0].name='YOU';b.players[0].color='#0abcde';b.players[1].name='WING';b.players[1].color='#fba000';b.s.syncCallsignEditors();
 for(const [id,name,color]of [['roomCallsignForm','YOU (P1)','#0abcde'],['menuCallsignForm','YOU (P1)','#0abcde'],['roomP2CallsignForm','WING (P2)','#fba000'],['menuP2CallsignForm','WING (P2)','#fba000']]){
  const form=b.$(id);assert.ok(form.label.innerHTML.includes(name));assert.ok(form.label.innerHTML.includes('color:'+color));
  assert.equal(form.elements.callsign.style.color,color);assert.equal(form.attributes['aria-label'],'Change '+name+' callsign');
 }
 const primary=b.$('roomCallsignForm');primary.elements.callsign.value='UNSAVED NAME';b.s.syncCallsignEditors();assert.equal(primary.elements.callsign.value,'UNSAVED NAME');assert.equal(b.players[0].name,'YOU');
 b.players.splice(1,1);b.s.syncCallsignEditors();assert.equal(b.$('roomP2CallsignForm').hidden,true);assert.ok(primary.label.innerHTML.includes('YOU (P1)'));assert.equal(b.players[0].name,'YOU');
});

test('Infinity pause editors use both active tanks and preserve newer drafts through confirmed saves',async()=>{
 const {s,$,players,wire,load}=boot(),calls=[],pilots=[{id:71,member:'infinity-1-0',name:'STAR',color:'#123456'},{id:72,member:'infinity-1-1',name:'WING',color:'#abcdef'}];let confirm;
 s.mode='room';s.online.connected=false;load('persistInfinityPilotName');
 s.window.leqraInfinity={localPilots:()=>pilots,renamePilot(index,name){calls.push([index,name]);return new Promise(resolve=>{confirm=canonical=>{pilots[index].name=canonical;s.persistInfinityPilotName(index,canonical);s.syncCallsignEditors();resolve(canonical);};});}};
 $('infiniteArena').open=true;s.syncCallsignEditors();
 for(const [id,name,color]of [['infiniteCallsignForm','STAR (P1)','#123456'],['infiniteP2CallsignForm','WING (P2)','#abcdef']]){
  const form=$(id);assert.equal(form.hidden,false);assert.equal(form.elements.callsign.disabled,false);assert.ok(form.label.innerHTML.includes(name));assert.ok(form.label.innerHTML.includes('local-pilot'));assert.equal(form.elements.callsign.style.color,color);
 }
 const form=$('infiniteP2CallsignForm'),field=form.elements.callsign;field.focus();field.value='NEW WING';form.dispatch('submit');
 assert.equal(form.status.textContent,'Saving…');form.dispatch('submit');await Promise.resolve();assert.deepEqual(calls,[[1,'NEW WING']]);
 field.value='NEXT DRAFT';confirm('NEW WING');await new Promise(setImmediate);
 assert.equal(field.value,'NEXT DRAFT');assert.equal(form.dataset.currentName,'NEW WING');assert.equal(form.status.textContent,'Saved.');assert.equal(s.document.activeElement,field);
 assert.equal(players[1].name,'NEW WING','source room follows the local role, not arena id 72');assert.equal(players[0].name,'HOST');assert.equal(wire.length,0,'Infinity owns its transport');assert.equal(s.savedLocalName,'NEW WING');assert.deepEqual(s.persistedNames,['HOST','NEW WING']);
 pilots.splice(1,1);s.syncCallsignEditors();assert.equal(form.hidden,true);assert.equal($('infiniteCallsignForm').hidden,false);
});

test('Infinity callsign errors and stale sessions cannot overwrite another session or its draft',async()=>{
 const {s,$}=boot();let pilots=[{id:71,member:'infinity-1-0',name:'STAR',color:'#123456'}],reject;
 s.window.leqraInfinity={localPilots:()=>pilots,renamePilot(){return new Promise((resolve,no)=>{reject=no;});}};
 $('infiniteArena').open=true;s.syncCallsignEditors();const form=$('infiniteCallsignForm'),field=form.elements.callsign;
 field.value='DRAFT';s.submitCallsign(form);await Promise.resolve();reject(Error('Reconnect before changing the callsign.'));await new Promise(setImmediate);
 assert.equal(field.value,'DRAFT');assert.match(form.status.textContent,/Reconnect/);assert.equal(form.infinityRenamePending,undefined);
 s.submitCallsign(form);await Promise.resolve();pilots=[{id:71,member:'infinity-2-0',name:'NEW SESSION',color:'#abcdef'}];s.syncCallsignEditors();reject(Error('Old connection closed.'));await new Promise(setImmediate);
 assert.equal(field.value,'NEW SESSION');assert.equal(form.dataset.currentName,'NEW SESSION');assert.equal(form.status.textContent,'');
 $('infiniteArena').open=false;s.syncCallsignEditors();assert.equal(form.hidden,true);assert.equal($('menuCallsignForm').elements.callsign.value,'HOST');
});

test('first End/Leave click survives callsign blur, save acknowledgement and a round transition',async()=>{
 for(const action of ['returnToRoom','leaveOnlineMatch'])for(const secondary of [false,true]){
  const b=boot(),{s,$,wire,begin,accept,players}=b,form=$(secondary?'menuP2CallsignForm':'menuCallsignForm'),player=players[secondary?1:0];
  form.elements.callsign.focus();form.elements.callsign.value='RENAMED PILOT';
  const pending=begin(action);
  assert.equal(wire.length,1);assert.equal(wire[0].type,secondary?'rename_local':'rename');assert.equal(form.status.textContent,'Saving…');assert.equal($('actionConfirmDialog').shows,1);
  s.acceptCallsign({id:player.id,member:player.member,name:'RENAMED PILOT'});
  s.online.roomData={...s.online.roomData,players:players.map(p=>({...p}))};s.renderOnlineRoom();
  assert.equal(form.status.textContent,'Saved.');assert.equal($('actionConfirmDialog').open,true);
  s.phase='roundOver';s.phase='countdown';s.online.generation++;s.online.roomData.phase='countdown';
  accept();await pending;
  if(action==='returnToRoom'){assert.equal(wire.filter(p=>p.type==='lobby').length,1);assert.ok(s.online.endMatchPending);assert.equal($('returnRoomBtn').disabled,true);}
  else assert.equal(s.left,1);
 }
});

test('blur autosave feedback keeps space reserved above match menu actions',()=>{
 assert.match(css,/body #onlineMenuScreen \.callsign-status\{min-height:1\.4em\}/);
 assert.match(css,/body #onlineMenuScreen \.callsign-status\[hidden\]\{display:block!important;visibility:hidden\}/);
 assert.match(css,/#infinitePauseMenu \.callsign-status\{min-height:1\.4em\}/);
 assert.match(css,/--callsign-form-gap:11px;--callsign-label-gap:6px;--callsign-input-height:38px;--callsign-input-pad-y:8px;--callsign-input-pad-x:10px;--callsign-feedback-gap:3px/);
 assert.match(css,/body\.touch-ui\{--callsign-form-gap:9px;--callsign-input-pad-y:7px;--callsign-input-pad-x:9px\}/);
 assert.match(css,/body\.touch-landscape\{--callsign-input-height:35px;--callsign-input-pad-x:10px\}/,'pause inputs adopt the existing compact startup dimensions in landscape');
 assert.match(css,/body :is\(#onlineMenuScreen,#infinitePauseMenu\) \.callsign-editor\{margin:0 0 max\(0px,calc\(var\(--callsign-form-gap\) - 9px\)\)\}/);
 assert.match(css,/body :is\(#onlineMenuScreen,#infinitePauseMenu\) \.secondary-callsign\{padding-top:0\}/);
 assert.match(css,/\.callsign-row \.net-input\{min-height:var\(--callsign-input-height\);padding:var\(--callsign-input-pad-y\) var\(--callsign-input-pad-x\)\}/);
 assert.match(css,/body :is\(#roomScreen,#onlineMenuScreen,#infinitePauseMenu\) \.callsign-row \.net-input\{min-height:var\(--callsign-input-height\);padding:var\(--callsign-input-pad-y\) var\(--callsign-input-pad-x\)\}/,'shared callsign input geometry outranks separate landscape network-screen and screen-card input rules');
 assert.match(css,/body\.touch-ui \.callsign-row \.net-input\{font-size:16px\}/);
 assert.match(css,/body :is\(#roomScreen,#onlineMenuScreen,#infinitePauseMenu\) \.callsign-status\{font:var\(--min-font-size\)\/1\.4 var\(--mono\);margin:var\(--callsign-feedback-gap\) 0 0\}/,'specific editor feedback styling overrides mobile screen-card paragraph margins and font size');
});

test('confirmed End sends once and stays pending through metadata renders until lobby acknowledgement',async()=>{
 const b=boot(),{s,$,wire,begin,accept}=b;const pending=begin('returnToRoom');accept();await pending;
 await s.returnToRoom();s.renderOnlineRoom();
 assert.equal(wire.filter(p=>p.type==='lobby').length,1);assert.equal($('returnRoomBtn').disabled,true);assert.equal($('returnRoomBtn').textContent,'ENDING…');
 s.online.roomData={...s.online.roomData,phase:'lobby'};s.renderOnlineRoom();assert.ok(s.online.endMatchPending,'metadata precedes authoritative state');
 // Run the acknowledgement hook from the production state receiver.
 s.phase='onlineLobby';const acknowledgement=declaration('receiveOnlineState').split('\n').find(line=>line.includes("phase==='onlineLobby'&&online.endMatchPending"));assert.ok(acknowledgement);vm.runInContext(acknowledgement,s);
 assert.equal(s.online.endMatchPending,null);assert.equal($('returnRoomBtn').disabled,false);assert.equal($('returnRoomBtn').textContent,'End match');assert.equal(b.timers.size,0);
});

test('only tiny End and Leave commands bypass movement backpressure, and Leave is queued before closing',async()=>{
 const b=boot(),{s,wire,events,socket,begin,accept,load}=b;socket.bufferedAmount=16384;
 assert.equal(s.sendOnline({type:'input',seq:99,fire:true}),false);assert.equal(s.sendOnline({type:'chat',text:'hello'}),false);assert.equal(s.sendOnline({type:'lobby',text:'x'.repeat(200)}),false);
 const pending=begin('returnToRoom');accept();await pending;assert.equal(wire.filter(p=>p.type==='lobby').length,1);
 load('leaveOnline');s.leaveOnline();
 assert.deepEqual(events,['send:lobby','send:leave','close']);assert.equal(s.online.endMatchPending,null);assert.equal(s.mode,'room');assert.equal(s.createdLocal,1);
});

test('End send errors, rejection and timeout release pending state without duplicate retries',async()=>{
 for(const reason of ['send','reject','timeout']){
  const b=boot(),{s,$,wire,begin,accept,timers}=b;if(reason==='send')s.sendFails=true;
  const pending=begin('returnToRoom');accept();await pending;
  if(reason==='reject')s.clearEndMatchPending('Host authority changed.');
  if(reason==='timeout')for(const fn of [...timers.values()])fn();
  assert.equal(s.online.endMatchPending,null,reason);assert.equal($('returnRoomBtn').disabled,false);assert.ok(s.notice);assert.equal($('onlineMenuMessage').textContent,s.notice,'failure remains visible above the arena overlay');assert.equal(wire.filter(p=>p.type==='lobby').length,reason==='send'?0:1);
 }
 assert.match(source,/msg\.action==='lobby'\)\{clearEndMatchPending\(msg\.message\)/);
 assert.match(source,/ws\.onclose=\(\)=>\{[\s\S]*?online\.socket!==ws\)return;online\.connected=false;[^\n]*\n  clearEndMatchPending\(\);/);
});

test('End/Leave remain bound to their room identity and End requires private host authority',async()=>{
 for(const action of ['returnToRoom','leaveOnlineMatch'])for(const change of ['room','socket','member']){
  const {s,wire,begin,accept}=boot(),pending=begin(action);if(change==='room')s.online.code='OTHER';else if(change==='socket')s.online.socket={};else s.online.member++;
  accept();await pending;assert.equal(wire.length,0);assert.equal(s.left,undefined);
 }
 for(const change of ['host','matchmaking','queue','awayMatch','connected']){
  const {s,wire,begin,accept}=boot(),pending=begin('returnToRoom');if(change==='host')s.online.roomData.host=1;else if(change==='connected')s.online.connected=false;else s.online.roomData[change]={};
  accept();await pending;assert.equal(wire.length,0,change);assert.equal(s.online.endMatchPending,null);
 }
});

test('match-end presentation preserves valid End/Leave confirmation and waits for its decision',async()=>{
 for(const action of ['returnToRoom','leaveOnlineMatch'])for(const delay of [0,500]){
  const {s,$,wire,begin,accept}=boot(),pending=begin(action);
  s.phase='matchOver';s.online.roomData.phase='matchOver';let results=0;
  s.queueMatchPresentation(()=>results++,delay);
  assert.equal($('actionConfirmDialog').open,true);assert.ok(s.pendingGameConfirmation);
  s.flushMatchPresentation(2000);assert.equal(results,0,'results cannot obscure an open confirmation');
  accept();await pending;
  if(action==='returnToRoom')assert.equal(wire.filter(p=>p.type==='lobby').length,1);else assert.equal(s.left,1);
  s.flushMatchPresentation(2000);assert.equal(results,0,'accepted End waits for lobby acknowledgement; Leave discards old results');
 }
 const {s,$}=boot();let current=true;const pending=s.confirmGameAction({title:'Older wave',message:'Restart?',isCurrent:()=>current});current=false;s.phase='matchOver';s.queueMatchPresentation(()=>{},500);
 assert.equal($('actionConfirmDialog').open,false);assert.equal(await pending,false,'stale action still cancels at match end');
});

test('zero-delay results wait for an already confirmed End but remain immediate without pending user intent',async()=>{
 const {s,begin,accept}=boot(),pending=begin('returnToRoom');accept();await pending;
 s.phase='matchOver';s.online.roomData.phase='matchOver';let results=0;
 s.queueMatchPresentation(()=>results++,0);s.flushMatchPresentation(2000);assert.equal(results,0);
 s.clearEndMatchPending('End was rejected.');s.flushMatchPresentation(2000);assert.equal(results,1,'failed End releases results instead of trapping the view');
 s.queueMatchPresentation(()=>results++,0);assert.equal(results,2,'completed joins with no dialog/pending End remain immediate');
});
