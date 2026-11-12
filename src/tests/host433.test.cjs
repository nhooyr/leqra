'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const identityFixture=require('./identity_fixture.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const lineEnd=source.indexOf('\n',start),first=source.slice(start,lineEnd);
 return first.endsWith('}')?first:source.slice(start,source.indexOf('\n}',lineEnd)+2);
}
class Element{
 constructor(tag){this.tagName=tag;this.children=[];this.parentElement=null;this.className='';this.dataset={};this.attributes={};this.events={};this.style={setProperty(){}};this.textContent='';}
 append(...nodes){for(const node of nodes){if(node.parentElement){const old=node.parentElement.children;old.splice(old.indexOf(node),1);}node.parentElement=this;this.children.push(node);}}
 setAttribute(key,value){this.attributes[key]=String(value);}
 addEventListener(type,fn){this.events[type]=fn;}
 querySelector(selector){for(const child of this.children){if(selector.startsWith('.')?child.className.split(' ').includes(selector.slice(1)):child.tagName===selector)return child;const found=child.querySelector(selector);if(found)return found;}return null;}
}
function boot({host=0,phase='playing',teamMode='teams'}={}){
 const room={host,phase,rules:{mode:'elimination',teamMode,teamNames:['Amber','Cobalt','Jade','Violet']}};
 const changes=[],kicks=[],spectating=[];
 const s={mode:'online',online:{connected:true,kickPending:null},document:{createElement:tag=>new Element(tag)},localPlayerID:()=>0,currentRules:()=>room.rules,roomData:()=>room,
  paintColor:color=>color,teamName:(team,rules)=>rules.teamNames[team-1],activeTeamCount:()=>4,
  changeSeat:(player,patch)=>changes.push({player,patch}),requestKick:player=>kicks.push(player),setPlayerSpectating:(player,value)=>spectating.push({player,value})};
 vm.createContext(s);identityFixture(s,source);vm.runInContext(['botLevelName','survivalMode','roomPlayerStatus','canEditTankPaint','roomKickDisabled','makeKickButton','makeRoomPlayerRow'].map(declaration).join('\n'),s);
 return {s,room,changes,kicks,spectating,row:(player,moderation=true)=>s.makeRoomPlayerRow(player,room,moderation)};
}
const bot={id:2,member:42,name:'RICOCHET',kind:'bot',team:2,color:'#58f',difficulty:'hard'};

test('Free-for-all paint is locked while room Infinity is running',()=>{
 const {s,room}=boot({phase:'lobby',teamMode:'ffa'});
 room.rules.infinity=true;
 assert.equal(s.canEditTankPaint(bot,room),true);
 room.infinityActive=true;
 assert.equal(s.canEditTankPaint(bot,room),false);
});

test('host moderation keeps team, public difficulty name and status with the tank identity',()=>{
 const b=boot(),row=b.row(bot),identity=row.querySelector('.seat-identity'),details=identity.querySelector('.seat-details');
 assert.equal(identity.querySelector('.pilot-name').textContent,'RICOCHET');
 assert.equal(details.querySelector('.team-badge').textContent,'Cobalt, Fierce');
 assert.equal(details.querySelector('.seat-kind').textContent,'BOT');
 assert.equal(row.querySelector('.seat-controls').querySelector('.team-badge'),null);
 assert.equal(row.querySelector('select'),null,'live moderation cannot change team or difficulty');
 assert.equal(row.querySelector('input'),null,'moderation cannot edit tank names');
 const remove=row.querySelector('.kick-button');assert.equal(remove.textContent,'REMOVE');assert.equal(remove.dataset.kickMember,42);
 remove.events.click();assert.equal(b.kicks[0],bot,'original stable member target survives compact layout');
});

