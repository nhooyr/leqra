'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
const code=source.slice(source.indexOf('const roomChat='),source.indexOf('function initRoomChat('));
const reconnectCode=source.slice(source.indexOf('function showReconnecting('),source.indexOf('function scheduleReconnect('));

function boot(){
 const list={rows:[],clientHeight:200,clientTop:0,top:40,_scrollTop:0,
  get scrollHeight(){return this.rows.reduce((n,r)=>n+r.height,0);},
  get scrollTop(){return this._scrollTop;},set scrollTop(n){this._scrollTop=Math.max(0,Math.min(n,this.scrollHeight-this.clientHeight));},
  append(row){if(row.fragment){for(const item of row.rows)this.append(item);return;}row.parent=this;this.rows.push(row);},
  replaceChildren(...rows){this.rows=[];for(const row of rows)this.append(row);this.scrollTop=0;},
  querySelector(selector){const id=selector.match(/data-chat-id="([^"]+)"/)[1];return this.rows.find(r=>r.dataset.chatId===id)||null;},
  getBoundingClientRect(){return{top:this.top};}};
 function row(m,channel){return{dataset:{chatId:channel+':'+m.id},height:m.height||30,parent:null,
  getBoundingClientRect(){return{top:list.top-list.scrollTop+list.rows.slice(0,list.rows.indexOf(this)).reduce((n,r)=>n+r.height,0),height:this.height};},
  remove(){const index=list.rows.indexOf(this);if(index>=0)list.rows.splice(index,1);}};}
 const controls=new Map(),packets=[],$=id=>{if(id==='chatMessages')return list;if(!controls.has(id))controls.set(id,{value:'',textContent:'',firstElementChild:{textContent:''},style:{removeProperty(){}},classList:{toggle(){}},setAttribute(){},focus(){}});return controls.get(id);};
 const s={online:{code:'ROOM',connected:true,roomData:{}},$,mode:'online',window:{},cancelKick(){},setScreen(){},clearInput(){},sendOnlineInput(){},sendOnline(packet){packets.push(packet);return true;},
  roomMember:()=>({member:1}),localPlayerID:()=>0,chatNotificationSound(){},
  document:{body:{classList:{toggle(){}}},createDocumentFragment:()=>({fragment:true,rows:[],append(item){this.rows.push(item);}})},makeRow:row};
 vm.createContext(s);vm.runInContext(code+reconnectCode+"\nrenderChatMessage=makeRow;this.realSyncChatStatus=syncChatStatus;syncChatStatus=()=>{$('chatError').textContent=chatState(roomChat.sendTarget).error;};opponentChatEnabled=()=>true;roomChatEnabled=()=>true;matchPartyChat=()=>true;roomChat.code='ROOM';roomChat.open=true;this.chat=roomChat;",s);
 return{s,list,$,packets,send(id,channel='room',height=30){return s.appendChat({id,text:'Message '+id,member:2,at:id,height},false,channel);},submit(text){$('chatInput').value=text;s.chat.draft=text;s.submitChat({preventDefault(){}});}};
}

