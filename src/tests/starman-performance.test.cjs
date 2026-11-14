'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
function laserFixture(){
 const start=source.indexOf('function fireLaser('),end=source.indexOf('\n}',start)+2;
 const counts={traces:0,effects:0,hits:0},tank={alive:true,power:'laser',starmanTime:8,charges:1,cooldown:0};
 const context={time:0,Net:require(assetPath('netcode.js')),fire(){},LASER_COOLDOWN:.85*2/3,POWER:{laser:{color:'#fff'}},muzzleBlocked:()=>false,
  laserTrace(){counts.traces++;return{x:0,y:0,endX:100,endY:0,points:[{x:0,y:0},{x:100,y:0}],target:context.target};},
  laserEffect(){counts.effects++;},shotSound(){},hurt(){counts.hits++;}};
 vm.createContext(context);vm.runInContext(source.slice(start,end),context);
 return{context,tank,counts};
}

test('Starman laser checks all 60 volleys while emitting 15 cosmetic beams per second',()=>{
 const {context,tank,counts}=laserFixture();
 for(let tick=0;tick<120;tick++){context.time=tick/120;context.fireLaser(tank);}
 assert.deepEqual(counts,{traces:60,effects:15,hits:0});
 assert.equal(tank.charges,1);assert.equal(tank.power,'laser');assert.equal(tank.cooldown,0);
});

test('a Starman laser hit between cosmetic samples still presents its exact beam immediately',()=>{
 const {context,tank,counts}=laserFixture();
 context.fireLaser(tank);context.time=1/60;context.target={alive:true};
 assert.equal(context.fireLaser(tank),true);
 assert.deepEqual(counts,{traces:2,effects:2,hits:1});assert.equal(tank.charges,1);
});

test('ordinary charged laser retains every shot cosmetic and its normal ammo cost',()=>{
 const {context,tank,counts}=laserFixture();tank.starmanTime=0;tank.charges=3;
 for(let shot=0;shot<3;shot++){tank.cooldown=0;context.time=shot;assert.equal(context.fireLaser(tank),true);}
 assert.deepEqual(counts,{traces:3,effects:3,hits:0});assert.equal(tank.charges,0);assert.equal(tank.power,null);
});

test('fixed projectile broad phase preserves exhaustive protected, allied, grazing and swept contacts',()=>{
 const {boot,tank}=require('./godlike426-harness.cjs'),{random}=require('./spatial439-harness.cjs'),s=boot(),rand=random(44937);
 s.tanks=Array.from({length:8},(_,id)=>tank(id,0,0,{team:id%3+1}));
 const exhaustive=(x,y,dx,dy,r,owner,impactOnly)=>{
  let first=null;for(const t of s.tanks){
   if(!t.alive||t.id===owner||!impactOnly&&(!s.canDamage(owner,t)||t.invulnerable>0))continue;
   const at=s.circleHit(x,y,dx,dy,t.x,t.y,t.r+r);if(at!==null&&(!first||at<first.at))first={at,tank:t};
  }return first;
 };
 for(let sample=0;sample<6000;sample++){
  for(const t of s.tanks){t.x=rand()*2000-1000;t.y=rand()*1200-600;t.alive=rand()>.2;t.invulnerable=rand()>.5?1:0;}
  s.friendlyFire=sample%2===0;
  const query=[rand()*2000-1000,rand()*1200-600,sample%11?rand()*2000-1000:0,sample%11?rand()*1200-600:0,[3.5,3.5/3,14,6][sample%4],sample%8,sample%3===0];
  const actual=s.tankHit(...query),expected=exhaustive(...query);
  assert.equal(actual?.tank.id,expected?.tank.id,'sample '+sample);assert.equal(actual?.at,expected?.at,'sample '+sample);
 }
 s.tanks=[tank(0,-100,0),tank(1,100,20.5),tank(2,100,20.5)];
 assert.equal(s.tankHit(0,0,200,0,3.5,0)?.tank.id,1,'grazing ties keep roster order');
 s.tanks[1].invulnerable=s.tanks[2].invulnerable=10;
 assert.equal(s.tankHit(0,0,200,0,3.5,0),null);
 assert.equal(s.tankHit(0,0,200,0,3.5,0,true)?.tank.id,1,'grenades still contact protected tanks');
});
