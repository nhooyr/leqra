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
 const STEP=1/60, STEP_MS=1000/60, MACHINE_CAPACITY=115, DIRECTION_TURN=5.8, TOUCH_TURN_ASSIST=3.2;
 // Resolve only a phased projectile's initial overlap. Ordinary ray sweeps
 // still ignore origins inside geometry; cover never becomes penetrable.
 function wallLaunch(x,y,ux,uy,radius,muzzle,walls,clearBounds){
  const launch={x,y,ux,uy,distance:0,muzzle,bounced:false,valid:true};
  const inside=(px,py,w)=>px>=w.x-radius&&px<=w.x+w.w+radius&&py>=w.y-radius&&py<=w.y+w.h+radius;
  let xs=null,ys=null;
  for(const w of walls)if(inside(x,y,w)){
   if(!xs){xs=[x];ys=[y];}
   xs.push(w.x-radius-.12,w.x+w.w+radius+.12);ys.push(w.y-radius-.12,w.y+w.h+radius+.12);
  }
  if(!xs)return launch;
  launch.bounced=true;launch.valid=false;let best=Infinity;
  for(const px of xs)for(const py of ys){
   const dx=px-x,dy=py-y,distance=dx*dx+dy*dy;
   if(distance>32*32||dx*ux+dy*uy>1e-7||clearBounds&&!clearBounds(px,py)||walls.some(w=>inside(px,py,w)))continue;
   if(distance>best+1e-7||Math.abs(distance-best)<=1e-7&&(px>launch.x+1e-7||Math.abs(px-launch.x)<=1e-7&&py>=launch.y))continue;
   best=distance;Object.assign(launch,{x:px,y:py,valid:true});
  }
  if(!launch.valid)return launch;
  launch.distance=Math.sqrt(best);launch.muzzle=Math.max(0,muzzle-launch.distance);
  if((launch.x-x)*ux<-1e-9)launch.ux=-ux;if((launch.y-y)*uy<-1e-9)launch.uy=-uy;
  return launch;
 }
 const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
 const delta=(a,b)=>Math.atan2(Math.sin(b-a),Math.cos(b-a));
 const neutral=()=>({forward:false,reverse:false,left:false,right:false,fire:false,stickX:0,stickY:0,aimOnly:false});
 // Wire-only expansion: physics and replay consume the unchanged bullet shape.
 // Bounding and finite checks keep malformed frames from creating NaN renders.
 function expandMachineBullets(records,colors){
  if(!Array.isArray(records))return[];
  const out=[];for(const a of records.slice(0,8*MACHINE_CAPACITY)){
   if(!Array.isArray(a)||a.length!==12||a.some(n=>!Number.isFinite(n))||!Number.isInteger(a[1])||a[1]<0||a[1]>=8||!Number.isInteger(a[11])||a[11]<0||a[11]>=8)continue;
   out.push({id:a[0],owner:a[1],shotSerial:a[2],spawnSerial:a[3],x:a[4],y:a[5],vx:a[6],vy:a[7],age:a[8],life:a[9],bounces:a[10],color:colors[a[11]],kind:'rapid',r:3.5/3,pellet:0,target:-1});
  }return out;
 }
 function controlsEqual(a,b){
  return !!a&&!!b&&a.forward===b.forward&&a.reverse===b.reverse&&a.left===b.left&&a.right===b.right&&a.fire===b.fire&&!!a.aimOnly===!!b.aimOnly&&!!a.touchAim===!!b.touchAim&&Math.abs(a.stickX-b.stickX)<.001&&Math.abs(a.stickY-b.stickY)<.001;
 }
 function smoothstep(value){
  const x=clamp(value,0,1);
  return x*x*(3-2*x);
 }
 function steeringTurn(diff,mag,assist,step){
  let rate=DIRECTION_TURN;
  if(assist)rate+=TOUCH_TURN_ASSIST*smoothstep((Math.min(mag,1)-.35)/.65)*smoothstep((Math.abs(diff)-Math.PI/12)/(Math.PI/2-Math.PI/12));
  const limit=rate*step;
  return clamp(diff,-limit,limit);
 }
 // Identical movement order, rates, angle normalization and wall collision to Go.
 // No fire, damage or scoring is performed here.
 function movementStacks(t){return Math.max(t.speedTime>0?clamp(t.speedStacks||1,1,5):0,t.starmanTime>0?2:0);}
 function move(t,input,dt,moveTank,ageStarman=true){
  if(ageStarman)t.starmanTime=Math.max(0,(t.starmanTime||0)-dt);
  t.speedTime=Math.max(0,(t.speedTime||0)-dt);
  if(t.speedTime<=0)t.speedStacks=0;
  const wasGhost=t.ghostTime>0;t.ghostTime=Math.max(0,(t.ghostTime||0)-dt);
  if(wasGhost&&t.ghostTime===0)moveTank(t,0,0,true);
  const x=t.x,y=t.y;
  const stacks=movementStacks(t);
  const speedScale=1+.65*stacks,turnScale=1+.25*stacks;
  let throttle=(input.forward?1:0)-(input.reverse?.72:0);
  const mag=Math.hypot(input.stickX,input.stickY);
  if(mag>.10){
   const diff=delta(t.angle,Math.atan2(input.stickY,input.stickX));
   t.angle+=steeringTurn(diff,mag,input.touchAim&&!input.aimOnly,turnScale*dt);
   if(!input.aimOnly)throttle=Math.min(mag,1)*Math.max(0,Math.cos(diff));
  }else t.angle+=((input.right?1:0)-(input.left?1:0))*3.65*turnScale*dt;
  t.angle=Math.atan2(Math.sin(t.angle),Math.cos(t.angle));
  moveTank(t,Math.cos(t.angle)*128*speedScale*throttle*dt,Math.sin(t.angle)*128*speedScale*throttle*dt);
  t.vx=dt?(t.x-x)/dt:0;t.vy=dt?(t.y-y)/dt:0;
  t.track=(t.track||0)+Math.hypot(t.x-x,t.y-y);
 }
 function moveRenderPose(t,dx,dy,moveTank){
  // Render offsets can be much larger than one physics step. Apply them in
  // wall-width increments so an endpoint on the far side cannot skip the wall.
  const steps=t.ghostTime>0?1:clamp(Math.ceil(Math.max(Math.abs(dx),Math.abs(dy))/8),1,6);
  for(let i=0;i<steps;i++){
   const {x,y}=t;
   moveTank(t,dx/steps,dy/steps);
   if(t.x===x&&t.y===y)break;
  }
 }
 function smoothCoordinate(a,b,start,end,f){
  const distance=b-a;
  if(Math.abs(distance)<1e-10)return a;
  let x=Math.max(0,start/distance),y=Math.max(0,end/distance);
  const length=Math.hypot(x,y);
  if(length>3){x*=3/length;y*=3/length;}
  const f2=f*f,f3=f2*f;
  return a+distance*((f3-2*f2+f)*x+(-2*f3+3*f2)+(f3-f2)*y);
 }
 function cubicCoordinate(a,b,start,end,f){
  const f2=f*f,f3=f2*f;
  return (2*f3-3*f2+1)*a+(f3-2*f2+f)*start+(-2*f3+3*f2)*b+(f3-f2)*end;
 }
 function presentation(t,dt,step,advance,moveTank,previous){
  const copy=source=>source.ai?{...source,ai:{...source.ai}}:{...source};
  const result=copy(t),f=clamp(dt/step,0,1);
  if(!t.alive||!(f>0))return result;
  const next=copy(t);advance(next,step);
  // A phase exit can eject a tank from a wall. Never blend that discontinuity.
  if((t.ghostTime>0)!==(next.ghostTime>0)){advance(result,f*step);return result;}
  if(movementStacks(t)!==movementStacks(next)){
   moveRenderPose(result,(next.x-t.x)*f,(next.y-t.y)*f,moveTank);
   result.angle=t.angle+delta(t.angle,next.angle)*f;
   result.track=(t.track||0)+((next.track||0)-(t.track||0))*f;
   return result;
  }
  const future=copy(next);advance(future,step);
  if((future.ghostTime>0)!==(next.ghostTime>0)||Math.hypot(future.x-next.x,future.y-next.y)>84){
   future.x=2*next.x-t.x;future.y=2*next.y-t.y;future.angle=next.angle+delta(t.angle,next.angle);
  }
  const before=previous&&previous.alive&&previous.spawnSerial===t.spawnSerial&&
   (previous.ghostTime>0)===(t.ghostTime>0)&&Math.hypot(previous.x-t.x,previous.y-t.y)<=84?previous:null;
  const firstX=before?(next.x-before.x)/2:(-3*t.x+4*next.x-future.x)/2;
  const firstY=before?(next.y-before.y)/2:(-3*t.y+4*next.y-future.y)/2;
  // A throttle perpendicular to its goal can turn without translating. Do
  // not invent a backwards excursion for a zero-displacement physics tick.
  const moving=Math.hypot(next.x-t.x,next.y-t.y)>1e-10;
  const x=moving?cubicCoordinate(t.x,next.x,firstX,(future.x-t.x)/2,f):t.x;
  const y=moving?cubicCoordinate(t.y,next.y,firstY,(future.y-t.y)/2,f):t.y;
  // Curves are cosmetic and remain constrained by the real wall resolver.
  moveRenderPose(result,x-t.x,y-t.y,moveTank);
  if(Math.hypot(result.x-x,result.y-y)>1e-7){
   result.x=t.x;result.y=t.y;
   moveRenderPose(result,(next.x-t.x)*f,(next.y-t.y)*f,moveTank);
  }
  const turn=delta(t.angle,next.angle),following=delta(next.angle,future.angle);
  result.angle=smoothCoordinate(t.angle,t.angle+turn,before?delta(before.angle,next.angle)/2:(3*turn-following)/2,(turn+following)/2,f);
  result.track=(t.track||0)+((next.track||0)-(t.track||0))*f;
  return result;
 }
 function visualMove(t,input,dt,moveTank,step=STEP,previous){
  return presentation(t,dt,step,(pose,span)=>move(pose,input,span,moveTank),moveTank,previous);
 }
 // A render-only ricochet path must reproduce BOTH authoritative endpoints.
 // Callers cache this result (including null) per immutable snapshot pair/ID.
 class RicochetPath{
  constructor(first,second,span,segments){this.first=first;this.second=second;this.span=span;this.segments=segments;}
  static between(first,second,span,projectileWall,{nudge=.12}={}){
   const kind=first?.kind||'',nextKind=second?.kind||'',before=first?.bounces||0,after=second?.bounces||0;
   if(!first||!second||typeof projectileWall!=='function'||!(span>0&&span<=.1)||!['','rapid','scatter','cannon'].includes(kind)||kind!==nextKind||
    first.id!==second.id||first.owner!==second.owner||!Number.isInteger(before)||!Number.isInteger(after)||after-before<1||after-before>4||
    ![first.x,first.y,first.vx,first.vy,first.life,second.x,second.y,second.vx,second.vy,second.life,nudge].every(Number.isFinite)||
    first.life+1e-9<span||Math.abs(first.life-second.life-span)>.025||nudge<0||nudge>.2)return null;
   const radius=kind==='rapid'?3.5/3:kind==='cannon'?14:3.5,segments=[];
   let x=first.x,y=first.y,vx=first.vx,vy=first.vy,time=0,bounces=before,reflections=0;
   for(let leg=0;leg<=4&&span-time>1e-9;leg++){
    const remaining=span-time,wall=projectileWall(kind,x,y,vx*remaining,vy*remaining,radius),fraction=wall?(wall.fraction??wall.t):1;
    if(!Number.isFinite(fraction)||fraction<0||fraction>1)return null;
    if(wall&&(![-1,0,1].includes(wall.nx)||![-1,0,1].includes(wall.ny)||!wall.nx&&!wall.ny))return null;
    const duration=remaining*fraction;
    segments.push({time,duration,x,y,vx,vy,bounces});x+=vx*duration;y+=vy*duration;time+=duration;
    if(!wall)break;
    if(reflections++>=4)return null;
    x+=wall.nx*nudge;y+=wall.ny*nudge;if(wall.nx)vx=-vx;if(wall.ny)vy=-vy;bounces++;
   }
   if(time<span-1e-8||bounces!==after||Math.hypot(x-second.x,y-second.y)>.5||Math.hypot(vx-second.vx,vy-second.vy)>.5)return null;
   return new RicochetPath({...first},{...second},span,segments);
  }
  sample(fraction){
   if(fraction<=0)return{...this.first};if(fraction>=1)return{...this.second};
   const time=this.span*clamp(fraction,0,1);let segment=this.segments[0];
   for(const next of this.segments){if(next.time>time)break;segment=next;}
   const elapsed=clamp(time-segment.time,0,segment.duration),value={...this.second,x:segment.x+segment.vx*elapsed,y:segment.y+segment.vy*elapsed,
    vx:segment.vx,vy:segment.vy,bounces:segment.bounces,life:this.first.life-time};
   if(Number.isFinite(this.first.age))value.age=this.first.age+time;
   return value;
  }
 }
 // Terminal paths recover authoritative flights that fit between snapshots.
 // This cache has no collision, input or score authority.
 class ProjectileFlights{
  constructor(){this.reset();}
  reset(){this.items=new Map();this.seen=new Set();this.completed=new Set();this.readyEffects=[];this.highWater=0;}
  observe(bullets){for(const b of bullets||[]){this.seen.delete(b.id);this.seen.add(b.id);while(this.seen.size>1024)this.seen.delete(this.seen.values().next().value);}}
  finish(id){const callbacks=this.items.get(id)?.effects;if(callbacks)this.readyEffects.push(...callbacks);this.items.delete(id);this.completed.add(id);while(this.completed.size>1024)this.completed.delete(this.completed.values().next().value);}
  defer(id,present){const item=this.items.get(id);if(item)(item.effects||=[]).push(present);else present();}
  flush(){if(!this.readyEffects.length)return;const ready=this.readyEffects.splice(0);for(const present of ready)present();}
  controls(id){return this.items.has(id)||this.completed.has(id);}
  accept(events,now,baseline=false,maxTick=Infinity){
   for(const event of events||[]){
    if(!Number.isSafeInteger(event.id)||event.id<=this.highWater)continue;
    this.highWater=event.id;
    const f=event.flight;if(baseline||!f||!Number.isSafeInteger(f.id)||f.id<0||!Number.isSafeInteger(f.owner)||f.owner<0||
     !Number.isInteger(f.colorIndex)||f.colorIndex<0||f.colorIndex>7||!['regular','rapid','scatter','homing','grenade','cannon'].includes(f.kind)||
     !Number.isFinite(f.radius)||f.radius<=0||f.radius>20||!Number.isFinite(f.startTick)||!Number.isFinite(f.endTick)||
     f.startTick<0||f.endTick<f.startTick||f.endTick>maxTick||f.endTick-f.startTick>601||!Array.isArray(f.points)||f.points.length<2||f.points.length>32)continue;
    let last=f.startTick,valid=true;
    for(const p of f.points){if(!p||![p.x,p.y,p.tick].every(Number.isFinite)||p.tick<last||p.tick<f.startTick||p.tick>f.endTick){valid=false;break;}last=p.tick;}
    if(!valid||f.points[0].tick!==f.startTick||f.points.at(-1).tick!==f.endTick)continue;
    if(this.completed.has(f.id))continue;
    this.items.set(f.id,{flight:{...f,points:f.points.map(p=>({...p}))},received:now,drawn:this.seen.has(f.id),replayAt:null});
    while(this.items.size>128)this.finish(this.items.keys().next().value);
   }
  }
  sample(tick,now){
   const out=[];
   for(const [id,item]of this.items){
    const f=item.flight;
    if(now-item.received>11000){this.finish(id);continue;}
    let at=tick;
    if(item.replayAt!==null){
     if(now-item.replayAt>=50){this.finish(id);continue;}
     const start=Math.max(f.startTick,f.endTick-3);at=start+(f.endTick-start)*clamp((now-item.replayAt)/50,0,1);
    }else if(at>=f.endTick){
     if(item.drawn){this.finish(id);continue;}
     item.replayAt=now;at=Math.max(f.startTick,f.endTick-3);
    }
    if(at<f.startTick)continue;
    const points=f.points;let a=points[0],b=points.at(-1);
    for(let i=1;i<points.length;i++){b=points[i];if(at<=b.tick)break;a=b;}
    let span=b.tick-a.tick,alpha=span>0?clamp((at-a.tick)/span,0,1):1,seconds=span*STEP;
    if(f.endTick===f.startTick&&item.replayAt!==null){
     const cursor=clamp((now-item.replayAt)/50,0,1)*(points.length-1),index=Math.min(points.length-2,Math.floor(cursor));
     a=points[index];b=points[index+1];alpha=cursor-index;seconds=.05/(points.length-1);
    }
    const shell={id,owner:f.owner,colorIndex:f.colorIndex,kind:f.kind==='regular'?'':f.kind,r:f.radius,
     x:a.x+(b.x-a.x)*alpha,y:a.y+(b.y-a.y)*alpha,vx:seconds>0?(b.x-a.x)/seconds:0,vy:seconds>0?(b.y-a.y)/seconds:0,
     life:Math.max(STEP,(f.endTick-at)*STEP),age:Math.max(0,(at-f.startTick)*STEP),bounces:Math.max(0,points.indexOf(a)),flight:true};
    shell.trail=[];
    if(f.kind!=='rapid'){
     const tailTick=Math.max(f.startTick,at-6);let tail=points[0];
     for(let i=1;i<points.length;i++)if(points[i].tick>=tailTick){const previous=points[i-1],next=points[i],span=next.tick-previous.tick,fraction=span>0?clamp((tailTick-previous.tick)/span,0,1):0;tail={x:previous.x+(next.x-previous.x)*fraction,y:previous.y+(next.y-previous.y)*fraction};break;}
     shell.trail=[{x:tail.x,y:tail.y},...points.filter(p=>p.tick>tailTick&&p.tick<at).map(p=>({x:p.x,y:p.y})),{x:shell.x,y:shell.y}];
    }
    out.push(shell);item.drawn=true;
   }
   return out;
  }
  pending(id){return this.items.has(id);}
  begin(b,tick){b.flightStartTick=tick;b.flightStartX=b.x;b.flightStartY=b.y;}
  vertex(b,tick){
   if(this.seen.has(b.id)||!Number.isFinite(b.flightStartTick))return;
   const points=b.flightPoints||=[{x:b.flightStartX,y:b.flightStartY,tick:b.flightStartTick}];
   if(points.length>=32)points.splice(1,1);
   points.push({x:b.x,y:b.y,tick:Math.max(b.flightStartTick,tick)});
  }
  terminal(b,tick,colorIndex,now){
   if(this.seen.has(b.id)||this.items.has(b.id)||this.completed.has(b.id)||!Number.isFinite(b.flightStartTick))return;
   this.vertex(b,tick);
   this.accept([{id:this.highWater+1,flight:{id:b.id,owner:Number.isSafeInteger(b.owner)?b.owner:0,colorIndex,kind:b.kind||'regular',radius:b.r,
    startTick:b.flightStartTick,endTick:b.flightPoints.at(-1).tick,points:b.flightPoints}}],now);
  }
 }
 class MotionPresenter{
  constructor(){this.reset();}
  reset(){this.previous=null;this.before=null;this.offset={x:0,y:0,angle:0};}
  rebase(x,y,angle){for(const state of [this.previous?.state,this.before])if(state){state.x+=x;state.y+=y;state.angle+=angle;}}
  render(state,input,remaining,tick,moveTank,step=STEP,advance=(pose,span,controls)=>move(pose,controls,span,moveTank),tickCorrections=true){
   const old=this.previous;
   const copy=source=>source.ai?{...source,ai:{...source.ai}}:{...source};
   const dt=old?(tick-old.tick)*step+remaining-old.remaining:0;
   if(!old||dt< -1e-8||dt>.1||state.spawnSerial!==old.state.spawnSerial||(state.ghostTime>0)!==(old.state.ghostTime>0)||Math.hypot(state.x-old.state.x,state.y-old.state.y)>=64)this.before=null;
   else if(tick>old.tick){
    this.before=copy(old.state);
    for(let i=1;i<tick-old.tick;i++)advance(this.before,step,old.input);
   }
   let before=this.before;
   if(!tickCorrections&&before&&Number.isFinite(state.vx)&&Number.isFinite(state.vy))before={...state,x:state.x-state.vx*step,y:state.y-state.vy*step,angle:before.angle};
   const raw=presentation(state,remaining,step,(pose,span)=>advance(pose,span,input),moveTank,before);
   const changed=old&&!controlsEqual({...old.input,fire:false},{...input,fire:false});
   const valid=old&&state.alive&&old.state.alive&&state.spawnSerial===old.state.spawnSerial&&
    (state.ghostTime>0)===(old.state.ghostTime>0)&&(raw.ghostTime>0)===(state.ghostTime>0)&&
    dt>=-1e-8&&dt<=.1&&Math.hypot(state.x-old.state.x,state.y-old.state.y)<64;
   if(!valid)this.offset={x:0,y:0,angle:0};
   else{
    const fade=Math.exp(-Math.max(0,dt)/.04);
    this.offset.x*=fade;this.offset.y*=fade;this.offset.angle*=fade;
    if(changed||tickCorrections&&tick!==old.tick){
     // Compare curves at the same display time. This preserves elapsed motion
     // when a new touch direction replaces a partially previewed physics tick.
     const expected=copy(old.state);let ahead=old.remaining+Math.max(0,dt),count=0,prior=before;
     while(ahead+1e-9>=step&&count++<6){prior=copy(expected);advance(expected,step,old.input);ahead=Math.max(0,ahead-step);}
     const previous=presentation(expected,ahead,step,(pose,span)=>advance(pose,span,old.input),moveTank,prior);
     this.offset.x+=previous.x-raw.x;this.offset.y+=previous.y-raw.y;
     this.offset.angle=delta(0,this.offset.angle+delta(raw.angle,previous.angle));
    }
    const limit=128*(1+.65*5)*step,length=Math.hypot(this.offset.x,this.offset.y);
    if(length>limit){this.offset.x*=limit/length;this.offset.y*=limit/length;}
    this.offset.angle=clamp(this.offset.angle,-20.25*step,20.25*step);
   }
   const value={...raw};moveRenderPose(value,this.offset.x,this.offset.y,moveTank);value.angle+=this.offset.angle;
   this.offset.x=value.x-raw.x;this.offset.y=value.y-raw.y;
   this.previous={state:copy(state),input:{...input},remaining,tick};
   return value;
  }
 }
 class Predictor{
  constructor(moveTank){this.moveTank=moveTank;this.reset(null);}
  reset(t){
   this.state=t?{...t}:null;this.frames=[];this.sent=new Map();this.stepID=0;
   this.accumulator=0;this.input=neutral();this.offset={x:0,y:0,angle:0};this.correctionVelocity={x:0,y:0,angle:0};
   this.presenter=new MotionPresenter();
   this.metrics={corrections:0,hardResets:0,lastError:0,maxError:0,replayed:0};
  }
  // A sequence identifies the *start* of a held input, not a single movement.
  // Go reports how many ticks it actually applied that input. This is necessary
  // because snapshots, input packets, and simulation ticks have different rates.
  sentInput(seq){
   this.sent.set(seq,this.stepID+1);
   while(this.sent.size>256)this.sent.delete(this.sent.keys().next().value);
  }
  neutralize(){this.input=neutral();}
  advance(dt,input,beforeStep){
   if(!this.state||!this.state.alive)return;
   this.input={...input};this.accumulator+=clamp(dt,0,.1);
   let count=0;
   while(this.accumulator+1e-9>=STEP&&count++<6){
    if(beforeStep)beforeStep(this.input,this.stepID+1);
    this.stepID++;
    const phasing=this.state.ghostTime>0;
    move(this.state,this.input,STEP,this.moveTank);
    if(phasing&&!(this.state.ghostTime>0)){this.offset={x:0,y:0,angle:0};this.correctionVelocity={x:0,y:0,angle:0};}
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
   const phasing=next.ghostTime>0,phaseChanged=(before.ghostTime>0)!==phasing;
   if(!historyOK||!authority.alive||error>64||phaseChanged){
    // Corrections cannot cross a change in wall collision policy.
    this.offset={x:0,y:0,angle:0};this.correctionVelocity={x:0,y:0,angle:0};this.presenter.reset();this.metrics.hardResets++;
   }else{
    this.presenter.rebase(next.x-before.x,next.y-before.y,delta(before.angle,next.angle));
    const oldNext={...before},newNext={...next};move(oldNext,this.input,STEP,this.moveTank);move(newNext,this.input,STEP,this.moveTank);
    this.correctionVelocity.x+=((oldNext.x-before.x)-(newNext.x-next.x))/STEP;
    this.correctionVelocity.y+=((oldNext.y-before.y)-(newNext.y-next.y))/STEP;
    this.correctionVelocity.angle+=(delta(before.angle,oldNext.angle)-delta(next.angle,newNext.angle))/STEP;
    this.offset.x+=before.x-next.x;this.offset.y+=before.y-next.y;
    if(phasing){
     // During Ghost or Starman, smooth timing errors along the tank's path
     // without carrying a sideways correction through a wall.
     const vx=before.vx||0,vy=before.vy||0,speed=Math.hypot(vx,vy);
     const correction=speed>1e-6?clamp((this.offset.x*vx+this.offset.y*vy)/speed,-12,12)/speed:0;
     this.offset.x=vx*correction;this.offset.y=vy*correction;
    }
    this.offset.angle=delta(0,this.offset.angle+delta(next.angle,before.angle));
    const length=Math.hypot(this.offset.x,this.offset.y);
    if(length>48){this.offset.x*=48/length;this.offset.y*=48/length;}
    this.offset.angle=clamp(this.offset.angle,-.7,.7);
   }
   this.state=next;
  }
  visual(dt,active=true){
   if(!this.state)return null;
   const span=clamp(dt,0,.1),omega=20,decay=Math.exp(-omega*span);
   for(const axis of ['x','y','angle']){
    const impulse=(this.correctionVelocity[axis]+omega*this.offset[axis])*span;
    this.offset[axis]=(this.offset[axis]+impulse)*decay;
    this.correctionVelocity[axis]=(this.correctionVelocity[axis]-omega*impulse)*decay;
    if(Math.abs(this.offset[axis])<1e-5&&Math.abs(this.correctionVelocity[axis])<1e-4)this.offset[axis]=this.correctionVelocity[axis]=0;
   }
   const limit=this.state.ghostTime>0?12:48,length=Math.hypot(this.offset.x,this.offset.y);
   if(length>limit){
    this.offset.x*=limit/length;this.offset.y*=limit/length;
    const outward=(this.correctionVelocity.x*this.offset.x+this.correctionVelocity.y*this.offset.y)/(limit*limit);
    if(outward>0){this.correctionVelocity.x-=this.offset.x*outward;this.correctionVelocity.y-=this.offset.y*outward;}
   }
   if(Math.abs(this.offset.angle)>.7){this.offset.angle=clamp(this.offset.angle,-.7,.7);if(this.offset.angle*this.correctionVelocity.angle>0)this.correctionVelocity.angle=0;}
   let t={...this.state};
   // Sub-tick render prediction keeps 90/120/144 Hz displays smooth without
   // changing the 60 Hz authoritative-compatible history.
   if(active&&t.alive)t=this.presenter.render(t,this.input,this.accumulator,this.stepID,this.moveTank,STEP,undefined,false);
   if(active&&t.alive&&(t.ghostTime>0)===(this.state.ghostTime>0)){
    moveRenderPose(t,this.offset.x,this.offset.y,this.moveTank);t.angle+=this.offset.angle;
   }
   return t;
  }
 }
 const newestTime=items=>items[items.length-1].netTime;
 class SnapshotBuffer{
  constructor(options={}){this.options={delay:75,minimumDelay:70,maximumDelay:180,intervals:2,...options};this.reset();}
  reset(){
   this.items=[];this.time=null;this.interval=1000/30;this.delay=this.options.delay;
   this.jitter=0;this.jitterPeak=0;this.lastArrival=null;this.lastStamp=null;
   this.underruns=0;this.starved=false;this.rate=1;
   this.curves=new Map();
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
    const wanted=clamp(this.interval*this.options.intervals+Math.max(this.jitter*2,this.jitterPeak*.85),this.options.minimumDelay,this.options.maximumDelay);
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
   if(frame.extrapolate<=0&&frame.a!==frame.b){
    const span=(frame.b.netTime-frame.a.netTime)/1000,key=frame.a.tick+':'+frame.b.tick+':'+id;
    let curve=this.curves.get(key);
    if(!curve){
     const first=this.items.indexOf(frame.a),second=this.items.indexOf(frame.b);
     const before=this.items[first-1],after=this.items[second+1],p=before?.tankMap.get(id),n=after?.tankMap.get(id);
     const same=tank=>tank?.alive&&tank.spawnSerial===a.spawnSerial&&(tank.ghostTime>0)===(a.ghostTime>0);
     const previous=same(p)?p:null,next=same(n)?n:null;
     const previousSpan=previous?(frame.b.netTime-before.netTime)/1000:span,nextSpan=next?(after.netTime-frame.a.netTime)/1000:span;
     const dx=b.x-a.x,dy=b.y-a.y;
     curve={x0:previous?(b.x-previous.x)*span/previousSpan:Number.isFinite(a.vx)?a.vx*span:dx,
      y0:previous?(b.y-previous.y)*span/previousSpan:Number.isFinite(a.vy)?a.vy*span:dy,
      x1:next?(next.x-a.x)*span/nextSpan:Number.isFinite(b.vx)?b.vx*span:dx,
      y1:next?(next.y-a.y)*span/nextSpan:Number.isFinite(b.vy)?b.vy*span:dy,
      angle0:previous?delta(previous.angle,b.angle)*span/previousSpan:delta(a.angle,b.angle),
      angle1:next?delta(a.angle,next.angle)*span/nextSpan:delta(a.angle,b.angle),safe:true};
     // Validate the curved route once per immutable snapshot pair. Collision
     // corners retain the original straight, wall-resolved interpolation.
     for(let i=1;i<8&&curve.safe;i++){
      const fraction=i/8,x=cubicCoordinate(a.x,b.x,curve.x0,curve.x1,fraction),y=cubicCoordinate(a.y,b.y,curve.y0,curve.y1,fraction),pose={...a};
      moveRenderPose(pose,x-a.x,y-a.y,moveTank);curve.safe=Math.hypot(pose.x-x,pose.y-y)<1e-6;
     }
     if(this.curves.size>=256)this.curves.delete(this.curves.keys().next().value);this.curves.set(key,curve);
    }
    if(curve.safe){
     const x=cubicCoordinate(a.x,b.x,curve.x0,curve.x1,f),y=cubicCoordinate(a.y,b.y,curve.y0,curve.y1,f),pose={...a};
     moveRenderPose(pose,x-a.x,y-a.y,moveTank);
     if(Math.hypot(pose.x-x,pose.y-y)<1e-6){t.x=x;t.y=y;}
     t.angle=smoothCoordinate(a.angle,a.angle+delta(a.angle,b.angle),curve.angle0,curve.angle1,f);
    }
   }
   if(frame.extrapolate>0&&t.alive){
    // Extrapolation is short and wall constrained. It never awards a hit.
    const dt=Math.min(.075,frame.extrapolate);
    moveRenderPose(t,(b.vx||0)*dt,(b.vy||0)*dt,moveTank);
    const items=this.items,prior=items.length>1?items[items.length-2]:null;
    const prev=prior?.tankMap.get(id),span=prior?(newestTime(items)-prior.netTime)/1000:0;
    if(prev?.alive&&prev.spawnSerial===b.spawnSerial&&span>0&&span<.25){
     // A tank can rotate in place: positional velocity alone loses that motion.
     const stacks=movementStacks(b),maxTurn=5.8*(1+.25*stacks);
     const omega=clamp(delta(prev.angle,b.angle)/span,-maxTurn,maxTurn);
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
   }else if(!this.hasPending(t.id)){
    // The deadline may approach, but never sawtooth back up for one volley.
    p.until=Math.min(p.until,now+Math.max(0,t.cooldown||0)*1000);
   }
   return p;
  }
  // Snapshot sync can find a pending shot without materializing every preview.
  hasPending(id){for(const v of this.previews.values())if(v.owner===id&&!v.accepted)return true;return false;}
  remove(id){this.pilots.delete(id);for(const [k,v]of this.previews)if(v.owner===id)this.previews.delete(k);}
  cooldown(t,now){if(t.starmanTime>0)return 0;const p=this.pilots.get(t.id);return p?Math.max(0,(p.until-now)/1000):Math.max(0,t.cooldown||0);}
  machineRounds(t){
   let remaining=Math.max(0,t.machineRounds||0);
   for(const v of this.previews.values())if(v.owner===t.id&&!v.accepted&&v.power==='rapid'&&!v.boosted)remaining--;
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
   const boosted=t.starmanTime>0,fast=boosted||t.power==='rapid';
   let pending=0,normalPending=0,slots=0,chargeUse=0;
   for(const v of this.previews.values())if(v.owner===t.id&&!v.accepted){
    pending++;
    if(!v.boosted){normalPending++;slots+=v.shells.length;if(v.power===t.power)chargeUse++;}
   }
   if(options.blocked||pending>=48||!fast&&normalPending>=4)return null;
   if(!boosted&&(this.cooldown(t,now)>.001||options.free-slots<options.need||
      options.charged&&t.charges-chargeUse<=0||t.power==='rapid'&&!(t.machineRounds-chargeUse>0)))return null;
   if(fast){const tick=Math.floor(now/STEP_MS);if(p.rapidTick===tick)return null;p.rapidTick=tick;}
   const shot=++p.next,key=this.key(t.id,p.life,shot),total=boosted?0:options.cooldown;
   const v={key,owner:t.id,life:p.life,shot,power:t.power||'',boosted,at:now,until:now+1000*total,
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
   for(const [id,p] of this.pilots)if(!this.hasPending(id))p.next=p.serial;
  }
 }
 return Object.freeze({wallLaunch,expandMachineBullets,STEP,STEP_MS,MACHINE_CAPACITY,clamp,delta,neutral,controlsEqual,steeringTurn,move,movementStacks,presentation,visualMove,RicochetPath,ProjectileFlights,MotionPresenter,Predictor,SnapshotBuffer,ShotPresentation});
});
