'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
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
 const s={mode:'online',online:{connected:true,kickPending:null},document:{createElement:tag=>new Element(tag)},localPlayerID:()=>0,currentRules:()=>room.rules,
  paintColor:color=>color,teamName:(team,rules)=>rules.teamNames[team-1],activeTeamCount:()=>4,
  changeSeat:(player,patch)=>changes.push({player,patch}),requestKick:player=>kicks.push(player),setPlayerSpectating:(player,value)=>spectating.push({player,value})};
 vm.createContext(s);vm.runInContext(['botLevelName','survivalMode','roomPlayerStatus','canEditTankPaint','makeKickButton','makeRoomPlayerRow'].map(declaration).join('\n'),s);
 return {s,room,changes,kicks,spectating,row:(player,moderation=true)=>s.makeRoomPlayerRow(player,room,moderation)};
}
const bot={id:2,member:42,name:'RICOCHET',kind:'bot',team:2,color:'#58f',difficulty:'hard'};

test('host moderation keeps team, public difficulty name and status with the tank identity',()=>{
 const b=boot(),row=b.row(bot),identity=row.querySelector('.seat-identity'),details=identity.querySelector('.seat-details');
 assert.equal(identity.querySelector('.pilot-name').textContent,'RICOCHET');
 assert.equal(details.querySelector('.team-badge').textContent,'Cobalt · Fierce');
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
