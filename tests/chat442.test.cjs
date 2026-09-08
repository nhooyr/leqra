'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),{boot}=require('./chat442-harness.cjs');

test('batched chat timestamps exactly match native per-message formatting and retain ordering',()=>{
 const b=boot(),expected=b.combinedChatMessages();b.renderActiveChat();assert.equal(b.list.children.length,120);
 for(let i=0;i<expected.length;i++){
  const {m,channel}=expected[i],row=b.list.children[i],head=row.children[0],when=head.children[3];
  assert.equal(row.dataset.chatId,channel+':'+m.id);assert.equal(head.children[0].textContent,m.name);assert.equal(row.children[1].textContent,m.text);
  assert.equal(when.dateTime,new Date(m.at).toISOString());assert.equal(when.textContent,new Date(m.at).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'}));
  assert.equal(head.children[1].textContent,channel==='opponent'?(m.member===1?'TO OPPONENT':'OPPONENT'):'PARTY');
 }
 assert.equal(b.list.scrollTop,b.list.scrollHeight,'history opening still follows the bottom');
});

test('history batches construct one formatter while live message append keeps fresh native formatting',()=>{
 let made=0,individual=0;
 const IntlType={DateTimeFormat:function(...args){made++;return new Intl.DateTimeFormat(...args);}};
 class DateType extends Date{toLocaleTimeString(...args){individual++;return super.toLocaleTimeString(...args);}}
 const b=boot({IntlType,DateType});b.renderActiveChat();assert.equal(made,1);assert.equal(individual,0);
 b.renderActiveChat();assert.equal(made,2,'a refresh does not retain a stale formatter');assert.equal(individual,0);
 const m=b.chat.channels.room.messages[0],row=b.renderChatMessage(m);assert.equal(individual,1);assert.equal(made,2);
 assert.equal(row.children[0].children[3].textContent,new Date(m.at).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'}));
});

test('reopening chat follows a changed device timezone without changing message dates',()=>{
 const original=process.env.TZ;
 try{
  const b=boot({perChannel:1});process.env.TZ='UTC';b.renderActiveChat();const first=b.list.children[0].children[0].children[3],before=first.textContent,dateTime=first.dateTime;
  process.env.TZ='America/Vancouver';b.renderActiveChat();const after=b.list.children[0].children[0].children[3];
  assert.notEqual(after.textContent,before);assert.equal(after.dateTime,dateTime);assert.equal(after.textContent,new Date(dateTime).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'}));
 }finally{if(original===undefined)delete process.env.TZ;else process.env.TZ=original;}
});

test('empty chat history skips locale setup and still clears prior rows',()=>{
 let made=0;const b=boot({perChannel:0,IntlType:{DateTimeFormat:function(...args){made++;return new Intl.DateTimeFormat(...args);}}});
 b.list.children.push({stale:true});b.renderActiveChat();assert.equal(made,0);assert.equal(b.list.children.length,0);assert.equal(b.list.scrollTop,0);
});
