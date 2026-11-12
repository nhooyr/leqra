'use strict';
const vm=require('node:vm');

// Execute the shared presentation helpers in focused DOM fixtures too. Keep
// identity behavior in the production functions rather than copying it here.
module.exports=function identityFixture(s,source){
 s.COLORS??=['#0ff','#f0f'];s.tanks??=[];
 s.paintColor??=color=>color;
 s.escapeHTML??=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 s.localPlayerID??=()=>s.online?.id??s.localRoom?.self??0;
 s.roomData??=()=>s.online?.roomData||s.localRoom;
 s.roomMembers??=r=>{r??=s.roomData();return [...(r?.players||[]),...(r?.spectators||[])];};
 s.roomMember??=id=>s.roomMembers().find(p=>p.id===id);
 s.secondaryMember??=()=>s.roomMembers().find(p=>p.kind==='local'&&p.owner===s.localPlayerID());
 s.secondaryID??=()=>s.secondaryMember()?.id;
 s.savedLocalCallsign??=()=> 'CO-PILOT';
 s.teamColor??=()=>s.COLORS[0];
 for(const name of ['pilotIdentity','pilotIdentityHTML','localPilotIdentity','localPilotIdentityHTML','isDeviceLocalPilot','roomPlayerIdentity','roomPlayerIdentityHTML','resultPilotIdentity','resultPilotIdentityHTML']){
  const start=source.indexOf('function '+name+'(');
  if(start<0)throw Error('Missing identity helper '+name);
  const end=source.indexOf('\n',start),line=source.slice(start,end);
  vm.runInContext(line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2),s);
 }
};
