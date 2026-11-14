'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8'),css=readFileSync(assetPath('style.css'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'('),end=source.indexOf('\n',start),line=source.slice(start,end);assert.ok(start>=0,name);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function spectators(){
 const elements=new Map(),$=id=>{if(!elements.has(id))elements.set(id,{hidden:false,textContent:'',title:'',open:false,setAttribute(){},replaceChildren(){},querySelectorAll:()=>[]});return elements.get(id);};
 const room={host:0,rules:{infinity:false},players:[{id:0,member:1,name:'Pilot',kind:'human'}],spectators:[]};
 const s={$,mode:'online',roomData:()=>room,online:{id:0,roomData:room,connected:true},localPlayerID:()=>0,roomMember:id=>room.players.find(p=>p.id===id),secondaryMember:()=>null,syncRoomRole(){},rolePending:false,lastSpectatorUI:'',survivalSeatLocked:()=>false,roomCapacity:()=>8,roomKickDisabled:()=>false,swapPending:null,isRoomHost:()=>true,syncSpectatingHUD(){}};
 vm.createContext(s);vm.runInContext(declaration('syncSpectators'),s);return{s,$,room};
}

test('room Infinity keeps spectator invites visible in the lobby and while its arena is active',()=>{
 const {s,$,room}=spectators();
 for(const infinity of [false,true])for(const active of [false,true]){
  room.rules.infinity=infinity;room.infinityActive=active;s.syncSpectators();
  for(const id of ['copySpectateBtn','copyWatchInGameBtn']){
   assert.equal($(id).hidden,false,`${id} remains in the same online menu position`);
   assert.match($(id).title,infinity?/follow tanks.*Infinity room/:/watch this match/);
  }
 }
 s.mode='room';s.syncSpectators();assert.equal($('copySpectateBtn').hidden,true,'a local room still needs sharing before an invite exists');
});

test('the same spectator invite preserves encoded room identity and explicitly requests a spectator seat',()=>{
 const s={URL,location:{href:'https://leqra.test/?room=old&debug=1#old'},online:{code:'Friends & bots'},watchInvite:true,watchResume:null,cleanPilotName:value=>value,validRoomCode:()=>true,rememberCallsign(){},$:()=>({value:'Viewer'}),connectOnline:request=>{s.request=request;}};
 vm.createContext(s);vm.runInContext(declaration('onlineInviteURL')+'\n'+declaration('joinWatchInvite'),s);
 const url=s.onlineInviteURL(true);assert.equal(url.searchParams.get('room'),'Friends & bots');assert.equal(url.searchParams.get('spectate'),'1');assert.equal(url.searchParams.has('debug'),false);assert.equal(url.hash,'');
 s.joinWatchInvite(url.searchParams.get('room'));assert.equal(s.request.type,'join');assert.equal(s.request.spectating,true);assert.equal(s.request.code,'Friends & bots');assert.equal(s.request.name,'Viewer');
});

test('only Public Infinity replaces the fixed room header and room presets retain their menu slot',()=>{
 assert.match(css,/body\.public-infinity-preview \.arena-shell>\.arena-bar:not\(\.infinity-preview-header\)/);
 assert.doesNotMatch(css,/body\.infinity-preview[^\n]*\{display:none/,'room preview cover styling cannot remove header or log height');
 assert.match(declaration('syncFeatureSummary'),/\$\('roomRulesBtn'\)\.hidden=\$\('roomPresetsBtn'\)\.hidden=false/);
 assert.match(css,/\.room-mode-help\{min-height:35px;padding-top:6px\}/,'two14.5px description lines plus6px padding fit without moving the next field');
});

test('room spectator auto-entry is private, happens once per run, and remains manually reenterable',()=>{
 const calls=[],sync=[],online={connected:true,spectating:true,code:'ROOM',token:'room-proof',restoreInfinity:true,roomData:{infinityActive:true,infinityPublic:false}};
 const s={online,window:{leqraInfinity:{syncRoom:(...args)=>sync.push(args),savedRoomGeneration:()=>7}},closeChat(){},startInfinity:(...args)=>calls.push(args)};
 vm.createContext(s);vm.runInContext(declaration('startRoomInfinity')+'\n'+declaration('syncOnlineRoomInfinity'),s);
 s.syncOnlineRoomInfinity();assert.equal(calls.length,1);assert.equal(calls[0][1].spectating,true);assert.equal(online.restoreInfinity,false);assert.equal(sync[0][3],true);
 s.syncOnlineRoomInfinity();assert.equal(calls.length,1,'ordinary room updates do not undo an explicit viewer exit');
 s.startRoomInfinity();assert.equal(calls.length,2,'Watch Infinity remains available for explicit reentry');
 online.roomData.infinityActive=false;s.syncOnlineRoomInfinity();assert.equal(sync.at(-1)[2],false);
 online.roomData.infinityActive=true;s.syncOnlineRoomInfinity();assert.equal(calls.length,3,'the next run starts a new spectator view');
 online.spectating=false;s.syncOnlineRoomInfinity();assert.equal(calls.length,4,'an explicit promotion enters combat with the new role');assert.equal(calls.at(-1)[1].spectating,false);
 online.spectating=true;s.syncOnlineRoomInfinity();assert.equal(calls.length,5,'demotion switches back to a read-only viewer');
 online.roomData.infinityPublic=true;s.syncOnlineRoomInfinity();s.startRoomInfinity();assert.equal(calls.length,5,'room watcher credentials never enter Public Infinity');
});

test('room Infinity role help describes following while public-party watchers remain in the lobby',()=>{
 const s={survivalSeatLocked:()=>false,roomCapacity:()=>8};vm.createContext(s);vm.runInContext(declaration('roomRoleHelpText'),s);
 const room={rules:{infinity:true},players:[]};
 assert.match(s.roomRoleHelpText({spectating:false},room),/spectating and follow tanks/);
 assert.match(s.roomRoleHelpText({spectating:false},{...room,infinityPublic:true}),/lobby-only/);
 assert.equal(s.roomRoleHelpText({spectating:true},room),'Select Play to enter the arena.');
});
