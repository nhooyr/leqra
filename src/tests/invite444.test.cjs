'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const {assetPath}=require('./web_assets.cjs');
const source=fs.readFileSync(process.env.LEQRA_INVITE_SOURCE||assetPath('game.js'),'utf8');
function declaration(name){let start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);if(source.slice(start-6,start)==='async ')start-=6;const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot({query='?room=Friday+tanks',session=null,name='SAVED PILOT',kicked=''}={}){
 const nodes=new Map(),noop=()=>{},saved=new Map([['leqra.name',name]]),stored=new Map([['leqra.session',JSON.stringify(session)],['leqra.kicked',kicked]]),connections=[];
 const $=id=>{if(!nodes.has(id))nodes.set(id,{id,value:'',open:false,disabled:false,hidden:false,textContent:'',dataset:{},listeners:{},firstElementChild:{},style:{setProperty:noop},classList:{toggle:noop,add:noop,remove:noop},addEventListener(kind,fn){this.listeners[kind]=fn;},focus(){this.focused=true;},select(){this.selected=true;},showModal(){this.open=true;},close(){this.open=false;},querySelector(){return this.heading||(this.heading={});}});return nodes.get(id);};
 const s={$,URL,URLSearchParams,Date,MAX_ROOM_RUNES:128,mode:'room',phase:'menu',watchInvite:false,watchResume:null,online:{connected:false,connecting:false,code:'',token:'',id:-1,roomData:null,inviteCode:'',inviteResumeRetries:0},
  location:{protocol:'https:',href:'https://leqra.test/'+query,search:query},document:{body:$('body'),documentElement:$('root'),querySelectorAll:()=>[]},window:{addEventListener:noop},performance:{now:()=>1000},setInterval:noop,setTimeout:()=>1,clearTimeout:noop,
  localStorage:{getItem:k=>saved.get(k),setItem:(k,v)=>saved.set(k,v)},sessionStorage:{getItem:k=>stored.get(k),setItem:(k,v)=>stored.set(k,v),removeItem:k=>stored.delete(k)},
  callsignForms:()=>[],storeOnlineSession:noop,initAudio:noop,renderOnlineRoom:noop,showReconnecting:noop,setScreen(which){s.screen=which;if(which==='online')$('joinDialog').showModal();},connections,
  connectOnline(request,reconnecting=false){connections.push({request:{...request},reconnecting});s.online.connecting=true;}};
 for(const name of ['confirmKick','cancelKick','leaveOnline','unshareOnlineRoom','openJoinDialog','submitRoomRename','returnToRoom','restartLocalMatch','requestRestartSurvivalWave','leaveOnlineMatch','copyOnlineInvite','toggleRoomMenu','toggleOnlineMenu'])s[name]=noop;
 vm.createContext(s);
 for(const name of ['cleanPilotName','cleanRoomCode','validRoomCode','rememberCallsign','setNetStatus','netBusy','openOnline','resetWatchDialog','openPilotInvite','joinOnlineRoom','openWatchInvite','joinWatchInvite','composingKey','initOnlineUI'])if(source.includes('function '+name+'('))vm.runInContext(declaration(name),s);
 s.initOnlineUI();
 return{s,$,stored,saved,join:()=>$('joinRoomBtn').listeners.click(),enter:id=>$(id).listeners.keydown({key:'Enter',preventDefault:noop})};
}
function recent(extra={}){return{code:'Friday tanks',token:'resume-token',name:'OLD PILOT',at:Date.now(),...extra};}

test('an unnamed fresh invite uses Player 1 and explicit callsigns remain unchanged',()=>{
 const {s,$,join,saved}=boot({name:''});assert.equal($('pilotName').value,'Player 1');$('pilotName').value='';join();assert.equal(s.connections[0].request.name,'Player 1');assert.equal(saved.get('leqra.name'),'Player 1');
 for(const name of ['PILOT','Pilot','YOU']){const h=boot({name});h.join();assert.equal(h.s.connections[0].request.name,name);}
});

