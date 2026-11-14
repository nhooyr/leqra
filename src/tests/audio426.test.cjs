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
  createBiquadFilter(){const n=node('filter');n.frequency=param();n.Q=param();return n;}
  createBufferSource(){return node('buffer');}
  createBuffer(channels,length,rate){const data=new Float32Array(length);return{length,sampleRate:rate,getChannelData:()=>data};}
  resume(){this.resumeCount++;if(options.deferResume)return new Promise(resolve=>this.pending.push(resolve));this.state='running';return Promise.resolve();}
  finishResume(){this.state='running';for(const resolve of this.pending.splice(0))resolve();}
 }
 class NativeAudio{
  constructor(){this.dataset={};this.muted=false;native.push(this);}
  setAttribute(){}
  pause(){this.paused=true;if(this.playingEvent)this.playingEvent.stopAt=Math.min(this.playingEvent.stopAt,clock);}
  play(){this.paused=false;this.ended=false;plays.push(this.src);const blob=blobs.get(this.src);this.playingEvent={url:this.src,at:clock,stopAt:Infinity,until:blob?clock+(blob.size-44)/44100*1000:Infinity};playEvents.push(this.playingEvent);if(options.deferNative)return new Promise((resolve,reject)=>{this.resolvePlay=resolve;this.rejectPlay=reject;});return Promise.resolve();}
 }
 const controls=new Map();const $=id=>{if(!controls.has(id))controls.set(id,{value:'',textContent:'',classList:{toggle(){}},setAttribute(){}});return controls.get(id);};
 const s={muted:false,audioVolume:50,audio:null,audioMaster:null,audioResume:null,noiseBuffer:null,lastChatNotify:0,SAFARI_BROWSER:options.safari!==false,TAU:Math.PI*2,
  document:{hidden:false,hasFocus:()=>focused,addEventListener:(event,fn)=>listeners.set(event,fn)},performance:{now:()=>clock},clamp:(n,a,b)=>Math.max(a,Math.min(b,n)),save(){},$,Blob,
  window:{AudioContext:options.noWebAudio?undefined:Context,addEventListener:(event,fn)=>listeners.set(event,fn)},Audio:NativeAudio,
  URL:{createObjectURL(blob){const url='blob:test-'+nextBlob++;blobs.set(url,blob);return url;},revokeObjectURL(url){blobs.delete(url);}},
  setTimeout(fn,delay){const id=++nextTimer;timers.set(id,{fn,time:clock+delay});return id;},clearTimeout:id=>timers.delete(id)};
 vm.createContext(s);vm.runInContext(audioCode+'\nsetArenaAudio(true);this.audioInspection=()=>({audioLevel,audioMix,audioEpoch,pendingAudioEffects,delayed:nativeAudioTimers.size,voices:nativeVoices.size,bounces:typeof onlineBounceCounts!=="undefined"?onlineBounceCounts.size:0});',s);
 return{s,contexts,native,plays,playEvents,nodes,blobs,listeners,timers,advance(ms){clock+=ms;for(const a of native){if(a.playingEvent&&!a.paused&&clock>=a.playingEvent.until){a.playingEvent.stopAt=Math.min(a.playingEvent.stopAt,a.playingEvent.until);a.ended=a.paused=true;a.onended?.();}}for(const [id,timer]of [...timers])if(timer.time<=clock){timers.delete(id);timer.fn();}},fire(event,extra={}){listeners.get(event)?.({isTrusted:true,...extra});},focus(value){focused=value;listeners.get(value?'focus':'blur')();}};
}

