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
 const s={$,wrap,GAME_VERSION:'test',combatPrefs:{fps:true,performance:false},resetFrameSample(){},resize(){},storePerformancePrefs(){},document:{addEventListener(){}}};
 vm.createContext(s);
 const start=source.indexOf('function initFrameSettings('),end=source.indexOf('\n}',start)+2;
 vm.runInContext(source.slice(start,end),s);s.initFrameSettings();
 assert.equal(insertions.find(row=>row.html.includes('id="fpsIndicator"')).name,'fixed canvas');
 assert.equal(insertions.find(row=>row.html.includes('id="infiniteFPSIndicator"')).name,'Infinity status header');
 assert.equal($('fpsIndicator').hidden,false);assert.equal($('infiniteFPSIndicator').hidden,false);
 $('showFPS').checked=false;$('showFPS').onchange();
 assert.equal($('fpsIndicator').hidden,true);assert.equal($('infiniteFPSIndicator').hidden,true);
 $('showFPS').checked=true;$('showFPS').onchange();
 assert.equal($('fpsIndicator').hidden,false);assert.equal($('infiniteFPSIndicator').hidden,false);
});
