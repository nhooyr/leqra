'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'('),end=source.indexOf('\n',start),line=source.slice(start,end);assert.ok(start>=0,name);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function storageClass(){return class{constructor(){this.data=new Map();}setItem(key,value){this.data.set(String(key),String(value));}removeItem(key){this.data.delete(key);}getItem(key){return this.data.get(key)??null;}};}
function boot(){
 const Storage=storageClass(),localStorage=new Storage(),sessionStorage=new Storage(),calls={close:0,infinity:0,preview:0,input:0,audio:0,suspend:0,frames:0,sent:[]};
 const s={Storage,localStorage,sessionStorage,settingsResetActive:false,settingsResetStorageLocked:false,phase:'playing',gameStarted:true,muted:false,audioVolume:50,
  online:{manual:false,connected:true,connecting:true,restoreInfinity:true,code:'ROOM',retryTimer:1,socket:{readyState:1,send:message=>calls.sent.push(JSON.parse(message)),close(){calls.close++;}}},
  resizeTimer:2,arenaResizeFrame:3,pendingMatchPresentation:{},bindingCapture:{},clearTimeout(){},cancelAnimationFrame(){},clearInput(){calls.input++;},cancelPendingAudio(){calls.audio++;},
  audio:{suspend(){calls.suspend++;return Promise.resolve();}},document:{hidden:false,hasFocus:()=>true},requestAnimationFrame(){calls.frames++;},
  window:{leqraInfinity:{close(){calls.infinity++;s.phase='menu';}},leqraInfinityPreview:{stop(){calls.preview++;}}}};
 vm.createContext(s);for(const name of ['freezeForSettingsReset','frame','connectOnline','arenaKeyBlocked','canPlayAudio','save'])vm.runInContext(declaration(name),s);
 return{s,calls};
}

test('reset stops both games, audio, previews and reconnects before blocking late settings writes',async()=>{
 const {s,calls}=boot();s.localStorage.setItem('leqra.name','Before');s.sessionStorage.setItem('leqra.session','Before');
 assert.equal(s.canPlayAudio(),true);s.freezeForSettingsReset();
 assert.equal(s.settingsResetActive,true);assert.equal(s.settingsResetStorageLocked,true);assert.equal(s.phase,'resetting');assert.equal(s.gameStarted,false);
 assert.equal(s.online.socket,null);assert.equal(s.online.connected,false);assert.equal(s.online.connecting,false);assert.equal(s.online.manual,true);
 assert.deepEqual(calls.sent,[{type:'leave',room:'ROOM'}]);for(const key of ['close','infinity','preview','input','audio','suspend'])assert.equal(calls[key],1,key);
 s.frame(1000);s.connectOnline({});assert.equal(calls.frames,0);assert.equal(s.arenaKeyBlocked({}),true);assert.equal(s.canPlayAudio(),false);
 s.localStorage.removeItem('leqra.name');s.sessionStorage.removeItem('leqra.session');
 await Promise.resolve().then(()=>{s.localStorage.setItem('leqra.name','Late');s.sessionStorage.setItem('leqra.session','Late');s.localStorage.setItem('ricochet.name','Legacy');s.save('volume',100);});
 assert.equal(s.localStorage.getItem('leqra.name'),null);assert.equal(s.localStorage.getItem('ricochet.name'),null);assert.equal(s.localStorage.getItem('leqra.volume'),null);assert.equal(s.sessionStorage.getItem('leqra.session'),null);
 s.localStorage.setItem('blog.preference','Kept');assert.equal(s.localStorage.getItem('blog.preference'),'Kept');
 const guarded=s.Storage.prototype.setItem;s.freezeForSettingsReset();assert.equal(s.Storage.prototype.setItem,guarded);assert.equal(calls.infinity,1,'retry cannot restart the stopped game');
});

test('a failed write lock leaves the game stopped and can retry without pretending settings are cleared',()=>{
 const {s,calls}=boot();Object.freeze(s.Storage.prototype);
 assert.throws(()=>s.freezeForSettingsReset(),/Cannot lock settings storage/);
 assert.equal(s.settingsResetActive,true);assert.equal(s.settingsResetStorageLocked,false);s.frame(1000);assert.equal(calls.frames,0);
 s.Storage=storageClass();s.freezeForSettingsReset();assert.equal(s.settingsResetStorageLocked,true);assert.equal(calls.close,1);
});