test('Starman PCM matches the shared native fixtures with quiet headroom and a silent loop seam',()=>{
 const {s}=boot(),fixture=JSON.parse(readFileSync(require('node:path').join(__dirname,'starman-audio-fixtures.json'),'utf8'));
 for(const reference of fixture.profiles){
  const pcm=s.starmanLoopSamples(reference.rate);assert.equal(pcm.length,reference.frames);
  let peak=0,energy=0;for(const value of pcm){assert.ok(Number.isFinite(value));peak=Math.max(peak,Math.abs(value));energy+=value*value;}
  assert.ok(Math.abs(peak-reference.peak)<1e-8);assert.ok(Math.abs(Math.sqrt(energy/pcm.length)-reference.rms)<1e-8);
  for(const {index,value}of reference.samples)assert.ok(Math.abs(pcm[index]-value)<1e-8);
  assert.equal(pcm[0],0);assert.equal(pcm.at(-1),0);assert.ok(peak*32<.17,'leaves headroom for ordinary effects and external music');
 }
});
test('one Starman loop survives repeated frames and volume edits, then fades on expiry, menu, mute and blur',async()=>{
 const b=boot();await b.s.initAudio();const loops=()=>b.nodes.filter(node=>node.kind==='buffer'&&node.loop);
 b.s.syncStarmanAudio(true);assert.equal(loops().length,1);const first=loops()[0],buffer=first.buffer;
 for(let i=0;i<1200;i++)b.s.syncStarmanAudio(true);
 b.s.setAudioVolume(75);b.s.syncStarmanAudio(true);assert.equal(loops().length,1);assert.equal(first.stopCalls,undefined);
 b.s.pickupSound();b.s.syncStarmanAudio(true);assert.equal(loops().length,1,'pickup and shots do not restart or duplicate the loop');
 b.s.syncStarmanAudio(false);assert.equal(first.stopped,.014);
 b.s.syncStarmanAudio(true);assert.equal(loops().length,2);assert.equal(loops()[1].buffer,buffer,'PCM buffer is reused');
 b.s.muted=true;b.s.syncSound();assert.equal(loops()[1].stopped,.014);
 b.s.muted=false;b.s.syncSound();b.s.syncStarmanAudio(true);b.focus(false);assert.equal(loops().at(-1).stopped,.014);
 b.focus(true);b.s.syncStarmanAudio(true);b.s.setArenaAudio(false);assert.equal(loops().at(-1).stopped,.014);
});
test('Starman loop ignores bot and remote boosts, follows either live local pilot, and stops on stale online state',async()=>{
 const b=boot();await b.s.initAudio();Object.assign(b.s,{gameStarted:true,phase:'playing',mode:'room',tanks:[{id:8,alive:true,starmanTime:5}],localPlayerID:()=>0,secondaryID:()=>1});
 const loops=()=>b.nodes.filter(node=>node.kind==='buffer'&&node.loop);
 b.s.syncFiniteStarmanAudio();assert.equal(loops().length,0);
 b.s.tanks.push({id:1,alive:true,starmanTime:5});b.s.syncFiniteStarmanAudio();assert.equal(loops().length,1);
 b.s.phase='paused';b.s.syncFiniteStarmanAudio();assert.equal(loops()[0].stopped,.014);
 b.s.phase='playing';b.s.syncFiniteStarmanAudio();b.s.tanks[1].alive=false;b.s.syncFiniteStarmanAudio();assert.equal(loops()[1].stopped,.014);
 b.s.tanks[1].alive=true;b.s.mode='online';b.s.online={connected:true,menu:false,spectating:false,snapshots:[{received:0}]};b.s.syncFiniteStarmanAudio();
 b.advance(2100);b.s.syncFiniteStarmanAudio();assert.equal(loops().at(-1).stopped,.014);
});
test('a delayed audio unlock cannot start an expired Starman loop',async()=>{
 const b=boot({state:'suspended',deferResume:true});b.s.syncStarmanAudio(true);b.s.syncStarmanAudio(false);b.contexts[0].finishResume();await flush();
 assert.equal(b.nodes.filter(node=>node.kind==='buffer'&&node.loop).length,0);
 b.s.syncStarmanAudio(true);assert.equal(b.nodes.filter(node=>node.kind==='buffer'&&node.loop).length,1);
});
test('a volume edit during first audio creation cannot strand the Starman startup latch',async()=>{
 const b=boot();b.s.syncStarmanAudio(true);b.s.setAudioVolume(75);await flush();b.s.syncStarmanAudio(true);
 assert.equal(b.nodes.filter(node=>node.kind==='buffer'&&node.loop).length,1);
});

