'use strict';
const assert=require('node:assert/strict'),{readFileSync}=require('node:fs'),path=require('node:path');
function declaration(source,name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function element(tag,fragment=false){return{tag,fragment,children:[],className:'',dataset:{},textContent:'',classList:{add(){}},append(...items){for(const item of items)this.children.push(...(item.fragment?item.children:[item]));},replaceChildren(...items){this.children=[];this.append(...items);},get scrollHeight(){return this.children.length*30;},scrollTop:0};}
function boot({sourcePath=process.env.LEQRA_CHAT_SOURCE||path.join(__dirname,'../web/game.js'),perChannel=60,IntlType=Intl,DateType=Date}={}){
 const source=readFileSync(sourcePath,'utf8'),list=element('div'),chat={channels:{room:{messages:[]},opponent:{messages:[]}}};
 for(const channel of Object.keys(chat.channels))for(let n=0;n<perChannel;n++)chat.channels[channel].messages.push({id:n+1,member:n%3+1,name:'PILOT '+n,team:n%4,text:channel+' message '+n,at:Date.parse('2026-03-08T06:30:00Z')+n*30*60*1000,spectating:n%7===0});
 const env={Intl:IntlType,Date:DateType,roomChat:chat,$:()=>list,roomMember:()=>({member:1}),localPlayerID:()=>0,matchPartyChat:()=>true,teamName:id=>'Team '+id,document:{createElement:tag=>element(tag),createDocumentFragment:()=>element('',true)}};
 const factory=new Function('env','const {'+Object.keys(env).join(',')+'}=env;\n'+['renderChatMessage','combinedChatMessages','renderActiveChat'].map(n=>declaration(source,n)).join('\n')+'\nreturn{renderChatMessage,renderActiveChat,combinedChatMessages};');
 return{...factory(env),list,chat};
}
module.exports={boot};
