'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
const audioCode=source.slice(source.indexOf('let audioLevel='),source.indexOf('function setLayout('));
const flush=async()=>{for(let i=0;i<6;i++)await Promise.resolve();};

function boot(options={}){
 let clock=0,nextTimer=0,nextBlob=0;const listeners=new Map(),timers=new Map(),blobs=new Map(),contexts=[],native=[],plays=[],nodes=[];
 function param(){return{value:1,events:[],setValueAtTime(value,t){this.value=value;this.events.push(['set',value,t]);},linearRampToValueAtTime(value,t){this.value=value;this.events.push(['ramp',value,t]);},exponentialRampToValueAtTime(value,t){this.value=value;this.events.push(['exponential',value,t]);},cancelAndHoldAtTime(t){this.events.push(['hold',t]);},cancelScheduledValues(t){this.events.push(['cancel',t]);}};}
 function node(kind){const n={kind,disconnected:false,connections:[],connect(target){this.connections.push(target);},disconnect(){this.disconnected=true;},start(t){this.started=t;},stop(t){this.stopped=t;}};nodes.push(n);return n;}
 class Context{
  constructor(){this.state=options.state||'running';this.currentTime=0;this.sampleRate=48000;this.destination={};this.resumeCount=0;this.pending=[];contexts.push(this);}
  createGain(){const n=node('gain');n.gain=param();return n;}
  createDynamicsCompressor(){const n=node('compressor');for(const key of ['threshold','knee','ratio','attack','release'])n[key]=param();return n;}
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
 b.s.setAudioVolume(25);assert.equal(gain.events.at(-1)[0],'ramp');assert.equal(gain.events.at(-1)[1],1);assert.equal(gain.events.at(-1)[2],.012);
});
test('native Safari fallback bakes attenuation into samples, with silent endpoints',async()=>{
 const b=boot({noWebAudio:true});b.s.nativeTone(500,700,.1,.035,'sine');await flush();assert.equal(b.plays.length,1);
 const data=new DataView(await b.blobs.get(b.plays[0]).arrayBuffer());let peak=0;
 for(let offset=44;offset<data.byteLength;offset+=2)peak=Math.max(peak,Math.abs(data.getInt16(offset,true)));
 assert.ok(peak>1000&&peak<=Math.ceil(32760*.49),'fallback is attenuated even when iOS ignores the volume property');
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
 const permanent=new Set([b.s.audioMaster,...b.s.audioMaster.connections,...b.s.audioMaster.connections.flatMap(n=>n.connections)]);
 assert.ok(b.nodes.filter(n=>!permanent.has(n)).every(n=>n.disconnected),'all effect nodes release their graph connections');
});
test('zero volume prevents both playback paths, while restoring volume allows a fresh effect',async()=>{
 const b=boot();await b.s.initAudio();b.s.setAudioVolume(0);b.s.tone(500,700,.1);b.s.boom();assert.equal(b.plays.length,0);assert.equal(b.nodes.filter(n=>n.kind==='oscillator').length,0);
 b.s.setAudioVolume(50);b.s.tone(500,700,.1);assert.equal(b.nodes.filter(n=>n.kind==='oscillator').length,1);
});