async function mixedNativePCM(b){
 const layers=[];let length=1;
 for(const event of b.playEvents){
  const data=new DataView(await b.blobs.get(event.url).arrayBuffer()),offset=Math.round(event.at*22.05),n=Math.max(0,Math.min((data.byteLength-44)/2,Math.round((event.stopAt-event.at)*22.05)));
  layers.push({data,offset,n});length=Math.max(length,offset+n);
 }
 const mix=new Float64Array(length);
 for(const {data,offset,n}of layers)for(let i=0;i<n;i++)mix[offset+i]+=data.getInt16(44+i*2,true)/32768;
 return mix;
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
 b.s.setAudioVolume(25);assert.equal(gain.events.at(-1)[0],'ramp');assert.equal(gain.events.at(-1)[1],.25);assert.equal(gain.events.at(-1)[2],.012);
});
test('native Safari fallback scales quiet samples with the slider and keeps silent endpoints',async()=>{
 const b=boot({noWebAudio:true});b.s.nativeTone(500,700,.1,.01,'sine');await flush();assert.equal(b.plays.length,1);
 const data=new DataView(await b.blobs.get(b.plays[0]).arrayBuffer());let peak=0;
 for(let offset=44;offset<data.byteLength;offset+=2)peak=Math.max(peak,Math.abs(data.getInt16(offset,true)));
 assert.ok(peak>1000&&peak<32760*.98,'fallback retains headroom even when iOS ignores the volume property');
 assert.equal(data.getInt16(44,true),0);assert.equal(data.getInt16(data.byteLength-2,true),0);
 b.s.setAudioVolume(25);b.s.nativeTone(500,700,.1,.01,'sine');await flush();const quieter=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer());let quietPeak=0;
 for(let offset=44;offset<quieter.byteLength;offset+=2)quietPeak=Math.max(quietPeak,Math.abs(quieter.getInt16(offset,true)));
 assert.ok(quietPeak<peak*.51&&quietPeak>peak*.49);
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
 assert.equal(b.s.audioMaster.gain.value,.5);
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
 assert.equal(b.s.audioVolume,50);assert.equal(b.s.audioMaster.gain.value,.5);
 for(const level of [0,25,50,75,100]){
  b.s.setAudioVolume(level,true);assert.equal(b.s.audioScale(),(level/100));assert.equal(b.s.audioMaster.gain.value,(level/100));
  assert.equal(b.s.$('masterVolume').value,String(level));assert.equal(b.s.$('masterVolumeValue').textContent,level+'%');
  assert.deepEqual(saved.at(-1),['volume',level]);
 }
 b.s.muted=true;b.s.syncSound();assert.equal(b.s.audioMaster.gain.value,0);assert.equal(b.s.audioVolume,100);
 b.s.muted=false;b.s.syncSound();assert.equal(b.s.audioMaster.gain.value,1);
});