test('fresh invite shows the callsign menu without connecting until JOIN is clicked',()=>{
 const {s,$,join,saved}=boot();assert.equal(s.connections.length,0);assert.equal($('joinDialog').open,true);assert.equal($('joinCode').value,'Friday tanks');assert.equal($('pilotName').value,'SAVED PILOT');assert.equal($('pilotName').focused,true);assert.equal($('pilotName').selected,true);assert.equal(s.mode,'room');
 $('pilotName').value='NEW PILOT';join();assert.equal(s.connections.length,1);assert.equal(s.connections[0].request.name,'NEW PILOT');assert.equal(s.connections[0].request.code,'Friday tanks');assert.equal(s.connections[0].request.token,undefined);assert.equal(saved.get('leqra.name'),'NEW PILOT');
});
test('recent matching saved sessions reconnect automatically from an invite',()=>{
 const {s,$,join}=boot({session:recent()});assert.equal(s.connections.length,1);assert.equal($('pilotName').value,'OLD PILOT');assert.equal($('joinCode').value,'Friday tanks');assert.equal(s.connections[0].request.token,'resume-token');assert.equal(s.connections[0].request.name,'OLD PILOT');assert.equal(s.connections[0].reconnecting,true);assert.equal(s.online.code,'Friday tanks');assert.equal(s.online.inviteCode,'','unconfirmed resume cannot fall back to a new seat');
 $('pilotName').value='LATE EDIT';join();assert.equal(s.connections.length,1,'pending recovery cannot create another connection');
});
test('expired, future or unrelated sessions never bypass the menu or supply another room token',()=>{
 for(const session of [recent({at:Date.now()-21000}),recent({at:Date.now()+10000}),recent({code:'Another room'})]){const {s,join}=boot({session});assert.equal(s.connections.length,0);join();assert.equal(s.connections[0].request.token,undefined);}
 const {s,$,join}=boot({session:recent({code:'Another room'})});$('joinCode').value='Different room';join();assert.equal(s.connections[0].request.code,'Different room');assert.equal(s.connections[0].request.token,undefined);assert.equal(s.online.inviteCode,'');
});
test('Back and Escape cancel a fresh invite without erasing another room’s saved session',()=>{
 for(const action of ['back','escape']){const {s,$,stored}=boot({session:recent({code:'Another room'})});if(action==='back')$('onlineBackBtn').listeners.click();else $('joinDialog').listeners.cancel({preventDefault(){}});assert.equal(s.connections.length,0);assert.equal(s.mode,'room');assert.equal(s.online.inviteCode,'');assert.equal(s.online.inviteResume,null);assert.equal(JSON.parse(stored.get('leqra.session')).token,'resume-token');}
});
test('Enter in callsign submits manually and invalid room names stay in the join menu',()=>{
 const {s,$,enter}=boot();$('pilotName').value='ENTER PILOT';enter('pilotName');assert.equal(s.connections.length,1);assert.equal(s.connections[0].request.name,'ENTER PILOT');
 const invalid=boot({query:'?room=%0A'});assert.equal(invalid.s.connections.length,0);invalid.$('joinCode').value='';invalid.join();assert.equal(invalid.s.connections.length,0);assert.equal(invalid.$('joinCode').focused,true);
});
test('composition Enter commits text without initiating a join or room rename',()=>{
 const {s,$,enter}=boot();
 for(const id of ['pilotName','joinCode','onlineRoomCode'])for(const state of [{isComposing:true},{keyCode:229}]){
  $(id).listeners.keydown({key:'Enter',...state,preventDefault(){assert.fail('leave composition commit to the browser');}});
 }
 assert.equal(s.connections.length,0);
 enter('pilotName');assert.equal(s.connections.length,1);
});
test('manual invite dialog works in the match menu and stays current through rename',async()=>{
 const {s,$}=boot({query:''});
 Object.assign(s,{mode:'online',phase:'playing',roomChat:{code:'Original name'},syncOnlineURL(){},toast(){},openFeature:id=>$(id+'Dialog').showModal(),navigator:{clipboard:{async writeText(){throw Error('denied');}}}});
 Object.assign(s.online,{code:'Original name',connected:true,member:1,socket:{},roomData:{code:'Original name'}});
 for(const name of ['onlineInviteURL','captureOnlineRoomActionScope','inviteCopyDetails','syncInviteFallback','copyOnlineInvite','acceptOnlineRoomCode'])vm.runInContext(declaration(name),s);
 await s.copyOnlineInvite(true);
 assert.equal($('inviteDialog').open,true);assert.equal($('inviteFallback').focused,true);assert.equal($('inviteFallback').selected,true);
 assert.equal(new URL($('inviteFallback').value).searchParams.get('room'),'Original name');
 s.acceptOnlineRoomCode('Current name',false,false);
 const updated=new URL($('inviteFallback').value);
 assert.equal(updated.searchParams.get('room'),'Current name');assert.equal(updated.searchParams.get('spectate'),'1');
 s.location.href='http://localhost:8080/';await s.copyOnlineInvite();
 assert.match($('inviteFallback').value,/^Room Current name/);
});
test('a removed player must explicitly JOIN and is not given the removed session token',()=>{
 const {s,$,join,stored}=boot({session:recent(),kicked:'Friday tanks'});assert.equal(s.connections.length,0);assert.match($('netStatus').textContent,/removed/i);join();assert.equal(s.connections.length,1);assert.equal(s.connections[0].request.token,undefined);assert.equal(stored.has('leqra.kicked'),false);
});
test('fresh spectator invites wait for callsign confirmation and retain spectator intent',()=>{
 const {s,$,join}=boot({query:'?room=Friday+tanks&spectate=1'});assert.equal(s.connections.length,0);assert.equal($('joinRoomBtn').firstElementChild.textContent,'START SPECTATING');assert.equal($('joinCode').readOnly,true);$('pilotName').value='VIEWER';join();assert.equal(s.connections[0].request.spectating,true);assert.equal(s.connections[0].request.name,'VIEWER');assert.equal(s.connections[0].request.token,undefined);
});
test('background recovery without an invite keeps its existing automatic resume behavior',()=>{
 const {s}=boot({query:'',session:recent()});assert.equal(s.connections.length,1);assert.equal(s.connections[0].request.token,'resume-token');assert.equal(s.connections[0].reconnecting,true);
 const fresh=boot({query:''});assert.equal(fresh.s.connections.length,0);assert.equal(fresh.$('joinDialog').open,false);
});

