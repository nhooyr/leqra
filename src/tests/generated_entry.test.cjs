'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const code=readFileSync(assetPath('game.js'),'utf8'),start=code.indexOf('function generatedEntryScope('),source=code.slice(start,code.indexOf('\n}',start)+2);
function boot(){
 const state={revision:0,active:true,keys:['first','second'],rules:{infinity:true},players:[{id:0,kind:'human',name:'provisional'},{id:1,kind:'bot',name:'RUST'}]};
 const s={settingsResetActive:false,window:{leqraCallsigns:{revision:()=>state.revision}},captureActionScope:()=>()=>state.active,publicIdentityToken:seat=>state.keys[seat],currentRules:()=>state.rules,localRoom:{players:state.players}};
 vm.createContext(s);vm.runInContext(source,s);return{state,s};
}
test('auto confirmation can complete but edits/imports cannot turn an old Play intent into a new account takeover',()=>{
 const {state,s}=boot();let current=s.generatedEntryScope();state.players[0].name='confirmed';assert.equal(current(),true);
 state.keys[0]='imported';assert.equal(current(),false,'import requires its own explicit Play');
 current=s.generatedEntryScope();state.revision++;assert.equal(current(),false,'typing or explicit Generate cancels stale intent');
 current=s.generatedEntryScope();state.rules.infinity=false;assert.equal(current(),false);
 current=s.generatedEntryScope();state.players[1].name='changed bot';assert.equal(current(),false);
 current=s.generatedEntryScope();state.active=false;assert.equal(current(),false);
});
