'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const {assetPath}=require('./web_assets.cjs');

test('generated showcase is identical across web and native clients',()=>{
 const context={window:{}};vm.runInNewContext(fs.readFileSync(assetPath('showcase-scene.js'),'utf8'),context);
 const scene=JSON.parse(JSON.stringify(context.window.leqraShowcaseScene));
 for(const file of ['ios/Sources/leqraCore/Resources/showcase.json','android/app/src/main/assets/showcase.json'])assert.deepEqual(JSON.parse(fs.readFileSync(path.join(__dirname,'../..',file),'utf8')),scene);
 assert.equal(scene.seed,14383);assert.equal(scene.localID,0);assert.equal(scene.tanks.length,8);assert.equal(scene.bullets.length,53);
 assert.equal(new Set(scene.pickups.map(item=>item.type)).size,10);assert.ok(scene.effects.find(effect=>effect.kind==='laser').points.length>=3);
 assert.deepEqual(scene.effects.slice(0,3).map(effect=>effect.showcaseAge),[36,120,105]);
 assert.equal(scene.tanks.find(tank=>tank.id===scene.localID).name,'aqsnow');
 assert.equal(scene.portrait.tanks.length,10);assert.equal(scene.portrait.pickups.length,4);assert.equal(scene.portrait.bullets.length,52);
 assert.equal(scene.portrait.fps,120);assert.equal(scene.portrait.ping,8);
 assert.equal(scene.desktop.tanks.length,20);assert.equal(scene.desktop.pickups.length,26);assert.equal(scene.desktop.bullets.length,130);
 assert.ok(scene.portrait.tanks.every(tank=>Math.abs(tank.x-42)<=168&&Math.abs(tank.y-42)<=252),'portrait tanks stay near the player');
 assert.ok(scene.portrait.tanks.some(tank=>tank.y<=42-250),'the top gap contains a tank');
 assert.ok(scene.portrait.tanks.some(tank=>tank.y>=42+250&&Math.abs(tank.x-42)<42),'the bottom-center gap contains a tank');
 for(const variant of [scene,scene.portrait,scene.desktop]){
  const destroyed=variant.tanks.filter(tank=>tank.hp===0);assert.equal(destroyed.length,1);
  assert.ok(variant.effects.some(effect=>effect.kind==='hit'&&effect.owner===destroyed[0].id),'the destroyed tank has a visible hit effect');
  const equipped=new Set();
  for(const tank of variant.tanks.filter(tank=>tank.hp>0)){
   if(tank.power&&tank.powerTime>0)equipped.add(tank.power);
   if(tank.shield>0)equipped.add('shield');if(tank.speedTime>0)equipped.add('speed');
   if(tank.ghostTime>0)equipped.add('ghost');if(tank.starmanTime>0)equipped.add('starman');
  }
  assert.deepEqual([...equipped].sort(),['cannon','ghost','grenade','homing','laser','rapid','scatter','shield','speed','starman'],'all ten powers are equipped by surviving tanks');
 }
});

test('the desktop addition preserves the original mobile wide and portrait scenes',()=>{
 const context={window:{}};vm.runInNewContext(fs.readFileSync(assetPath('showcase-scene.js'),'utf8'),context);
 const {desktop,...mobile}=context.window.leqraShowcaseScene;
 function sorted(value){return Array.isArray(value)?value.map(sorted):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(key=>[key,sorted(value[key])])):value;}
 assert.equal(createHash('sha256').update(JSON.stringify(sorted(mobile))).digest('hex'),'3d08f184b3e97421a37a04db572d53d8889be7ebdd1bef2adcbd4986164b60fe');
});

