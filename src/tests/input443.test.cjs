'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
const start=source.indexOf('function sendOnlineInput('),end=source.indexOf('\n}',start)+2;
assert.ok(start>=0&&end>start);

function boot(){
 const sent=[],controls={forward:true,fire:false};
 const s={mode:'online',phase:'playing',MAX_TANKS:8,now:1000,
  online:{connected:true,code:'ROOM',id:0,member:101,spectating:false,seq:5000,secondary:{seq:30}},
  local:null,secondLocal:()=>s.local,onlineControls:()=>controls,performance:{now:()=>s.now},
  Net:{controlsEqual:()=>false},previewOnlineFire(){},sendOnline(packet){sent.push(packet);return true;}};
 vm.createContext(s);vm.runInContext(source.slice(start,end),s);return {s,sent,controls};
}

test('in-flight inputs retain the sending pilot identity when P1 and P2 exchange the same seat',()=>{
 const {s,sent,controls}=boot();s.sendOnlineInput(true,controls);
 const oldPrimary=sent.at(-1);assert.equal(oldPrimary.member,101);assert.equal(oldPrimary.seq,5001);
 s.online.id=8;s.online.spectating=true;s.local={id:0,member:202};s.now+=50;
 s.sendOnlineInput(true,controls);
 const currentLocal=sent.at(-1);assert.equal(currentLocal.player,oldPrimary.player);assert.equal(currentLocal.member,202);assert.equal(currentLocal.seq,31);
 s.online.id=0;s.online.spectating=false;s.local=null;s.now+=50;s.sendOnlineInput(true,controls);
 const currentPrimary=sent.at(-1);assert.equal(currentPrimary.player,currentLocal.player);assert.equal(currentPrimary.member,101);assert.equal(currentPrimary.seq,5002);
 assert.equal(oldPrimary.member,101,'a queued packet must remain bound to its original pilot');
 assert.equal(currentLocal.member,202,'swapping back cannot retarget the previous P2 packet');
});

test('both active local input channels include their own current member identity',()=>{
 const {s,sent,controls}=boot();s.local={id:2,member:202};s.sendOnlineInput(true,controls);
 assert.deepEqual(sent.map(p=>[p.player,p.member,p.seq]),[[0,101,5001],[2,202,31]]);
 // Replacing P2 in the same seat must change the identity on later packets.
 s.local={id:2,member:303};s.now+=50;s.sendOnlineInput(true,controls,true);
 assert.equal(sent.at(-1).member,303);assert.equal(sent.at(-1).seq,32);
});
