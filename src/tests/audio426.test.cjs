'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
const flush=async()=>{for(let i=0;i<6;i++)await Promise.resolve();};

function boot(options={}){
 const audioSource=options.source||source,audioCode=audioSource.slice(audioSource.indexOf('let audioLevel='),audioSource.indexOf('function setLayout('));
 let clock=0,nextTimer=0,nextBlob=0,focused=true;const listeners=new Map(),timers=new Map(),blobs=new Map(),contexts=[],native=[],plays=[],playEvents=[],nodes=[];
 function param(){return{value:1,events:[],setValueAtTime(value,t){this.value=value;this.events.push(['set',value,t]);},linearRampToValueAtTime(value,t){this.value=value;this.events.push(['ramp',value,t]);},exponentialRampToValueAtTime(value,t){this.value=value;this.events.push(['exponential',value,t]);},cancelAndHoldAtTime(t){this.events.push(['hold',t]);},cancelScheduledValues(t){this.events.push(['cancel',t]);}};}
 function node(kind){const n={kind,disconnected:false,connections:[],connect(target){this.connections.push(target);},disconnect(){this.disconnected=true;},start(t){this.started=t;},stop(t){this.stopped=t;this.stopCalls=(this.stopCalls||0)+1;}};nodes.push(n);return n;}
 class Context{
  constructor(){this.state=options.state||'running';this.currentTime=0;this.sampleRate=48000;this.destination={};this.resumeCount=0;this.pending=[];contexts.push(this);}
  createGain(){const n=node('gain');n.gain=param();return n;}
  createDynamicsCompressor(){const n=node('compressor');for(const key of ['threshold','knee','ratio','attack','release'])n[key]=param();return n;}
  createWaveShaper(){return node('shaper');}
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
  play(){this.paused=false;plays.push(this.src);playEvents.push({url:this.src,at:clock});if(options.deferNative)return new Promise((resolve,reject)=>{this.resolvePlay=resolve;this.rejectPlay=reject;});return Promise.resolve();}
 }
 const controls=new Map();const $=id=>{if(!controls.has(id))controls.set(id,{value:'',textContent:'',classList:{toggle(){}},setAttribute(){}});return controls.get(id);};
 const s={muted:false,audioVolume:50,audio:null,audioMaster:null,audioResume:null,noiseBuffer:null,lastChatNotify:0,SAFARI_BROWSER:options.safari!==false,TAU:Math.PI*2,
  document:{hidden:false,hasFocus:()=>focused,addEventListener:(event,fn)=>listeners.set(event,fn)},performance:{now:()=>clock},clamp:(n,a,b)=>Math.max(a,Math.min(b,n)),save(){},$,Blob,
  window:{AudioContext:options.noWebAudio?undefined:Context,addEventListener:(event,fn)=>listeners.set(event,fn)},Audio:NativeAudio,
  URL:{createObjectURL(blob){const url='blob:test-'+nextBlob++;blobs.set(url,blob);return url;},revokeObjectURL(url){blobs.delete(url);}},
  setTimeout(fn,delay){const id=++nextTimer;timers.set(id,{fn,time:clock+delay});return id;},clearTimeout:id=>timers.delete(id)};
 vm.createContext(s);vm.runInContext(audioCode+'\nsetArenaAudio(true);this.audioInspection=()=>({audioLevel,audioMix,audioEpoch,pendingAudioEffects,delayed:nativeAudioTimers.size,bounces:typeof onlineBounceCounts!=="undefined"?onlineBounceCounts.size:0});',s);
 return{s,contexts,native,plays,playEvents,nodes,blobs,listeners,timers,advance(ms){clock+=ms;for(const [id,timer]of [...timers])if(timer.time<=clock){timers.delete(id);timer.fn();}},fire(event,extra={}){listeners.get(event)?.({isTrusted:true,...extra});},focus(value){focused=value;listeners.get(value?'focus':'blur')();}};
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
test('a touch release can unlock audio immediately after a passive resume attempt',async()=>{
 const b=boot({state:'interrupted',deferResume:true});
 b.s.initAudio(true);
 b.s.primeAudioUnlock({type:'pointerdown',pointerType:'touch',isTrusted:true});
 assert.equal(b.contexts[0].resumeCount,1);
 b.advance(20);
 b.s.primeAudioUnlock({type:'pointerup',pointerType:'touch',isTrusted:true});
 assert.equal(b.contexts[0].resumeCount,2,'a genuine gesture retries the passive attempt inside the coalescing window');
 b.fire('click');
 assert.equal(b.contexts[0].resumeCount,2,'the compatibility click coalesces with the successful gesture');
 b.contexts[0].finishResume();await flush();assert.equal(await b.s.initAudio(),true);
});
test('running audio does not reschedule gain for every click; volume changes ramp',async()=>{
 const b=boot();await b.s.initAudio();const gain=b.s.audioMaster.gain;const initial=gain.events.length;
 for(let i=0;i<50;i++){b.fire('click');await b.s.initAudio();}assert.equal(gain.events.length,initial);
 b.s.setAudioVolume(25);assert.equal(gain.events.at(-1)[0],'ramp');assert.equal(gain.events.at(-1)[1],.0625);assert.equal(gain.events.at(-1)[2],.012);
});
test('native Safari fallback scales quiet samples with the slider and keeps silent endpoints',async()=>{
 const b=boot({noWebAudio:true});b.s.nativeTone(500,700,.1,.01,'sine');await flush();assert.equal(b.plays.length,1);
 const data=new DataView(await b.blobs.get(b.plays[0]).arrayBuffer());let peak=0;
 for(let offset=44;offset<data.byteLength;offset+=2)peak=Math.max(peak,Math.abs(data.getInt16(offset,true)));
 assert.ok(peak>1000&&peak<32760*.98,'fallback retains headroom even when iOS ignores the volume property');
 assert.equal(data.getInt16(44,true),0);assert.equal(data.getInt16(data.byteLength-2,true),0);
 b.s.setAudioVolume(25);b.s.nativeTone(500,700,.1,.01,'sine');await flush();const quieter=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer());let quietPeak=0;
 for(let offset=44;offset<quieter.byteLength;offset+=2)quietPeak=Math.max(quietPeak,Math.abs(quieter.getInt16(offset,true)));
 assert.ok(quietPeak<peak*.26&&quietPeak>peak*.24);
});
test('muting stops native playback and cancels delayed tones across subsequent unmute',async()=>{
 const b=boot({noWebAudio:true});b.s.nativeTone(500,700,.1);b.s.nativeTone(700,900,.1,.035,'sine',.1);assert.equal(b.s.audioInspection().delayed,1);
 b.s.muted=true;b.s.syncSound();assert.equal(b.native[0].paused,true);assert.equal(b.native[0].muted,true);assert.equal(b.s.audioInspection().delayed,0);
 b.s.muted=false;b.s.syncSound();b.advance(150);await flush();assert.equal(b.plays.length,1);
});
test('a visible background window stops effects and restores sound on focus',async()=>{
 const b=boot();await b.s.initAudio();b.s.boom();
 const effects=b.nodes.length;
 b.focus(false);
 assert.equal(b.s.document.hidden,false);
 assert.equal(b.s.audioMaster.gain.value,0);
 b.s.boom();b.s.pickupSound();b.s.chatNotificationSound();
 assert.equal(b.nodes.length,effects);
 b.focus(true);
 assert.equal(b.s.audioMaster.gain.value,.25);
 b.s.boom();assert.ok(b.nodes.length>effects);
 b.s.document.hidden=true;b.fire('visibilitychange');
 assert.equal(b.s.audioMaster.gain.value,0);
});
test('losing window focus stops the native fallback and discards delayed cues',async()=>{
 const b=boot({noWebAudio:true});b.s.pickupSound();
 assert.equal(b.plays.length,1);
 assert.equal(b.s.audioInspection().delayed,2);
 b.focus(false);
 assert.ok(b.native[0].paused&&b.native[0].muted);
 assert.equal(b.s.audioInspection().delayed,0);
 b.s.boom();b.focus(true);b.advance(200);await flush();
 assert.equal(b.plays.length,1);
});
test('the start menu is silent for automatic cues and still allows a volume preview',async()=>{
 const b=boot();b.s.setArenaAudio(false);await b.s.initAudio();b.advance(200);
 b.s.tone(430,550,.12);b.s.boom();b.s.pickupSound();b.s.chatNotificationSound();
 assert.equal(b.nodes.filter(n=>n.kind==='oscillator'||n.kind==='buffer').length,0);
 b.s.setAudioVolume(60,false,true);
 assert.equal(b.nodes.filter(n=>n.kind==='oscillator').length,1);
});
test('returning to the menu cancels scheduled Web Audio and native round notes',async()=>{
 const web=boot();await web.s.initAudio();
 web.s.tone(430,550,.12);web.s.tone(650,800,.19,.04,'triangle',.13);
 const oscillators=web.nodes.filter(n=>n.kind==='oscillator');
 assert.equal(oscillators[1].started,.13);
 web.s.setArenaAudio(false);
 assert.ok(oscillators.every(n=>n.stopCalls===2&&n.stopped===undefined));
 const native=boot({noWebAudio:true});
 native.s.tone(430,550,.12);native.s.tone(650,800,.19,.04,'triangle',.13);
 native.s.setArenaAudio(false);native.s.setArenaAudio(true);native.advance(200);await flush();
 assert.equal(native.plays.length,1);
 assert.ok(native.native[0].paused&&native.native[0].muted);
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
 const b=boot();await b.s.initAudio();const permanent=new Set(b.nodes);b.s.webTone(500,700,.1);b.s.boom();
 for(const n of b.nodes.filter(n=>n.kind==='oscillator'||n.kind==='buffer')){assert.equal(typeof n.onended,'function');n.onended();assert.equal(n.disconnected,true);}
 assert.ok(b.nodes.filter(n=>!permanent.has(n)).every(n=>n.disconnected),'all effect nodes release their graph connections');
});
test('zero volume prevents both playback paths, while restoring volume allows a fresh effect',async()=>{
 const b=boot();await b.s.initAudio();b.s.setAudioVolume(0);b.s.tone(500,700,.1);b.s.boom();assert.equal(b.plays.length,0);assert.equal(b.nodes.filter(n=>n.kind==='oscillator').length,0);
 b.s.setAudioVolume(50);b.s.tone(500,700,.1);assert.equal(b.nodes.filter(n=>n.kind==='oscillator').length,1);
});

