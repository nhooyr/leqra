'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');

function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const lineEnd=source.indexOf('\n',start),first=source.slice(start,lineEnd);
 return first.endsWith('}')?first:source.slice(start,source.indexOf('\n}',lineEnd)+2);
}

// Only the DOM operations used by the renderer are modeled. Row construction is
// counted independently; the shipped reconciliation and status functions run in
// a VM, so node identity and lost draft regressions need no browser dependency.
class Element {
 constructor(tag='div'){this.tagName=tag.toUpperCase();this.children=[];this.parentElement=null;this.className='';this.textContent='';this.value='';this.insertions=0;this.removals=0;}
 append(...nodes){for(const node of nodes)this.insertBefore(node,null);}
 insertBefore(node,reference){
  assert.ok(reference===null||this.children.includes(reference),'reference belongs to container');
  if(node===reference)return node;
  if(node.parentElement)node.remove();
  const at=reference===null?this.children.length:this.children.indexOf(reference);
  this.children.splice(at,0,node);node.parentElement=this;this.insertions++;return node;
 }
 remove(){if(this.parentElement){const parent=this.parentElement;parent.children.splice(parent.children.indexOf(this),1);parent.removals++;this.parentElement=null;}}
 querySelector(selector){
  for(const child of this.children){
   if(selector[0]==='.'?child.className.split(' ').includes(selector.slice(1)):child.tagName===selector.toUpperCase())return child;
   const nested=child.querySelector(selector);if(nested)return nested;
  }
  return null;
 }
}

function boot(){
 const room={code:'ROOM',host:0,phase:'lobby',rules:{mode:'elimination',teamMode:'teams',teamNames:['A','B','C','D'],teamColors:[0,1,2,3]},players:[
  {id:0,member:10,name:'HOST',kind:'human',team:1,color:'#fff',connected:true},
  {id:1,member:11,name:'GUEST',kind:'human',team:2,color:'#aaa',connected:true},
  {id:2,member:12,name:'BOT',kind:'bot',team:3,color:'#bbb',difficulty:'normal',connected:true}
 ]};
 const creations=[],container=new Element();
 const s={mode:'online',selfID:0,MAX_TANKS:8,online:{connected:true},document:{createElement:tag=>new Element(tag)},localPlayerID:()=>s.selfID,currentRules:()=>room.rules,
  makeRoomPlayerRow(player,r,moderationOnly){
   const row=new Element(),input=new Element('input'),status=new Element('small');
   row.className='seat-row';input.value=player.name;status.className='seat-kind';row.append(input,status);
   creations.push({id:player.id,member:player.member,row,moderationOnly});return row;
  }
 };
 vm.createContext(s);vm.runInContext('const roomRosterCache=new WeakMap();\n'+declaration('roomPlayerStatus')+'\n'+declaration('renderRoomPlayerRows'),s);
 const render=(r=room,options={})=>s.renderRoomPlayerRows(options.container||container,r.players,r,options.moderationOnly||false,options.showOpenSeats!==false);
 return {s,room,container,creations,render};
}
const snapshot=room=>JSON.parse(JSON.stringify(room));
const seatRows=container=>container.children.filter(node=>node.className==='seat-row');
const freeRows=container=>container.children.filter(node=>node.className==='free-seats');

test('100 identical room packets create no new rows or DOM attachments and preserve a name draft',()=>{
 const b=boot();b.render();const original=seatRows(b.container),input=original[2].querySelector('input');input.value='UNSAVED BOT NAME';
 const insertions=b.container.insertions,removals=b.container.removals;
 for(let i=0;i<100;i++)b.render(snapshot(b.room));
 assert.equal(b.creations.length,3,'only the three initial rows were constructed');
 assert.deepEqual(seatRows(b.container),original);
 assert.equal(original[2].querySelector('input'),input);assert.equal(input.value,'UNSAVED BOT NAME');
 assert.equal(b.container.insertions,insertions);assert.equal(b.container.removals,removals);
});

