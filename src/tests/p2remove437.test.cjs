'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),first=source.slice(start,end);return first.endsWith('}')?first:source.slice(start,source.indexOf('\n}',end)+2);}
class Element{
 constructor(tag='div'){this.tagName=tag.toUpperCase();this.children=[];this.parentElement=null;this.className='';this.dataset={};this.events={};this.style={setProperty(){}};this.classList={toggle(){}};this.disabled=false;this.hidden=false;this.textContent='';this.open=false;}
 append(...nodes){for(const node of nodes)this.insertBefore(node,null);}
 insertBefore(node,before){node.remove();node.parentElement=this;this.children.splice(before?this.children.indexOf(before):this.children.length,0,node);}
 remove(){if(this.parentElement){const parent=this.parentElement;parent.children.splice(parent.children.indexOf(this),1);this.parentElement=null;}}
 replaceChildren(...nodes){for(const node of [...this.children])node.remove();this.append(...nodes);}
 addEventListener(type,handler){this.events[type]=handler;}
 setAttribute(){}
 showModal(){this.open=true;}
 close(){this.open=false;}
 focus(){}
 get firstElementChild(){return this.children[0]||(this.append(new Element('span')),this.children[0]);}
 matches(selector){return selector.startsWith('.')?this.className.split(' ').includes(selector.slice(1)):selector==='[data-kick-target]'?'kickTarget'in this.dataset:selector==='[data-spectate-player]'?'spectatePlayer'in this.dataset:this.tagName===selector.toUpperCase();}
 querySelectorAll(selector){const found=[];for(const child of this.children){if(child.matches(selector))found.push(child);found.push(...child.querySelectorAll(selector));}return found;}
 querySelector(selector){return this.querySelectorAll(selector)[0]||null;}
}
function boot(){
 const elements=new Map(),$=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
 const local={id:1,member:12,kind:'local',owner:0,name:'PLAYER 2',color:'#f0f',team:1},host={id:0,member:11,kind:'human',name:'HOST',color:'#0ff',team:1};
 const room={code:'ROOM',host:0,phase:'lobby',rules:{mode:'elimination',teamMode:'teams',teamNames:['A','B','C','D'],teamColors:[0,1,2,3]},players:[host,local]};
 const roster=$('roomRoster'),menu=$('menuKickRoster'),q={id:1,key:'teams',stage:'searching',required:4,members:[],name:'Teams',since:Date.now()};
 const s={console,Date,URL,mode:'online',MAX_TANKS:8,online:{connected:true,kickPending:null,roomData:room},matchmaking:{pending:false,pendingKey:'',catalog:[],selected:'teams',seenInvite:0},MATCH_QUEUES:[{key:'teams',mode:'elimination',teamSize:2,target:5,seconds:75,cols:7,rows:7}],
  roomData:()=>room,currentRules:()=>room.rules,roomMembers:r=>[...r.players,...(r.spectators||[])],roomMember:id=>[...room.players,...(room.spectators||[])].find(p=>p.id===id),localPlayerID:()=>0,isRoomHost:()=>room.host===0,
  $,document:{createElement:tag=>new Element(tag),querySelector:()=>$('queueCard'),querySelectorAll(selector){if(selector.includes('#roomRoster'))return [...roster.querySelectorAll('select'),...menu.querySelectorAll('select'),...roster.querySelectorAll('[data-kick-target]')];return [...roster.querySelectorAll(selector),...menu.querySelectorAll(selector)];}},
  rolePending:false,swapPending:null,lastSpectatorUI:'',survivalSeatLocked:()=>false,syncSpectatingHUD(){},cancelSwap(){},paintColor:c=>c,teamName:(n,r)=>r.teamNames[n-1],activeTeamCount:()=>4,changeSeat(){},setPlayerSpectating(){},queueEligibility:()=>'',syncResultActions(){},closeChat(){},clearInput(){},sendOnlineInput(){},clearTimeout(){},toast(){},matchmakingNotice(){}
 };
 $('queueCard').append(Object.assign(new Element(),{className:'queue-count'}));
 vm.createContext(s);
 const names=['survivalMode','roomCapacity','roomPlayerStatus','canEditTankPaint','makeKickButton','makeRoomPlayerRow','renderRoomPlayerRows','realParty','renderMatchmaking','matchmakingPacket','cancelKick','requestKick','spectatorRow','syncSpectators'];
 if(source.includes('function roomKickDisabled('))names.unshift('roomKickDisabled');
 vm.runInContext('const roomRosterCache=new WeakMap();\n'+names.map(declaration).join('\n'),s);
 s.renderOnlineRoom=()=>{s.renderRoomPlayerRows(roster,room.players,room);s.renderRoomPlayerRows(menu,room.players.slice(1),room,true);s.syncSpectators();s.renderMatchmaking();};
 s.renderOnlineRoom();return {s,room,q,$,local,roster,button:()=>roster.querySelector('.kick-button')};
}

