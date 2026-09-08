'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path');
const {boot,tank}=require('./godlike426-harness.cjs');
// Keep the previous object-based implementation as an independent scoring oracle.
const previousSource="function godlikePickupValue(t,p){\n if(p.type==='shield')return shieldCount(t)>=5&&t.shield>4?0:shieldCount(t)?2.2:4.5;\n if(p.type==='speed')return speedCount(t)>=MAX_SPEED_STACKS&&t.speedTime>4?0:speedCount(t)<2?3.5:1.5;\n if(p.type==='ghost')return t.ghostTime>4?0:3;\n if(p.type==='scope')return t.scopeTime>3?0:.3;\n const value={rapid:2.6,scatter:2.2,homing:3.1,grenade:2,laser:3.3,cannon:3.7};\n if(!t.power||t.powerTime<2||t.power==='rapid'&&(t.machineRounds??180)<120)return value[p.type]||0;\n if(t.power===p.type)return t.powerTime<5||t.charges<=1?1.4:.15;\n return Math.max(0,(value[p.type]||0)-(value[t.power]||0)+.25);\n}";

test('Godlike pickup scoring preserves weapon, expiry, ammunition and buff decisions',()=>{
 const s=boot(),previous=new Function('shieldCount','speedCount','MAX_SPEED_STACKS',previousSource+';return godlikePickupValue;')(s.shieldCount,s.speedCount,5);
 const kinds=['rapid','scatter','homing','grenade','laser','cannon','shield','speed','ghost','scope','','unknown'];
 const check=t=>{for(const type of kinds){const p={type};assert.equal(s.godlikePickupValue(t,p),previous(t,p),JSON.stringify({type,power:t.power,time:t.powerTime,charges:t.charges,rounds:t.machineRounds}));}};
 for(const power of kinds)for(const powerTime of [0,1.99,2,3,5,8])for(const charges of [0,1,3])for(const machineRounds of [undefined,119,120,180])check(tank(0,126,126,{power,powerTime,charges,machineRounds}));
 for(const duration of [0,3,3.0001,4,4.0001,10])for(const stacks of [0,1,5,6])check(tank(0,126,126,{shield:duration,shieldCharges:stacks,speedTime:duration,speedStacks:stacks,ghostTime:duration,scopeTime:duration}));
});

test('production and unversioned game assets remain identical after pickup scoring optimization',()=>{
 assert.equal(readFileSync(path.join(__dirname,'../web/game.js'),'utf8'),readFileSync(path.join(__dirname,'../web/assets/v4.46.0/game.js'),'utf8'));
});