test('an open chat retains only the latest 60 rendered messages per channel',()=>{
 const b=boot();for(let n=1;n<=1000;n++)b.send(n);
 assert.equal(b.list.rows.length,60);assert.equal(b.s.chat.channels.room.messages.length,60);
 assert.equal(b.list.rows[0].dataset.chatId,'room:941');assert.equal(b.list.rows.at(-1).dataset.chatId,'room:1000');
 assert.equal(b.send(1000),false);assert.equal(b.list.rows.length,60,'duplicate packets do not change the panel');
});
test('interleaved party and opponent messages evict only their own channel rows',()=>{
 const b=boot();for(let n=1;n<=80;n++){b.send(n,'room');b.send(n,'opponent');}
 assert.equal(b.list.rows.length,120);
 for(const channel of ['room','opponent'])assert.deepEqual(b.list.rows.filter(r=>r.dataset.chatId.startsWith(channel+':')).map(r=>Number(r.dataset.chatId.split(':')[1])),Array.from({length:60},(_,n)=>n+21));
});
test('readers keep the same message and pixel position when an earlier row expires',()=>{
 const b=boot();for(let n=1;n<=60;n++)b.send(n,'room',n===1?53:30);
 b.list.scrollTop=303;const anchor=b.list.rows[20],before=anchor.getBoundingClientRect().top;
 b.send(61);assert.equal(b.list.scrollTop,250);assert.equal(anchor.getBoundingClientRect().top,before);
});
test('evicting a row below the visible conversation does not move the reader',()=>{
 const b=boot();for(let n=1;n<=60;n++)b.send(n,'opponent');for(let n=1;n<=60;n++)b.send(n,'room');
 b.list.scrollTop=90;const anchor=b.list.rows[6],before=anchor.getBoundingClientRect().top;
 b.send(61,'room');assert.equal(b.list.scrollTop,90);assert.equal(anchor.getBoundingClientRect().top,before);
});
test('chat keeps following new messages when already at the bottom',()=>{
 const b=boot();for(let n=1;n<=80;n++){b.send(n,'room',20+n%4*15);assert.equal(b.list.scrollTop,Math.max(0,b.list.scrollHeight-b.list.clientHeight));}
});
test('open history replacement and closed-history reopening share the same bounds',()=>{
 const b=boot();for(let n=1;n<=65;n++)b.send(n,'opponent');
 const messages=Array.from({length:90},(_,n)=>({id:n+1,text:'History',member:2,at:n+1}));
 b.s.chatPacket({type:'chat_history',room:'ROOM',channel:'room',messages});assert.equal(b.list.rows.length,120);
 assert.equal(b.list.rows.filter(r=>r.dataset.chatId.startsWith('room:')).length,60);
 b.s.chat.open=false;for(let n=91;n<=160;n++)b.send(n);assert.equal(b.list.rows.length,120,'hidden panel is not rebuilt per message');
 b.s.chat.open=true;b.s.renderActiveChat();assert.equal(b.list.rows.length,120);
 assert.equal(b.list.rows.find(r=>r.dataset.chatId.startsWith('room:')).dataset.chatId,'room:101');
});
test('reconnect restores an unacknowledged message without sending it again',()=>{
 const b=boot();b.submit('Defend the hill');assert.equal(b.s.chat.draft,'');assert.equal(b.$('chatInput').value,'');assert.equal(b.packets.length,1);
 b.s.online.connected=false;b.s.showReconnecting();assert.equal(b.s.chat.draft,'Defend the hill');assert.equal(b.$('chatInput').value,'Defend the hill');assert.equal(b.s.chat.channels.room.pending,null);
 assert.match(b.$('chatError').textContent,/Delivery unconfirmed.*history before resending/);assert.equal(b.packets.length,1);
 b.s.showReconnecting();assert.equal(b.s.chat.draft,'Defend the hill');assert.equal(b.packets.length,1,'repeated reconnect notices never resend');
});
test('reconnect preserves a newer draft and keeps the previous message recoverable',()=>{
 const b=boot();b.submit('Original message');b.s.chat.draft=b.$('chatInput').value='Still typing a new message';
 b.s.online.connected=false;b.s.showReconnecting();assert.equal(b.s.chat.draft,'Still typing a new message');assert.equal(b.$('chatInput').value,'Still typing a new message');assert.equal(b.s.chat.channels.room.unconfirmed,'Original message');
 b.s.chat.draft=b.$('chatInput').value='';b.s.setChatSendTarget('room');assert.equal(b.s.chat.draft,'Original message');assert.equal(b.packets.length,1);
});
test('two unacknowledged channels recover independently without changing recipients',()=>{
 const b=boot();b.submit('Private party plan');b.s.setChatSendTarget('opponent');b.submit('Good luck');
 b.s.online.connected=false;b.s.showReconnecting();assert.equal(b.s.chat.sendTarget,'opponent');assert.equal(b.s.chat.draft,'Good luck');assert.equal(b.s.chat.channels.room.unconfirmed,'Private party plan');
 assert.equal(b.s.chat.channels.room.pending,null);assert.equal(b.s.chat.channels.opponent.pending,null);
 b.s.chat.draft=b.$('chatInput').value='';b.s.setChatSendTarget('room');assert.equal(b.s.chat.draft,'Private party plan');assert.equal(b.s.chat.sendTarget,'room');assert.equal(b.packets.length,2);
});
test('hidden chat preserves its restored text when reopened after reconnect',()=>{
 const b=boot();b.submit('Stay together');b.s.closeChat();b.s.online.connected=false;b.s.showReconnecting();
 assert.equal(b.s.chat.open,false);assert.equal(b.s.chat.draft,'Stay together');b.s.openChat();assert.equal(b.s.chat.open,true);assert.equal(b.$('chatInput').value,'Stay together');assert.equal(b.packets.length,1);
});
test('reconnected history preserves the delivery warning and cannot resend a draft',()=>{
 const b=boot();b.submit('Hold position');b.s.online.connected=false;b.s.showReconnecting();b.s.online.connected=true;
 b.s.chatPacket({type:'chat_history',room:'ROOM',channel:'room',messages:[{id:1,text:'Hold position',member:1,at:1}]});
 assert.equal(b.s.chat.draft,'Hold position');assert.match(b.$('chatError').textContent,/Delivery unconfirmed/);assert.equal(b.packets.length,1);
 b.submit('Follow me instead');assert.equal(b.packets.length,2);assert.equal(b.packets[1].text,'Follow me instead');assert.equal(b.s.chat.channels.room.error,'');assert.equal(b.s.chat.channels.room.unconfirmed,null);
});
test('leaving a room clears unconfirmed texts as well as the current draft',()=>{
 const b=boot();b.submit('Old room message');b.s.chat.draft=b.$('chatInput').value='Newer draft';b.s.online.connected=false;b.s.showReconnecting();assert.equal(b.s.chat.channels.room.unconfirmed,'Old room message');
 b.s.clearRoomChat('NEW ROOM');assert.equal(b.s.chat.draft,'');assert.equal(b.s.chat.channels.room.unconfirmed,null);assert.equal(b.s.chat.channels.opponent.unconfirmed,null);assert.equal(b.$('chatInput').value,'');
});
test('a reconnect welcome cannot change an opponent draft to the party recipient',()=>{
 const b=boot();b.s.setChatSendTarget('opponent');b.submit('Good match');b.s.online.connected=false;b.s.showReconnecting();
 b.s.online.connected=true;b.s.online.roomData=null;b.s.opponentChatEnabled=()=>!!b.s.online.roomData?.matchmaking;b.s.realSyncChatStatus();
 assert.equal(b.s.chat.sendTarget,'opponent');assert.equal(b.s.chat.draft,'Good match');assert.equal(b.$('chatSendBtn').textContent,'SEND TO OPPONENT');assert.equal(b.$('chatSendBtn').disabled,true);assert.equal(b.$('chatInput').disabled,true);
 b.s.submitChat({preventDefault(){}});assert.equal(b.packets.length,1,'programmatic submission is blocked while recipient availability is unknown');
 b.s.online.roomData={matchmaking:true};b.s.realSyncChatStatus();assert.equal(b.s.chat.sendTarget,'opponent');assert.equal(b.$('chatSendBtn').disabled,false);assert.equal(b.$('chatInput').disabled,false);
 assert.equal(b.packets.length,1);b.submit('Good match');assert.equal(b.packets[1].channel,'opponent');
});
