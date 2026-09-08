'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const events=[],bounds={width:900,height:600},frames=[];
 const canvas={_width:900,_height:600,get width(){return this._width;},set width(v){this._width=v;events.push('clear width');},get height(){return this._height;},set height(v){this._height=v;events.push('clear height');}};
 const noop=()=>{},ctx=new Proxy({fillRect(){events.push('draw background');}},{get:(t,k)=>t[k]||noop});
 const s={canvas,ctx,wrap:{getBoundingClientRect:()=>bounds},cssW:900,cssH:600,dpr:1,W:588,H:588,scale:1,offsetX:0,offsetY:0,touchUI:false,touchLandscape:false,WEBKIT_ENGINE:false,arenaResizeFrame:0,renderPixelRatio:()=>1,isSpectating:()=>false,requestAnimationFrame:fn=>frames.push(fn),theme:{},paintColor:x=>x,shake:0,mapCanvas:null,pickups:[],tanks:[],bullets:[],rings:[],particles:[],drawObjectives:noop,drawAimingGuides:noop,drawFlags:noop,drawMissileWarnings:noop,drawLasers:noop};
 vm.createContext(s);for(const name of ['resize','scheduleArenaResize','stabilizeArenaLayout','syncCanvasSize','render'])vm.runInContext(declaration(name),s);
 return{s,events,bounds,frames};
}
test('layout and ResizeObserver callbacks leave the last drawn canvas intact until the next render',()=>{
 const {s,events,bounds,frames}=boot();bounds.height=520;s.stabilizeArenaLayout();s.stabilizeArenaLayout();
 assert.deepEqual(events,[]);assert.equal(frames.length,1);assert.equal(s.canvas.height,600);assert.equal(s.cssH,520);
 frames.shift()();assert.deepEqual(events,[]);s.render();assert.deepEqual(events,['clear height','draw background']);assert.equal(s.canvas.height,520);
 events.length=0;s.render();assert.deepEqual(events,['draw background'],'unchanged frames do not reallocate the bitmap');
});
test('render allocation retains WebKit one-pixel jitter suppression while applying real viewport changes',()=>{
 const {s,events,bounds}=boot();s.WEBKIT_ENGINE=true;bounds.height=599.2;s.resize();s.render();assert.deepEqual(events,['draw background']);assert.equal(s.canvas.height,600);
 events.length=0;bounds.width=700;bounds.height=500;s.resize();assert.deepEqual(events,[]);s.render();assert.deepEqual(events,['clear width','clear height','draw background']);assert.equal(s.canvas.width,700);assert.equal(s.canvas.height,500);
});
test('GO initializes the round and HUD before exposing the arena',()=>{
 const steps=[],s={mode:'room',roomStartError:()=>'',initAudio(){},clearInput(){},scores:[],MAX_TANKS:8,round:0,gameStarted:false,beginLocalMatchStats(){},logLines:[],addLog(){},modeLabel:()=>'',displayScoreTarget:()=>'',startRound(){s.phase='countdown';steps.push('round and HUD ready');},setScreen(screen){assert.equal(screen,null);assert.equal(s.phase,'countdown');steps.push('arena revealed');},canvas:{focus(){steps.push('focused');}}};
 vm.createContext(s);vm.runInContext(declaration('startMatch'),s);s.startMatch();assert.deepEqual(steps,['round and HUD ready','arena revealed','focused']);
});
