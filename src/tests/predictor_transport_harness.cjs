'use strict';

// Real Predictor/sentInput/reconcile/visual calls across independent 60 Hz
// server and 120 Hz display clocks. Both FIFO transport directions have bounded
// deterministic jitter; server state alone supplies held-input acknowledgements.
const free=(pose,dx,dy)=>{pose.x+=dx;pose.y+=dy;};
const jitter=[-12,5,-7,12,-3,9,-10,2];
const initial=()=>({id:0,x:2000,y:2000,angle:0,r:17,alive:true,spawnSerial:1,track:0,vx:0,vy:0,
 speedTime:1000,speedStacks:5,ghostTime:0,ack:0,ackSteps:0});
function percentile(values,fraction){const ordered=[...values].sort((a,b)=>a-b);return ordered[Math.floor((ordered.length-1)*fraction)]||0;}
function measure(Net,{rtt=150,control='touch',seconds=12,recordPhysics=false}={}){
 const predictor=new Net.Predictor(free),server=initial(),uplink=[],downlink=[],samples=[],physics=[];
 predictor.reset(server);
 let now=0,serverAt=7,serverTick=0,sequence=0,lastSendStep=-2,upCount=0,downCount=0,upDue=-Infinity,downDue=-Infinity;
 let held=Net.neutral(),ack=0,ackSteps=0,maxOffset=0,maxViewError=0,maxCorrectionVelocity=0;
 const controls=time=>control==='keyboard'?{...Net.neutral(),forward:true,right:true}:
  {...Net.neutral(),stickX:Math.cos(time*7+.8),stickY:Math.sin(time*7+.8),touchAim:true};
 const snapshot=()=>({...server,x:Math.round(server.x*1000)/1000,y:Math.round(server.y*1000)/1000,ack,ackSteps});
 for(let frame=1;frame<=seconds*120;frame++){
  now=frame*1000/120;
  const input=controls(now/1000);
  predictor.advance(1/120,input,(sent,step)=>{
   if(step-lastSendStep<2)return;
   lastSendStep=step;predictor.sentInput(++sequence);
   upDue=Math.max(upDue+.001,now+Math.max(0,rtt/2+jitter[upCount++%jitter.length]));
   uplink.push({at:upDue,input:{...sent},seq:sequence});
  });
  while(serverAt<=now+1e-7){
   while(uplink[0]?.at<=serverAt+1e-7){const packet=uplink.shift();held=packet.input;ack=packet.seq;ackSteps=0;}
   Net.move(server,held,Net.STEP,free);ackSteps++;serverTick++;
   if(serverTick%2===0){
    downDue=Math.max(downDue+.001,serverAt+Math.max(0,rtt/2+jitter[(downCount++*3+2)%jitter.length]));
    downlink.push({at:downDue,state:snapshot()});
   }
   serverAt+=1000/60;
  }
  while(downlink[0]?.at<=now+1e-7)predictor.reconcile(downlink.shift().state);
  const before={...predictor.state},pose=predictor.visual(1/120);
  // Cosmetics must leave replay/authority unchanged on every actual frame.
  if(JSON.stringify(before)!==JSON.stringify(predictor.state))throw Error('visual mutated authoritative replay state');
  if(recordPhysics)physics.push({...predictor.state});
  if(now>=2000){
   samples.push({x:pose.x,y:pose.y,at:now});
   maxOffset=Math.max(maxOffset,Math.hypot(predictor.offset.x,predictor.offset.y));
   maxViewError=Math.max(maxViewError,Math.hypot(pose.x-predictor.state.x,pose.y-predictor.state.y));
   if(predictor.correctionVelocity)maxCorrectionVelocity=Math.max(maxCorrectionVelocity,Math.hypot(predictor.correctionVelocity.x,predictor.correctionVelocity.y));
  }
 }
 const speeds=samples.slice(1).map((pose,i)=>Math.hypot(pose.x-samples[i].x,pose.y-samples[i].y)/((pose.at-samples[i].at)/1000));
 const changes=speeds.slice(1).map((speed,i)=>Math.abs(speed-speeds[i]));
 return{rtt,control,jitterMs:12,frames:samples.length,p95SpeedChange:percentile(changes,.95),p99SpeedChange:percentile(changes,.99),
  maxSpeedChange:Math.max(...changes),minSpeed:Math.min(...speeds),maxSpeed:Math.max(...speeds),stalls:speeds.filter(speed=>speed<1).length,
  maxOffset,maxViewError,maxCorrectionVelocity,maxReconciliationError:predictor.metrics.maxError,
  corrections:predictor.metrics.corrections,hardResets:predictor.metrics.hardResets,physics};
}
module.exports={measure,percentile};
