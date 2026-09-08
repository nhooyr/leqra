'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(process.env.LEQRA_INVITE_SOURCE||path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot({query='?room=Friday+tanks',session=null,name='SAVED PILOT',kicked=''}={}){
 const nodes=new Map(),noop=()=>{},saved=new Map([['leqra.name',name]]),stored=new Map([['leqra.session',JSON.stringify(session)],['leqra.kicked',kicked]]),connections=[];
 const $=id=>{if(!nodes.has(id))nodes.set(id,{id,value:'',open:false,disabled:false,hidden:false,textContent:'',dataset:{},listeners:{},firstElementChild:{},style:{setProperty:noop},classList:{toggle:noop,add:noop,remove:noop},addEventListener(kind,fn){this.listeners[kind]=fn;},focus(){this.focused=true;},select(){this.selected=true;},showModal(){this.open=true;},close(){this.open=false;},querySelector(){return this.heading||(this.heading={});}});return nodes.get(id);};
 const s={$,URL,URLSearchParams,Date,MAX_ROOM_RUNES:128,mode:'room',phase:'menu',watchInvite:false,watchResume:null,online:{connected:false,connecting:false,code:'',token:'',id:-1,roomData:null,inviteCode:'',inviteResumeRetries:0},
  location:{protocol:'https:',href:'https://leqra.test/'+query,search:query},document:{body:$('body'),documentElement:$('root'),querySelectorAll:()=>[]},window:{addEventListener:noop},performance:{now:()=>1000},setInterval:noop,setTimeout:()=>1,clearTimeout:noop,
  localStorage:{getItem:k=>saved.get(k),setItem:(k,v)=>saved.set(k,v)},sessionStorage:{getItem:k=>stored.get(k),setItem:(k,v)=>stored.set(k,v),removeItem:k=>stored.delete(k)},
  callsignForms:()=>[],storeOnlineSession:noop,initAudio:noop,renderOnlineRoom:noop,showReconnecting:noop,setScreen:noop,connections,
  connectOnline(request,reconnecting=false){connections.push({request:{...request},reconnecting});s.online.connecting=true;}};
 for(const name of ['confirmKick','cancelKick','leaveOnline','unshareOnlineRoom','openJoinDialog','submitRoomRename','returnToRoom','restartLocalMatch','requestRestartSurvivalWave','leaveOnlineMatch','copyOnlineInvite','toggleRoomMenu','toggleOnlineMenu'])s[name]=noop;
 vm.createContext(s);
 for(const name of ['cleanPilotName','cleanRoomCode','validRoomCode','rememberCallsign','setNetStatus','netBusy','openOnline','resetWatchDialog','openPilotInvite','joinOnlineRoom','openWatchInvite','joinWatchInvite','initOnlineUI'])if(source.includes('function '+name+'('))vm.runInContext(declaration(name),s);
 s.initOnlineUI();
 return{s,$,stored,saved,join:()=>$('joinRoomBtn').listeners.click(),enter:id=>$(id).listeners.keydown({key:'Enter',preventDefault:noop})};
}
function recent(extra={}){return{code:'Friday tanks',token:'resume-token',name:'OLD PILOT',at:Date.now(),...extra};}