test('v440 doubles the shared output gain while retaining displayed and saved slider percentages',async()=>{
 const b=boot(),saved=[];b.s.save=(...entry)=>saved.push(entry);await b.s.initAudio();
 assert.equal(b.s.audioVolume,50);assert.equal(b.s.audioMaster.gain.value,2);
 for(const level of [0,25,50,75,100]){
  b.s.setAudioVolume(level,true);assert.equal(b.s.audioScale(),level/25);assert.equal(b.s.audioMaster.gain.value,level/25);
  assert.equal(b.s.$('masterVolume').value,String(level));assert.equal(b.s.$('masterVolumeValue').textContent,level+'%');
  assert.deepEqual(saved.at(-1),['volume',level]);
 }
 b.s.muted=true;b.s.syncSound();assert.equal(b.s.audioMaster.gain.value,0);assert.equal(b.s.audioVolume,100);
 b.s.muted=false;b.s.syncSound();assert.equal(b.s.audioMaster.gain.value,4);
});
test('v440 tones and explosions share the doubled master and retain single-effect headroom at maximum volume',async()=>{
 for(const level of [50,100]){
  const b=boot();await b.s.initAudio();b.s.setAudioVolume(level);b.s.webTone(500,700,.1);b.s.boom();
  const gains=b.nodes.filter(n=>n.kind==='gain'&&n.connections.includes(b.s.audioMaster));
  assert.equal(gains.length,3);assert.ok(gains.every(n=>n.connections.includes(b.s.audioMaster)));
  const peaks=gains.map(n=>Math.max(...n.gain.events.filter(e=>e[0]==='ramp').map(e=>e[1])));
  assert.deepEqual(peaks,[.035,.15,.06],'effect envelopes retain their relative levels');
  assert.equal(b.s.audioMaster.gain.value,level/25);
  assert.ok((peaks[1]+peaks[2])*b.s.audioMaster.gain.value<1,'one explosion and its bass tone retain output headroom');
 }
});
test('v440 Safari fallback doubles uncapped PCM samples instead of relying on element volume',async()=>{
 const b=boot({noWebAudio:true});
 for(const level of [25,50,75,100]){
  b.s.setAudioVolume(level);const previous=b.s.wavToneURL(500,700,.1,'sine',.025*(level/50)*7);
  b.s.nativeTone(500,700,.1,.025,'sine');await flush();
  const before=new DataView(await b.blobs.get(previous).arrayBuffer()),after=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer());
  assert.equal(before.byteLength,after.byteLength);
  for(let offset=44;offset<after.byteLength;offset+=2)assert.ok(Math.abs(after.getInt16(offset,true)-before.getInt16(offset,true)*2)<=1,'PCM is twice its old amplitude within integer rounding');
  assert.equal(after.getInt16(44,true),0);assert.equal(after.getInt16(after.byteLength-2,true),0);
  assert.equal(b.native[(b.plays.length-1)%8].volume,1);
 }
 const played=b.plays.length;b.s.setAudioVolume(0);b.s.nativeTone(500,700,.1);b.s.boom();assert.equal(b.plays.length,played);
});
test('v440 loud Safari fallback preserves waveform shape and keeps increasing through 100 percent',async()=>{
 const b=boot({noWebAudio:true});let previousPeak=0;
 for(const level of [25,50,75,99,100]){
  b.s.setAudioVolume(level);b.s.nativeTone(95,32,.28,.12,'triangle');await flush();
  const data=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer()),nominal=.12*(level/25)*7,gain=nominal<=.7?nominal:.7+.28*(nominal-.7)/(.28+nominal-.7);
  const expected=new DataView(await b.blobs.get(b.s.wavToneURL(95,32,.28,'triangle',gain)).arrayBuffer());let peak=0;
  for(let offset=44;offset<data.byteLength;offset+=2){const sample=data.getInt16(offset,true);peak=Math.max(peak,Math.abs(sample));assert.equal(sample,expected.getInt16(offset,true),'soft gain mapping scales the whole waveform without hard-clipping samples');}
  assert.ok(peak>previousPeak&&peak<32760*.98);previousPeak=peak;
  assert.equal(data.getInt16(44,true),0);assert.equal(data.getInt16(data.byteLength-2,true),0);
 }
});
test('v440 every native effect level retains headroom and grows at the top of the slider',()=>{
 const b=boot({noWebAudio:true});
 for(const volume of [.009,.016,.018,.022,.023,.025,.028,.03,.035,.04,.042,.045,.05,.06,.08,.12]){
  let previous=0;
  for(let level=1;level<=100;level++){
   b.s.audioVolume=level;const gain=b.s.nativeToneGain(volume);
   assert.ok(gain>previous&&gain<.98,'whole-wave gain remains increasing below full scale');previous=gain;
  }
 }
});
test('v440 one shared peak compressor protects overlapping sounds and compensates automatic makeup gain',async()=>{
 const b=boot();await b.s.initAudio();const master=b.s.audioMaster,peak=master.connections[0],trim=peak.connections[0];
 assert.equal(peak.kind,'compressor');assert.equal(trim.kind,'gain');assert.equal(trim.connections[0],b.s.audio.destination);
 assert.equal(peak.threshold.value,-3);assert.equal(peak.knee.value,0);assert.equal(peak.ratio.value,20);assert.equal(peak.attack.value,0);assert.equal(peak.release.value,.08);
 const fullScaleDb=peak.threshold.value*(1-1/peak.ratio.value),makeup=Math.pow(10,-fullScaleDb*.6/20);
 assert.ok(Math.abs(trim.gain.value*makeup-1)<1e-12,'quiet mix retains its requested gain');
 // Check the configured steady-state transfer, not a mock claim about browser DSP.
 for(const amplitude of [1,2,4,8,10.4]){
  const inputDb=20*Math.log10(amplitude),compressedDb=peak.threshold.value+(inputDb-peak.threshold.value)/peak.ratio.value;
  assert.ok(Math.pow(10,compressedDb/20)<.82,'configured curve has headroom even for eight stacked explosions and shots');
 }
 for(let i=0;i<20;i++){b.s.webTone(500,700,.1);b.s.boom();await b.s.initAudio();}
 assert.equal(b.nodes.filter(n=>n.kind==='compressor').length,1);assert.equal(master.connections.length,1);
 b.s.audio.state='closed';await b.s.initAudio();assert.equal(b.nodes.filter(n=>n.kind==='compressor').length,2,'recreated context owns one fresh processor');
});
test('v440 startup preserves the default 50 percent and saved volume and mute preferences',()=>{
 assert.match(source,/muted=false, audioVolume=50,/);
 const startup=source.slice(source.indexOf('try{muted=localStorage.getItem'),source.indexOf('\nconst rnd='));
 for(const saved of [null,'0','25','50','100']){
  const b=boot();b.s.localStorage={getItem:key=>key==='leqra.volume'?saved:key==='leqra.muted'?'1':null};b.s.DIFFICULTY={};
  vm.runInContext(startup,b.s);assert.equal(b.s.audioVolume,saved===null?50:Number(saved));assert.equal(b.s.muted,true);
 }
});
