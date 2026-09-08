'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
const audioCode=source.slice(source.indexOf('let audioLevel='),source.indexOf('function setLayout('));
const flush=async()=>{for(let i=0;i<6;i++)await Promise.resolve();};

function boot(options={}){
 let clock=0,nextTimer=0,nextBlob=0;const listeners=new Map(),timers=new Map(),blobs=new Map(),contexts=[],native=[],plays=[],nodes=[];
 function param(){return{value:1,events:[],setValueAtTime(value,t){this.value=value;this.events.push(['set',value,t]);},linearRampToValueAtTime(value,t){this.value=value;this.events.push(['ramp',value,t]);},exponentialRampToValueAtTime(value,t){this.value=value;this.events.push(['exponential',value,t]);},cancelAndHoldAtTime(t){this.events.push(['hold',t]);},cancelScheduledValues(t){this.events.push(['cancel',t]);}};}
 function node(kind){const n={kind,disconnected:false,connect(){},disconnect(){this.disconnected=true;},start(t){this.started=t;},stop(t){this.stopped=t;}};nodes.push(n);return n;}
 class Context{
  constructor(){this.state=options.state||'running';this.currentTime=0;this.sampleRate=48000;this.destination={};this.resumeCount=0;this.pending=[];contexts.push(this);}
  createGain(){const n=node('gain');n.gain=param();return n;}
  createOscillator(){const n=node('oscillator');n.frequency=param();return n;}
  createBiquadFilter(){const n=node('filter');n.frequency=param();return n;}
  createBufferSource(){return node('buffer');}
  createBuffer(channels,length,rate){const data=new Float32Array(length);return{length,sampleRate:rate,getChannelData:()=>data};}
  resume(){this.resumeCount++;if(options.deferResume)return new Promise(resolve=>this.pending.push(resolve));this.state='running';return Promise.resolve();}
  finishResume(){this.state='running';for(const resolve of this.pending.splice(0))resolve();}
 }
 class NativeAudio{
  constructor(){this.dataset={};this.muted=false;native.push(this);}
  setAttribute(){}
  pause(){this.paused=true;}
  play(){this.paused=false;plays.push(this.src);if(options.deferNative)return new Promise((resolve,reject)=>{this.resolvePlay=resolve;this.rejectPlay=reject;});return Promise.resolve();}
 }
 const controls=new Map();const $=id=>{if(!controls.has(id))controls.set(id,{value:'',textContent:'',classList:{toggle(){}},setAttribute(){}});return controls.get(id);};
 const s={muted:false,audioVolume:50,audio:null,audioMaster:null,audioResume:null,noiseBuffer:null,lastChatNotify:0,SAFARI_BROWSER:options.safari!==false,TAU:Math.PI*2,
  document:{hidden:false},performance:{now:()=>clock},clamp:(n,a,b)=>Math.max(a,Math.min(b,n)),save(){},$,Blob,
  window:{AudioContext:options.noWebAudio?undefined:Context,addEventListener:(event,fn)=>listeners.set(event,fn)},Audio:NativeAudio,
  URL:{createObjectURL(blob){const url='blob:test-'+nextBlob++;blobs.set(url,blob);return url;},revokeObjectURL(url){blobs.delete(url);}},
  setTimeout(fn,delay){const id=++nextTimer;timers.set(id,{fn,time:clock+delay});return id;},clearTimeout:id=>timers.delete(id)};
 vm.createContext(s);vm.runInContext(audioCode+'\nthis.audioInspection=()=>({audioLevel,audioEpoch,pendingAudioEffects,delayed:nativeAudioTimers.size});',s);
 return{s,contexts,native,plays,nodes,blobs,listeners,timers,advance(ms){clock+=ms;for(const [id,timer]of [...timers])if(timer.time<=clock){timers.delete(id);timer.fn();}},fire(event,extra={}){listeners.get(event)?.({isTrusted:true,...extra});}};
}

