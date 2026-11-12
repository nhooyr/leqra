'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs'),source=readFileSync(assetPath('game.js'),'utf8');
function fixture(){
 const images=[],draws=[],start=source.indexOf('function drawCannonTrail('),end=source.indexOf('\n}',start)+2;
 const s={useCannonTrailCache:true,cannonTrailCache:new Map(),paintColor:color=>color,document:{createElement(){const alphas=[],g={setTransform(){},beginPath(){},moveTo(){},lineTo(){},stroke(){alphas.push(this.globalAlpha);}},image={alphas,getContext:()=>g};images.push(image);return image;}}};
 vm.createContext(s);vm.runInContext(source.slice(start,end),s);
 const c={shadowBlur:0,getTransform:()=>({a:1,b:0,c:0,d:1}),save(){},restore(){},translate(){},rotate(){},drawImage:(...args)=>draws.push(args)};
 const bullet={color:'#ff9679',trail:Array.from({length:11},(_,i)=>({x:i*9.4,y:0}))};
 return{s,c,bullet,images,draws};
}
test('straight Cannon trails reuse their alpha steps without combining overlapping bullets',()=>{
 const {s,c,bullet,images,draws}=fixture();
 for(let frame=0;frame<1000;frame++)assert.equal(s.drawCannonTrail(bullet,c),true);
 assert.equal(images.length,1);assert.equal(draws.length,1000);
 assert.deepEqual(images[0].alphas,Array.from({length:10},(_,i)=>(i+1)/11*.23),'each original segment keeps its own source-over alpha');
 for(let i=0;i<80;i++)s.drawCannonTrail({...bullet,color:'#'+i.toString(16).padStart(6,'0')},c);
 assert.equal(s.cannonTrailCache.size,48);
 assert.ok(images.every(image=>image.width*image.height<=65536),'raster dimensions remain bounded');
});
test('color and zoom changes use distinct Cannon strips while irregular trails keep vector geometry',()=>{
 const {s,c,bullet,images}=fixture();s.drawCannonTrail(bullet,c);
 s.drawCannonTrail({...bullet,color:'#73cee4'},c);assert.equal(images.length,2);
 c.getTransform=()=>({a:2,b:0,c:0,d:2});s.drawCannonTrail(bullet,c);assert.equal(images.length,3);
 for(const trail of [bullet.trail.map((p,i)=>({...p,y:i===5?1:0})),bullet.trail.map((p,i)=>({...p,x:i===5?p.x+1:p.x})),bullet.trail.slice(0,3)]){
  assert.equal(s.drawCannonTrail({...bullet,trail},c),false);assert.equal(images.length,3);
 }
 s.useCannonTrailCache=false;assert.equal(s.drawCannonTrail(bullet,c),false);
});
test('unsupported or oversized Cannon strips retain the original rendering path',()=>{
 const {s,c,bullet,images}=fixture();
 c.getTransform=()=>({a:4,b:0,c:0,d:4});
 assert.equal(s.drawCannonTrail({...bullet,trail:bullet.trail.map((p,i)=>({x:i*63,y:0}))},c),false);
 c.getTransform=()=>({a:.00001,b:0,c:0,d:.00001});assert.equal(s.drawCannonTrail(bullet,c),false);
 c.getTransform=()=>({a:1,b:0,c:0,d:2});assert.equal(s.drawCannonTrail(bullet,c),false);
 c.getTransform=()=>({a:1,b:0,c:.6,d:.8});assert.equal(s.drawCannonTrail(bullet,c),false,'equal-scale shear retains vector rendering');
 assert.equal(s.drawCannonTrail(bullet,{}),false);assert.equal(images.length,0);
});