test('moderation preserves host permissions, connection restrictions and pending kick state',()=>{
 assert.equal(boot({host:1}).row(bot).querySelector('.kick-button'),null,'guests have no moderation action');
 for(const condition of ['disconnected','pending']){const b=boot();if(condition==='disconnected')b.s.online.connected=false;else b.s.online.kickPending={id:7};assert.equal(b.row(bot).querySelector('.kick-button').disabled,true,condition);}
 const b=boot(),self=b.row({...bot,id:0,kind:'human'});assert.equal(self.querySelector('.kick-button'),null,'host cannot remove self');
});

test('local Player 2 spectate and remove actions retain owner handling in the compact host row',()=>{
 const player={...bot,kind:'local',owner:0},b=boot(),row=b.row(player),controls=row.querySelector('.seat-controls');
 assert.equal(controls.children.length,2);const spectate=controls.children.find(child=>child.dataset.spectatePlayer===2);assert.ok(spectate);
 spectate.onclick();assert.equal(b.spectating[0].player,player);assert.equal(b.spectating[0].value,true);
 const remote=boot().row({...player,owner:1});assert.equal(remote.querySelector('.seat-controls').children.length,1,'another controller’s P2 exposes no spectate action');
});

test('read-only lobby metadata uses visible difficulty names and hides nonexistent FFA teams',()=>{
 for(const [difficulty,want]of [['easy','Chill'],['normal','Normal'],['hard','Fierce'],['godlike','Godlike']]){
  const b=boot({host:1,phase:'lobby',teamMode:'ffa'}),row=b.row({...bot,team:0,difficulty},false);
  assert.equal(row.querySelector('.team-badge').textContent,want);assert.equal(row.querySelector('.seat-identity'),null,'editable lobby layout remains separate');
 }
});

test('lobby bot editing retains name, team and difficulty events',()=>{
 const b=boot({phase:'lobby'}),row=b.row(bot,false),name=row.querySelector('input'),controls=row.querySelector('.seat-controls');
 name.value='BOUNCE';name.events.change();
 const team=controls.children.find(child=>'team'in child.dataset),difficulty=controls.children.find(child=>'botDifficulty'in child.dataset);
 assert.equal(team.children.length,4);assert.equal(difficulty.children.length,4);
 team.value='3';team.events.change();difficulty.value='godlike';difficulty.events.change();
 assert.deepEqual(JSON.parse(JSON.stringify(b.changes.map(change=>change.patch))),[{name:'BOUNCE'},{team:3},{difficulty:'godlike'}]);
});

test('room labels keep raw callsigns, tank colors and local suffixes for every viewer',()=>{
 const b=boot({teamMode:'ffa'}),primary={id:0,member:1,name:'YOU',kind:'human',color:'#10aeef',connected:true},local={id:1,member:2,name:'WING',kind:'local',owner:0,color:'#ffaa00',connected:true},remote={id:3,member:4,name:'VISITOR',kind:'human',color:'#ff00ee',connected:true};
 b.room.players=[primary,local,remote,bot];const raw=JSON.stringify(b.room.players);
 for(const [player,want]of [[primary,'YOU (P1)'],[local,'WING (P2)'],[remote,'VISITOR (P1)'],[bot,'RICOCHET']]){
  const name=b.row(player).querySelector('.pilot-name');assert.equal(name.textContent,want);assert.equal(name.style.color,player.color);
 }
 b.s.localPlayerID=()=>3;
 assert.equal(b.s.roomPlayerIdentity(primary,b.room).label,'YOU (P1)','remote controllers retain their role suffix');
 assert.equal(b.s.roomPlayerIdentity(local,b.room).label,'WING (P2)');
 b.room.players.splice(1,1);
 assert.equal(b.s.roomPlayerIdentity(primary,b.room).label,'YOU (P1)','a solo primary still advertises the first local slot');
 b.room.players.splice(1,0,local);assert.equal(JSON.stringify(b.room.players),raw,'presentation must never rewrite saved or wire names');
});