test('LOCAL P2 Remove recovers after queue status/cancel packets without a bot mutation',()=>{
 const b=boot(),{s,room,q,button}=b;assert.equal(button().disabled,false);
 s.matchmakingPacket({type:'queue_status',queue:q});assert.equal(button().disabled,true);
 s.matchmakingPacket({type:'queue_cancelled',message:'Search cancelled.'});assert.equal(room.queue,null);
 assert.equal(button().disabled,false,'queue cancellation must immediately restore LOCAL P2 removal');
 button().events.click();assert.equal(s.online.kickPending.member,b.local.member);assert.equal(b.$('kickDialog').open,true);s.cancelKick();
 // The ordinary unchanged metadata update must keep the button usable too.
 s.renderOnlineRoom();assert.equal(button().disabled,false);
});

test('unchanged cached roster repairs a stale disabled Remove without replacing name controls',()=>{
 const b=boot(),original=b.button(),row=original.parentElement.parentElement;
 original.disabled=true;
 b.s.renderOnlineRoom();assert.equal(b.button(),original,'cached controls stay attached');assert.equal(b.button().disabled,false);assert.equal(original.parentElement.parentElement,row);
});

test('closing Remove confirmation cannot unlock restricted roster actions',()=>{
 for(const reason of ['queue','matchmaking','away','disconnected','host','local_playing']){
  const b=boot(),{s,room,button}=b;
  if(reason==='queue')room.queue=b.q;
  else if(reason==='matchmaking')room.matchmaking={name:'Battle'};
  else if(reason==='away')room.awayMatch='OTHER';
  else if(reason==='disconnected')s.online.connected=false;
  else if(reason==='host')room.host=2;
  else{s.mode='room';room.phase='playing';}
  s.online.kickPending={id:1,member:12};button().disabled=true;s.cancelKick();
  assert.equal(button().disabled,true,reason+' must remain restricted');assert.equal(s.online.kickPending,null);
 }
 const b=boot();b.s.online.kickPending={id:1,member:12};b.button().disabled=true;b.s.cancelKick();assert.equal(b.button().disabled,false,'ordinary cancellation restores the permitted action');
});


test('cached spectator Remove restores after queue cancellation in both spectator lists',()=>{
 for(const kind of ['local','human']){
  const b=boot(),{s,room,q,$}=b;room.players=room.players.slice(0,1);room.spectators=[{...b.local,id:8,spectating:true,kind,connected:true}];
  s.matchmakingPacket({type:'queue_status',queue:q});
  const buttons=['roomSpectatorList','spectatorList'].map(id=>$(id).querySelector('.kick-button'));assert.equal(buttons.every(button=>button.disabled),true);
  s.matchmakingPacket({type:'queue_cancelled',message:'Search cancelled.'});
  for(const [i,id]of ['roomSpectatorList','spectatorList'].entries()){assert.equal($(id).querySelector('.kick-button'),buttons[i],'unchanged spectator rows stay attached');assert.equal(buttons[i].disabled,false,kind+' removal must recover after queue cancellation');}
  // Queue entry must also lock rows that were already built in a plain lobby.
  s.matchmakingPacket({type:'queue_status',queue:q});assert.equal(buttons.every(button=>button.disabled),true);
 }
});