test('unrelated ready, connection and score packets patch status without rebuilding another pilot draft',()=>{
 const b=boot();b.render();const original=seatRows(b.container),input=original[2].querySelector('input');input.value='DRAFT';
 for(let i=0;i<100;i++){
  const r=snapshot(b.room);r.players[1].ready=i%2===0;r.players[1].connected=i%3!==0;r.players[1].score=i;r.scores=[0,i,0];
  b.render(r);
  assert.equal(original[1].querySelector('.seat-kind').textContent,!r.players[1].connected?'RECONNECTING':r.players[1].ready?'READY ✓':'PILOT');
  assert.deepEqual(seatRows(b.container),original);assert.equal(input.value,'DRAFT');
 }
 assert.equal(b.creations.length,3,'100 unrelated updates constructed zero replacement rows');
});

test('room status handles host, self, ready, reconnecting, bot, local P2 and away pilots',()=>{
 const b=boot();
 for(const [player,host,want] of [
  [{id:0,kind:'human',connected:true},0,'YOU · HOST'],
  [{id:0,kind:'human',connected:true},1,'YOU · PILOT'],
  [{id:1,kind:'human',connected:true},1,'HOST'],
  [{id:1,kind:'human',connected:true,ready:true},0,'READY ✓'],
  [{id:1,kind:'human',connected:false,ready:true},0,'RECONNECTING'],
  [{id:1,kind:'human',connected:true},0,'PILOT'],
  [{id:1,kind:'bot'},0,'BOT'],
  [{id:1,kind:'local'},0,'LOCAL P2'],
  [{id:0,kind:'human',away:true},0,'IN MATCH']
 ])assert.equal(b.s.roomPlayerStatus(player,{host}),want);
});

test('editing a tank rebuilds only that tank row and preserves the other controls',()=>{
 for(const change of [{name:'NEW BOT'},{difficulty:'hard'},{team:4},{color:'#ccc'},{colorIndex:2},{kind:'local',owner:1}]){
  const b=boot();b.render();const original=seatRows(b.container),input=original[1].querySelector('input');input.value='OTHER DRAFT';
  const r=snapshot(b.room);Object.assign(r.players[2],change);b.render(r);
  const current=seatRows(b.container);
  assert.equal(b.creations.length,4);assert.equal(current[0],original[0]);assert.equal(current[1],original[1]);assert.notEqual(current[2],original[2]);
  assert.equal(input.value,'OTHER DRAFT');assert.equal(original[2].parentElement,null);
 }
});

test('a removed or reused seat cannot inherit the previous member row or draft',()=>{
 const b=boot();b.render();const original=seatRows(b.container);original[1].querySelector('input').value='OLD MEMBER DRAFT';
 let r=snapshot(b.room);r.players[1].member=99;r.players[1].name='REPLACEMENT';b.render(r);
 const replacement=seatRows(b.container)[1];assert.notEqual(replacement,original[1]);assert.equal(replacement.querySelector('input').value,'REPLACEMENT');
 assert.equal(original[1].parentElement,null);
 r.players.splice(1,1);b.render(r);assert.equal(replacement.parentElement,null);
 r.players.splice(1,0,{...b.room.players[1],member:99,name:'RETURNED'});b.render(r);
 assert.notEqual(seatRows(b.container)[1],replacement);assert.equal(seatRows(b.container)[0],original[0]);assert.equal(seatRows(b.container)[2],original[2]);
 assert.equal(b.creations.length,5);
});

test('roster order changes move existing rows without discarding input nodes or drafts',()=>{
 const b=boot();b.render();const original=seatRows(b.container);original[2].querySelector('input').value='DRAFT';
 const r=snapshot(b.room);r.players.reverse();b.render(r);
 assert.deepEqual(seatRows(b.container),[original[2],original[1],original[0]]);assert.equal(b.creations.length,3);
 assert.equal(original[2].querySelector('input').value,'DRAFT');assert.equal(freeRows(b.container).length,1);
});

