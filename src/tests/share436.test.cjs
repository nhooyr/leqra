'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8'),css=readFileSync(path.join(__dirname,'../web/style.css'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'('),end=source.indexOf('\n',start),line=source.slice(start,end);assert.ok(start>=0,name);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot({spectating=false,p2=true}={}){
 const nodes=new Map(),classes=new Set(),noop=()=>{};
 function element(){const el={value:'',hidden:false,open:false,textContent:'',dataset:{},children:[],style:{setProperty:noop,removeProperty:noop},classList:{add:k=>classes.add(k),remove:k=>classes.delete(k),contains:k=>classes.has(k),toggle:(k,on)=>on?classes.add(k):classes.delete(k)},append(...children){this.children.push(...children);},setAttribute:noop,showModal(){this.open=true;},close(){this.open=false;},focus:noop};return el;}
 const $=id=>{if(!nodes.has(id))nodes.set(id,element());return nodes.get(id);};
 const players=[{id:spectating?8:0,member:4,name:'HOST',kind:'human',owner:0,team:1,spectating},...(p2?[{id:3,member:5,name:'P2',kind:'local',owner:spectating?8:0,team:1}]:[]),{id:6,member:6,name:'BOT',kind:'bot',owner:0,team:1,difficulty:'godlike'}];
 const rules={mode:'survival',mapSize:'huge',teamMode:'teams',scoreTarget:15};
 const s={URL,Map,Set,mode:'room',phase:'menu',localRoom:{self:players[0].id,code:'',players,rules},online:{connected:false,connecting:false,code:'',token:'',id:-1,roomData:null,snapshots:[],generation:-1,ownedIDs:new Set(),activeIDs:new Set(),shots:{sync:noop,prune:noop},localBullets:new Map()},
  tanks:players.filter(p=>!p.spectating).map(p=>({...p,alive:true,power:null})),pickups:[{id:11,type:'shield',x:42,y:42,life:30}],walls:[{x:0,y:0,w:84,h:8}],cols:14,rows:12,W:1176,H:1008,grid:[],particles:[],rings:[],traces:[],bullets:[],shake:0,goUntil:0,gameStarted:false,
  GAME_VERSION:'test',MAX_TANKS:8,COLORS:Array(8).fill('#fff'),Net:{expandMachineBullets:()=>[]},$,performance:{now:()=>1000},
  location:{protocol:'https:',href:'https://leqra.test/'},document:{body:element(),documentElement:element(),querySelectorAll:()=>[],createElement:element},
  sessionStorage:{removeItem:noop},setTimeout:()=>1,clearTimeout:noop,matchmaking:{},roomChat:{code:''},watchInvite:false,watchResume:null,rolePending:false,rulesPending:false,presetsPending:false,
  teamColor:()=> '#fff',paintColor:v=>v,roomCapacity:()=>4,defaultRoomRules:()=>({mode:'elimination',mapSize:'standard'}),cleanRoomCode:v=>v,validRoomCode:()=>true,
  toast:noop,netBusy:noop,setNetStatus:noop,setScreen:noop,renderOnlineRoom:noop,clearInput:noop,closeVictory:noop,matchmakingWelcome:noop,resetWatchDialog:noop,clearRoomChat:noop,syncChatStatus:noop,syncOnlineURL:noop,storeOnlineSession:noop,initAudio:noop,addLog:noop,
  rememberCallsign:noop,rememberLocalCallsign:noop,syncCallsignEditors:noop,sendOnlineInput:noop,updateHUD:noop,survivalState:()=>null,showStartingControls:noop,cacheMap:noop,resize:noop,syncRestartWaveActions:noop,
  clearRestartWavePending:noop,clearRoomModePending:noop,syncRoomModePicker:noop,cancelSwap:noop,cancelKick:noop,cancelCallsignSave:noop,clearEndMatchPending:noop,
  sendOnline(message){s.sent.push(message);},sent:[],
  resetOnlineMotion(){s.online.snapshots=[];s.online.buffer={push(snapshot){s.online.snapshots.push(snapshot);}};s.online.predictor={reconcile:noop};},
  WebSocket:class{constructor(){s.socket=this;this.readyState=1;}close(){this.readyState=3;this.onclose?.();}}};
 vm.createContext(s);vm.runInContext(declaration('orderedRoster'),s);
 for(const name of ['roomData','roomMembers','roomMember','localPlayerID','secondaryMember','secondLocal','secondaryID']){const line=source.split('\n').find(line=>line.startsWith('const '+name+'='));vm.runInContext(line+'\nglobalThis.'+name+'='+name+';',s);}
 for(const name of ['shareLocalRoom','connectOnline','currentRules','applyOnlineTankEffects','liveFeedbackTank','pilotLoadoutTank','receiveOnlineState','netTank','showVersionMismatch'])vm.runInContext(declaration(name),s);
 return{s,$,players,rules,receive:packet=>s.socket.onmessage({data:JSON.stringify(packet)}),snapshot:(extra={})=>({type:'state',tick:0,generation:0,phase:'lobby',round:1,roundClock:75,phaseTime:0,winner:-1,scores:Array(8).fill(0),tanks:[],bullets:[],pickups:[],events:[],rules,objectives:null,...extra})};
}
test('sharing preserves the current pilots, rules, maze and pickups through handshake and generation zero',()=>{
 for(const spectating of [false,true])for(const p2 of [false,true]){
  const {s,players,rules,receive,snapshot}=boot({spectating,p2}),original={tanks:s.tanks,pickups:s.pickups,walls:s.walls};
  s.shareLocalRoom();assert.equal(s.mode,'online');assert.equal(s.online.publishing,true);assert.equal(s.currentRules(),rules);assert.equal(s.localPlayerID(),players[0].id);assert.equal(!!s.secondaryMember(),p2);assert.equal(!!s.pilotLoadoutTank(players[0].id),!spectating);
  receive({type:'server_hello',version:'test',protocol:1});assert.equal(s.sent.at(-1).type,'publish');
  receive({type:'welcome',room:'SHARED',id:spectating?8:0,member:1,token:'token',spectating,created:true});
  assert.equal(s.online.publishing,true,'keep local layout until complete roster arrives');assert.equal(s.currentRules(),rules);assert.equal(!!s.secondaryMember(),p2);
  const serverPlayers=players.filter(p=>!p.spectating).map((p,i)=>({...p,id:i,owner:spectating?8:0}));
  receive({type:'room',code:'SHARED',host:spectating?8:0,players:serverPlayers,spectators:spectating?[players[0]]:[],rules,phase:'lobby'});
  assert.equal(s.online.publishing,false);assert.equal(s.currentRules().mode,'survival');assert.equal(!!s.secondaryMember(),p2);
  receive(snapshot());receive(snapshot({tick:1}));
  assert.equal(s.tanks,original.tanks);assert.equal(s.pickups,original.pickups);assert.equal(s.walls,original.walls);assert.equal(s.W,1176);assert.equal(s.H,1008);
  receive(snapshot({tick:2,generation:1,phase:'countdown',world:{cols:14,rows:12,width:1176,height:1008,walls:[{x:0,y:0,w:84,h:8}]}}));
  assert.notEqual(s.walls,original.walls,'real round replaces the maze');assert.equal(s.tanks.length,0);assert.equal(s.pickups.length,0,'real generation retires preview equipment');
 }
});
test('failed publish, refused version and unavailable server preserve the local room preview',()=>{
 for(const failure of ['conflict','version','unavailable']){
  const {s,rules,players,receive}=boot(),tanks=s.tanks,pickups=s.pickups,walls=s.walls;s.shareLocalRoom();
  if(failure==='conflict')receive({type:'error',action:'publish',code:'room_exists',message:'That name is already in use.'});
  else if(failure==='version')receive({type:'server_hello',version:'old',protocol:1});
  else s.socket.close();
  assert.equal(s.mode,'room',failure);assert.equal(s.phase,'menu');assert.equal(s.online.publishing,false);assert.equal(s.localRoom.players,players);assert.equal(s.currentRules(),rules);assert.equal(s.tanks,tanks);assert.equal(s.pickups,pickups);assert.equal(s.walls,walls);
 }
});
test('the fixed objective HUD row reserves the same geometry for every mode including Elimination',()=>{
 const selector=css.match(/(?:^|\n)(\.objective-bar\[hidden\])\{([^}]+)\}/);assert.ok(selector,'hidden status row must be independent of selected mode');assert.match(selector[2],/display:flex!important/);assert.match(selector[2],/visibility:hidden/);
 assert.doesNotMatch(css,/body\.has-objective-bar\s+\.objective-bar\[hidden\]/,'mode switching cannot add or remove reserved space');
 for(const mode of ['elimination','ctf','koth','survival']){
  const b=boot();b.rules.mode=mode;b.s.shareLocalRoom();assert.equal(b.s.currentRules().mode,mode);assert.equal(b.s.W,1176);assert.equal(b.s.H,1008);
 }
});
