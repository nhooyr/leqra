'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){let start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);if(source.slice(start-6,start)==='async ')start-=6;const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const nodes=new Map(),noop=()=>{},timers=new Map();let serial=0;
 const $=id=>{if(!nodes.has(id))nodes.set(id,{id,value:'',open:false,hidden:false,disabled:false,textContent:'',dataset:{},style:{setProperty:noop,removeProperty:noop},classList:{add:noop,remove:noop},firstElementChild:{},querySelector:()=>({}),close(){this.open=false;}});return nodes.get(id);};
 const room={code:'ROOM',host:0,phase:'lobby',players:[{id:0,member:1,name:'HOST',kind:'human'}]};
 const s={URL,mode:'room',phase:'menu',MAX_TANKS:8,COLORS:Array(8).fill('#fff'),GAME_VERSION:'test',localMatchStats:null,localRoom:{players:[],self:0},
  online:{connected:false,connecting:false,roomData:room,code:'',token:'',id:0,member:1,generation:1,snapshots:[]},matchmaking:{},roomChat:{code:'ROOM'},$,performance:{now:()=>1000},
  document:{body:$('body'),documentElement:$('root'),querySelectorAll:()=>[]},location:{protocol:'https:',href:'https://leqra.test/'},history:{replaceState:noop},sessionStorage:{removeItem:noop},
  setTimeout(fn){timers.set(++serial,fn);return serial;},clearTimeout:id=>timers.delete(id),
  WebSocket:class{constructor(){this.readyState=1;s.socket=this;}close(){this.readyState=3;this.onclose?.();}},
  netBusy:noop,setNetStatus:noop,clearInput:noop,sendOnlineInput:noop,toast:noop,renderOnlineRoom:noop,setScreen:noop,syncChatStatus:noop,recoverPendingChat:noop,scheduleReconnect:noop,
  clearRestartWavePending:noop,clearRoomModePending:noop,syncRoomModePicker:noop,cancelSwap:noop,cancelKick:noop,cancelCallsignSave:noop,syncCallsignEditors:noop,clearEndMatchPending:noop,
  resetMatchmaking:noop,closeChat:noop,clearRoomChat:noop,resetWatchDialog:noop,callsignForms:()=>[],callsignStatus:noop,resetOnlineMotion:noop,forgetOnlineSession:noop,createLocalRoom:noop,
  roomData:()=>s.online.roomData,localPlayerID:()=>s.online.id,confirmGameAction:async()=>true,
  localSnapshotFromOnline:()=>({code:s.online.code,attempt:s.sent.length,preview:{walls:[1,2,3]}}),sent:[],sendOnline(message){s.sent.push(message);return !s.sendFails;}};
 vm.createContext(s);
 for(const name of ['captureActionScope','unshareOnlineRoom','connectOnline','showReconnecting','leaveOnline'])vm.runInContext(declaration(name),s);
 s.connectOnline({type:'join',code:'ROOM'});Object.assign(s.online,{connecting:false,connected:true,code:'ROOM',token:'token'});s.phase='onlineLobby';
 return {s,$,room,receive:packet=>s.socket.onmessage({data:JSON.stringify(packet)})};
}

test('an interrupted Unshare request cannot permanently disable Unshare after reconnecting',async()=>{
 const {s}=boot();await s.unshareOnlineRoom();assert.equal(s.sent.at(-1).type,'unshare');assert.equal(s.online.unsharePending,true);
 const oldSocket=s.socket,oldSnapshot=s.online.unshareSnapshot;oldSocket.close();
 assert.equal(s.online.unsharePending,false,'connection loss must release the old request');assert.equal(s.online.unshareSnapshot,null,'old saved lobby cannot leak into a later request');
 s.connectOnline({type:'join',code:'ROOM',token:'token'},true);Object.assign(s.online,{connected:true,connecting:false});s.phase='onlineLobby';
 await s.unshareOnlineRoom();assert.equal(s.sent.filter(p=>p.type==='unshare').length,2);assert.notEqual(s.online.unshareSnapshot,oldSnapshot);
 oldSocket.onclose();assert.equal(s.online.unsharePending,true,'late close from the old socket must not clear the new attempt');
});

test('leaving during Unshare clears its pending state before a different room is joined',async()=>{
 const {s,room}=boot();await s.unshareOnlineRoom();s.leaveOnline();
 assert.equal(s.mode,'room');assert.equal(s.online.unsharePending,false);assert.equal(s.online.unshareSnapshot,null);
 s.connectOnline({type:'join',code:'OTHER'});Object.assign(s.online,{connected:true,connecting:false,code:'OTHER',token:'other',id:0,roomData:{...room,code:'OTHER'}});s.phase='onlineLobby';
 await s.unshareOnlineRoom();assert.equal(s.sent.at(-1).type,'unshare');assert.equal(s.online.unshareSnapshot.code,'OTHER');
});

test('a rejected or unsent Unshare releases its snapshot and permits retry',async()=>{
 for(const failure of ['send','reject']){
  const {s,receive}=boot();s.sendFails=failure==='send';await s.unshareOnlineRoom();
  if(failure==='reject')receive({type:'error',action:'unshare',message:'Room is busy.'});
  assert.equal(s.online.unsharePending,false,failure);assert.equal(s.online.unshareSnapshot,null,failure);
  s.sendFails=false;await s.unshareOnlineRoom();assert.equal(s.online.unsharePending,true);assert.equal(s.sent.filter(p=>p.type==='unshare').length,2);
 }
});