test('saved membership restores its own spectator role regardless of invite type',()=>{
 for(const spectating of [false,true])for(const query of ['','?room=Friday+tanks','?room=Friday+tanks&spectate=1']){
  const {s}=boot({query,session:recent({spectating})});assert.equal(s.connections.length,1);assert.equal(s.connections[0].request.token,'resume-token');assert.equal(Object.hasOwn(s.connections[0].request,'spectating'),false,'automatic recovery must preserve the server role and callsign');assert.equal(s.online.spectating,spectating);assert.equal(s.connections[0].reconnecting,true);
 }
});
test('saved names alone cannot bypass JOIN, and a kicked session cannot resume without an invite',()=>{
 for(const session of [recent({token:''}),recent({token:null}),{code:'Friday tanks',name:'OLD PILOT',at:Date.now()}])assert.equal(boot({session}).s.connections.length,0);
 const {s}=boot({query:'',session:recent(),kicked:'Friday tanks'});assert.equal(s.connections.length,0);
});
function sockets(s){
 const noop=()=>{};Object.assign(s,{GAME_VERSION:'test',MAX_TANKS:8,COLORS:Array(8).fill('#fff'),matchmaking:{},roomChat:{code:'Friday tanks'},Net:{},paintColor:v=>v,sent:[],sendOnline:m=>{s.sent.push(m);return true;},WebSocket:class{constructor(){s.socket=this;this.readyState=1;}close(){this.readyState=3;this.onclose?.();}},});
 for(const name of ['clearInput','closeVictory','matchmakingWelcome','resetOnlineMotion','clearRoomChat','syncChatStatus','syncOnlineURL','addLog','cancelCallsignSave','clearRestartWavePending','clearRoomModePending','syncRoomModePicker','cancelSwap','syncCallsignEditors','clearEndMatchPending'])s[name]=noop;
 for(const name of ['forgetOnlineSession','closeRoomInfinity','connectOnline'])vm.runInContext(declaration(name),s);
 s.scheduleReconnect=()=>{s.retryScheduled=true;};s.receiveKick=()=>{s.kickReceived=true;};s.joinInviteAsNewPilot=()=>{throw new Error('Unconfirmed saved session must never allocate a new seat');};
 s.online.connecting=false;s.connectOnline(s.connections[0].request,true);
}
test('automatic saved-session welcomes keep the server callsign without a rename request',()=>{
 const {s,$}=boot({session:recent()});sockets(s);
 s.socket.onmessage({data:JSON.stringify({type:'welcome',room:'Friday tanks',id:0,member:1,token:'resume-token',resumed:true})});
 assert.equal(s.online.connected,true);assert.equal($('joinDialog').open,false);assert.equal(s.sent.filter(m=>m.type==='rename').length,0);assert.equal(s.online.inviteName,'');assert.equal(s.online.inviteResume,null);
});
test('rejected saved sessions return to JOIN and require confirmation before taking a new seat',()=>{
 for(const code of ['resume_expired','room_missing'])for(const query of ['','?room=Friday+tanks','?room=Friday+tanks&spectate=1']){
  const {s,$,stored,join}=boot({query,session:recent()});sockets(s);s.socket.onmessage({data:JSON.stringify({type:'error',code,message:'Saved session expired.'})});
  assert.equal($('joinDialog').open,true);assert.equal(s.screen,'online');assert.equal(s.online.connecting,false);assert.equal(s.online.token,'');assert.equal(s.online.manual,true);assert.equal($('joinCode').value,'Friday tanks');assert.equal($('pilotName').value,'OLD PILOT');assert.equal(stored.has('leqra.session'),false);assert.equal(s.retryScheduled,undefined);assert.match($('netStatus').textContent,/expired/);
  s.connectOnline=request=>s.connections.push({request:{...request}});join();assert.equal(s.connections.length,2);assert.equal(s.connections[1].request.token,undefined);
 }
});
test('an active saved session retries without allocating a second seat; server kicks stop recovery',()=>{
 const active=boot({session:recent()});sockets(active.s);active.s.socket.onmessage({data:JSON.stringify({type:'error',code:'session_active',message:'Already connected.'})});assert.equal(active.s.retryScheduled,true);assert.equal(active.s.online.token,'resume-token');
 const kicked=boot({session:recent()});sockets(kicked.s);kicked.s.socket.onmessage({data:JSON.stringify({type:'error',code:'kicked',message:'Removed.'})});assert.equal(kicked.s.kickReceived,true);assert.equal(kicked.s.retryScheduled,undefined);
});
test('real kick teardown clears saved membership and requires an explicit fresh JOIN',()=>{
 for(const spectating of [false,true])for(const message of [{type:'kicked',room:'Friday tanks',message:'Removed.'},{type:'error',code:'kicked',message:'Removed.'}]){
  const {s,$,stored,join}=boot({session:recent({spectating})});sockets(s);
  for(const name of ['resetMatchmaking','closeChat','sendOnlineInput','createLocalRoom'])s[name]=()=>{};
  $('root').style.removeProperty=()=>{};
  for(const name of ['leaveOnline','receiveKick'])vm.runInContext(declaration(name),s);
  s.socket.onmessage({data:JSON.stringify(message)});
  assert.equal($('joinDialog').open,true);assert.equal($('joinCode').value,'Friday tanks');assert.equal(s.online.token,'');assert.equal(s.online.manual,true);assert.equal(s.online.connected,false);assert.equal(s.online.connecting,false);
  assert.equal(stored.has('leqra.session'),false);assert.equal(stored.get('leqra.kicked'),'Friday tanks');assert.equal(s.retryScheduled,undefined);assert.equal(s.connections.length,1,'kick cannot silently allocate a replacement membership');
  s.connectOnline=request=>s.connections.push({request:{...request}});join();assert.equal(s.connections.length,2);assert.equal(s.connections[1].request.token,undefined);assert.equal(stored.has('leqra.kicked'),false);
 }
});