test('permission, host and game-format transitions rebuild controls before displaying the new state',()=>{
 const transitions=[
  ['match starts',b=>{b.room.phase='playing';}],
  ['host changes',b=>{b.room.host=1;}],
  ['queued room locks',b=>{b.room.queue={};}],
  ['matchmaking locks',b=>{b.room.matchmaking=true;}],
  ['away match locks',b=>{b.room.awayMatch=true;}],
  ['disconnect disables actions',b=>{b.s.online.connected=false;}],
  ['online to local room',b=>{b.s.mode='room';}],
  ['CTF has two team choices',b=>{b.room.rules.mode='ctf';}],
  ['FFA removes team choices',b=>{b.room.rules.teamMode='ffa';}],
  ['viewer role changes',b=>{b.s.selfID=1;}]
 ];
 for(const [label,change] of transitions){
  const b=boot();b.render();const original=seatRows(b.container);change(b);b.render();
  assert.equal(b.creations.length,6,label);
  seatRows(b.container).forEach((row,i)=>assert.notEqual(row,original[i],label));
  b.render();assert.equal(b.creations.length,6,label+' stabilizes after rebuilding');
 }
});

test('moderation roster caches are independent and switching moderation mode rebuilds controls',()=>{
 const b=boot(),moderation=new Element();b.render();const original=seatRows(b.container);
 b.render(b.room,{container:moderation,moderationOnly:true,showOpenSeats:false});assert.equal(b.creations.length,6);
 seatRows(moderation).forEach((row,i)=>assert.notEqual(row,original[i]));assert.equal(freeRows(moderation).length,0);
 b.render(b.room,{container:moderation,moderationOnly:true,showOpenSeats:false});assert.equal(b.creations.length,6);
 b.render(b.room,{moderationOnly:true});assert.equal(b.creations.length,9);
});

test('the open-seat notice stays unique, follows capacity, and disappears when full or disabled',()=>{
 const b=boot();b.render();const free=freeRows(b.container)[0];
 for(let i=0;i<100;i++){b.render(snapshot(b.room));assert.deepEqual(freeRows(b.container),[free]);}
 assert.equal(free.textContent,'5 OPEN SEATS · ADD A PILOT, BOT, OR FRIEND');
 const r=snapshot(b.room);for(let id=3;id<8;id++)r.players.push({id,member:id+10,name:'BOT '+id,kind:'bot',team:1});
 b.render(r);assert.equal(freeRows(b.container).length,0);assert.equal(free.parentElement,null);
 r.players.pop();b.render(r);assert.deepEqual(freeRows(b.container),[free]);assert.equal(free.textContent,'1 OPEN SEAT · ADD A PILOT, BOT, OR FRIEND');
 b.render(r,{showOpenSeats:false});assert.equal(freeRows(b.container).length,0);
 b.render(r);assert.deepEqual(freeRows(b.container),[free]);
});

test('a bot killed by remote grenade detonation stops before movement even when its target survives',()=>{
 const bot={id:0,alive:true,x:90,y:210,angle:0,r:17,ghostTime:0,ai:{target:1,think:0,pathClock:1,shotClock:0,bankClock:1,dodgeTime:0,dodgeClock:1,recoverTime:0,aim:null,path:[1],goal:0,lastX:90,lastY:210,stuck:0}},enemy={id:1,alive:true,x:190,y:210,r:17,invulnerable:0};
 let moves=0,detonations=0;
 const s={difficulty:'normal',DIFFICULTY:{normal:{think:.2,speed:108,turn:3.4,reaction:.4,dodge:false}},tanks:[bot,enemy],BLAST_RADIUS:220,CELL:84,RADIUS:17,
  speedCount:()=>0,isEnemy:(a,b)=>a.id!==b.id,distance:(a,b)=>Math.hypot(a.x-b.x,a.y-b.y),objectiveGoal:()=>null,rnd:()=>1,
  ownedGrenades:()=>[{x:140,y:210}],rayWalls:()=>null,detonateOwned(t){t.alive=false;detonations++;},
  chooseBotAim:()=>null,cellAt:()=>0,routeControl:()=>({angle:0,drive:1}),chooseGrenadeAvoid:()=>null,angleDelta:(a,b)=>b-a,clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),
  moveTank(t,dx,dy){moves++;t.x+=dx;t.y+=dy;}
 };
 vm.createContext(s);vm.runInContext(declaration('botControl'),s);s.botControl(bot,1/60);
 assert.equal(detonations,1);assert.equal(bot.alive,false);assert.equal(enemy.alive,true);assert.equal(moves,0);assert.equal(bot.x,90);assert.equal(bot.y,210);
});