function boot(scene={}){
 const nodes=[],listeners=new Map(),rendered=[];let draws=0,restored=0,touch=false;
 const listen=(target,type,callback)=>listeners.set(target+':'+type,callback);
 const document={activeElement:{focus(){restored++;}},hidden:false,body:{append(node){nodes.push(node);}},createElement(tag){return{tag,dataset:{},classList:{toggle(){}},querySelector(){return null;},children:[],setAttribute(){},append(node){this.children.push(node);},addEventListener(type,callback){listen(tag,type,callback);},showModal(){this.open=true;},close(){this.open=false;}};},addEventListener(type,callback){listen('document',type,callback);}};
 const window={leqraInfinityArt:{isTouchUI:()=>touch},leqraShowcaseScene:scene,leqraInfinity:{showcaseRenderer:(_canvas,selected)=>{rendered.push(selected);return()=>{draws++;};}},addEventListener(type,callback){listen('window',type,callback);}};
 // Exercise the modal lifecycle without reimplementing the browser DOM here.
 // The browser matrix verifies the real cloned header, HUD and leaderboard.
 const source=fs.readFileSync(assetPath('showcase.js'),'utf8').replace(/function buildChrome\(scene\)\{[\s\S]*?\nfunction draw\(\)/,'function buildChrome(){}\nfunction draw()');
 const context={document,window,innerWidth:1560,innerHeight:930};vm.runInNewContext(source,context);
 return{window,document,dialog:nodes[0],rendered,resize(width,height,isTouch){context.innerWidth=width;context.innerHeight=height;touch=isTouch;listeners.get('window:resize')();},event(target,type,values={}){const event={preventDefault(){this.prevented=true;},stopImmediatePropagation(){this.stopped=true;},...values};listeners.get(target+':'+type)?.(event);return event;},get draws(){return draws;},get restored(){return restored;}};
}
test('Showcase selects the dense desktop only for non-touch displays and falls back to wide',()=>{
 const scene={seed:1,portrait:{seed:2},desktop:{seed:3}},h=boot(scene);h.window.leqraShowcase.open();
 assert.equal(h.dialog.dataset.scene,'desktop');assert.equal(h.rendered.at(-1),scene.desktop);
 h.resize(844,390,true);assert.equal(h.dialog.dataset.scene,'wide');assert.equal(h.rendered.at(-1),scene);
 h.resize(390,844,true);assert.equal(h.dialog.dataset.scene,'portrait');assert.equal(h.rendered.at(-1),scene.portrait);
 h.resize(1712,1000,false);assert.equal(h.dialog.dataset.scene,'desktop');assert.equal(h.rendered.at(-1),scene.desktop);
 const legacy={seed:4},fallback=boot(legacy);fallback.window.leqraShowcase.open();assert.equal(fallback.dialog.dataset.scene,'wide');assert.equal(fallback.rendered.at(-1),legacy);
});
test('showcase modal consumes every key except Escape',()=>{
 const h=boot();h.window.leqraShowcase.open();assert.equal(h.dialog.open,true);assert.equal(h.dialog.children.length,1);assert.equal(h.dialog.children[0].children[0].tag,'canvas');assert.equal(h.draws,1);
 for(const code of ['KeyP','KeyQ','Space','Backspace']){const event=h.event('window','keydown',{code});assert.equal(event.prevented,true);assert.equal(h.dialog.open,true);}
 assert.equal(h.event('dialog','cancel').prevented,true);assert.equal(h.dialog.open,true);
 h.event('window','keydown',{code:'Escape'});assert.equal(h.dialog.open,false);assert.equal(h.restored,1);
});
test('backgrounding then returning exits Showcase, while an ordinary resize only redraws',()=>{
 const h=boot();h.window.leqraShowcase.open();h.event('window','resize');assert.equal(h.draws,2);assert.equal(h.dialog.open,true);
 h.document.hidden=true;h.event('document','visibilitychange');assert.equal(h.dialog.open,true);
 h.document.hidden=false;h.event('document','visibilitychange');assert.equal(h.dialog.open,false);
 h.window.leqraShowcase.open();h.event('window','pagehide');h.event('window','pageshow');assert.equal(h.dialog.open,false);
});
