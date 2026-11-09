'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {declaration}=require('./godlike426-harness.cjs');

function boot(storage){
 const label={};
 const s=vm.createContext({$:(id)=>{assert.equal(id,'recordLabel');return label;},bestWins:3,onlineWins:new Set(),ONLINE_WIN_PREFIX:'leqra.onlineWin.',localStorage:{
  get length(){return storage.size;},key:i=>Array.from(storage.keys())[i],setItem:(key,value)=>storage.set(key,value)
 }});
 for(const name of ['save','renderDeviceWins','loadOnlineWins','creditOnlineWin'])vm.runInContext(declaration(name),s);
 s.loadOnlineWins();s.renderDeviceWins();
 return {s,label};
}

test('online wins count each match once across result replays and preserve the previous device total',()=>{
 const storage=new Map([['leqra.wins','3']]);
 const report={id:'ab'.repeat(16),players:[{member:21,controllerMember:22,winner:true},{member:22,winner:false}]};
 const first=boot(storage);
 first.s.creditOnlineWin(report,23);
 assert.equal(first.label.textContent,'3 MATCH WINS ON THIS DEVICE');
 first.s.creditOnlineWin(report,22);
 first.s.creditOnlineWin(report,22);
 assert.equal(first.label.textContent,'4 MATCH WINS ON THIS DEVICE');
 const reloaded=boot(storage);
 reloaded.s.creditOnlineWin(report,22);
 assert.equal(reloaded.label.textContent,'4 MATCH WINS ON THIS DEVICE');
 reloaded.s.creditOnlineWin({id:'bc'.repeat(16),players:[{member:21,controllerMember:22,winner:true},{member:22,winner:true}]},22);
 assert.equal(reloaded.label.textContent,'5 MATCH WINS ON THIS DEVICE');
 assert.equal(storage.get('leqra.wins'),'3');
});
