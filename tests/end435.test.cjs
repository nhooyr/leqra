'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8'),css=readFileSync(path.join(__dirname,'../web/style.css'),'utf8');
function declaration(name){let start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);if(source.slice(start-6,start)==='async ')start-=6;const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const elements=new Map(),timers=new Map(),wire=[],events=[];let doc,serial=0;
 class Element{
  constructor(tag='div'){this.tagName=tag.toUpperCase();this.children=[];this.listeners=new Map();this.dataset={};this.attributes={};this.style={removeProperty(){}};this.classList={toggle(){},add(){},remove(){}};this.open=false;this.hidden=false;this.disabled=false;this.value='';this.textContent='';this.isConnected=true;}
  set id(v){this._id=v;elements.set(v,this);}get id(){return this._id;}
  append(...nodes){for(const node of nodes){node.parentElement=this;this.children.push(node);}}
  setAttribute(k,v){this.attributes[k]=v;}
  querySelector(selector){if(selector==='button')return this.children.find(n=>n.tagName==='BUTTON')||null;if(selector==='.callsign-status')return this.status||null;return null;}
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
 for(const id of ['returnRoomBtn','leaveMatchBtn','pilotName','roomBtn','bestInline','barHint','announcer','onlineMenuMessage'])add(id,id.endsWith('Btn')?'button':'input');
 const players=[{id:0,member:101,name:'HOST',kind:'human'},{id:1,member:102,name:'PLAYER 2',kind:'local',owner:0}];
 for(const id of ['roomCallsignForm','menuCallsignForm','roomP2CallsignForm','menuP2CallsignForm']){
  const form=add(id,'form');if(id.includes('P2'))form.dataset.pilot='secondary';form.elements={callsign:new Element('input')};form.status=new Element('p');form.status.hidden=true;form.append(form.elements.callsign,form.status);
 }
 const socket={readyState:1,bufferedAmount:0,send(data){if(s.sendFails)throw Error('closed');wire.push(JSON.parse(data));events.push('send:'+JSON.parse(data).type);},close(){events.push('close');this.readyState=3;}};
 const s={console,Promise,WebSocket:{OPEN:1},mode:'online',phase:'playing',pendingGameConfirmation:null,pendingMatchPresentation:null,localMatchReport:null,localObjectives:null,localMatchStats:{},localRoom:{self:0,players},
  online:{socket,code:'ROOM',member:101,id:0,generation:2,connected:true,menu:true,roomData:{host:0,phase:'playing',players},renamePending:null,endMatchPending:null},
  document:doc,$,setTimeout(fn){const id=++serial;timers.set(id,fn);return id;},clearTimeout(id){timers.delete(id);},
  roomData:()=>s.online.roomData,roomMember:id=>s.online.roomData?.players.find(p=>p.id===id),localPlayerID:()=>s.online.id,secondaryMember:()=>s.online.roomData?.players.find(p=>p.kind==='local'),cleanPilotName:n=>String(n).trim().replace(/[^\w -]/g,'').slice(0,16),
  rememberCallsign(name){$('pilotName').value=name;},rememberLocalCallsign(){},initAudio(){},updateHUD(){},renderOnlineRoom(){s.syncCallsignEditors();s.syncEndMatchAction();},
  clearInput(){},sendOnlineInput(){},toast(message){s.notice=message;},performance:{now:()=>1000},closeVictory(){s.pendingMatchPresentation=null;},setScreen(){},
  clearRestartWavePending(){},resetMatchmaking(){},closeChat(){},clearRoomChat(){},cancelSwap(){},resetWatchDialog(){},cancelKick(){},resetOnlineMotion(){},forgetOnlineSession(){},createLocalRoom(){s.createdLocal=(s.createdLocal||0)+1;},
  readyRoom(){s.ready=true;},leaveOnline(){s.left=(s.left||0)+1;s.mode='room';}
 };
 vm.createContext(s);
 for(const name of ['sendOnline','callsignForms','editorPilot','callsignStatus','syncCallsignEditors','cancelCallsignSave','submitCallsign','acceptCallsign','captureOnlineRoomActionScope','syncEndMatchAction','clearEndMatchPending','finishGameConfirmation','confirmGameAction','leaveOnlineMatch','returnToRoom','queueMatchPresentation','flushMatchPresentation'])vm.runInContext(declaration(name),s);
 // Execute the actual callsign event bindings, including the blur autosave.
 const bindings=source.split('\n').find(line=>line.includes("for(const form of callsignForms())")&&line.includes("field.addEventListener('blur'"));assert.ok(bindings);vm.runInContext(bindings,s);
 s.syncCallsignEditors();
 const accept=()=>{$('actionConfirmAccept').onclick();},begin=name=>{let pending;const button=$(name==='returnToRoom'?'returnRoomBtn':'leaveMatchBtn');button.addEventListener('click',()=>{pending=s[name]();});button.focus();button.dispatch('click');return pending;};
 return{s,$,timers,wire,events,socket,players,begin,accept,load:name=>vm.runInContext(declaration(name),s)};
}

test('first End/Leave click survives callsign blur, save acknowledgement and a round transition',async()=>{
 for(const action of ['returnToRoom','leaveOnlineMatch'])for(const secondary of [false,true]){
  const b=boot(),{s,$,wire,begin,accept,players}=b,form=$(secondary?'menuP2CallsignForm':'menuCallsignForm'),player=players[secondary?1:0];
  form.elements.callsign.focus();form.elements.callsign.value='RENAMED PILOT';
  const pending=begin(action);
  assert.equal(wire.length,1);assert.equal(wire[0].type,secondary?'rename_local':'rename');assert.equal(form.status.textContent,'Saving…');assert.equal($('actionConfirmDialog').shows,1);
  s.acceptCallsign({id:player.id,member:player.member,name:'RENAMED PILOT'});
  s.online.roomData={...s.online.roomData,players:players.map(p=>({...p}))};s.renderOnlineRoom();
  assert.match(form.status.textContent,/Saved as RENAMED PILOT/);assert.equal($('actionConfirmDialog').open,true);
  s.phase='roundOver';s.phase='countdown';s.online.generation++;s.online.roomData.phase='countdown';
  accept();await pending;
  if(action==='returnToRoom'){assert.equal(wire.filter(p=>p.type==='lobby').length,1);assert.ok(s.online.endMatchPending);assert.equal($('returnRoomBtn').disabled,true);}
  else assert.equal(s.left,1);
 }
});

test('blur autosave feedback keeps space reserved above match menu actions',()=>{
 assert.match(css,/body #onlineMenuScreen \.callsign-status\{min-height:2\.8em\}/);
 assert.match(css,/body #onlineMenuScreen \.callsign-status\[hidden\]\{display:block!important;visibility:hidden\}/);
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