test('the default 50 percent has twice the output of 25 percent on both audio paths',async()=>{
 const web=boot();await web.s.initAudio();
 assert.equal(web.s.audioVolume,50);
 const half=web.s.audioMaster.gain.value;web.s.setAudioVolume(25);assert.equal(half/web.s.audioMaster.gain.value,2);
 const native=boot({noWebAudio:true});native.s.setAudioVolume(100);
 const full=native.s.nativeToneGain(.035);
 const previous=new DataView(await native.blobs.get(native.s.wavToneURL(500,700,.1,'sine',full*.25)).arrayBuffer());
 native.s.setAudioVolume(50);native.s.nativeTone(500,700,.1,.035,'sine');await flush();
 const current=new DataView(await native.blobs.get(native.plays.at(-1)).arrayBuffer());
 assert.equal(current.byteLength,previous.byteLength);
 let energy=0;
 for(let offset=44;offset<current.byteLength;offset+=2){
  const before=previous.getInt16(offset,true),after=current.getInt16(offset,true);
  assert.ok(Math.abs(after-2*before)<=2,'native waveform doubles without changing its shape');
  energy+=after*after;
 }
 assert.ok(energy>0);
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
  assert.equal(peaks[0],.035,'the ordinary preview tone keeps its original level');
  assert.ok(peaks.every(peak=>Number.isFinite(peak)&&peak>0&&peak<=1),'effect layers have positive bounded recipe levels');
  assert.equal(b.s.audioMaster.gain.value,(level/100));
  assert.equal(mix.connections[0].kind,'compressor','the combined mix passes through the peak compressor before the slider');
 }
});
test('tank destruction softens the noise attack and uses a smooth low bass tone',async()=>{
 const b=boot();await b.s.initAudio();b.s.boom();
 const filter=b.nodes.find(n=>n.kind==='filter');assert.equal(filter.type,'lowpass');
 assert.ok(filter.frequency.value<=400&&filter.Q.value<=Math.SQRT1_2,'low noise cutoff avoids a bright or resonant crash');
 const envelope=filter.connections[0].gain.events,attack=envelope.find(e=>e[0]==='ramp'&&e[1]>0);
 assert.ok(attack&&attack[2]>=.015,'noise fades in instead of striking within a few milliseconds');
 const bass=b.nodes.find(n=>n.kind==='oscillator');assert.equal(bass.type,'sine');
 assert.ok(bass.frequency.events[0][1]<=100&&bass.frequency.events.at(-1)[1]>=35,'the body stays in a low bass range');
 assert.equal(b.s.audioMaster.gain.value,.5);b.s.setAudioVolume(100);assert.equal(b.s.audioMaster.gain.value,1,'the shared output slider retains full-volume headroom');
});
test('Safari fallback applies the linear output slider to normalized PCM samples',async()=>{
 const b=boot({noWebAudio:true});
 b.s.setAudioVolume(100);b.s.nativeTone(500,700,.1,.04,'sine');await flush();
 const full=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer());
 for(const level of [25,50,75,100]){
  b.s.setAudioVolume(level);b.s.nativeTone(500,700,.1,.04,'sine');await flush();
  const after=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer());
  assert.equal(full.byteLength,after.byteLength);
  for(let offset=44;offset<after.byteLength;offset+=2)assert.ok(Math.abs(after.getInt16(offset,true)-full.getInt16(offset,true)*(level/100))<=1,'output remains proportional after full-level normalization');
  assert.equal(after.getInt16(44,true),0);assert.equal(after.getInt16(after.byteLength-2,true),0);
  assert.equal(b.native[(b.plays.length-1)%8].volume,1);
 }
 const played=b.plays.length;b.s.setAudioVolume(0);b.s.nativeTone(500,700,.1);b.s.boom();assert.equal(b.plays.length,played);
});
test('v440 loud Safari fallback preserves waveform shape and keeps increasing through 100 percent',async()=>{
 const b=boot({noWebAudio:true});let previousPeak=0;
 for(const level of [25,50,75,99,100]){
  b.s.setAudioVolume(level);b.s.nativeTone(95,32,.28,.12,'triangle');await flush();
  const data=new DataView(await b.blobs.get(b.plays.at(-1)).arrayBuffer()),gain=b.s.nativeToneGain(.12);
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
 const fixedGain=mix.gain.value;assert.ok(fixedGain>0);b.s.setAudioVolume(25);assert.equal(mix.gain.value,fixedGain,'the slider changes output rather than input compression');
 assert.equal(peak.kind,'compressor');assert.equal(trim.kind,'gain');assert.equal(limit.kind,'shaper');
 assert.ok(limit.curve.length>=3&&Array.from(limit.curve).every(value=>Number.isFinite(value)&&Math.abs(value)<1),'the safety curve remains bounded below full scale');
 assert.equal(limit.connections[0],master);assert.equal(master.connections[0],b.s.audio.destination);
 assert.ok(peak.threshold.value<0&&peak.knee.value>=0&&peak.ratio.value>1&&peak.attack.value>=0&&peak.release.value>0);
 const fullScaleDb=peak.threshold.value*(1-1/peak.ratio.value),makeup=Math.pow(10,-fullScaleDb*.6/20);
 assert.ok(Math.abs(trim.gain.value*makeup-1)<1e-12,'quiet mix retains its requested gain');
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
 assert.equal(shell.bounces,1);assert.ok(shell.vx<0);assert.equal(b.plays.length,1);
 const reference=b.plays[0];b.s.cancelPendingAudio();b.s.ricochetSound();assert.equal(b.plays.at(-1),reference,'the actual collision uses the shared ricochet recipe');
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
  if(native){assert.equal(b.plays.length,1);assert.equal(b.s.audioInspection().delayed,1);b.advance(20);assert.equal(b.plays.length,2);}
  else assert.equal(b.nodes.filter(n=>n.kind==='filter').length,1);
  b.advance(71);b.s.boom();if(native)assert.equal(b.plays.length,3);else assert.equal(b.nodes.filter(n=>n.kind==='filter').length,2);
  b.s.muted=true;b.s.syncSound();b.s.muted=false;b.s.syncSound();b.s.boom();if(native)assert.equal(b.plays.length,4);else assert.equal(b.nodes.filter(n=>n.kind==='filter').length,3);
 }
});
test('grenade blast and local or delayed authoritative tank deaths use distinct audio routes',()=>{
 const {boot:gameBoot,tank,bullet,declaration}=require('./godlike426-harness.cjs'),s=gameBoot(),sounds=[],noop=()=>{};
 Object.assign(s,{time:0,POWER:{grenade:{color:'#fff'}},COLORS:['#fff'],combatPrefs:{performance:true},rings:[],reduceMotion:true,
  burst:noop,addRing:noop,eventShake:noop,recordLocalDeath:noop,objectiveMode:()=>false,addLog:noop,updateHUD:noop,
  secondaryID:()=>undefined,boom:()=>sounds.push('tank'),grenadeBoom:()=>sounds.push('grenade'),online:{id:0}});
 for(const name of ['blastEffect','detonate','hurt','onlineEffect'])vm.runInContext(declaration(name),s);
 s.tanks=[tank(0,42,42),tank(1,100,42),tank(2,150,42)];
 s.detonate(bullet(0,142,42));
 assert.deepEqual(sounds,['grenade'],'tank death audio waits for contact presentation');s.fire.flights.sample(0,0);s.fire.flights.flush();s.fire.flights.sample(0,9);s.fire.flights.flush();
 assert.deepEqual(sounds,['grenade','tank','tank'],'one grenade uses its blast route while each victim remains a soft tank death');
 assert.equal(s.tanks[1].alive,false);assert.equal(s.tanks[2].alive,false);
 sounds.length=0;
 s.onlineEffect({type:'blast',x:142,y:42,generation:1},{generation:1,tankMap:new Map()});
 s.onlineEffect({type:'hit',player:1,x:100,y:42,generation:1},{generation:1,tankMap:new Map()});
 assert.deepEqual(sounds,['grenade','tank'],'a separately delivered hit cannot replay the louder grenade sound');
 const rammed=tank(3,100,42,{shield:10,shieldCharges:3});s.tanks.push(rammed);s.hurt(rammed,{owner:0,kind:'starman'});s.fire.flights.sample(0,10);s.fire.flights.flush();s.fire.flights.sample(0,19);s.fire.flights.flush();
 assert.equal(rammed.alive,false);assert.deepEqual(sounds,['grenade','tank','tank'],'Starman contact still produces a soft destruction cue');
});
test('grenade audio takes priority over a recent tank death without making later deaths loud',()=>{
 const capture=()=>{const b=boot({noWebAudio:true});b.cues=[];b.s.nativeTone=(...args)=>b.cues.push(args);return b;};
 const tank=capture();tank.s.boom();const grenade=capture();grenade.s.grenadeBoom();
 assert.ok(tank.cues.length&&grenade.cues.length);assert.notDeepEqual(grenade.cues,tank.cues,'grenades have a separate sound profile');
 const afterGrenade=capture();afterGrenade.s.grenadeBoom();afterGrenade.s.boom();afterGrenade.s.grenadeBoom();
 assert.deepEqual(afterGrenade.cues,grenade.cues,'one blast and its immediate victims share one grenade cue');
 afterGrenade.advance(71);afterGrenade.s.boom();
 assert.deepEqual(afterGrenade.cues,[...grenade.cues,...tank.cues],'a delayed death remains the softer tank profile');
 const afterTank=capture();afterTank.s.boom();afterTank.advance(1);afterTank.s.grenadeBoom();
 assert.deepEqual(afterTank.cues,[...tank.cues,...grenade.cues],'an unrelated death cannot suppress the following grenade blast');
 afterTank.s.cancelPendingAudio();afterTank.s.grenadeBoom();
 assert.deepEqual(afterTank.cues,[...tank.cues,...grenade.cues,...grenade.cues],'cancellation resets both cue throttles');
});
test('native grenade priority clears older voices and tails while preserving its complete waveform',async()=>{
 const {declaration}=require('./godlike426-harness.cjs');
 for(const level of [25,50,100]){
  const isolated=boot({noWebAudio:true});isolated.s.setAudioVolume(level);isolated.s.grenadeBoom();for(let i=0;i<400;i++)isolated.advance(1);
  const busy=boot({noWebAudio:true});busy.s.setAudioVolume(level);busy.s.time=1;vm.runInContext(declaration('shotSound'),busy.s);
  busy.s.pickupSound();busy.s.boom();
  for(let i=0;i<12;i++){busy.s.nativeTone(400,200,.1,.01,'triangle');busy.advance(1);}
  const previous=busy.playEvents.length;busy.s.grenadeBoom();
  assert.ok(busy.playEvents.slice(0,previous).every(event=>event.stopAt<=12),'older native voices are actually stopped');
  for(let i=0;i<400;i++)busy.advance(1);
  const grenade=busy.playEvents.slice(previous);assert.equal(grenade.length,isolated.playEvents.length,'old pickup/death tails cannot restart inside the grenade');
  for(let i=0;i<grenade.length;i++)assert.deepEqual(new Uint8Array(await busy.blobs.get(grenade[i].url).arrayBuffer()),new Uint8Array(await isolated.blobs.get(isolated.playEvents[i].url).arrayBuffer()),'busy scenes do not starve grenade layers');
  let peak=0;for(const sample of await mixedNativePCM(busy))peak=Math.max(peak,Math.abs(sample));
  assert.ok(peak<=.98*(level/100)+8/32768,'the actual mixed PCM retains headroom while voices are replaced');
  assert.equal(busy.s.audioInspection().voices,0);assert.equal(busy.s.audioInspection().delayed,0);
 }
});
test('stale native play and end callbacks cannot change a reused audio voice',async()=>{
 for(const completion of ['resolve','reject','ended']){
  const b=boot({noWebAudio:true,deferNative:true});
  for(let i=0;i<8;i++)b.s.nativeTone(400+i*20,300,.1,.001,'sine');
  const voice=b.native[0],oldResolve=voice.resolvePlay,oldReject=voice.rejectPlay,oldEnd=voice.onended;
  b.s.cancelPendingAudio();b.s.nativeTone(900,600,.1,.001,'sine');
  assert.equal(b.native[0],voice);assert.equal(voice.paused,false);assert.equal(b.s.audioInspection().voices,1);
  if(completion==='resolve')oldResolve();else if(completion==='reject')oldReject(Error('old blocked play'));else oldEnd();
  await flush();assert.equal(voice.paused,false,completion);assert.equal(b.s.audioInspection().voices,1,completion);
 }
});
test('recovered Web Audio stops the old native fallback before starting a fresh effect',async()=>{
 const b=boot({state:'suspended',deferResume:true});b.s.nativeTone(500,300,.15,.01,'sine');
 assert.equal(b.s.audioInspection().voices,1);b.s.initAudio();b.contexts[0].finishResume();await flush();
 b.s.webTone(650,400,.12,.02,'sine');
 assert.equal(b.native[0].paused,true);assert.equal(b.s.audioInspection().voices,0);assert.equal(b.nodes.filter(n=>n.kind==='oscillator').length,1);
});
test('every firing power uses rounded timbres with quieter matching remote voices',()=>{
 const {declaration}=require('./godlike426-harness.cjs'),b=boot(),calls=[];b.s.time=1;b.s.lastMachineTone=-Infinity;b.s.tone=(...args)=>calls.push(args);vm.runInContext(declaration('shotSound'),b.s);
 for(const kind of ['rapid','scatter','laser','homing','grenade','cannon','regular']){
  calls.length=0;b.s.time+=1;b.s.shotSound(kind,true);const local=calls.splice(0);b.s.time+=1;b.s.shotSound(kind,false);const remote=calls.splice(0);
  assert.ok(local.length>0,kind);assert.deepEqual(remote.map(a=>[a[0],a[1],a[2],a[4]]),local.map(a=>[a[0],a[1],a[2],a[4]]),'near and far voices keep the same contour');
  for(let i=0;i<local.length;i++){const layer=local[i],ratio=remote[i][3]/layer[3];assert.ok(['sine','triangle'].includes(layer[4]),kind+' avoids a buzzy sawtooth or square');assert.ok(layer[0]>=50&&layer[0]<=1200&&layer[1]>=35&&layer[1]<=1200&&layer[2]>=.04&&layer[2]<=.35);assert.ok(ratio>=.45&&ratio<=.75,'remote shot remains audible below the local voice');}
  if(kind==='scatter')assert.ok(local.length>1,'shotgun has its own layered volley voice');
 }
});
test('v441 local and authoritative online shield impacts play the same balanced cue',async()=>{
 const {declaration}=require('./godlike426-harness.cjs'),b=boot({noWebAudio:true}),noop=()=>{},s={online:{id:0},POWER:{shield:{color:'#fff'}},COLORS:['#fff'],canDamage:()=>true,shieldCount:t=>t.shieldCharges,burst:noop,addRing:noop,toast:noop,shieldSound:b.s.shieldSound};
 vm.createContext(s);vm.runInContext(declaration('hurt')+'\n'+declaration('onlineEffect'),s);
 const target={id:0,alive:true,shield:10,shieldCharges:1,invulnerable:0};s.hurt(target,{owner:1,kind:''});await flush();assert.equal(target.shieldCharges,0);assert.equal(b.plays.length,1);
 b.s.cancelPendingAudio();s.onlineEffect({type:'shield',player:0,generation:1},{generation:1,tankMap:new Map()});await flush();assert.equal(b.plays.length,2);assert.equal(b.plays[0],b.plays[1]);
});
test('v441 the complete native explosion keeps summed PCM headroom and grows through 100 percent',async()=>{
 let previousPeak=0;
 for(const level of [25,50,75,99,100]){
  const b=boot({noWebAudio:true});b.s.setAudioVolume(level);b.s.boom();b.advance(20);assert.equal(b.playEvents.length,2);
  const layers=[];let length=0;
  for(const e of b.playEvents){const data=new DataView(await b.blobs.get(e.url).arrayBuffer()),offset=Math.round(e.at*22050/1000),n=(data.byteLength-44)/2;layers.push({data,offset,n});length=Math.max(length,offset+n);}
  const mix=new Float64Array(length);for(const {data,offset,n}of layers)for(let i=0;i<n;i++)mix[offset+i]+=data.getInt16(44+i*2,true)/32768;
  let peak=0,energy=0,differences=0;for(let i=0;i<mix.length;i++){const sample=mix[i];peak=Math.max(peak,Math.abs(sample));energy+=sample*sample;if(i)differences+=(sample-mix[i-1])**2;}
  assert.ok(peak>previousPeak&&peak<.98,'entire effect grows without clipping its two-layer mix');previousPeak=peak;
  assert.ok(Math.sqrt(differences/energy)<.05,'the native bass waveform avoids a sharp sawtooth edge');
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