test('room identity HTML escapes names and resolves missing colors from room paint',()=>{
 const b=boot({teamMode:'ffa'}),player={id:3,member:4,name:'<YOU & WING>',kind:'human',team:0,colorIndex:6};b.room.players=[player];
 assert.equal(b.s.pilotIdentity(0,null).name,'Player 1');assert.equal(b.s.pilotIdentity(1,null,true).name,'CO-PILOT');assert.equal(b.s.pilotIdentity(0,{name:'PILOT'}).name,'PILOT');
 let requested;b.s.teamColor=(...args)=>{requested=args;return '#bada55';};
 const html=b.s.roomPlayerIdentityHTML(player,b.room);
 assert.ok(html.includes('&lt;YOU &amp; WING&gt; (P1)'));assert.ok(html.includes('color:#bada55'));assert.equal(html.includes('<YOU'),false);
 assert.equal(requested[0],3);assert.equal(requested[2],6);assert.equal(requested[3],b.room.rules);
 assert.equal(player.name,'<YOU & WING>');
 for(const flags of [{kind:'bot'},{bot:true},{survivalEnemy:true},{human:false}])assert.equal(b.s.roomPlayerIdentity({...player,...flags},b.room).label,player.name,'AI bodies never acquire a local pilot suffix');
});

test('identity spans and menu rows bold only the device pilots across room and frozen result metadata',()=>{
 const b=boot({teamMode:'ffa'}),primary={id:0,member:11,name:'HOST',kind:'human',color:'#123456'},local={id:1,member:12,name:'WING',kind:'local',owner:0,color:'#abcdef'},remote={id:3,member:13,name:'FRIEND',kind:'human'},remoteLocal={id:4,member:14,name:'REMOTE WING',kind:'local',owner:3};
 b.room.players=[primary,local,remote,remoteLocal,bot];
 for(const [player,owned]of [[primary,true],[local,true],[remote,false],[remoteLocal,false],[bot,false]]){
  assert.equal(b.s.isDeviceLocalPilot(player,b.room),owned);
  assert.equal(/class="pilot-identity local-pilot"/.test(b.s.roomPlayerIdentityHTML(player,b.room)),owned);
  assert.equal(b.row(player).querySelector('.pilot-name')?.className.includes('local-pilot')||false,owned);
  assert.equal(/class="pilot-identity local-pilot"/.test(b.s.resultPilotIdentityHTML({...player,id:999,seat:player.id})),owned);
 }
 assert.equal(b.s.isDeviceLocalPilot({...primary,member:99},b.room),false,'a reused combat seat does not own an earlier participant identity');
 assert.match(b.s.localPilotIdentityHTML(0),/class="pilot-identity local-pilot"/,'Controls and pause labels use the same local marker');
 b.room.players=b.room.players.filter(p=>p!==primary);b.room.spectators=[{...primary,id:8}];b.s.localPlayerID=()=>8;
 assert.equal(b.s.isDeviceLocalPilot({...primary,id:999,seat:0}),true,'frozen participant ownership survives a spectator seat move');
});

test('spectator rows use colored callsigns instead of YOU or bare local slot identities',()=>{
 const b=boot(),primary={id:8,member:1,name:'YOU',kind:'human',color:'#123abc',connected:true,spectating:true},local={id:9,member:2,name:'WING',kind:'local',owner:8,color:'#fedcba',connected:true,spectating:true};
 b.room.players=[];b.room.spectators=[primary,local];b.s.localPlayerID=()=>8;
 Object.assign(b.s,{isRoomHost:()=>false,survivalSeatLocked:()=>false,roomCapacity:()=>8,rolePending:false});
 vm.runInContext(declaration('spectatorRow'),b.s);
 for(const [player,want]of [[primary,'YOU (P1)'],[local,'WING (P2)']]){
  const row=b.s.spectatorRow(player,b.room),identity=row.querySelector('.spectator-person');
  assert.equal(identity.children[0].textContent,want);assert.equal(identity.children[0].style.color,player.color);
  assert.equal(identity.children[1].textContent,'SPECTATING');
 }
});