test('fresh invite shows the callsign menu without connecting until JOIN is clicked',()=>{
 const {s,$,join,saved}=boot();assert.equal(s.connections.length,0);assert.equal($('joinDialog').open,true);assert.equal($('joinCode').value,'Friday tanks');assert.equal($('pilotName').value,'SAVED PILOT');assert.equal($('pilotName').focused,true);assert.equal($('pilotName').selected,true);assert.equal(s.mode,'room');
 $('pilotName').value='NEW PILOT';join();assert.equal(s.connections.length,1);assert.equal(s.connections[0].request.name,'NEW PILOT');assert.equal(s.connections[0].request.code,'Friday tanks');assert.equal(s.connections[0].request.token,undefined);assert.equal(saved.get('leqra.name'),'NEW PILOT');
});
test('recent matching sessions also wait, then recover their seat with the selected name',()=>{
 const {s,$,join}=boot({session:recent()});assert.equal(s.connections.length,0);assert.equal($('pilotName').value,'OLD PILOT');$('pilotName').value='NEW PILOT';join();assert.equal(s.connections[0].request.token,'resume-token');assert.equal(s.connections[0].request.name,'NEW PILOT');assert.equal(s.online.inviteName,'NEW PILOT');assert.equal(s.online.code,'Friday tanks');
 $('pilotName').value='LATE EDIT';join();assert.equal(s.connections.length,1);assert.equal(s.online.inviteName,'NEW PILOT','pending attempt keeps the callsign confirmed on click');
});
test('expired, future or unrelated sessions never bypass the menu or supply another room token',()=>{
 for(const session of [recent({at:Date.now()-21000}),recent({at:Date.now()+10000}),recent({code:'Another room'})]){const {s,join}=boot({session});assert.equal(s.connections.length,0);join();assert.equal(s.connections[0].request.token,undefined);}
 const {s,$,join}=boot({session:recent()});$('joinCode').value='Different room';join();assert.equal(s.connections[0].request.code,'Different room');assert.equal(s.connections[0].request.token,undefined);assert.equal(s.online.inviteCode,'');
});
test('Back and Escape cancel an invite without joining, retaining resume credentials for a later visit',()=>{
 for(const action of ['back','escape']){const {s,$,stored}=boot({session:recent()});if(action==='back')$('onlineBackBtn').listeners.click();else $('joinDialog').listeners.cancel({preventDefault(){}});assert.equal(s.connections.length,0);assert.equal(s.mode,'room');assert.equal(s.online.inviteCode,'');assert.equal(s.online.inviteResume,null);assert.equal(JSON.parse(stored.get('leqra.session')).token,'resume-token');}
});
test('Enter in callsign submits manually and invalid room names stay in the join menu',()=>{
 const {s,$,enter}=boot();$('pilotName').value='ENTER PILOT';enter('pilotName');assert.equal(s.connections.length,1);assert.equal(s.connections[0].request.name,'ENTER PILOT');
 const invalid=boot({query:'?room=%0A'});assert.equal(invalid.s.connections.length,0);invalid.$('joinCode').value='';invalid.join();assert.equal(invalid.s.connections.length,0);assert.equal(invalid.$('joinCode').focused,true);
});
test('a removed player must explicitly JOIN and is not given the removed session token',()=>{
 const {s,$,join,stored}=boot({session:recent(),kicked:'Friday tanks'});assert.equal(s.connections.length,0);assert.match($('netStatus').textContent,/removed/);join();assert.equal(s.connections.length,1);assert.equal(s.connections[0].request.token,undefined);assert.equal(stored.has('leqra.kicked'),false);
});
test('spectator invites still wait for callsign confirmation and retain spectator intent',()=>{
 const {s,$,join}=boot({query:'?room=Friday+tanks&spectate=1',session:recent()});assert.equal(s.connections.length,0);assert.equal($('joinRoomBtn').firstElementChild.textContent,'START SPECTATING');assert.equal($('joinCode').readOnly,true);$('pilotName').value='VIEWER';join();assert.equal(s.connections[0].request.spectating,true);assert.equal(s.connections[0].request.name,'VIEWER');assert.equal(s.connections[0].request.token,'resume-token');
});
test('background recovery without an invite keeps its existing automatic resume behavior',()=>{
 const {s}=boot({query:'',session:recent()});assert.equal(s.connections.length,1);assert.equal(s.connections[0].request.token,'resume-token');assert.equal(s.connections[0].reconnecting,true);
 const fresh=boot({query:''});assert.equal(fresh.s.connections.length,0);assert.equal(fresh.$('joinDialog').open,false);
});

test('confirmed invite callsign is applied after a resumed welcome, including a network retry',()=>{
 for(const retry of [false,true]){
  const {s,$,join}=boot({session:recent()});$('pilotName').value='RENAMED PILOT';join();s.online.connecting=false;
  const noop=()=>{};Object.assign(s,{GAME_VERSION:'test',MAX_TANKS:8,COLORS:Array(8).fill('#fff'),matchmaking:{},roomChat:{code:'Friday tanks'},Net:{},paintColor:v=>v,sent:[],sendOnline:m=>{s.sent.push(m);return true;},WebSocket:class{constructor(){s.socket=this;this.readyState=1;}close(){this.readyState=3;}},});
  for(const name of ['clearInput','closeVictory','matchmakingWelcome','resetOnlineMotion','clearRoomChat','syncChatStatus','syncOnlineURL','addLog','cancelCallsignSave','clearRestartWavePending','clearRoomModePending','syncRoomModePicker','cancelSwap','syncCallsignEditors','clearEndMatchPending','forgetOnlineSession'])s[name]=noop;
  vm.runInContext(declaration('connectOnline'),s);s.connectOnline({type:'join',code:'Friday tanks',token:'resume-token',name:'RENAMED PILOT'},retry);
  s.socket.onmessage({data:JSON.stringify({type:'welcome',room:'Friday tanks',id:0,member:1,token:'resume-token',resumed:true})});
  assert.equal(s.sent.filter(m=>m.type==='rename').length,1);assert.equal(s.sent.find(m=>m.type==='rename').name,'RENAMED PILOT');assert.equal(s.online.inviteName,'');assert.equal(s.online.inviteResume,null);
 }
});
