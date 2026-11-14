'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {boot,tank}=require('./godlike426-harness.cjs');

test('Dumb bots hesitate and do not predict a moving target',()=>{
 const s=boot(),bot=tank(0,210,210,{difficulty:'dumb'}),enemy=tank(1,378,210,{human:true,vx:100,vy:70});
 s.tanks=[bot,enemy];s.rnd=(lo)=>lo;
 for(let i=0;i<240;i++)s.botControl(bot,1/120);
 assert.equal(s.fired||0,0,'a skipped attack decision must not fire');
 assert.equal(bot.ai.aim,null);
 const point=s.leadPoint(bot,enemy,s.tune.dumb);
 assert.equal(point.x,enemy.x);assert.equal(point.y,enemy.y);
});

test('Dumb firing stays slow even with a machine gun or Starman',()=>{
 for(const power of [null,'rapid','laser'])for(const starmanTime of [0,8]){
  const s=boot(),bot=tank(0,210,210,{difficulty:'dumb',power,starmanTime}),enemy=tank(1,378,210,{human:true});
  bot.ai.shotClock=1.8;s.tanks=[bot,enemy];const shots=[];let clock=0;
  s.fire=()=>{shots.push(clock);return true;};
  for(let i=0;i<1440;i++){clock+=1/120;s.botControl(bot,1/120);}
  assert.ok(shots.length>=2,'Dumb bots can still fire '+power);
  assert.ok(shots[0]>=1.8-1e-8,'initial reaction delay');
  for(let i=1;i<shots.length;i++)assert.ok(shots[i]-shots[i-1]>=1.8-1e-8,power+' bypassed the reaction delay');
 }
});
