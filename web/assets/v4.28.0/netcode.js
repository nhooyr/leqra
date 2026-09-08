/* leqra v4.2 networking math. No DOM, dependencies, or trusted client state.
 * Used by the game and deterministic Node tests.
 * See PROTOCOL.md for held-input acknowledgements (ack + ackSteps).
 */
(function(root,factory){
 'use strict';
 const api=factory();
 if(typeof module==='object'&&module.exports)module.exports=api;
 else root.leqraNet=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
 'use strict';
 const STEP=1/60, STEP_MS=1000/60;
 const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
 const delta=(a,b)=>Math.atan2(Math.sin(b-a),Math.cos(b-a));
 const neutral=()=>({forward:false,reverse:false,left:false,right:false,fire:false,stickX:0,stickY:0});
 // Wire-only expansion: physics and replay consume the unchanged bullet shape.
 // Bounding and finite checks keep malformed frames from creating NaN renders.
 function expandMachineBullets(records,colors){
  if(!Array.isArray(records))return[];
  const out=[];for(const a of records.slice(0,768)){
   if(!Array.isArray(a)||a.length!==12||a.some(n=>!Number.isFinite(n))||!Number.isInteger(a[1])||a[1]<0||a[1]>=8||!Number.isInteger(a[11])||a[11]<0||a[11]>=8)continue;
   out.push({id:a[0],owner:a[1],shotSerial:a[2],spawnSerial:a[3],x:a[4],y:a[5],vx:a[6],vy:a[7],age:a[8],life:a[9],bounces:a[10],color:colors[a[11]],kind:'rapid',r:3.5/3,pellet:0,target:-1});
  }return out;
 }
 function controlsEqual(a,b){
  return !!a&&!!b&&a.forward===b.forward&&a.reverse===b.reverse&&a.left===b.left&&a.right===b.right&&a.fire===b.fire&&Math.abs(a.stickX-b.stickX)<.001&&Math.abs(a.stickY-b.stickY)<.001;
 }
 // Identical movement order, rates, angle normalization and wall collision to Go.
 // No fire, damage or scoring is performed here.
 function move(t,input,dt,moveTank){
  const x=t.x,y=t.y;
  t.speedTime=Math.max(0,(t.speedTime||0)-dt);
  if(t.speedTime<=0)t.speedStacks=0;
  const wasGhost=t.ghostTime>0;t.ghostTime=Math.max(0,(t.ghostTime||0)-dt);
  if(wasGhost&&t.ghostTime===0)moveTank(t,0,0,true);
  const stacks=t.speedTime>0?Math.max(1,Math.min(5,t.speedStacks||1)):0;
  const speedScale=1+.65*stacks,turnScale=1+.25*stacks;
  let throttle=(input.forward?1:0)-(input.reverse?.72:0);
  const mag=Math.hypot(input.stickX,input.stickY);
  if(mag>.10){
   const diff=delta(t.angle,Math.atan2(input.stickY,input.stickX));
   t.angle+=clamp(diff,-5.8*turnScale*dt,5.8*turnScale*dt);
   throttle=Math.min(mag,1)*Math.max(0,Math.cos(diff));
  }else t.angle+=((input.right?1:0)-(input.left?1:0))*3.65*turnScale*dt;
  t.angle=Math.atan2(Math.sin(t.angle),Math.cos(t.angle));
  moveTank(t,Math.cos(t.angle)*128*speedScale*throttle*dt,Math.sin(t.angle)*128*speedScale*throttle*dt);
  t.vx=dt?(t.x-x)/dt:0;t.vy=dt?(t.y-y)/dt:0;
  t.track=(t.track||0)+Math.hypot(t.x-x,t.y-y);
 }
 class Predictor{
  constructor(moveTank){this.moveTank=moveTank;this.reset(null);}
  reset(t){
   this.state=t?{...t}:null;this.frames=[];this.sent=new Map();this.stepID=0;
   this.accumulator=0;this.input=neutral();this.offset={x:0,y:0,angle:0};
   this.metrics={corrections:0,hardResets:0,lastError:0,maxError:0,replayed:0};
  }
  // A sequence identifies the *start* of a held input, not a single movement.
  // Go reports how many ticks it actually applied that input. This is necessary
  // because snapshots, input packets, and simulation ticks have different rates.
  sentInput(seq){
   this.sent.set(seq,this.stepID+1);
   while(this.sent.size>256)this.sent.delete(this.sent.keys().next().value);
  }
  advance(dt,input,beforeStep){
   if(!this.state||!this.state.alive)return;
   this.input={...input};this.accumulator+=clamp(dt,0,.1);
   let count=0;
   while(this.accumulator+1e-9>=STEP&&count++<6){
    if(beforeStep)beforeStep(this.input,this.stepID+1);
    this.stepID++;
    move(this.state,this.input,STEP,this.moveTank);
    this.frames.push({step:this.stepID,input:{...this.input}});
    if(this.frames.length>240)this.frames.shift();
    this.accumulator=Math.max(0,this.accumulator-STEP);
   }
  }
  reconcile(authority,snap=false){
   if(!this.state||snap||this.state.alive!==authority.alive){this.reset(authority);return;}
   const before={...this.state},next={...authority};
   const start=this.sent.get(authority.ack);
   const processed=start===undefined?(authority.ack===0?0:this.stepID):start+Math.max(1,authority.ackSteps||1)-1;
   const oldest=this.frames[0]?.step??this.stepID+1;
   let replayed=0;
   // Never replay an incomplete history after a long suspended tab / outage.
   const historyOK=processed>=oldest-1;
   if(authority.alive&&historyOK){
    for(const f of this.frames)if(f.step>processed){move(next,f.input,STEP,this.moveTank);replayed++;}
   }
   const error=Math.hypot(before.x-next.x,before.y-next.y);
   this.metrics.lastError=error;this.metrics.maxError=Math.max(error,this.metrics.maxError);
   this.metrics.replayed=replayed;
   if(error>.025||Math.abs(delta(next.angle,before.angle))>.001)this.metrics.corrections++;
   // Only the *rendered* offset is softened. Physics immediately uses the
   // authoritative state plus unacknowledged inputs, never a blended position.
   const ghosting=(before.ghostTime||0)>0||(next.ghostTime||0)>0;
   if(!historyOK||!authority.alive||error>64||ghosting){
    // Ghost movement passes through interior walls. Blending an old correction
    // vector while phasing can visibly tug the tank sideways across a wall even
    // though replayed physics is correct, so render the replayed trajectory directly.
    this.offset={x:0,y:0,angle:0};if(!ghosting)this.metrics.hardResets++;
   }else{
    this.offset.x+=before.x-next.x;this.offset.y+=before.y-next.y;
    this.offset.angle=delta(0,this.offset.angle+delta(next.angle,before.angle));
    const length=Math.hypot(this.offset.x,this.offset.y);
    if(length>48){this.offset.x*=48/length;this.offset.y*=48/length;}
    this.offset.angle=clamp(this.offset.angle,-.7,.7);
   }
   this.state=next;
  }
  visual(dt,active=true){
   if(!this.state)return null;
   const t={...this.state};
   // Sub-tick render prediction keeps 90/120/144 Hz displays smooth without
   // changing the 60 Hz authoritative-compatible history.
   if(active&&t.alive&&this.accumulator>0)move(t,this.input,this.accumulator,this.moveTank);
   if(active&&t.alive){
    this.moveTank(t,this.offset.x,this.offset.y);t.angle+=this.offset.angle;
   }
   const f=Math.exp(-clamp(dt,0,.1)/.11);
   this.offset.x*=f;this.offset.y*=f;this.offset.angle*=f;
   return t;
  }
 }
 const newestTime=items=>items[items.length-1].netTime;
 class SnapshotBuffer{
  constructor(){this.reset();}
  reset(){
   this.items=[];this.time=null;this.interval=1000/30;this.delay=75;
   this.jitter=0;this.jitterPeak=0;this.lastArrival=null;this.lastStamp=null;
   this.underruns=0;this.starved=false;this.rate=1;
  }
  push(snapshot,now){
   const stamp=snapshot.tick*STEP_MS,last=this.items[this.items.length-1];
   if(last&&snapshot.tick<=last.tick)return false;
   if(last){
    const sample=stamp-this.lastStamp;
    if(sample>0&&sample<250)this.interval+=(sample-this.interval)*.06;
    const variation=Math.abs((now-this.lastArrival)-sample);
    this.jitter+=(Math.min(variation,200)-this.jitter)*.1;
    this.jitterPeak=Math.max(this.jitterPeak*.92,Math.min(variation,140));
    const wanted=clamp(this.interval*2+Math.max(this.jitter*2,this.jitterPeak*.85),70,180);
    this.delay+=(wanted-this.delay)*(wanted>this.delay?.25:.018);
   }
   snapshot.netTime=stamp;this.items.push(snapshot);
   if(this.items.length>90)this.items.shift();
   this.lastArrival=now;this.lastStamp=stamp;
   if(this.time===null)this.time=stamp-this.delay;
   return true;
  }
  advance(dt){
   if(!this.items.length)return null;
   const newest=this.items[this.items.length-1];
   const fill=newest.netTime-this.time;
   // Playback never restarts or runs backward on packet arrival. Small rate
   // adjustments grow/shrink the buffer instead of teleporting its playhead.
   const error=fill-this.delay,deadband=Math.max(12,this.interval*.6);
   const wanted=error>deadband?1.05:error<-deadband?.95:1;
   this.rate+=(wanted-this.rate)*Math.min(1,dt*6);
   this.time+=clamp(dt,0,.1)*1000*this.rate;
   const limit=newest.netTime+75;
   if(this.time>limit){
    this.time=limit;
    if(!this.starved)this.underruns++;
    this.starved=true;
   }else this.starved=false;
   // After a very long browser suspension skip obsolete *past* frames only.
   if(newest.netTime-this.time>600)this.time=newest.netTime-this.delay;
   const oldest=this.items[0];
   let a=oldest,b=oldest;
   for(let i=1;i<this.items.length;i++){
    b=this.items[i];
    if(b.netTime>=this.time)break;
    a=b;
   }
   if(this.time>=newest.netTime)a=b=newest;
   const span=b.netTime-a.netTime;
   return{a,b,alpha:span>0?clamp((this.time-a.netTime)/span,0,1):1,
    extrapolate:Math.max(0,this.time-newest.netTime)/1000,time:this.time};
  }
  tank(id,frame,moveTank){
   const latest=this.items[this.items.length-1]?.tankMap.get(id);
   if(!latest||!frame)return null;
   const a=frame.a.tankMap.get(id),b=frame.b.tankMap.get(id);
   // Never resurrect a tank or blend a respawn/teleport across generations.
   if(!latest.alive||!a||!b||(a.ghostTime>0)!==(b.ghostTime>0)||(b.ghostTime>0)!==(latest.ghostTime>0)||a.alive!==b.alive||a.spawnSerial!==b.spawnSerial||a.spawnSerial!==latest.spawnSerial||b.spawnSerial!==latest.spawnSerial||Math.hypot(a.x-b.x,a.y-b.y)>100)return{...latest};
   const f=frame.alpha,t={...b,x:a.x+(b.x-a.x)*f,y:a.y+(b.y-a.y)*f,
    angle:a.angle+delta(a.angle,b.angle)*f,track:a.track+(b.track-a.track)*f};
   if(frame.extrapolate>0&&t.alive){
    // Extrapolation is short and wall constrained. It never awards a hit.
    const dt=Math.min(.075,frame.extrapolate);
    moveTank(t,(b.vx||0)*dt,(b.vy||0)*dt);
    const items=this.items,prior=items.length>1?items[items.length-2]:null;
    const prev=prior?.tankMap.get(id),span=prior?(newestTime(items)-prior.netTime)/1000:0;
    if(prev?.alive&&prev.spawnSerial===b.spawnSerial&&span>0&&span<.25){
     // A tank can rotate in place: positional velocity alone loses that motion.
     const omega=clamp(delta(prev.angle,b.angle)/span,-7.25,7.25);
     t.angle=b.angle+omega*dt;
    }
   }else moveTank(t,0,0); // Keep interpolated corners outside solid walls too.
   return t;
  }
 }

 // Local response only: this ledger cannot spend authoritative ammunition, choose
 // a victim, or award a hit. Accepted server volley IDs reconcile predictions.
 class ShotPresentation {
  constructor(){this.reset();}
  reset(){this.pilots=new Map();this.previews=new Map();this.soundKeys=new Map();}
  key(id,life,shot){return id+':'+(life||0)+':'+shot;}
  sync(t,phase,now){
   let p=this.pilots.get(t.id);const life=t.spawnSerial||0,serial=t.shotSerial||0;
   if(!p||p.life!==life){
    this.remove(t.id);p={life,serial,next:serial,until:now+(t.cooldown||0)*1000,total:t.cooldownTotal||.34,held:false,blocked:false};
    this.pilots.set(t.id,p);
   }
   if(phase!=='playing'||!t.alive){
    for(const [k,v]of this.previews)if(v.owner===t.id)this.previews.delete(k);
    p.until=now;p.held=false;p.blocked=false;p.serial=p.next=serial;return p;
   }
   if(serial!==p.serial){
    const key=this.key(t.id,life,serial),pred=this.previews.get(key);
    // Keep the already-shown countdown when the same shot is acknowledged.
    if(!pred){p.until=now+Math.max(0,t.cooldown||0)*1000;p.total=t.cooldownTotal||p.total;}
    for(const v of this.previews.values())if(v.owner===t.id&&v.shot<=serial)v.accepted=true;
    p.serial=serial;p.next=Math.max(p.next,serial);
   }else if(![...this.previews.values()].some(v=>v.owner===t.id&&!v.accepted)){
    // The deadline may approach, but never sawtooth back up for one volley.
    p.until=Math.min(p.until,now+Math.max(0,t.cooldown||0)*1000);
   }
   return p;
  }
  remove(id){this.pilots.delete(id);for(const [k,v]of this.previews)if(v.owner===id)this.previews.delete(k);}
  cooldown(t,now){const p=this.pilots.get(t.id);return p?Math.max(0,(p.until-now)/1000):Math.max(0,t.cooldown||0);}
  machineRounds(t){
   let remaining=Math.max(0,t.machineRounds||0);
   for(const v of this.previews.values())if(v.owner===t.id&&!v.accepted&&v.power==='rapid')remaining--;
   return Math.max(0,remaining);
  }
  tryFire(t,held,now,options){
   const p=this.pilots.get(t.id);if(!p)return null;
   const pressed=held&&!p.held;p.held=held;if(!held)p.blocked=false;
   if(!options.active||!t.alive||!held)return null;
   if(pressed&&options.grenade){p.blocked=true;return null;}
   if(p.blocked)return null;
   // Grenade is a press action, not an automatic weapon. A blocked throw consumes
   // the hold just as it does on Go; it must not fire later by itself.
   if(t.power==='grenade'){if(!pressed)return null;p.blocked=true;}
   // A single pass avoids three temporary arrays on the 60 Hz rapid-fire path.
   let pending=0,slots=0,chargeUse=0;
   for(const v of this.previews.values())if(v.owner===t.id&&!v.accepted){pending++;slots+=v.shells.length;if(v.power===t.power)chargeUse++;}
   if(this.cooldown(t,now)>.001||options.blocked||options.free-slots<options.need||pending>=(t.power==='rapid'?48:4)||
      (options.charged&&t.charges-chargeUse<=0)||(t.power==='rapid'&&!(t.machineRounds-chargeUse>0)))return null;
   if(t.power==='rapid'){const tick=Math.floor(now/STEP_MS);if(p.rapidTick===tick)return null;p.rapidTick=tick;}
   const shot=++p.next,key=this.key(t.id,p.life,shot),total=options.cooldown;
   const v={key,owner:t.id,life:p.life,shot,power:t.power||'',at:now,until:now+1000*total,
    expires:now+clamp(options.ttl||600,250,900),shells:[],accepted:false,confirmed:new Set()};
   p.until=v.until;p.total=total;this.previews.set(key,v);this.soundKeys.set(key,now+2000);
   return v;
  }
  heard(id,life,shot){return this.soundKeys.has(this.key(id,life,shot));}
  pendingGrenade(id){for(const v of this.previews.values())if(v.owner===id&&v.power==='grenade'&&!v.accepted)return true;return false;}
  prune(now,activeIDs){
   for(const [k,v]of this.previews)if(now>v.expires||!activeIDs.has(v.owner))this.previews.delete(k);
   for(const [k,until]of this.soundKeys)if(now>until)this.soundKeys.delete(k);
   for(const id of this.pilots.keys())if(!activeIDs.has(id))this.remove(id);
   for(const p of this.pilots.values()){let pending=false;for(const v of this.previews.values())if(v.owner!==undefined&&this.pilots.get(v.owner)===p&&!v.accepted){pending=true;break;}if(!pending)p.next=p.serial;}
  }
 }
 return Object.freeze({expandMachineBullets,STEP,STEP_MS,clamp,delta,neutral,controlsEqual,move,Predictor,SnapshotBuffer,ShotPresentation});
});
