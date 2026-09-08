'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'('),end=source.indexOf('\n',start),line=source.slice(start,end);assert.ok(start>=0);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const elements=new Map();let s;
 class Element{
  constructor(){this.children=[];this.attributes={};this.open=false;this.classList={add(){},remove(){}};}
  set id(id){this._id=id;elements.set(id,this);}get id(){return this._id;}
  append(...nodes){this.children.push(...nodes);}setAttribute(k,v){this.attributes[k]=v;}
  showModal(){this.open=true;}close(){this.open=false;}focus(){s.focused=this.id;}
 }
 const $=id=>elements.get(id);for(const id of ['roomStatus','joinDialog','queueDialog']){const e=new Element();e.id=id;e.open=id!=='roomStatus';}
 const players=[{id:0,name:'PILOT'},{id:1,name:'BOT'}];
 s={URL,GAME_VERSION:'test-client',mode:'room',phase:'menu',localRoom:{players},online:{connected:false,connecting:false,code:'',token:'',roomData:null},$,
  document:{body:new Element(),createElement:()=>new Element()},location:{protocol:'https:',href:'https://leqra.test/',reload(){s.reloads++;}},reloads:0,
  performance:{now:()=>1000},setTimeout:()=>1,clearTimeout(){},netBusy(){},setNetStatus(){},setScreen(screen){s.screen=screen;},renderOnlineRoom(){s.rendered=true;},
  sendOnline(message){s.sent.push(message);},sent:[],WebSocket:class{constructor(){s.socket=this;}close(code,reason){this.closed={code,reason};this.onclose?.();}}};
 vm.createContext(s);vm.runInContext(declaration('showVersionMismatch')+'\n'+declaration('connectOnline'),s);
 s.connectOnline({type:'join',code:'ROOM'},true);
 return{s,$,players,receive:message=>s.socket.onmessage({data:JSON.stringify(message)})};
}
test('both mismatch responses refuse online play and expose reload while preserving the local roster',()=>{
 for(const message of [{type:'server_hello',version:'older-server',protocol:1},{type:'server_hello',version:'test-client',protocol:99},{type:'error',action:'version',message:'<b>Reload required</b>'}]){
  const b=boot(),{s,$}=b;b.receive(message);
  assert.equal(s.mode,'room');assert.equal(s.phase,'menu');assert.equal(s.online.connected,false);assert.equal(s.online.connecting,false);assert.equal(s.online.manual,true);assert.equal(s.online.socket,null);assert.equal(s.socket.closed.reason,'Version mismatch');assert.equal(s.sent.length,0);
  assert.equal(s.localRoom.players,b.players);assert.equal(s.localRoom.players.length,2);assert.equal($('joinDialog').open,false);assert.equal($('queueDialog').open,false);
  assert.equal($('versionMismatchDialog').open,true);assert.equal(s.focused,'versionReloadBtn');assert.match($('versionMismatchMessage').textContent,/Reload/);
  if(message.type==='error')assert.equal($('versionMismatchMessage').textContent,message.message,'server copy is plain text');
  $('versionOfflineBtn').onclick();assert.equal($('versionMismatchDialog').open,false);assert.equal($('joinDialog').open,false);assert.equal(s.reloads,0);assert.equal(s.mode,'room');
  s.showVersionMismatch('Reload again');assert.equal(s.document.body.children.length,1,'reuse one notice');$('versionReloadBtn').onclick();assert.equal(s.reloads,1);
 }
});
test('compatible handshake proceeds without an update dialog',()=>{
 const b=boot();b.receive({type:'server_hello',version:'test-client',protocol:1});
 assert.equal(b.$('versionMismatchDialog'),undefined);assert.equal(b.s.mode,'online');assert.equal(b.s.socket.closed,undefined);
 assert.deepEqual(JSON.parse(JSON.stringify(b.s.sent)),[{type:'client_hello',version:'test-client',protocol:1},{type:'join',code:'ROOM'}]);
});