test('the louder shared output retains displayed and saved slider percentages',async()=>{
 const b=boot(),saved=[];b.s.save=(...entry)=>saved.push(entry);await b.s.initAudio();
 assert.equal(b.s.audioVolume,50);assert.equal(b.s.audioMaster.gain.value,.25);
 for(const level of [0,25,50,75,100]){
  b.s.setAudioVolume(level,true);assert.equal(b.s.audioScale(),Math.pow(level/100,2));assert.equal(b.s.audioMaster.gain.value,Math.pow(level/100,2));
  assert.equal(b.s.$('masterVolume').value,String(level));assert.equal(b.s.$('masterVolumeValue').textContent,level+'%');
  assert.deepEqual(saved.at(-1),['volume',level]);
 }
 b.s.muted=true;b.s.syncSound();assert.equal(b.s.audioMaster.gain.value,0);assert.equal(b.s.audioVolume,100);
 b.s.muted=false;b.s.syncSound();assert.equal(b.s.audioMaster.gain.value,1);
});

test('the volume slider snaps around its default and keyboard arrows can leave the midpoint',()=>{
 const b=boot(),saved=[];b.s.save=(...entry)=>saved.push(entry);
 for(const level of [46,49,50,51,54]){
  b.s.setAudioVolume(level,true);
  assert.equal(b.s.audioVolume,50);
  assert.equal(b.s.$('masterVolume').value,'50');
  assert.deepEqual(saved.at(-1),['volume',50]);
 }
 const start=source.indexOf("$('masterVolume').onkeydown=e=>{");
 const end=source.indexOf('\n };',start)+4;
 assert.ok(start>=0&&end>start);
 vm.runInContext(source.slice(start,end),b.s);
 const slider=b.s.$('masterVolume');
 for(const [key,want] of [['ArrowRight',55],['ArrowUp',55],['ArrowLeft',45],['ArrowDown',45]]){
  b.s.setAudioVolume(50);
  let prevented=false;
  slider.onkeydown({key,preventDefault(){prevented=true;}});
  assert.ok(prevented);
  assert.equal(b.s.audioVolume,want);
  assert.deepEqual(saved.at(-1),['volume',want]);
 }
 b.s.setAudioVolume(50);
 slider.onkeydown({key:'ArrowRight',metaKey:true,preventDefault(){assert.fail('system shortcut intercepted');}});
 assert.equal(b.s.audioVolume,50);
});
test('tones and explosions share fixed mix processing before the output volume control',async()=>{
 for(const level of [50,100]){
  const b=boot();await b.s.initAudio();b.s.setAudioVolume(level);b.s.webTone(500,700,.1);b.s.boom();
  const mix=b.s.audioInspection().audioMix;
  const gains=b.nodes.filter(n=>n.kind==='gain'&&n.connections.includes(mix));
  assert.equal(gains.length,3);assert.ok(gains.every(n=>n.connections.includes(mix)));
  const peaks=gains.map(n=>Math.max(...n.gain.events.filter(e=>e[0]==='ramp').map(e=>e[1])));
  assert.deepEqual(peaks,[.035,.065,.035],'balanced death layers use their requested recipe levels');
  assert.equal(b.s.audioMaster.gain.value,Math.pow(level/100,2));
  assert.equal(mix.connections[0].kind,'compressor','the combined mix passes through the peak compressor before the slider');
 }
});
test('Safari fallback applies the squared output slider to normalized PCM samples',async()=>{
 const b=boot({noWebAudio:true});
 b.s.setAudioVolume(100);b.s.nativeTone(500,700,.1,.04,'sine');await flush();
 const full=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer());
 for(const level of [25,50,75,100]){
  b.s.setAudioVolume(level);b.s.nativeTone(500,700,.1,.04,'sine');await flush();
  const after=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer());
  assert.equal(full.byteLength,after.byteLength);
  for(let offset=44;offset<after.byteLength;offset+=2)assert.ok(Math.abs(after.getInt16(offset,true)-full.getInt16(offset,true)*Math.pow(level/100,2))<=1,'output remains proportional after full-level normalization');
  assert.equal(after.getInt16(44,true),0);assert.equal(after.getInt16(after.byteLength-2,true),0);
  assert.equal(b.native[(b.plays.length-1)%8].volume,1);
 }
 const played=b.plays.length;b.s.setAudioVolume(0);b.s.nativeTone(500,700,.1);b.s.boom();assert.equal(b.plays.length,played);
});
test('v440 loud Safari fallback preserves waveform shape and keeps increasing through 100 percent',async()=>{
 const b=boot({noWebAudio:true});let previousPeak=0;
 for(const level of [25,50,75,99,100]){
  b.s.setAudioVolume(level);b.s.nativeTone(95,32,.28,.12,'triangle');await flush();
  const data=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer()),nominal=.12*256,full=nominal<=.7?nominal:.7+.28*(nominal-.7)/(.28+nominal-.7),gain=full*Math.pow(level/100,2);
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
test('one shared compressor and bounded limiter protect the mix before output volume',async()=>{
 const b=boot();await b.s.initAudio();const master=b.s.audioMaster,mix=b.s.audioInspection().audioMix,peak=mix.connections[0],trim=peak.connections[0],limit=trim.connections[0];
 assert.equal(mix.gain.value,256);
 assert.equal(peak.kind,'compressor');assert.equal(trim.kind,'gain');assert.equal(limit.kind,'shaper');
 assert.deepEqual(Array.from(limit.curve),[-.98,0,.98].map(Math.fround));
 assert.equal(limit.connections[0],master);assert.equal(master.connections[0],b.s.audio.destination);
 assert.equal(peak.threshold.value,-3);assert.equal(peak.knee.value,0);assert.equal(peak.ratio.value,20);assert.equal(peak.attack.value,0);assert.equal(peak.release.value,.08);
 const fullScaleDb=peak.threshold.value*(1-1/peak.ratio.value),makeup=Math.pow(10,-fullScaleDb*.6/20);
 assert.ok(Math.abs(trim.gain.value*makeup-1)<1e-12,'quiet mix retains its requested gain');
 // Check the configured steady-state transfer, not a mock claim about browser DSP.
 for(const amplitude of [1,2,4,8,10.4,20.8]){
  const inputDb=20*Math.log10(amplitude),compressedDb=peak.threshold.value+(inputDb-peak.threshold.value)/peak.ratio.value;
  assert.ok(Math.pow(10,compressedDb/20)<.85,'configured curve has headroom even for eight stacked explosions and shots');
 }
 for(let i=0;i<20;i++){b.s.webTone(500,700,.1);b.s.boom();await b.s.initAudio();}
 assert.equal(b.nodes.filter(n=>n.kind==='compressor').length,1);assert.equal(b.nodes.filter(n=>n.kind==='shaper').length,1);assert.equal(master.connections.length,1);
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

test('v441 an actual local wall collision uses the louder shared ricochet cue',async()=>{
 const {boot:gameBoot,declaration}=require('./godlike426-harness.cjs'),b=boot({noWebAudio:true}),s=gameBoot({wallList:[{x:220,y:100,w:8,h:200,axis:'v'}]});
 Object.assign(s,{burst(){},ricochetSound:b.s.ricochetSound});
 for(const name of ['updateBullets','compactNotDead'])vm.runInContext(declaration(name),s);
 const shell={id:1,owner:0,x:200,y:200,vx:282,vy:0,r:3.5,kind:'',age:0,life:5,bounces:0,trail:[],color:'#fff'};s.bullets=[shell];s.updateBullets(.1);await flush();
 assert.equal(shell.bounces,1);assert.ok(shell.vx<0);assert.equal(b.plays.length,1);assert.equal(b.native[0].dataset.baseVolume,'0.035');
 const reference=b.s.wavToneURL(650,420,.045,'sine',b.s.nativeToneGain(.035));assert.equal(b.plays[0],reference);
});
test('v441 online ricochets follow displayed bounce high-water counts without history, replay or unbounded cache',async()=>{
 const b=boot({noWebAudio:true}),items=[{id:1,bounces:3},{id:2,bounces:0},{id:3,bounces:9,preview:true}];
 b.s.updateOnlineBounceSounds(items,1);assert.equal(b.plays.length,0,'joining does not play old bounces');assert.equal(b.s.audioInspection().bounces,2);
 items[0].bounces=4;items[1].bounces=1;b.s.updateOnlineBounceSounds(items,1);await flush();assert.equal(b.plays.length,1,'simultaneous collisions share the ricochet throttle');
 for(const count of [4,3,4]){items[0].bounces=count;b.s.updateOnlineBounceSounds(items,1);}assert.equal(b.plays.length,1,'interpolation rewind does not repeat sounds');
 b.advance(71);items[0].bounces=5;b.s.updateOnlineBounceSounds(items,1);assert.equal(b.plays.length,2);
 b.s.updateOnlineBounceSounds([],null);assert.equal(b.s.audioInspection().bounces,0);items[0].bounces=9;b.s.updateOnlineBounceSounds(items,1);assert.equal(b.plays.length,2,'same-generation reconnect starts with fresh history');
 b.advance(71);items[0].bounces=10;b.s.updateOnlineBounceSounds(items,1);assert.equal(b.plays.length,3);
 b.s.updateOnlineBounceSounds(items,2);assert.equal(b.plays.length,3,'new maze baselines retained IDs');b.s.updateOnlineBounceSounds([],2);assert.equal(b.s.audioInspection().bounces,0);
 assert.ok(b.plays.every(url=>url===b.plays[0]),'online and local cues use one recipe');
});
test('v441 clustered grenade deaths share one explosion cue, with fresh cues after the short burst',async()=>{
 for(const native of [false,true]){
  const b=boot({noWebAudio:native});if(!native)await b.s.initAudio();
  for(let i=0;i<9;i++)b.s.boom();
  if(native){assert.equal(b.plays.length,1);assert.equal(b.s.audioInspection().delayed,1);b.advance(15);assert.equal(b.plays.length,2);}
  else assert.equal(b.nodes.filter(n=>n.kind==='filter').length,1);
  b.advance(71);b.s.boom();if(native)assert.equal(b.plays.length,3);else assert.equal(b.nodes.filter(n=>n.kind==='filter').length,2);
  b.s.muted=true;b.s.syncSound();b.s.muted=false;b.s.syncSound();b.s.boom();if(native)assert.equal(b.plays.length,4);else assert.equal(b.nodes.filter(n=>n.kind==='filter').length,3);
 }
});
test('v441 weapon recipes keep their timbres and reduce the local/remote level gap',()=>{
 const {declaration}=require('./godlike426-harness.cjs'),b=boot(),calls=[];b.s.time=1;b.s.lastMachineTone=-Infinity;b.s.tone=(...args)=>calls.push(args);vm.runInContext(declaration('shotSound'),b.s);
 const shapes={rapid:[[160,65,.055,'triangle']],laser:[[1100,160,.23,'sawtooth'],[1700,500,.14,'sine']],homing:[[110,370,.24,'sawtooth']],grenade:[[95,42,.15,'triangle']],cannon:[[75,28,.24,'triangle'],[180,45,.11,'sawtooth']],regular:[[145,60,.085,'triangle']]};
 for(const [kind,shape]of Object.entries(shapes)){
  calls.length=0;b.s.time+=1;b.s.shotSound(kind,true);const local=calls.splice(0);b.s.time+=1;b.s.shotSound(kind,false);const remote=calls.splice(0);
  assert.deepEqual(local.map(a=>[a[0],a[1],a[2],a[4]]),shape);assert.deepEqual(remote.map(a=>[a[0],a[1],a[2],a[4]]),shape);
  for(let i=0;i<local.length;i++){assert.ok(local[i][3]>=remote[i][3]);assert.ok(local[i][3]/remote[i][3]<1.3,'remote shot stays audible');}
 }
});
test('v441 local and authoritative online shield impacts play the same balanced cue',async()=>{
 const {declaration}=require('./godlike426-harness.cjs'),b=boot({noWebAudio:true}),noop=()=>{},s={online:{id:0},POWER:{shield:{color:'#fff'}},COLORS:['#fff'],canDamage:()=>true,shieldCount:t=>t.shieldCharges,burst:noop,addRing:noop,toast:noop,shieldSound:b.s.shieldSound};
 vm.createContext(s);vm.runInContext(declaration('hurt')+'\n'+declaration('onlineEffect'),s);
 const target={id:0,alive:true,shield:10,shieldCharges:1,invulnerable:0};s.hurt(target,{owner:1,kind:''});await flush();assert.equal(target.shieldCharges,0);assert.equal(b.plays.length,1);
 s.onlineEffect({type:'shield',player:0,generation:1},{generation:1,tankMap:new Map()});await flush();assert.equal(b.plays.length,2);assert.equal(b.plays[0],b.plays[1]);assert.equal(b.native[0].dataset.baseVolume,'0.037');
});
test('v441 the complete native explosion keeps summed PCM headroom and grows through 100 percent',async()=>{
 let previousPeak=0;
 for(const level of [25,50,75,99,100]){
  const b=boot({noWebAudio:true});b.s.setAudioVolume(level);b.s.boom();b.advance(15);assert.equal(b.playEvents.length,2);
  const layers=[];let length=0;
  for(const e of b.playEvents){const data=new DataView(await b.blobs.get(e.url).arrayBuffer()),offset=Math.round(e.at*22050/1000),n=(data.byteLength-44)/2;layers.push({data,offset,n});length=Math.max(length,offset+n);}
  const mix=new Float64Array(length);for(const {data,offset,n}of layers)for(let i=0;i<n;i++)mix[offset+i]+=data.getInt16(44+i*2,true)/32768;
  let peak=0;for(const sample of mix)peak=Math.max(peak,Math.abs(sample));assert.ok(peak>previousPeak&&peak<.98,'entire effect grows without clipping its two-layer mix');previousPeak=peak;
 }
});
test('v441 layered native weapons fit their combined budget and still grow through 100 percent',async()=>{
 const {declaration}=require('./godlike426-harness.cjs');
 for(const kind of ['laser','cannon'])for(const local of [true,false]){
  let previousPeak=0;
  for(const level of [50,75,99,100]){
   const b=boot({noWebAudio:true});b.s.setAudioVolume(level);b.s.time=1;b.s.lastMachineTone=-Infinity;vm.runInContext(declaration('shotSound'),b.s);b.s.shotSound(kind,local);assert.equal(b.playEvents.length,2);
   const layers=[];let length=0;for(const event of b.playEvents){const data=new DataView(await b.blobs.get(event.url).arrayBuffer()),n=(data.byteLength-44)/2;layers.push({data,n});length=Math.max(length,n);}
   const mix=new Float64Array(length);for(const {data,n}of layers)for(let i=0;i<n;i++)mix[i]+=data.getInt16(44+i*2,true)/32768;
   let peak=0;for(const value of mix)peak=Math.max(peak,Math.abs(value));assert.ok(peak>previousPeak&&peak<.98,kind+' combined native cue remains increasing below full scale');previousPeak=peak;
  }
 }
});
