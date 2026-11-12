'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');

test('FPS uses the fixed canvas corner and the Infinity header, with one shared visibility setting',()=>{
 const nodes=new Map(),insertions=[];
 const $=id=>{if(!nodes.has(id))nodes.set(id,{});return nodes.get(id);};
 const parent=name=>({insertAdjacentHTML(position,html){insertions.push({name,html});const id=html.match(/id="([^"]+)"/);if(id)$(id[1]);}});
 const wrap=parent('fixed canvas'),header=parent('Infinity status header'),stage=parent('Infinity stage'),body=parent('Controls');
 nodes.set('infiniteStatusbar',header);$('infiniteCanvas').parentElement=stage;
 $('controlsDialog').querySelector=()=>body;
 const s={$,wrap,GAME_VERSION:'test',combatPrefs:{fps:true,performance:false},resetFrameSample(){},initMenuPing(){},resize(){},storePerformancePrefs(){},document:{addEventListener(){}}};
 vm.createContext(s);
 const start=source.indexOf('function initFrameSettings('),end=source.indexOf('\n}',start)+2;
 vm.runInContext(source.slice(start,end),s);s.initFrameSettings();
 assert.equal(insertions.find(row=>row.html.includes('id="fpsIndicator"')).name,'fixed canvas');
 assert.equal(insertions.find(row=>row.html.includes('id="infiniteFPSIndicator"')).name,'Infinity status header');
 assert.match(insertions.find(row=>row.name==='Controls').html,/> FPS and ping time<\/label>/);
 assert.equal($('fpsIndicator').hidden,false);assert.equal($('infiniteFPSIndicator').hidden,false);
 $('showFPS').checked=false;$('showFPS').onchange();
 assert.equal($('fpsIndicator').hidden,true);assert.equal($('infiniteFPSIndicator').hidden,true);
 $('showFPS').checked=true;$('showFPS').onchange();
 assert.equal($('fpsIndicator').hidden,false);assert.equal($('infiniteFPSIndicator').hidden,false);
});

test('frame readouts label real ping during online play and omit it for offline matches',()=>{
 function reading(mode,phase='playing',measured=true,latency=47,surface='fpsIndicator',override){
  const nodes=new Map(),$=id=>{if(!nodes.has(id))nodes.set(id,{classList:{toggle(){}}});return nodes.get(id);};
  const s={$,mode,phase,online:{connected:true,pingMeasured:measured,latency},combatPrefs:{fps:true}};
  vm.createContext(s);vm.runInContext(source.slice(source.indexOf('const frameStats='),source.indexOf('function initFrameSettings(')),s);
  for(let i=0;i<90;i++){
   const args=[1000+i*1000/60,2,surface];if(override)args.push(override.latency);
   s.sampleFrame(...args);
  }
  return $(surface);
 }
 assert.equal(reading('room').textContent,'fps: 60');
 assert.equal(reading('online','onlineLobby').textContent,'fps: 60, ping: 47 ms');
 const online=reading('online');assert.equal(online.textContent,'fps: 60, ping: 47 ms');
 assert.match(online.title,/Browser frame interval: 16\.7 ms/);assert.match(online.title,/Network round trip: 47 ms/);
 assert.equal(reading('online','playing',false).textContent,'fps: 60, ping: —');
 assert.equal(reading('online','playing',true,0).textContent,'fps: 60, ping: 0 ms');
 assert.equal(reading('room','menu',false,0,'infiniteFPSIndicator',{latency:83}).textContent,'fps: 60, ping: 83 ms');
 assert.equal(reading('online','playing',true,47,'infiniteFPSIndicator',{latency:null}).textContent,'fps: 60');
});

test('menu responses and new game ping samples update the HUD without waiting for the FPS interval',()=>{
 const nodes=new Map(),$=id=>{if(!nodes.has(id))nodes.set(id,{classList:{toggle(){}}});return nodes.get(id);};
 const s={$,mode:'room',phase:'menu',online:{},combatPrefs:{fps:true}};
 vm.createContext(s);vm.runInContext(source.slice(source.indexOf('const frameStats='),source.indexOf('function initFrameSettings(')),s);
 s.beginMenuPing();s.sampleFrame(100,0);assert.equal($('fpsIndicator').textContent,'fps: —, ping: —');
 s.setMenuPing(23);assert.equal($('fpsIndicator').textContent,'fps: —, ping: 23 ms');
 s.sampleFrame(110,0,'infiniteFPSIndicator',81);assert.equal($('infiniteFPSIndicator').textContent,'fps: —, ping: 81 ms');
 s.sampleFrame(120,0,'infiniteFPSIndicator',19);assert.equal($('infiniteFPSIndicator').textContent,'fps: —, ping: 19 ms');
});
