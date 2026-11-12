'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),{readFileSync}=require('node:fs'),{join}=require('node:path');
const source=readFileSync(join(__dirname,'..','leaderboard_admin_ui.go'),'utf8').match(/const leaderboardAdminJS = `([\s\S]*?)`/)[1];
function fixture(){
 const nodes=new Map(),requests=[];
 const node=()=>({value:'',disabled:false,listeners:{},addEventListener(type,fn){this.listeners[type]=fn;},replaceChildren(){},append(){}});
 const context=vm.createContext({document:{querySelector(selector){if(!nodes.has(selector)){const value=node();if(selector==='#pattern')value.value='old';nodes.set(selector,value);}return nodes.get(selector);},createElement:node},
  fetch:(url,options)=>new Promise(resolve=>requests.push({url,options,resolve})),confirm:()=>true,clearTimeout(){},setTimeout(){},setInterval(){}});
 vm.runInContext(source,context);
 return{context,nodes,requests};
}
const response=(matched=3)=>({ok:true,json:async()=>({csrfToken:'secret',matched,total:matched,connected:0,entries:[]})});
async function settle(){for(let i=0;i<5;i++)await Promise.resolve();}

test('admin Clear matches stays disabled after failed or invalidated mutation refreshes',async()=>{
 for(const outcome of ['failed','changed']){
  const {context,nodes,requests}=fixture(),pattern=nodes.get('#pattern'),remove=nodes.get('#remove');
  requests[0].resolve(response());await settle();assert.equal(remove.disabled,false);
  const mutation=context.change('/api/remove',{pattern:'old'},'Clear old matches?');
  requests[1].resolve({ok:true,json:async()=>({affected:3})});await settle();assert.equal(requests[2].url,'/api/leaderboard?pattern=old');
  if(outcome==='changed'){pattern.value='new';pattern.listeners.input();requests[2].resolve(response(99));}
  else requests[2].resolve({ok:false,text:async()=>'refresh failed'});
  await mutation;assert.equal(remove.disabled,true,outcome);
  const before=requests.length;await context.change('/api/remove',{pattern:pattern.value},'Clear unverified matches?');assert.equal(requests.length,before,outcome+' cannot mutate with stale match counts');
 }
});
