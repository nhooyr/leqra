"use strict";
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const source=readFileSync(process.env.LEQRA_ROOM_LOOKUP_SOURCE||path.join(__dirname,'../web/game.js'),'utf8');
const declarations=source.slice(source.indexOf('const roomMembers='),source.indexOf('const isSpectating='));
function boot(){
 const primary={id:0,kind:'human'},local={id:1,kind:'local',owner:0},other={id:2,kind:'local',owner:3};
 const s={mode:'room',localRoom:{self:0,players:[primary,other,local]},online:{id:8,publishing:false,roomData:null}};
 vm.createContext(s);vm.runInContext(declarations+'\nObject.assign(globalThis,{roomMember,secondaryMember,secondLocal});',s);
 return{s,primary,local,other};
}

test('local lookups return the current participants and exclude another owner’s secondary seat',()=>{
 const {s,primary,local,other}=boot();assert.equal(s.roomMember(0),primary);assert.equal(s.secondaryMember(),local);assert.equal(s.secondLocal(),local);
 local.spectating=true;assert.equal(s.secondaryMember(),local);assert.equal(s.secondLocal(),undefined);
 s.localRoom.self=3;assert.equal(s.secondaryMember(),other);assert.equal(s.secondLocal(),other);
 s.localRoom.players=[primary];assert.equal(s.roomMember(1),undefined);assert.equal(s.secondaryMember(),undefined);
});

test('publishing uses the local roster until server membership arrives',()=>{
 const {s,local}=boot();s.mode='online';s.online.publishing=true;
 assert.equal(s.roomMember(1),local);assert.equal(s.secondaryMember(),local);assert.equal(s.secondLocal(),local);
 const own={id:8,kind:'human',spectating:true},remote={id:4,kind:'local',owner:8};
 s.online.roomData={players:[remote],spectators:[own]};assert.equal(s.roomMember(8),own);assert.equal(s.secondaryMember(),remote);assert.equal(s.secondLocal(),remote);assert.equal(s.roomMember(1),undefined);
});

test('online lookups follow spectator changes and replacement room packets',()=>{
 const {s}=boot();s.mode='online';
 assert.equal(s.roomMember(8),undefined);assert.equal(s.secondaryMember(),undefined);assert.equal(s.secondLocal(),undefined);
 const own={id:8,kind:'human',spectating:true},local={id:9,kind:'local',owner:8,spectating:true};
 s.online.roomData={spectators:[own,local]};assert.equal(s.roomMember(9),local);assert.equal(s.secondaryMember(),local);assert.equal(s.secondLocal(),undefined);
 const active={id:1,kind:'local',owner:8};s.online.roomData={players:[active],spectators:[own]};
 assert.equal(s.roomMember(9),undefined);assert.equal(s.secondaryMember(),active);assert.equal(s.secondLocal(),active);
 s.online.id=0;assert.equal(s.secondaryMember(),undefined);assert.equal(s.secondLocal(),undefined);
});

test('an explicit room takes precedence and searches players before spectators',()=>{
 const {s,primary}=boot(),player={id:0,kind:'human'},spectator={id:0,kind:'human',spectating:true},room={players:[player],spectators:[spectator]};
 assert.equal(s.roomMember(0,room),player);assert.equal(s.roomMember(0,{spectators:[spectator]}),spectator);assert.equal(s.roomMember(0,{}),undefined);
 assert.equal(s.roomMember(0,null),primary);assert.equal(s.roomMember(0),primary);
});
