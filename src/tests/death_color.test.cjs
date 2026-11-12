'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),{readFileSync}=require('node:fs');
const {assetPath}=require('./web_assets.cjs');
const game=readFileSync(assetPath('game.js'),'utf8'),fixtures=require('./killer-color-fixtures.json');
function declaration(name){const start=game.indexOf('function '+name+'('),end=game.indexOf('\n',start),line=game.slice(start,end);assert.ok(start>=0,name);return line.endsWith('}')?line:game.slice(start,game.indexOf('\n}',end)+2);}
class Element{
 constructor(tag='div'){this.tagName=tag.toUpperCase();this.children=[];this.style={};this.hidden=false;this.text='';}
 get textContent(){return this.text+this.children.map(child=>child.textContent).join('');}
 set textContent(value){this.text=String(value);this.children=[];}
 replaceChildren(...children){this.text='';this.children=children;}
}
function boot(){
 const nodes=new Map(),$=id=>{if(!nodes.has(id))nodes.set(id,new Element());return nodes.get(id);};
 const document={documentElement:{dataset:{},style:{}},querySelector:()=>null,createElement:tag=>new Element(tag)};
 const context=vm.createContext({window:{},document,$});vm.runInContext(readFileSync(assetPath('theme.js'),'utf8'),context);context.paintColor=context.window.leqraTheme.assetColor;
 vm.runInContext(declaration('renderDeathNotice'),context);return{context,$};
}
test('death notices safely bold only the killer name and map every canonical tank color',()=>{
 const {context:s,$}=boot();
 for(const fixture of fixtures){
  s.renderDeathNotice({alive:false,killedBy:'RUST <img src=x> & "雪"',killedByColor:fixture.canonical},2,true);
  const notice=$('deathNotice2'),[prefix,killer]=notice.children;
  assert.equal(notice.textContent,'Killed by RUST <img src=x> & "雪"');assert.equal(notice.hidden,false);
  assert.equal(prefix.textContent,'Killed by ');assert.equal(prefix.style.color,undefined);assert.equal(killer.tagName,'STRONG');assert.equal(killer.style.color,fixture.painted);assert.equal(killer.children.length,0);
  s.renderDeathNotice({alive:false,killedBy:'RUST <img src=x> & "雪"',killedByColor:fixture.canonical},2,true);assert.equal(notice.children[1],killer,'unchanged HUD refreshes retain the name node');
 }
});
test('offscreen killers, independent local victims and missing colors never borrow another notice’s tint',()=>{
 const {context:s,$}=boot(),id=key=>'infinite'+key[0].toUpperCase()+key.slice(1);
 s.renderDeathNotice({alive:false,killedBy:'Absent bot',killedByColor:fixtures[5].canonical},1,true,id);
 s.renderDeathNotice({alive:false,killedBy:'Absent pilot',killedByColor:fixtures[6].canonical},2,true,id);
 assert.equal($('infiniteDeathNotice1').children[1].style.color,fixtures[5].painted);assert.equal($('infiniteDeathNotice2').children[1].style.color,fixtures[6].painted);
 s.renderDeathNotice({alive:false,killedBy:'Unknown paint'},1,true,id);assert.equal($('infiniteDeathNotice1').children[1].style.color,undefined);
 s.renderDeathNotice({alive:true,killedBy:'old',killedByColor:fixtures[5].canonical},1,true,id);assert.equal($('infiniteDeathNotice1').hidden,true);assert.equal($('infiniteDeathNotice1').children.length,0);assert.equal($('infiniteDeathNotice2').hidden,false);
});
test('fixed local deaths capture the killer color before departure and clear metadata on respawn',()=>{
 const {context:s}=boot(),owner={id:1,name:'BOT',color:fixtures[3].canonical},target={id:3,name:'Victim',color:fixtures[0].canonical,alive:true,invulnerable:0,shield:0,r:17};
 const noop=()=>{};Object.assign(s,{tanks:[owner,target],canDamage:()=>true,recordLocalDeath:noop,objectiveMode:()=>false,burst:noop,addRing:noop,reduceMotion:true,boom:noop,addLog:noop,mode:'room',touchUI:false,updateHUD:noop});
 vm.runInContext(declaration('hurt'),s);assert.equal(s.hurt(target,{owner:1}),true);assert.equal(target.killedByColor,fixtures[3].canonical);
 s.tanks=[target];s.renderDeathNotice(target,2,true);assert.equal(s.$('deathNotice2').children[1].style.color,fixtures[3].painted);
 Object.assign(s,{localObjectives:null,spawnCells:()=>Array(8).fill(0),MAX_TANKS:8,grid:[{neighbors:[]}],center:()=>({x:42,y:42}),flagSafeSpawn:()=>true,distance:()=>1000,bullets:[],cols:1,rows:1,newTank:()=>({alive:true,r:17,color:target.color}),firePresses:new Set(),localPlayerID:()=>3,mouseAim:{},addRing:noop});
 vm.runInContext(declaration('respawnLocalTank'),s);s.respawnLocalTank(target);assert.equal(target.killedBy,'');assert.equal(target.killedByColor,'');s.renderDeathNotice(target,2,true);assert.equal(s.$('deathNotice2').hidden,true);
});
