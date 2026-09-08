'use strict';
const {readFileSync}=require('node:fs'),path=require('node:path'),{performance}=require('node:perf_hooks');
const source=readFileSync(process.env.LEQRA_PICKUP_SOURCE||path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');if(start<0)return '';const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
const score=new Function('shieldCount','speedCount','MAX_SPEED_STACKS',declaration('godlikeWeaponValue')+'\n'+declaration('godlikePickupValue')+';return godlikePickupValue;')(()=>0,()=>0,5);
const pickups=['rapid','scatter','homing','grenade','laser','cannon'].map(type=>({type})),results=[];let checksum=0;
for(const power of ['', 'homing']){
 const pilot={power,powerTime:10,charges:3,machineRounds:180},samples=[];
 for(let sample=0;sample<12;sample++){
  const start=performance.now();let total=0;
  for(let i=0;i<1000000;i++)total+=score(pilot,pickups[i%pickups.length]);
  checksum+=total;if(sample>=4)samples.push((performance.now()-start)*1000000/1000000);
 }
 samples.sort((a,b)=>a-b);results.push({power:power||'unarmed',medianNs:+samples[samples.length>>1].toFixed(3),samples:samples.length});
}
console.log(JSON.stringify({runtime:process.version,scope:'Isolated production Godlike weapon pickup scoring; excludes full AI, rendering and networking.',checksum,results},null,2));
