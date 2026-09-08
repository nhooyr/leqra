'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const end=source.indexOf('\n',start),line=source.slice(start,end);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);
}
class Element{
 constructor(){this.children=[];this.style={setProperty(){}};this.classList={toggle(){}};this.textContent='';this.open=false;}
 append(...children){this.children.push(...children);}
 replaceChildren(...children){this.children=[...children];}
 setAttribute(k,v){this[k]=v;}
 focus(){}
 showModal(){this.open=true;}
 close(){this.open=false;}
}
function boot({teams=false,target=1}={}){
 const elements=new Map(),$=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
 const players=[{id:0,member:101,name:'ORIGINAL',kind:'human',team:teams?1:0},
  {id:1,member:102,name:teams?'ALLY':'RIVAL',kind:teams?'local':'bot',owner:0,team:teams?1:0}];
 if(teams)players.push({id:2,member:103,name:'RIVAL',kind:'bot',team:2});
 const rules={mode:'elimination',teamMode:teams?'teams':'ffa',scoreTarget:target};
 const s={mode:'room',phase:'playing',MAX_TANKS:8,localRoom:{players,self:0,nextMember:103,nextViewer:8},
  tanks:players.map(p=>({...p,alive:p.name!=='RIVAL',human:p.kind!=='bot',color:'#fff'})),scores:Array(8).fill(0),
  round:1,roundWinner:-1,phaseTime:0,roundClock:75,bullets:[],particles:[],rings:[],fxTime:0,time:0,toastTime:0,shake:0,uiClock:1,
  localObjectives:null,localMatchStats:null,localMatchReport:null,localMatchResult:null,goUntil:0,bestWins:0,
  COLORS:['#fff'],$,document:{createElement:()=>new Element(),querySelectorAll:()=>[]},
  teamKey:p=>p.team>0?'team'+p.team:'pilot'+p.id,teamName:id=>'TEAM '+id,teamColor:()=>'#fff',paintColor:c=>c,
  currentRules:()=>rules,objectiveMode:()=>false,suddenDeath:()=>false,
  clearInput(){},dropLocalFlags(){},addLog(){},tone(){},updateHUD(){},updateTraces(){},compactLife(){},save(){},setScreen(){},renderOnlineRoom(){},syncResultActions(){},
  renderMatchStats(report){s.renderedReport=report;},startRound(){s.starts=(s.starts||0)+1;s.phase='countdown';},
  localPlayerID:()=>s.localRoom.self,controlledTank:()=>s.tanks.find(t=>t.id===s.localRoom.self),
  roomData:()=>({players:s.localRoom.players.filter(p=>!p.spectating),spectators:s.localRoom.players.filter(p=>p.spectating)}),
  roomMember:id=>s.localRoom.players.find(p=>p.id===id),secondaryMember:()=>s.localRoom.players.find(p=>p.kind==='local'&&p.owner===s.localRoom.self),
  winnerName:id=>s.tanks.find(t=>t.id===id)?.name||'MISSING',newTank:id=>({...s.localRoom.players.find(p=>p.id===id),alive:true,color:'#fff'})};
 vm.createContext(s);
 const names=['survivalMode','beginLocalMatchStats','bindLocalTankStats','finishLocalMatchStats','finishRound','clearLocalSeat','moveLocalMember','update','finishMatch','showVictory','restartLocalMatch'];
 for(const helper of ['matchResultEntries','resultMemberMatches'])if(source.includes('function '+helper+'('))names.push(helper);
 for(const name of names)vm.runInContext(declaration(name),s);
 s.beginLocalMatchStats();for(const tank of s.tanks)s.bindLocalTankStats(tank);
 return {s,$,players};
}
function complete(s){s.phaseTime=0;s.update(1/120);}
function winnerRow(s){return s.localMatchReport?.players.find(row=>row.member===101);}
function scoreLabels($){return $('victoryScores').children.map(row=>row.children.map(c=>c.textContent).join(':'));}

