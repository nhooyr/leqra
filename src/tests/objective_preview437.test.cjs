'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);return source.slice(start,source.indexOf('\n}',start)+2);}
function boot(gameMode,network=false){
 const calls=[],noop=()=>{},ctx=new Proxy({arc(...args){calls.push(['arc',...args]);},fillText(...args){calls.push(['text',...args]);}},{get:(target,key)=>target[key]??noop});
 const objective={mode:gameMode,flags:gameMode==='ctf'?[{team:1,homeX:42,homeY:42,x:42,y:42,home:true,carrier:-1},{team:2,homeX:546,homeY:546,x:546,y:546,home:true,carrier:-1}]:[],hillX:294,hillY:294,radius:42,owner:1,hold:.25};
 const s={mode:network?'online':'room',phase:'playing',pendingMatchPresentation:null,ctx,scale:1,W:588,H:588,TAU:Math.PI*2,COLORS:['#0ff','#f0f'],tanks:[],theme:{neutralHillFill:'#123',neutralHill:'#fff'},reduceMotion:true,fxTime:0,
  objectiveState:()=>objective,objectiveMode:()=>true,teamColor:(_id,team)=>team===1?'#0ff':'#f0f',paintColor:c=>c,clamp:(n,a,b)=>Math.max(a,Math.min(b,n)),roundRect:noop};
 vm.createContext(s);vm.runInContext(declaration('drawObjectives')+'\n'+declaration('drawFlags'),s);
 const draw=()=>{calls.length=0;s.drawObjectives();s.drawFlags();return JSON.parse(JSON.stringify(calls));};
 return{s,objective,draw};
}
test('CTF flags/bases and Hill remain in the frozen final scene during local and online result previews',()=>{
 for(const gameMode of ['ctf','koth'])for(const online of [false,true]){
  const {s,objective,draw}=boot(gameMode,online),before=JSON.stringify(objective),live=draw();assert.ok(live.length>0);
  s.phase='matchOver';s.pendingMatchPresentation={at:2000};assert.deepEqual(draw(),live,gameMode+' final scene');
  assert.equal(JSON.stringify(objective),before,'drawing never advances the finalized objective');
  s.pendingMatchPresentation=null;assert.deepEqual(draw(),[],'hide objectives after the full results menu opens');
 }
});
test('objective preview visibility still excludes lobbies and sudden-death objectives',()=>{
 for(const gameMode of ['ctf','koth']){
  const {s,objective,draw}=boot(gameMode);s.pendingMatchPresentation={at:2000};
  for(const phase of ['menu','onlineLobby']){s.phase=phase;assert.deepEqual(draw(),[]);}
  s.phase='matchOver';objective.suddenDeath=true;assert.deepEqual(draw(),[]);
 }
});