test('Controls opening and repeated scrolling never play native unlock tones',async()=>{
 const b=boot({state:'suspended',deferResume:true});b.fire('click');
 assert.equal(b.contexts.length,1);assert.equal(b.contexts[0].resumeCount,1);
 for(let i=0;i<20;i++)for(const event of ['pointerdown','touchstart','pointerup','touchend','scroll'])b.fire(event);
 assert.equal(b.contexts[0].resumeCount,1);assert.equal(b.native.length,0);assert.equal(b.plays.length,0);
 const unlock=b.nodes.find(n=>n.kind==='buffer');assert.ok(unlock);
 assert.ok([...unlock.buffer.getChannelData(0)].every(sample=>sample===0),'the Web Audio unlock contains actual digital silence');
 unlock.onended();assert.equal(unlock.disconnected,true);
 b.contexts[0].finishResume();await flush();b.fire('click');assert.equal(b.contexts[0].resumeCount,1);
});
test('unlock ignores synthetic clicks, held-key repeats, muted audio, and hidden pages',()=>{
 for(const setup of [b=>b.fire('click',{isTrusted:false}),b=>b.fire('keydown',{repeat:true}),b=>{b.s.muted=true;b.fire('click');},b=>{b.s.document.hidden=true;b.fire('click');}]){const b=boot();setup(b);assert.equal(b.contexts.length,0);assert.equal(b.plays.length,0);}
});
test('duplicate unlock events coalesce and a later activation can retry an interrupted context',async()=>{
 const b=boot({state:'interrupted',deferResume:true});b.fire('click');b.fire('keydown');assert.equal(b.contexts[0].resumeCount,1);
 b.advance(101);b.fire('click');assert.equal(b.contexts[0].resumeCount,2);b.contexts[0].finishResume();await flush();assert.equal(await b.s.initAudio(),true);
});
test('running audio does not reschedule gain for every click; volume changes ramp',async()=>{
 const b=boot();await b.s.initAudio();const gain=b.s.audioMaster.gain;const initial=gain.events.length;
 for(let i=0;i<50;i++){b.fire('click');await b.s.initAudio();}assert.equal(gain.events.length,initial);
 b.s.setAudioVolume(25);assert.equal(gain.events.at(-1)[0],'ramp');assert.equal(gain.events.at(-1)[1],.5);assert.equal(gain.events.at(-1)[2],.012);
});
test('native Safari fallback bakes attenuation into samples, with silent endpoints',async()=>{
 const b=boot({noWebAudio:true});b.s.nativeTone(500,700,.1,.035,'sine');await flush();assert.equal(b.plays.length,1);
 const data=new DataView(await b.blobs.get(b.plays[0]).arrayBuffer());let peak=0;
 for(let offset=44;offset<data.byteLength;offset+=2)peak=Math.max(peak,Math.abs(data.getInt16(offset,true)));
 assert.ok(peak>1000&&peak<=Math.ceil(32760*.245),'fallback is attenuated even when iOS ignores the volume property');
 assert.equal(data.getInt16(44,true),0);assert.equal(data.getInt16(data.byteLength-2,true),0);
 b.s.setAudioVolume(25);b.s.nativeTone(500,700,.1,.035,'sine');await flush();const quieter=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer());let quietPeak=0;
 for(let offset=44;offset<quieter.byteLength;offset+=2)quietPeak=Math.max(quietPeak,Math.abs(quieter.getInt16(offset,true)));
 assert.ok(quietPeak<peak*.51&&quietPeak>peak*.49);
});
test('muting stops native playback and cancels delayed tones across subsequent unmute',async()=>{
 const b=boot({noWebAudio:true});b.s.nativeTone(500,700,.1);b.s.nativeTone(700,900,.1,.035,'sine',.1);assert.equal(b.s.audioInspection().delayed,1);
 b.s.muted=true;b.s.syncSound();assert.equal(b.native[0].paused,true);assert.equal(b.native[0].muted,true);assert.equal(b.s.audioInspection().delayed,0);
 b.s.muted=false;b.s.syncSound();b.advance(150);await flush();assert.equal(b.plays.length,1);
});
test('a delayed tone uses Web Audio when the context recovers before playback',async()=>{
 const b=boot({state:'suspended'});b.s.nativeTone(500,700,.1,.035,'sine',.1);await b.s.initAudio();b.advance(100);await flush();
 assert.equal(b.plays.length,0);assert.equal(b.nodes.filter(n=>n.kind==='oscillator').length,1);
});
test('delayed and resumed effects expire instead of bursting after a stall',async()=>{
 const b=boot({state:'suspended',deferResume:true});let count=0;b.s.audioWhenReady(()=>count++);b.s.nativeTone(500,700,.1,.035,'sine',.1);
 b.advance(500);b.contexts[0].finishResume();await flush();assert.equal(count,0);assert.equal(b.plays.length,0);assert.equal(b.nodes.filter(n=>n.kind==='oscillator').length,0);
});
test('async resume respects mute even if the user unmutes before it completes',async()=>{
 const b=boot({state:'suspended',deferResume:true});let count=0;b.s.audioWhenReady(()=>count++);b.s.muted=true;b.s.syncSound();b.s.muted=false;b.s.syncSound();b.contexts[0].finishResume();await flush();assert.equal(count,0);
});
test('blocked audio queues a bounded number of callbacks and releases them on resume',async()=>{
 const b=boot({state:'suspended',deferResume:true});let count=0;for(let i=0;i<500;i++)b.s.audioWhenReady(()=>count++);
 assert.equal(b.s.audioInspection().pendingAudioEffects,24);assert.equal(b.contexts[0].resumeCount,1);b.advance(500);b.contexts[0].finishResume();await flush();assert.equal(count,0);assert.equal(b.s.audioInspection().pendingAudioEffects,0);
 b.s.audioWhenReady(()=>count++);assert.equal(count,1);
});
test('finished oscillators and explosions disconnect their transient graph nodes',async()=>{
 const b=boot();await b.s.initAudio();b.s.webTone(500,700,.1);b.s.boom();
 for(const n of b.nodes.filter(n=>n.kind==='oscillator'||n.kind==='buffer')){assert.equal(typeof n.onended,'function');n.onended();assert.equal(n.disconnected,true);}
 assert.ok(b.nodes.filter(n=>n!==b.s.audioMaster).every(n=>n.disconnected),'all effect nodes release their graph connections');
});
test('zero volume prevents both playback paths, while restoring volume allows a fresh effect',async()=>{
 const b=boot();await b.s.initAudio();b.s.setAudioVolume(0);b.s.tone(500,700,.1);b.s.boom();assert.equal(b.plays.length,0);assert.equal(b.nodes.filter(n=>n.kind==='oscillator').length,0);
 b.s.setAudioVolume(50);b.s.tone(500,700,.1);assert.equal(b.nodes.filter(n=>n.kind==='oscillator').length,1);
});