test('winning team result keeps original members and score when the winning pilot spectates',()=>{
 const {s,$,players}=boot({teams:true});s.finishRound(0);
 s.moveLocalMember(players[0],s.localRoom.nextViewer++,true);complete(s);
 assert.equal(s.phase,'matchOver');
 assert.equal(winnerRow(s)?.winner,true);
 assert.equal(winnerRow(s)?.active,true,'result records participants at the winning moment');
 assert.equal(winnerRow(s)?.score,1);
 assert.equal($('victoryTitle').textContent,'TEAM 1 WINS!');
 assert.match($('victoryMembers').textContent,/ORIGINAL/);
 assert.ok(scoreLabels($).includes('TEAM 1:1'));
});
test('a spectator swapping into the winning seat cannot receive the original pilot win',()=>{
 const {s,$,players}=boot();
 const replacement={id:8,member:104,name:'REPLACEMENT',kind:'local',owner:0,spectating:true,team:0};players.push(replacement);
 s.finishRound(0);s.moveLocalMember(players[0],9,true);s.moveLocalMember(replacement,0,false,0,1);complete(s);
 assert.equal(s.phase,'matchOver');assert.equal(winnerRow(s)?.winner,true);
 assert.equal(s.localMatchReport.players.some(row=>row.member===104&&row.winner),false);
 assert.match($('victoryTitle').textContent,/ORIGINAL/);
 assert.equal($('victoryMembers').textContent,'ORIGINAL');
 assert.ok(scoreLabels($).includes('ORIGINAL:1'));
 assert.equal(scoreLabels($).some(label=>label.startsWith('REPLACEMENT:')),false);
});
test('reusing a winning seat with a reset score cannot cancel a clinched match',()=>{
 const {s,$,players}=boot();s.finishRound(0);
 s.moveLocalMember(players[0],8,true);s.moveLocalMember(players[0],0,false,0);
 assert.equal(s.scores[0],0,'normal seat initialization resets the live score');complete(s);
 assert.equal(s.phase,'matchOver');assert.equal(s.starts,undefined);
 assert.equal(winnerRow(s)?.winner,true);assert.equal(winnerRow(s)?.score,1);
 assert.ok(scoreLabels($).includes('ORIGINAL:1'));
});
test('a nonfinal round remains open and starts the next round after its result delay',()=>{
 const {s,players}=boot({teams:true,target:2});s.finishRound(0);
 assert.equal(s.localMatchReport,null);assert.equal(s.localMatchResult,null);
 s.moveLocalMember(players[0],s.localRoom.nextViewer++,true);complete(s);
 assert.equal(s.phase,'countdown');assert.equal(s.round,2);assert.equal(s.starts,1);
 assert.equal(s.localMatchReport,null);
});
test('starting a new local match clears the frozen result from the previous match',()=>{
 const {s}=boot();s.finishRound(0);complete(s);assert.ok(s.localMatchReport);assert.ok(s.localMatchResult);
 s.beginLocalMatchStats();assert.equal(s.localMatchReport,null);assert.equal(s.localMatchResult,null);
});
test('result ownership follows membership across role changes and rejects reused seats',()=>{
 const {s}=boot();assert.equal(typeof s.resultMemberMatches,'function');
 assert.equal(s.resultMemberMatches({member:101,id:0},{member:101,id:8,spectating:true}),true);
 assert.equal(s.resultMemberMatches({member:101,id:0},{member:104,id:0}),false);
 assert.equal(s.resultMemberMatches({member:101,id:0},null),false);
 assert.equal(s.resultMemberMatches({member:0,id:0},{member:101,id:0}),true,'legacy reports can use a seat fallback');
});

test('restart during a clinched result opens results instead of starting another round',()=>{
 const {s,$}=boot();s.finishRound(0);s.phase='paused';s.restartLocalMatch();
 assert.equal(s.phase,'matchOver');assert.equal(s.starts,undefined);
 assert.match($('victoryTitle').textContent,/ORIGINAL/);
});
