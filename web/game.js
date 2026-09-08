
/* leqra — dependency-free Canvas 2D arcade game.
   Simulation uses a fixed 120 Hz timestep, swept projectile collisions,
   a connected, procedural maze, and coordinated player-hunting bots.
   v1.1: player-only targeting, bot-team immunity, predictive aiming,
   wall-aware dodging, weighted squad routes, and team round scoring.
   v2.1: held-input replay, buffered timeline rendering, and 30 Hz snapshots.
   v2.5: guided missiles, fused grenades, and independently timed speed boosts.
   v2.8: shared legend/maze icons and dodgeable, range-budgeted missile ricochets.
   v3.2: host rules, objectives, presets, remapping and combat feedback.
   v3.1: impact grenades, logical keyboard fire aliases, named secondary loadout HUD,
   and stronger finite-rate missile guidance. */
(() => {
'use strict';
const $ = id => document.getElementById(id);
const canvas=$('arena'), ctx=canvas.getContext('2d',{alpha:false}), wrap=$('arenaWrap');
if(!ctx){ $('lobbyScreen').textContent='This browser cannot create a 2D canvas. Please open the game in another browser.'; return; }
const GAME_VERSION='4.20.0';
const TAU=Math.PI*2, CELL=84, WALL=8, RADIUS=17, TARGET=5, ROUND_SECONDS=75;
const Theme=window.leqraTheme;
let theme=Theme.palette; // Cached palette, never read CSS/layout during rendering.
const MAX_TANKS=8;
const COLORS=['#d2f65a','#ff9679','#73cee4','#c5a2ff','#ffc46b','#ff83bd','#75f0cb','#b7c6ee'];
const NAMES=['YOU','RUST','VAPOR','EMBER'];
const DIFFICULTY={
 easy:{speed:89,turn:2.8,think:.30,aim:.10,reaction:.72,lead:.4,dodge:false,dodgeLook:0,bank:false},
 normal:{speed:108,turn:3.4,think:.19,aim:.037,reaction:.42,lead:.85,dodge:true,dodgeLook:.65,bank:true},
 hard:{speed:123,turn:4.3,think:.13,aim:.012,reaction:.26,lead:1,dodge:true,dodgeLook:.88,bank:true}
};
const POWER_EFFECT_DURATION=10;
const BOOST_SPEED_PER_STACK=.65, BOOST_TURN_PER_STACK=.25, MAX_SPEED_STACKS=5, MISSILE_SPEED=235, MISSILE_TURN=4.8, MISSILE_VIEW_COS=-.75, MISSILE_LOCK_DELAY=.06, MISSILE_WALL_DELAY=.04, GRENADE_SPEED=205, GRENADE_FUSE=10, GRENADE_CRUISE_DRAG=.025, GRENADE_BRAKE_START=7, GRENADE_BRAKE_DRAG=2, BLAST_RADIUS=220, GRENADE_AVOID_PADDING=10;
const POWER={rapid:{color:'#d2f65a',name:'MACHINE GUN',short:'MACHINE GUN'},scatter:{color:'#c5a2ff',name:'SHOTGUN'},shield:{color:'#73cee4',name:'SHIELD'},
 homing:{color:'#ff83bd',name:'HOMING MISSILE',short:'HOMING'},
 grenade:{color:'#ffc46b',name:'GRENADE'},
 speed:{color:'#75f0cb',name:'SUPER SPEED'},
 laser:{color:'#f57cff',name:'LASER'},
 scope:{color:'#8fb8ff',name:'SCOPE'},
 cannon:{color:'#ffad70',name:'CANNON'},ghost:{color:'#cce4ff',name:'GHOST'}};
const LASER_MAX_SEGMENTS=128,LASER_RADIUS=3,LASER_COOLDOWN=.85,SCOPE_DURATION=POWER_EFFECT_DURATION,GHOST_DURATION=POWER_EFFECT_DURATION;
const MACHINE_SPEED=282*3,MACHINE_RADIUS=3.5/3,MACHINE_CAPACITY=96;
const CANNON_RADIUS=3.5*4,CANNON_SPEED=282*4,CANNON_LIFETIME=5.3,CANNON_COOLDOWN=.85;
let phase='menu', pausedFrom='playing', mode='room', difficulty='normal';
let cols=12,rows=8,W=cols*CELL,H=rows*CELL,grid=[],walls=[],tanks=[],bullets=[],particles=[],pickups=[],rings=[],traces=[];
let scores=Array(MAX_TANKS).fill(0),round=1,roundClock=ROUND_SECONDS,phaseTime=0,time=0,fxTime=0,spawnClock=5,toastTime=0,shake=0,uiClock=0,roundWinner=-1;
let cssW=0,cssH=0,dpr=1,scale=1,offsetX=0,offsetY=0,mapCanvas=null,touchUI=false,touchLandscape=false;
let lastFrame=0,accumulator=0,bulletId=0,logLines=[],bestWins=0,resizeTimer=0,arenaResizeFrame=0,gameStarted=false;
let goUntil=0; // One-shot countdown transition, never a cosmetic event timer.
let guideEnabled=true, muted=false, audio=null,noiseBuffer=null,lastBounceSound=0,lastChatNotify=0;
const reduceMotion=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const UA=navigator.userAgent||'';
const IOS_WEBKIT=/iP(?:hone|ad|od)/i.test(UA)||(navigator.platform==='MacIntel'&&(navigator.maxTouchPoints||0)>1);
const WEBKIT_ENGINE=/AppleWebKit\//.test(UA)&&(!/(?:Chrome|Chromium|Edg|OPR)\//.test(UA)||IOS_WEBKIT);
const SAFARI_BROWSER=WEBKIT_ENGINE&&/Safari\//.test(UA)&&!/(?:CriOS|FxiOS|EdgiOS|OPiOS)\//.test(UA);
document.body.classList.toggle('webkit-engine',WEBKIT_ENGINE);document.body.classList.toggle('safari-browser',SAFARI_BROWSER);document.body.classList.toggle('ios-webkit',IOS_WEBKIT);
const keys=new Set(), firePointers=new Set(), firePresses=new Set();
const stick={id:null,x:0,y:0,mag:0,cx:0,cy:0,max:36};
const Net=window.leqraNet;
const online={socket:null,code:'',id:-1,token:'',roomData:null,connected:false,connecting:false,menu:false,seq:0,latency:0,lastMessage:0,lastPing:0,retryTimer:0,retryAt:0,retries:0,manual:false,generation:-1,snapshots:[],predicted:null,predictor:null,buffer:null,lastControl:null,lastControlStep:-10,lastEvent:0,eventsInitialized:false,lastMatch:-1,renamePending:null,roomRenamePending:false,kickPending:null,inviteCode:'',inviteResumeRetries:0,ownedIDs:new Set(),activeIDs:new Set(),trailIDs:new Set()};
const escapeHTML=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const localRoom={code:'',players:[],self:0,nextViewer:MAX_TANKS,nextMember:0,rules:defaultRoomRules()};
let watchInvite=false,watchResume=null,rolePending=false,swapPending=null,lastSpectatorUI='';
const STORAGE_PREFIX='leqra.';
const LEGACY_STORAGE_PREFIX='ricochet.';
function migrateLegacyStorage(storage,keys){
 try{for(const key of keys){const current=STORAGE_PREFIX+key,legacy=LEGACY_STORAGE_PREFIX+key;if(storage.getItem(current)==null){const value=storage.getItem(legacy);if(value!=null)storage.setItem(current,value);}}}catch(_){}
}
migrateLegacyStorage(localStorage,['muted','wins','difficulty','name','local2Name','roomRules.v1','bindings.v1','feedback.v1','presets.v1','sidebarHidden']);
migrateLegacyStorage(sessionStorage,['session','kicked']);

const pilotFeedback=[{text:'',until:0},{text:'',until:0}];
let bindings=loadBindings(),bindingCapture=null,combatPrefs=readCombatPrefs(),savedPresets=loadPresets(),localObjectives=null,rulesPending=false,presetsPending=false;
let localMatchStats=null,localMatchReport=null;
const lastLocks={},lastLockTone={};
const teamName=(team,rules=currentRules())=>rules?.teamNames?.[team-1]||('Team '+team);
const teamKey=p=>p.team>0?'team'+p.team:'pilot'+p.id;
// Cosmetic IDs are stable across browsers; the selected theme chooses the paint.
const colorIndex=(id,team,selection,rules=currentRules())=>team>0?(rules.teamColors?.[team-1]??team-1):Number.isInteger(selection)&&selection>=0&&selection<8?selection:((id%MAX_TANKS)+MAX_TANKS)%MAX_TANKS;
const teamColor=(id,team,selection,rules=currentRules())=>COLORS[colorIndex(id,team,selection,rules)];
const paintColor=(c)=>Theme.assetColor(c);
function shieldCount(t){return t?.shield>0?clamp(t.shieldCharges||1,1,5):0;}
function speedCount(t){return t?.speedTime>0?clamp(t.speedStacks||1,1,MAX_SPEED_STACKS):0;}
function choosePickup(types){const weight=k=>k==='shield'||k==='speed'?3:1,total=types.reduce((n,k)=>n+weight(k),0);let n=Math.random()*total;for(const k of types){n-=weight(k);if(n<0)return k;}return types.at(-1);}
// Power-up colors use one dark palette shared by all icons.
for(const [kind,def] of Object.entries(POWER)){const raw=def.color;Object.defineProperty(def,'color',{get:()=>Theme.powerColor(kind,raw)});}
const roomData=()=>mode==='online'?online.roomData:{host:localRoom.self,code:localRoom.code,players:localRoom.players.filter(p=>!p.spectating).map(p=>({...p,color:teamColor(p.id,p.team,p.colorIndex),connected:true,ready:true})),spectators:localRoom.players.filter(p=>p.spectating).map(p=>({...p,color:'#aebbc4',connected:true,ready:false})),maxPlayers:MAX_TANKS,maxSpectators:16,rules:localRoom.rules,phase:phase==='menu'?'lobby':phase};
const roomMembers=(r)=>r?[...(r.players||[]),...(r.spectators||[])]:mode==='online'?[...(online.roomData?.players||[]),...(online.roomData?.spectators||[])]:localRoom.players;
const roomMember=(id,r)=>roomMembers(r).find(p=>p.id===id);
const localPlayerID=()=>mode==='online'?online.id:localRoom.self;
const secondaryMember=()=>roomMembers().find(p=>p.kind==='local'&&p.owner===localPlayerID());
const secondLocal=()=>roomMembers().find(p=>!p.spectating&&p.kind==='local'&&p.owner===localPlayerID());
const isSpectating=()=>!!roomMember(localPlayerID())?.spectating;
const controlledTank=()=>tanks.find(t=>t.id===localPlayerID());
const hasLocalP2=()=>mode==='duel'||!!secondaryMember();
const secondaryID=()=>mode==='duel'?1:secondLocal()?.id;
const primaryFireHeld=()=>heldAction(0,'fire')||firePointers.size>0;
const primaryFireKey=code=>keyForAction(0,'fire',code);

try{muted=localStorage.getItem('leqra.muted')==='1';bestWins=Number(localStorage.getItem('leqra.wins')||0)||0;const saved=localStorage.getItem('leqra.difficulty');if(DIFFICULTY[saved])difficulty=saved;}catch(_){}
const rnd=(a,b)=>a+Math.random()*(b-a), clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
// Grenades keep most of their speed until the final three seconds, then brake
// progressively harder. The integrated curve keeps local, online and AI projection
// consistent even when they advance with different step sizes.
function grenadeDragIntegral(age){
 age=clamp(age,0,GRENADE_FUSE);let integral=GRENADE_CRUISE_DRAG*age;
 if(age>GRENADE_BRAKE_START){const duration=GRENADE_FUSE-GRENADE_BRAKE_START,x=age-GRENADE_BRAKE_START;integral+=GRENADE_BRAKE_DRAG*x*x*x/(3*duration*duration);}
 return integral;
}
function grenadeDragFactor(lifeBefore,lifeAfter){
 const age0=GRENADE_FUSE-clamp(lifeBefore,0,GRENADE_FUSE),age1=GRENADE_FUSE-clamp(lifeAfter,0,GRENADE_FUSE);
 return Math.exp(-(grenadeDragIntegral(age1)-grenadeDragIntegral(age0)));
}
const distance=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
const angleDelta=(a,b)=>Math.atan2(Math.sin(b-a),Math.cos(b-a));
const cellAt=(x,y)=>clamp(Math.floor(y/CELL),0,rows-1)*cols+clamp(Math.floor(x/CELL),0,cols-1);
const center=i=>({x:(i%cols+.5)*CELL,y:(Math.floor(i/cols)+.5)*CELL});
const alive=()=>tanks.filter(t=>t.alive);
const isEnemy=(a,b)=>a.id!==b.id&&(a.team===0||a.team!==b.team);
// One damage rule is used for collision detection, prediction, and the damage
// handler itself. Friendly-fire rules never suppress self damage, in any seat.
// Human self-ricochets and grenade damage deliberately remain enabled.
function canDamage(owner,target){const shooter=tanks.find(t=>t.id===owner);return !!shooter&&(shooter.id===target.id||!!currentRules().friendlyFire||isEnemy(shooter,target));}
function scoreboardEntries(){
 if(mode==='room'||mode==='online'){
  const data=roomData(),result=[],groups=new Map();
  for(const p of data?.players||[]){const key=teamKey(p);let entry=groups.get(key);const alive=tanks.find(t=>t.id===p.id)?.alive??true;
   if(!entry){entry={...p,color:p.team>0?teamColor(p.id,p.team):p.color,name:p.team>0?teamName(p.team):p.name,alive:false,meta:'',members:[]};groups.set(key,entry);result.push(entry);}
   entry.alive ||= alive;entry.members.push(p.name);entry.meta=p.team>0?entry.members.join(' + '):p.kind==='bot'?(p.difficulty||'normal').toUpperCase()+' BOT':p.id===localPlayerID()?'YOU':p.kind==='local'?'LOCAL PLAYER 2':'ONLINE PILOT';
  }return result;
 }
 if(mode==='duel')return tanks.map(t=>({...t,meta:t.alive?'HUMAN PILOT':'ELIMINATED'}));
 const player=tanks[0],bots=tanks.filter(t=>!t.human);if(!player)return[];
 return[{...player,meta:player.alive?'HUMAN PILOT':'ELIMINATED'},{id:1,name:'BOT SQUAD',color:COLORS[1],alive:bots.some(t=>t.alive),human:false,meta:bots.map(t=>t.name+(t.alive?'':' ×')).join(' + ')}];
}
function winnerName(winner){const p=roomData()?.players.find(t=>t.id===winner)||tanks.find(t=>t.id===winner);return mode==='solo'&&winner>0?'BOT SQUAD':p?.team>0?teamName(p.team):p?.name||'PILOT';}
function save(key,val){try{localStorage.setItem('leqra.'+key,String(val));}catch(_){}}
function roundRect(c,x,y,w,h,r){r=Math.max(0,Math.min(r,w/2,h/2));c.beginPath();c.moveTo(x+r,y);c.arcTo(x+w,y,x+w,y+h,r);c.arcTo(x+w,y+h,x,y+h,r);c.arcTo(x,y+h,x,y,r);c.arcTo(x,y,x+w,y,r);c.closePath();}
function initAudio(){
 if(muted)return;
 try{if(!audio){const AC=window.AudioContext||window.webkitAudioContext;if(!AC)return;audio=new AC();}if(audio.state==='suspended')audio.resume().catch(()=>{});}catch(_){}
}
function ensureNoiseBuffer(){
 if(noiseBuffer||!audio)return noiseBuffer;
 try{const n=Math.floor(audio.sampleRate*.3);noiseBuffer=audio.createBuffer(1,n,audio.sampleRate);const data=noiseBuffer.getChannelData(0);for(let i=0;i<n;i++)data[i]=(Math.random()*2-1)*(1-i/n);}catch(_){noiseBuffer=null;}return noiseBuffer;
}
function tone(freq,end,duration,volume=.035,type='sine',delay=0){
 if(muted||!audio||audio.state!=='running')return;
 try{const t=audio.currentTime+delay,o=audio.createOscillator(),g=audio.createGain();o.type=type;o.frequency.setValueAtTime(freq,t);o.frequency.exponentialRampToValueAtTime(Math.max(20,end),t+duration);g.gain.setValueAtTime(.0001,t);g.gain.linearRampToValueAtTime(volume,t+.004);g.gain.exponentialRampToValueAtTime(.0001,t+duration);o.connect(g);g.connect(audio.destination);o.start(t);o.stop(t+duration+.01);}catch(_){}
}
function boom(){if(muted||!audio||audio.state!=='running'||!ensureNoiseBuffer())return;try{const s=audio.createBufferSource(),f=audio.createBiquadFilter(),g=audio.createGain();s.buffer=noiseBuffer;f.type='lowpass';f.frequency.value=850;g.gain.value=.15;s.connect(f);f.connect(g);g.connect(audio.destination);s.start();tone(100,30,.24,.06,'triangle');}catch(_){}}
function pickupSound(){tone(480,500,.09,.05,'sine');tone(700,800,.11,.04,'sine',.08);tone(1000,1200,.14,.035,'sine',.15);}
function chatNotificationSound(){if(muted)return;const now=performance.now();if(now-lastChatNotify<180)return;lastChatNotify=now;initAudio();tone(920,740,.075,.035,'sine');tone(1180,900,.09,.028,'sine',.065);}
function syncSound(){ $('soundBtn').classList.toggle('muted',muted);$('soundBtn').setAttribute('aria-pressed',String(!muted));$('soundBtn').setAttribute('aria-label',muted?'Unmute sound':'Mute sound'); }
function toggleSound(){muted=!muted;save('muted',muted?1:0);syncSound();if(!muted){initAudio();tone(500,700,.1);}}
function setLayout(){
 const coarse=window.matchMedia('(pointer: coarse)').matches||window.matchMedia('(any-pointer: coarse)').matches;
 touchUI=coarse||innerWidth<760||IOS_WEBKIT&&(navigator.maxTouchPoints||0)>0;
 const viewportH=window.visualViewport?.height||innerHeight;
 touchLandscape=touchUI&&innerWidth>viewportH&&viewportH<620;
 document.body.classList.toggle('touch-ui',touchUI);document.body.classList.toggle('touch-landscape',touchLandscape);renderPowerLegend();
 $('pauseInstructions').textContent=controlSummary(0)+(hasLocalP2()?' · '+controlSummary(1):'')+' · '+modeInstructions();
 resize();
}
function scheduleArenaResize(){
 if(arenaResizeFrame)return;
 arenaResizeFrame=requestAnimationFrame(()=>{arenaResizeFrame=0;resize();});
}
function stabilizeArenaLayout(){resize();scheduleArenaResize();}
function renderPixelRatio(width,height){
 const native=Math.max(1,window.devicePixelRatio||1);
 if(combatPrefs.performance)return 1;
 let cap=2,maxPixels=Infinity;
 if(WEBKIT_ENGINE){cap=touchUI?1.5:1.75;maxPixels=touchUI?1_250_000:2_750_000;}
 let ratio=Math.min(native,cap);
 if(Number.isFinite(maxPixels))ratio=Math.min(ratio,Math.sqrt(maxPixels/Math.max(1,width*height)));
 return Math.max(1,ratio);
}
function resize(){
 const b=wrap.getBoundingClientRect();cssW=Math.max(1,b.width);cssH=Math.max(1,b.height);dpr=renderPixelRatio(cssW,cssH);
 let pxW=Math.max(1,Math.round(cssW*dpr)),pxH=Math.max(1,Math.round(cssH*dpr));
 // WebKit can report fractional CSS-size jitter while browser chrome animates.
 // Keep a 1px backing-store wobble from reallocating the entire canvas.
 if(WEBKIT_ENGINE&&Math.abs(canvas.width-pxW)<=1)pxW=canvas.width;if(WEBKIT_ENGINE&&Math.abs(canvas.height-pxH)<=1)pxH=canvas.height;
 if(canvas.width!==pxW)canvas.width=pxW;if(canvas.height!==pxH)canvas.height=pxH;
 const reserved=touchLandscape&&!isSpectating()?252:0,padding=touchUI?12:28;
 scale=Math.min((cssW-reserved-padding)/W,(cssH-padding)/H);scale=Math.max(.05,scale);
 offsetX=(cssW-W*scale)/2;offsetY=(cssH-H*scale)/2;
}
function makeMaze(){
 [cols,rows]=mapDimensions();W=cols*CELL;H=rows*CELL;
 grid=Array.from({length:cols*rows},()=>({n:true,e:true,s:true,w:true,seen:false,neighbors:[]}));
 const stack=[Math.floor(Math.random()*grid.length)];grid[stack[0]].seen=true;
 const directions=[[-cols,'n','s'],[1,'e','w'],[cols,'s','n'],[-1,'w','e']],candidates=new Uint8Array(4);
 while(stack.length){const at=stack[stack.length-1],x=at%cols,y=Math.floor(at/cols);let count=0;if(y>0&&!grid[at-cols].seen)candidates[count++]=0;if(x<cols-1&&!grid[at+1].seen)candidates[count++]=1;if(y<rows-1&&!grid[at+cols].seen)candidates[count++]=2;if(x>0&&!grid[at-1].seen)candidates[count++]=3;if(!count){stack.pop();continue;}const [delta,side,other]=directions[candidates[Math.floor(Math.random()*count)]];grid[at][side]=false;grid[at+delta][other]=false;grid[at+delta].seen=true;stack.push(at+delta);}
 // Extra openings create loops, bank-shot lanes, and more than one escape route.
 for(let y=0;y<rows;y++)for(let x=0;x<cols;x++){const i=y*cols+x;if(x<cols-1&&grid[i].e&&Math.random()<.25){grid[i].e=false;grid[i+1].w=false;}if(y<rows-1&&grid[i].s&&Math.random()<.25){grid[i].s=false;grid[i+cols].n=false;}}
 walls=[];
 for(let y=0;y<rows;y++)for(let x=0;x<cols;x++){const i=y*cols+x,c=grid[i];if(c.n)walls.push({x:x*CELL-WALL/2,y:y*CELL-WALL/2,w:CELL+WALL,h:WALL,axis:'h',line:y*CELL});if(c.w)walls.push({x:x*CELL-WALL/2,y:y*CELL-WALL/2,w:WALL,h:CELL+WALL,axis:'v',line:x*CELL});if(y===rows-1)walls.push({x:x*CELL-WALL/2,y:H-WALL/2,w:CELL+WALL,h:WALL,axis:'h',line:H});if(x===cols-1)walls.push({x:W-WALL/2,y:y*CELL-WALL/2,w:WALL,h:CELL+WALL,axis:'v',line:W});if(!c.n)c.neighbors.push(i-cols);if(!c.e)c.neighbors.push(i+1);if(!c.s)c.neighbors.push(i+cols);if(!c.w)c.neighbors.push(i-1);}
 cacheMap();resize();
}
function cacheMap(){
 const maxCachePixels=combatPrefs.performance?2_000_000:WEBKIT_ENGINE?(touchUI?2_000_000:3_000_000):5_000_000,factor=Math.min(WEBKIT_ENGINE?1.3:1.5,Math.sqrt(maxCachePixels/Math.max(1,W*H)));mapCanvas=document.createElement('canvas');mapCanvas.width=Math.round(W*factor);mapCanvas.height=Math.round(H*factor);const c=mapCanvas.getContext('2d');c.scale(factor,factor);c.fillStyle=theme.floor;c.fillRect(0,0,W,H);
 for(let y=0;y<rows;y++)for(let x=0;x<cols;x++){const X=x*CELL,Y=y*CELL;c.fillStyle=(x+y)%2?theme.tileA:theme.tileB;c.fillRect(X+4,Y+4,CELL-8,CELL-8);c.strokeStyle=theme.tileLine;c.lineWidth=1;c.strokeRect(X+10,Y+10,CELL-20,CELL-20);c.fillStyle=theme.dots;for(const dx of [19,65])for(const dy of [19,65])c.fillRect(X+dx,Y+dy,1.5,1.5);c.fillStyle=theme.cross;c.fillRect(X+CELL/2-2,Y+CELL/2-.5,4,1);c.fillRect(X+CELL/2-.5,Y+CELL/2-2,1,4);}
 for(const w of walls){c.fillStyle=theme.wallShadow;c.fillRect(w.x+1,w.y+4,w.w,w.h+2);c.fillStyle=theme.wall;roundRect(c,w.x,w.y,w.w,w.h,2);c.fill();c.fillStyle=theme.wallEdge;if(w.axis==='h')c.fillRect(w.x+1,w.y+.8,w.w-2,1.2);else c.fillRect(w.x+.8,w.y+1,1.2,w.h-2);}
 // Sparse hazard marks are decorative, not additional collision objects.
 c.globalAlpha=.36;c.strokeStyle=theme.accent;c.lineWidth=2;
 for(let i=0;i<walls.length;i+=17){const w=walls[i];if(w.axis==='h'&&w.line>0&&w.line<H){for(let n=0;n<3;n++){c.beginPath();c.moveTo(w.x+31+n*6,w.y+1);c.lineTo(w.x+35+n*6,w.y+6);c.stroke();}}}
 c.globalAlpha=1;c.strokeStyle=theme.rim;c.lineWidth=2;c.strokeRect(1,1,W-2,H-2);
}
function pathScratch(a){
 const n=grid.length;if(!a||a.pathPrev?.length!==n){if(!a)return null;a.pathCost=new Float64Array(n);a.pathPrev=new Int16Array(n);a.pathClosed=new Uint8Array(n);a.pathReserved=new Uint8Array(n);a.pathDanger=new Uint8Array(n);a.pathOpen=[];a.pathQueue=[];a.pathScratch=[];}return a;
}
function tracePath(from,to,prev,a){const path=a?.pathScratch||[];path.length=0;for(let at=to;at!==from;at=prev[at]){if(at<0||path.length>grid.length){path.length=0;return path;}path.push(at);}path.reverse();return path;}
function bfs(from,to,a=null){if(from===to){if(a?.pathScratch)a.pathScratch.length=0;return a?.pathScratch||[];}const scratch=pathScratch(a),prev=scratch?.pathPrev||new Int16Array(grid.length),q=scratch?.pathQueue||[];prev.fill(-1);prev[from]=from;q.length=0;q.push(from);for(let p=0;p<q.length;p++){const i=q[p];for(const n of grid[i].neighbors){if(prev[n]!==-1)continue;prev[n]=i;if(n===to)return tracePath(from,to,prev,scratch);q.push(n);}}if(scratch?.pathScratch)scratch.pathScratch.length=0;return scratch?.pathScratch||[];}
function newTank(i,cell){const p=center(cell);const member=mode==='room'?localRoom.players.find(p=>p.id===i):null;return{id:i,name:member?member.name:mode==='duel'?(i===0?'PLAYER 1':'PLAYER 2'):NAMES[i],color:member?teamColor(i,member.team,member.colorIndex):COLORS[i],x:p.x,y:p.y,angle:i===0?-Math.PI/2:Math.PI/2,r:RADIUS,alive:true,human:member?member.kind!=='bot':i===0||mode==='duel',difficulty:member?.difficulty||difficulty,localIndex:member?.kind==='local'?1:0,team:member?member.team:mode==='duel'?'p'+i:i===0?'player':'bots',cooldown:0,shield:0,shieldCharges:0,speedTime:0,speedStacks:0,scopeTime:0,ghostTime:0,invulnerable:.75,power:null,powerTime:0,charges:0,recoil:0,vx:0,vy:0,track:0,ai:{think:rnd(.15,.5),path:[],pathClock:0,target:-1,aim:null,shotClock:rnd(.6,1.6),bankClock:0,bankAim:null,goal:-1,dodgeClock:0,dodgeTime:0,dodgeAngle:0,dodgeDrive:1,recoverTime:0,recoverAngle:0,recoverDrive:0,stuck:0,lastX:p.x,lastY:p.y}};}
function spawnCells(){return [(rows-1)*cols,cols-1,rows*cols-1,0,Math.floor(cols/2),Math.floor(rows/2)*cols+cols-1,(rows-1)*cols+Math.floor(cols/2),Math.floor(rows/2)*cols];}
function resetTanks(){const spawn=spawnCells();if(mode==='room'){tanks=localRoom.players.filter(p=>!p.spectating).map(p=>newTank(p.id,spawn[p.id]));return;}if(mode==='solo'&&Math.random()<.5)spawn[2]=0;tanks=spawn.slice(0,mode==='duel'?2:3).map((s,i)=>newTank(i,s));}
function resetPreview(){localObjectives=null;makeMaze();resetTanks();bullets=[];particles=[];rings=[];traces=[];pickups=[];seedPickups();if(!gameStarted)scores=Array(MAX_TANKS).fill(0);updateHUD(true);}
function setScreen(which){document.body.classList.toggle('room-setup',which==='room');if(which==='online'){which='room';if(!$('joinDialog').open)$('joinDialog').showModal();}document.body.classList.toggle('overlay-open',!!which);$('overlay').hidden=!which;for(const id of ['lobby','pause','match','online','room','onlineMenu'])$(id+'Screen').hidden=id!==which;stabilizeArenaLayout();}
function clearInput(){keys.clear();firePointers.clear();firePresses.clear();for(const t of tanks){t.fireHeld=false;t.fireBlocked=false;}stick.id=null;stick.x=stick.y=stick.mag=0;stick.cx=stick.cy=0;$('stickKnob').style.transform='translate(0,0)';$('fireBtn').classList.remove('held');}
function setMode(value){if(value==='online'){openOnline();return;}mode=value;document.querySelectorAll('[data-mode]').forEach(b=>{const selected=b.dataset.mode===mode;b.classList.toggle('selected',selected);b.setAttribute('aria-pressed',String(selected));});$('difficultyOptions').style.opacity=mode==='duel'?'.35':'1';document.querySelectorAll('[data-difficulty]').forEach(b=>b.disabled=mode==='duel');$('difficultyLabel').textContent=mode==='duel'?'TWO PLAYERS · ONE KEYBOARD':'BOT DIFFICULTY';$('lobbyNote').textContent=mode==='duel'?'P1: WASD + Q · P2: ARROWS + SPACE':'FIRST TO 5 · YOU VS. BOT SQUAD · FRESH MAZES';if(mode==='duel')$('manualContent').innerHTML='<div class="manual-line"><span>Player 1</span><kbd>WASD + Q</kbd></div><div class="manual-line"><span>Player 2</span><kbd>ARROWS + SPACE</kbd></div><div class="manual-line"><span>Pause</span><kbd>P / ESC</kbd></div><div class="manual-line"><span>Fullscreen</span><kbd>F</kbd></div><div class="warning"><b>One keyboard. Two rivals.</b><br>First to 5 wins. Every ricochet is live.</div>';else $('manualContent').innerHTML='<div class="manual-line manual-move-line"><span>Drive &amp; steer</span><div class="manual-key-options"><div class="keys"><kbd>↑</kbd><kbd>←</kbd><kbd>↓</kbd><kbd>→</kbd></div><span class="manual-or">OR</span><div class="keys"><kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd></div></div></div><div class="manual-line"><span>Fire / hold to fire</span><div class="keys"><kbd>Q</kbd><span class="manual-or">OR</span><kbd>SPACE</kbd></div></div><div class="manual-line"><span>Pause</span><div class="keys"><kbd>P</kbd><kbd>ESC</kbd></div></div><div class="manual-line"><span>Fullscreen</span><kbd>F</kbd></div><div class="warning"><b>Two bots. One enemy: you.</b><br>Bot shots pass through bots. Your own ricochets can still hit you.</div>';
 if(phase==='menu'){resetPreview();setLayout();}}
function setDifficulty(value){if(!DIFFICULTY[value])return;difficulty=value;save('difficulty',value);document.querySelectorAll('[data-difficulty]').forEach(b=>{const selected=b.dataset.difficulty===value;b.classList.toggle('selected',selected);b.setAttribute('aria-pressed',String(selected));});}
function startMatch(){if(mode==='room'&&roomStartError()){toast(roomStartError(),3);return;}initAudio();clearInput();scores=Array(MAX_TANKS).fill(0);round=1;gameStarted=true;beginLocalMatchStats();logLines=[];setScreen(null);addLog(mode==='room'?'Room battle. First side to 5.':mode==='solo'?'You vs. the bot squad. First to 5.':'Local duel. First to 5.');startRound();canvas.focus({preventScroll:true});}
function startRound(){goUntil=0;closeVictory();clearInput();makeMaze();resetTanks();bullets=[];particles=[];rings=[];traces=[];pickups=[];spawnClock=pickupInterval()[0];roundClock=currentRules().timeLimit;phase='countdown';phaseTime=2.6;roundWinner=-1;for(const t of tanks)bindLocalTankStats(t);initObjectives();seedPickups();$('toast').hidden=true;toastTime=0;updateHUD(true);}
function readyRoom(){goUntil=0;closeVictory();if(mode==='online'){leaveOnline();return;}phase='menu';gameStarted=false;clearInput();scores=Array(MAX_TANKS).fill(0);round=1;phaseTime=0;roundClock=ROUND_SECONDS;setScreen(mode==='room'?'room':'lobby');$('announcer').hidden=true;$('toast').hidden=true;resetPreview();if(mode==='room')renderOnlineRoom();setLayout();}
function togglePause(){if(mode==='room'){toggleRoomMenu();return;}if(mode==='online'){toggleOnlineMenu();return;}if(['menu','matchOver'].includes(phase))return;if(phase==='paused'){phase=pausedFrom;setScreen(null);initAudio();lastFrame=performance.now();accumulator=0;clearInput();canvas.focus({preventScroll:true});}else{pausedFrom=phase;phase='paused';clearInput();setScreen('pause');$('announcer').hidden=true;$('resumeBtn').focus({preventScroll:true});}updateHUD();}
function toast(message,duration=2.5){$('toast').textContent=message;$('toast').hidden=false;toastTime=duration;}
function addLog(message){logLines.unshift(message);logLines=logLines.slice(0,3);$('combatLog').replaceChildren(...logLines.map(s=>{const d=document.createElement('div');d.textContent=s;return d;}));}
function spawnPower(){if(pickups.length>=pickupCap()||currentRules().pickupRate==='off'||!currentRules().weapons.length)return;let pos=null;for(let tries=0;tries<60;tries++){const cell=Math.floor(Math.random()*grid.length),p=center(cell);if(tanks.every(t=>!t.alive||distance(p,t)>CELL*.85)&&pickups.every(t=>distance(p,t)>CELL*1.1)){pos=p;break;}}if(!pos)return;const types=currentRules().weapons;pickups.push({...pos,type:choosePickup(types),age:0,life:pickupLifetime()});}
function powerCapacity(t){return t.power==='rapid'?MACHINE_CAPACITY:t.power==='scatter'?12:['homing','grenade','laser','cannon'].includes(t.power)?3:5;}
function activeAmmo(t){if(t.power==='laser')return Math.max(0,3-t.charges);const list=mode==='online'?(online.snapshots.at(-1)?.bullets||[]):bullets;return list.reduce((n,b)=>n+(b.owner===t.id&&!b.dead?1:0),0);}
// Earliest entry into an expanded wall rectangle, with simultaneous corner normals.
// Static maze broad phase. Preserve wall order for identical corner handling.
let wallIndex=null;
function nearbyWalls(x,y,dx,dy,r){
 if(walls.length<24)return walls;
 let z=wallIndex;
 if(!z||z.source!==walls||z.count!==walls.length||z.cols!==cols||z.rows!==rows){
  z={source:walls,count:walls.length,cols,rows,bins:Array.from({length:cols*rows},()=>[]),seen:new Uint32Array(walls.length),stamp:0,ids:[],result:[],order:new Map(walls.map((w,i)=>[w,i]))};
  for(let i=0;i<walls.length;i++){const w=walls[i],x0=clamp(Math.floor(w.x/CELL),0,cols-1),x1=clamp(Math.floor((w.x+w.w)/CELL),0,cols-1),y0=clamp(Math.floor(w.y/CELL),0,rows-1),y1=clamp(Math.floor((w.y+w.h)/CELL),0,rows-1);for(let yy=y0;yy<=y1;yy++)for(let xx=x0;xx<=x1;xx++)z.bins[yy*cols+xx].push(i);}
  wallIndex=z;
 }
 const x0=clamp(Math.floor((Math.min(x,x+dx)-r)/CELL),0,cols-1),x1=clamp(Math.floor((Math.max(x,x+dx)+r)/CELL),0,cols-1),y0=clamp(Math.floor((Math.min(y,y+dy)-r)/CELL),0,rows-1),y1=clamp(Math.floor((Math.max(y,y+dy)+r)/CELL),0,rows-1);
 if((x1-x0+1)*(y1-y0+1)>cols*rows/3)return walls;
 z.stamp=(z.stamp+1)>>>0;if(z.stamp===0){z.seen.fill(0);z.stamp=1;}z.ids.length=0;z.result.length=0;
 for(let yy=y0;yy<=y1;yy++)for(let xx=x0;xx<=x1;xx++)for(const id of z.bins[yy*cols+xx])if(z.seen[id]!==z.stamp){z.seen[id]=z.stamp;z.ids.push(id);}
 z.ids.sort((a,b)=>a-b);for(const id of z.ids)z.result.push(walls[id]);return z.result;
}

function rayWalls(x,y,dx,dy,r=0){
 let nearest=null,best=1+1e-8;
 for(const w of nearbyWalls(x,y,dx,dy,r)){
  const minX=w.x-r,maxX=w.x+w.w+r,minY=w.y-r,maxY=w.y+w.h+r;
  if(Math.max(x,x+dx)<minX||Math.min(x,x+dx)>maxX||Math.max(y,y+dy)<minY||Math.min(y,y+dy)>maxY)continue;
  let tx1=-Infinity,tx2=Infinity,ty1=-Infinity,ty2=Infinity;
  if(Math.abs(dx)<1e-9){if(x<minX||x>maxX)continue;}else{tx1=(minX-x)/dx;tx2=(maxX-x)/dx;if(tx1>tx2)[tx1,tx2]=[tx2,tx1];}
  if(Math.abs(dy)<1e-9){if(y<minY||y>maxY)continue;}else{ty1=(minY-y)/dy;ty2=(maxY-y)/dy;if(ty1>ty2)[ty1,ty2]=[ty2,ty1];}
  const entry=Math.max(tx1,ty1),exit=Math.min(tx2,ty2);
  if(entry>exit||exit<0||entry>1||entry<-.0001)continue;
  const hit=Math.max(0,entry);let nx=0,ny=0;
  if(Math.abs(tx1-ty1)<1e-7){nx=dx>0?-1:1;ny=dy>0?-1:1;}else if(tx1>ty1)nx=dx>0?-1:1;else ny=dy>0?-1:1;
  if(hit<best-1e-7){best=hit;nearest={t:hit,nx,ny,wall:w};}else if(nearest&&Math.abs(hit-best)<1e-7){if(nx)nearest.nx=nx;if(ny)nearest.ny=ny;}
 }
 return nearest;
}
function circleHit(x,y,dx,dy,tx,ty,r){const a=dx*dx+dy*dy,ox=x-tx,oy=y-ty,c=ox*ox+oy*oy-r*r;if(c<=0)return 0;if(a<1e-12)return null;const b=2*(ox*dx+oy*dy),disc=b*b-4*a*c;if(disc<0)return null;const n=(-b-Math.sqrt(disc))/(2*a);return n>=0&&n<=1?n:null;}
function tankHit(x,y,dx,dy,r,owner,ignoreOwner,impactOnly=false){let first=null;for(const t of tanks){if(!t.alive||(t.id===owner&&ignoreOwner)||!impactOnly&&(!canDamage(owner,t)||t.invulnerable>0))continue;const hit=circleHit(x,y,dx,dy,t.x,t.y,t.r+r);if(hit!==null&&(!first||hit<first.at))first={at:hit,tank:t};}return first;}
// Outer-rim sweep shared by live Cannon physics, guidance, threat forecasts and
// remote visuals. Adjacent wall tile seams cannot create spurious reflections.
function rayBounds(x,y,dx,dy,r){
 const min=WALL/2+r,maxX=W-min,maxY=H-min;let best=null;
 const consider=(at,nx,ny)=>{if(at< -1e-7||at>1+1e-7)return;at=clamp(at,0,1);
  if(!best||at<best.t-1e-7)best={t:at,nx,ny};else if(Math.abs(at-best.t)<1e-7){if(nx)best.nx=nx;if(ny)best.ny=ny;}};
 if(dx>1e-9)consider((maxX-x)/dx,-1,0);else if(dx< -1e-9)consider((min-x)/dx,1,0);
 if(dy>1e-9)consider((maxY-y)/dy,0,-1);else if(dy< -1e-9)consider((min-y)/dy,0,1);
 return best;
}
function projectileWall(kind,x,y,dx,dy,r){return kind==='cannon'?rayBounds(x,y,dx,dy,r):rayWalls(x,y,dx,dy,r);}
function movementWall(ghost,x,y,dx,dy,r){return ghost?rayBounds(x,y,dx,dy,r):rayWalls(x,y,dx,dy,r);}
function clearTankAt(x,y,r){
 const margin=WALL/2+r;if(x<margin||x>W-margin||y<margin||y>H-margin)return false;
 for(const w of nearbyWalls(x,y,0,0,r+.001))if(Math.hypot(x-clamp(x,w.x,w.x+w.w),y-clamp(y,w.y,w.y+w.h))<r+.0001)return false;
 return true;
}
function finishGhost(t){
 if(clearTankAt(t.x,t.y,t.r))return;
 let x=t.x,y=t.y,best=Infinity;const margin=WALL/2+t.r+.01;
 for(let row=0;row<rows;row++)for(let col=0;col<cols;col++){
  const xx=clamp(t.x,col*CELL+margin,(col+1)*CELL-margin),yy=clamp(t.y,row*CELL+margin,(row+1)*CELL-margin),d=(xx-t.x)**2+(yy-t.y)**2;
  if(d<best-1e-8&&clearTankAt(xx,yy,t.r)){x=xx;y=yy;best=d;}
 }
 if(Number.isFinite(best)){t.x=x;t.y=y;}else resolveWalls(t);
 if(t.ai){t.ai.path=[];t.ai.think=0;t.ai.recoverTime=0;}
}
function advanceGhost(t,dt){const was=t.ghostTime>0;t.ghostTime=Math.max(0,(t.ghostTime||0)-dt);if(was&&t.ghostTime===0)finishGhost(t);}
function cannonGuide(t){
 let x=t.x,y=t.y,ux=Math.cos(t.angle),uy=Math.sin(t.angle),left=t.scopeTime>0?W+H:112,travel=0;
 const points=[{x,y}];let target=null;
 for(let segment=0;segment<32&&left>1e-7;segment++){
  const dx=ux*left,dy=uy*left,w=rayBounds(x,y,dx,dy,CANNON_RADIUS);let stop=w?w.t:1,hit=null;
  for(const o of tanks){
   if(!o.alive||o.invulnerable>0||!canDamage(t.id,o))continue;
   const at=circleHit(x,y,dx,dy,o.x,o.y,o.r+CANNON_RADIUS);
   if(o.id===t.id&&(at===null||travel+left*at<28+CANNON_SPEED*.2))continue;
   if(at!==null&&at<stop){stop=at;hit=o;}
  }
  const len=left*stop;x+=ux*len;y+=uy*len;left-=len;travel+=len;points.push({x,y});
  if(hit){target=hit;break;}if(!w||left<=1e-7)break;
  if(w.nx)ux=-ux;if(w.ny)uy=-uy;
  const nudge=Math.min(.001,left);x+=ux*nudge;y+=uy*nudge;left-=nudge;travel+=nudge;
 }
 return{tank:target,points};
}

function moveTank(t,dx,dy,ghostExpired=false){
 if(ghostExpired)finishGhost(t);
 if(t.ghostTime>0){t.x=clamp(t.x+dx,WALL/2+t.r,W-WALL/2-t.r);t.y=clamp(t.y+dy,WALL/2+t.r,H-WALL/2-t.r);return;}
 t.x+=dx;resolveWalls(t);t.y+=dy;resolveWalls(t);t.x=clamp(t.x,WALL/2+t.r,W-WALL/2-t.r);t.y=clamp(t.y,WALL/2+t.r,H-WALL/2-t.r);
}
// Re-query after a push: it may bring a later wall into contact. Never revisit
// an earlier wall within the same pass; this preserves the exhaustive algorithm.
function resolveWalls(t){
 for(let pass=0;pass<2;pass++){
  let candidates=nearbyWalls(t.x,t.y,0,0,t.r);
  for(let i=0;i<candidates.length;i++){
   const w=candidates[i],wi=candidates===walls?i:wallIndex.order.get(w);
   const qx=clamp(t.x,w.x,w.x+w.w),qy=clamp(t.y,w.y,w.y+w.h),dx=t.x-qx,dy=t.y-qy,ds=dx*dx+dy*dy;
   if(ds>=t.r*t.r)continue;
   if(ds>.000001){const d=Math.sqrt(ds),push=t.r-d+.002;t.x+=dx/d*push;t.y+=dy/d*push;}
   else{const choices=[{v:t.x-w.x,dx:-1,dy:0},{v:w.x+w.w-t.x,dx:1,dy:0},{v:t.y-w.y,dx:0,dy:-1},{v:w.y+w.h-t.y,dx:0,dy:1}];let choice=choices[0];for(let k=1;k<4;k++)if(choices[k].v<choice.v)choice=choices[k];t.x+=choice.dx*(choice.v+t.r+.002);t.y+=choice.dy*(choice.v+t.r+.002);}
   candidates=nearbyWalls(t.x,t.y,0,0,t.r);i=0;while(i<candidates.length&&(candidates===walls?i:wallIndex.order.get(candidates[i]))<=wi)i++;i--;
  }
 }
}

function burst(x,y,color,count=13,speed=85){const webkitLite=WEBKIT_ENGINE&&!combatPrefs.performance,room=(combatPrefs.performance?180:webkitLite?300:450)-particles.length;if(combatPrefs.performance)count=Math.ceil(count*.6);else if(webkitLite)count=Math.ceil(count*.8);for(let i=0;i<Math.min(count,room);i++){const a=rnd(0,TAU),s=rnd(speed*.15,speed),life=rnd(.18,.55);particles.push({x,y,vx:Math.cos(a)*s,vy:Math.sin(a)*s,color,life,max:life,size:rnd(1.4,3.7)});}}
function addRing(x,y,color,max=52){rings.push({x,y,color,life:.45,maxLife:.45,max});if(rings.length>30)rings.shift();}
function projectileSpec(power){
 const base={speed:282,r:3.5,life:5.3,cooldown:.34,kind:''};
 if(power==='rapid')return{...base,speed:MACHINE_SPEED,r:MACHINE_RADIUS,life:(W+H)/(2*MACHINE_SPEED),cooldown:0,kind:'rapid'};
 if(power==='scatter')return{...base,speed:282*3,life:3.9,cooldown:.54,kind:'scatter'};
 if(power==='homing')return{speed:MISSILE_SPEED,r:5,life:(W+H)/MISSILE_SPEED+.5,cooldown:.72,kind:'homing'};
 if(power==='grenade')return{speed:GRENADE_SPEED,r:6,life:GRENADE_FUSE,cooldown:.8,kind:'grenade'};
 if(power==='cannon')return{speed:CANNON_SPEED,r:CANNON_RADIUS,life:CANNON_LIFETIME,cooldown:CANNON_COOLDOWN,kind:'cannon'};
 return base;
}
function muzzleProjectile(t,angle){
 const spec=projectileSpec(t.power),cs=Math.cos(angle),sn=Math.sin(angle);
 const muzzle=spec.kind==='cannon'?Math.max(28,t.r+spec.r+1):28;
 const b={...spec,owner:t.id,x:t.x+cs*muzzle,y:t.y+sn*muzzle,vx:cs*spec.speed,vy:sn*spec.speed,age:0,color:t.color,bounces:0,target:-1,trail:[],dead:false};
 const hit=projectileWall(b.kind,t.x,t.y,cs*muzzle,sn*muzzle,b.r);
 if(hit){b.x=t.x+cs*muzzle*hit.t+hit.nx*.12;b.y=t.y+sn*muzzle*hit.t+hit.ny*.12;if(hit.nx)b.vx=-b.vx;if(hit.ny)b.vy=-b.vy;b.bounces++;}
 const launchDistance=hit?muzzle*hit.t+Math.hypot(hit.nx,hit.ny)*.12:muzzle;
 if(b.kind==='homing'){b.rangeLeft=Math.max(0,W+H-launchDistance);b.seekDelay=hit?MISSILE_WALL_DELAY:0;}
 else if(b.kind==='rapid')b.life=Math.max(0,((W+H)/2-launchDistance)/MACHINE_SPEED);
 return b;
}
let lastMachineTone=-Infinity;
function shotSound(kind,local=true){
 if(kind==='rapid'){if(time-lastMachineTone<.065)return;lastMachineTone=time;tone(160,65,.055,local?.022:.009,'triangle');return;}
 if(kind==='laser'){tone(1100,160,.23,local?.045:.022,'sawtooth');tone(1700,500,.14,local?.03:.016,'sine');}
 else if(kind==='homing')tone(110,370,.24,local?.042:.022,'sawtooth');
 else if(kind==='grenade')tone(95,42,.15,local?.06:.03,'triangle');
 else if(kind==='cannon'){tone(75,28,.24,local?.08:.04,'triangle');tone(180,45,.11,local?.035:.018,'sawtooth');}
 else tone(145,60,.085,local?.045:.025,'triangle');
}
function fire(t){
 if(!t.alive||t.cooldown>0||(t.ghostTime>0&&t.power!=='cannon'&&!clearTankAt(t.x,t.y,0)))return false;
 if(t.power==='laser')return fireLaser(t);
 if(t.power==='cannon'&&t.charges<=0)return false;
 if(t.power==='rapid'&&t.rapidTick===Math.floor((time+1e-7)*60))return false;
 const available=powerCapacity(t)-activeAmmo(t),spread=t.power==='scatter'?[-.21,0,.21]:[0];
 if(available<spread.length)return false;
 const spec=projectileSpec(t.power);if(t.power==='rapid')t.rapidTick=Math.floor((time+1e-7)*60);t.cooldown=spec.cooldown;t.cooldownTotal=t.cooldown;t.recoil=1;
 for(const offset of spread){const angle=t.angle+offset,b=muzzleProjectile(t,angle);b.id=++bulletId;
  bullets.push(b);
  if(spec.kind!=='rapid'||Math.floor(time*60)%4===0)burst(t.x+Math.cos(angle)*27,t.y+Math.sin(angle)*27,t.color,3,40);
 }
 shotSound(spec.kind,t.human);
 if(['scatter','homing','grenade','cannon'].includes(t.power)){t.charges--;if(t.charges<=0){t.power=null;t.powerTime=0;}}
 return true;
}
// The same bounded multi-segment trace as Go. Bot beams pass through bots;
// the shooter remains immune, including after a wall reflection.
function laserTrace(t,angle=t.angle){
 let x=t.x,y=t.y,ux=Math.cos(angle),uy=Math.sin(angle),remaining=2*(W+H),target=null;
 const points=[];let bounces=0;
 for(let segment=0;segment<LASER_MAX_SEGMENTS&&remaining>1e-7;segment++){
  const dx=ux*remaining,dy=uy*remaining,wall=rayWalls(x,y,dx,dy,LASER_RADIUS);
  let stop=wall?wall.t:1;
  for(const other of tanks){if(other.id===t.id||!other.alive||other.invulnerable>0||!canDamage(t.id,other))continue;
   const at=circleHit(x,y,dx,dy,other.x,other.y,other.r+LASER_RADIUS);
   if(at!==null&&at<stop){stop=at;target=other;}
  }
  const length=remaining*stop;
  if(segment===0){const start=Math.min(28,length);points.push({x:x+ux*start,y:y+uy*start});}
  x+=ux*length;y+=uy*length;points.push({x,y});remaining-=length;
  if(target||!wall||remaining<=1e-7)break;
  if(wall.nx)ux=-ux;if(wall.ny)uy=-uy;bounces++;
  const nudge=Math.min(.001,remaining);x+=ux*nudge;y+=uy*nudge;remaining-=nudge;
 }
 const start=points[0]||{x:t.x,y:t.y},end=points.at(-1)||start;
 return{x:start.x,y:start.y,endX:end.x,endY:end.y,points,target,bounces};
}
function laserEffect(x,y,endX,endY,color=POWER.laser.color,path=null){
 if(![x,y,endX,endY].every(Number.isFinite))return;
 const points=Array.isArray(path)?path.slice(0,LASER_MAX_SEGMENTS+1).filter(p=>Number.isFinite(p.x)&&Number.isFinite(p.y)).map(p=>({x:p.x,y:p.y})):[{x,y},{x:endX,y:endY}];
 if(points.length<2)return;
 traces.push({x,y,endX,endY,points,color,life:.23,maxLife:.23});if(traces.length>32)traces.shift();
 for(let i=1;i<Math.min(points.length-1,20);i++)burst(points[i].x,points[i].y,color,2,45);
 burst(endX,endY,color,10,95);
}
function fireLaser(t){
 if(!t.alive||t.cooldown>0||t.power!=='laser'||t.charges<=0)return false;
 const beam=laserTrace(t);t.cooldown=LASER_COOLDOWN;t.cooldownTotal=t.cooldown;t.recoil=1;
 laserEffect(beam.x,beam.y,beam.endX,beam.endY,POWER.laser.color,beam.points);shotSound('laser',t.human);
 if(beam.target)hurt(beam.target,{owner:t.id,kind:'laser'});
 t.charges--;if(t.charges<=0){t.power=null;t.powerTime=0;}return true;
}
function compactLife(list){let write=0;for(let i=0;i<list.length;i++){const item=list[i];if(item.life>0)list[write++]=item;}list.length=write;return list;}
function compactNotDead(list){let write=0;for(let i=0;i<list.length;i++){const item=list[i];if(!item.dead)list[write++]=item;}list.length=write;return list;}
function updateTraces(dt){for(const b of traces)b.life-=dt;compactLife(traces);}
// Scope is a visual aiming aid, never an extension to weapon damage/range.
// Trace only owned live tanks. The path includes its muzzle and nudge distances.
function aimingGuide(t){
 if(t.ghostTime>0&&t.power!=='cannon'&&!clearTankAt(t.x,t.y,0))return{tank:null,points:[]};
 if(t.power==='cannon')return cannonGuide(t);
 if(!(t.scopeTime>0))return shotPrediction(t,t.angle,1,112);
 let x=t.x,y=t.y,ux=Math.cos(t.angle),uy=Math.sin(t.angle),remaining=W+H;
 const radius=projectileSpec(t.power).r,points=[{x,y}];let hitTank=null;
 for(let segment=0;segment<LASER_MAX_SEGMENTS&&remaining>1e-7;segment++){
  const dx=ux*remaining,dy=uy*remaining,w=rayWalls(x,y,dx,dy,radius);
  let stop=w?w.t:1,target=null;
  for(const other of tanks){
   if(!other.alive||other.invulnerable>0||!canDamage(t.id,other)||(other.id===t.id&&(segment===0||t.power==='laser'||t.power==='scatter')))continue;
   const at=circleHit(x,y,dx,dy,other.x,other.y,other.r+radius);
   if(at!==null&&at<stop){stop=at;target=other;}
  }
  const length=remaining*stop;x+=ux*length;y+=uy*length;remaining-=length;points.push({x,y});
  if(target){hitTank=target;break;}if(!w||remaining<=1e-7)break;
  if(w.nx)ux=-ux;if(w.ny)uy=-uy;
  const nudge=Math.min(.001,remaining);x+=ux*nudge;y+=uy*nudge;remaining-=nudge;
 }
 return{tank:hitTank,points};
}
function drawAimingGuides(){
 if(!guideEnabled||['menu','matchOver','onlineLobby'].includes(phase))return;
 const primary=controlledTank(),secondary=tanks.find(p=>p.id===secondaryID());
 for(const t of [primary,secondary]){
  if(!t||!t.alive)continue;
  // Keep the previous secondary display unless this pilot has a Scope pickup.
  if(t!==primary&&!(t.scopeTime>0))continue;
  const guide=aimingGuide(t);if(guide.points.length<2)continue;
  ctx.save();ctx.strokeStyle=paintColor(guideInk(t.color));ctx.globalAlpha=t.scopeTime>0?.48:theme.guideAlpha;
  ctx.setLineDash([3,7]);ctx.lineWidth=1.3;ctx.beginPath();
  // Trim the barrel from the first segment, never extend the trace past a wall.
  const first=guide.points[0],next=guide.points[1],length=distance(first,next),skip=Math.min(28,length);
  ctx.moveTo(first.x+(next.x-first.x)*(length?skip/length:0),first.y+(next.y-first.y)*(length?skip/length:0));
  for(let i=1;i<guide.points.length;i++)ctx.lineTo(guide.points[i].x,guide.points[i].y);
  ctx.stroke();ctx.restore();
 }
}

function drawLasers(){
 ctx.save();ctx.lineCap='round';ctx.lineJoin='round';
 for(const b of traces){const fade=clamp(b.life/b.maxLife,0,1);
  ctx.strokeStyle=paintColor(b.color);ctx.globalAlpha=fade*.2;ctx.lineWidth=14;ctx.beginPath();
  ctx.moveTo(b.points[0].x,b.points[0].y);for(let i=1;i<b.points.length;i++)ctx.lineTo(b.points[i].x,b.points[i].y);ctx.stroke();
  ctx.globalAlpha=fade;ctx.lineWidth=6;ctx.stroke();ctx.strokeStyle=paintColor('#fff4ff');ctx.lineWidth=2;ctx.stroke();
 }
 ctx.restore();
}
function ownedGrenades(t){const list=mode==='online'?(online.snapshots.at(-1)?.bullets||[]):bullets;return list.filter(b=>!b.dead&&b.kind==='grenade'&&b.owner===t.id);}
function detonateOwned(t){
 if(!t.alive)return false;
 const owned=ownedGrenades(t);for(const b of owned)detonate(b);return owned.length>0;
}
function weaponControl(t,held,pressed){
 if(!t.alive)return;
 if(!held)t.fireBlocked=false;
 if(pressed){
  if(detonateOwned(t)){t.fireBlocked=held;return;}
  if(t.power==='grenade'){t.fireBlocked=held;fire(t);return;}
 }
 if(!t.fireBlocked&&t.power!=='grenade'&&(held||pressed))fire(t);
}

function impactEffect(x,y,color,radius=25){burst(x,y,color,10,95);addRing(x,y,color,radius);tone(160,65,.10,.023,'triangle');}
function eventShake(x,y,amount){if(reduceMotion)return;const own=[controlledTank(),tanks.find(t=>t.id===secondaryID())].filter(Boolean);if(own.some(t=>distance(t,{x,y})<180))shake=Math.max(shake,amount);}
function blastEffect(x,y,color,radius=BLAST_RADIUS){
 burst(x,y,POWER.grenade.color,48,240);burst(x,y,color,18,165);
 // Cache a wall-clipped flash polygon once, rather than recasting every frame.
 const outline=[],segments=combatPrefs.performance?28:48;for(let i=0;i<segments;i++){const a=TAU*i/segments,dx=Math.cos(a)*radius,dy=Math.sin(a)*radius,w=rayWalls(x,y,dx,dy,0),f=w?w.t:1;outline.push({x:dx*f,y:dy*f});}
 rings.push({x,y,color:POWER.grenade.color,life:.45,maxLife:.45,max:radius,outline});if(rings.length>30)rings.shift();
 boom();eventShake(x,y,.08);
}
function detonate(b){
 if(b.dead)return;b.dead=true;blastEffect(b.x,b.y,b.color);
 for(const t of tanks){if(t.alive&&canDamage(b.owner,t)&&distance(b,t)<=BLAST_RADIUS+t.r&&!rayWalls(b.x,b.y,t.x-b.x,t.y-b.y,0))hurt(t,b);}
}
// Match Go's forward seeker, finite turn rate, and lock/rebound cooldowns.
function steerMissile(b,dt){
 b.seekDelay=Math.max(0,(b.seekDelay||0)-dt);if(b.age<.1||b.seekDelay>0)return;
 const visible=t=>{
  if(!t||t.id===b.owner||!t.alive||t.invulnerable>0||!isEnemy(tanks.find(o=>o.id===b.owner)||{id:b.owner,team:0},t))return false;
  const rx=t.x-b.x,ry=t.y-b.y,d=Math.hypot(rx,ry);
  if(d>CELL*10||(d>1e-8&&rx*b.vx+ry*b.vy<MISSILE_VIEW_COS*d*Math.hypot(b.vx,b.vy)))return false;
  return !rayWalls(b.x,b.y,rx,ry,b.r);
 };
 let target=null;
 if(b.target>=0){target=tanks.find(t=>t.id===b.target&&visible(t));if(!target){b.target=-1;b.seekDelay=MISSILE_LOCK_DELAY;return;}}
 if(!target){let best=Infinity;for(const t of tanks){if(!visible(t))continue;const d=distance(b,t);if(d<best){best=d;target=t;}}}
 b.target=target?target.id:-1;if(!target)return;
 let angle=Math.atan2(b.vy,b.vx);angle+=clamp(angleDelta(angle,Math.atan2(target.y-b.y,target.x-b.x)),-MISSILE_TURN*dt,MISSILE_TURN*dt);
 b.vx=Math.cos(angle)*MISSILE_SPEED;b.vy=Math.sin(angle)*MISSILE_SPEED;
}
// Subtract actual path length, including tiny collision-separation movements.
function spendMissileRange(b,length){if(b.kind==='homing')b.rangeLeft=Math.max(0,(b.rangeLeft??(W+H))-length);}
function missileWallNudge(b,wall){
 const normal=Math.hypot(wall.nx,wall.ny),nudge=b.kind==='homing'?Math.min(.08,Math.max(0,b.rangeLeft)/Math.max(1,normal)):.08;
 b.x+=wall.nx*nudge;b.y+=wall.ny*nudge;spendMissileRange(b,nudge*normal);
 if(wall.nx)b.vx=-b.vx;if(wall.ny)b.vy=-b.vy;b.bounces=(b.bounces||0)+1;
 if(b.kind==='homing'){b.target=-1;b.seekDelay=MISSILE_WALL_DELAY;}
}
// Used only for grenade guidance/AI, not authoritative online damage.
function grenadeForecast(source,seconds=source.life){
 const b={...source};let left=Math.max(0,Math.min(seconds,b.life));
 while(left>1e-6){const dt=Math.min(1/60,left),lifeBefore=b.life;b.life=Math.max(0,b.life-dt);const drag=grenadeDragFactor(lifeBefore,b.life);b.vx*=drag;b.vy*=drag;let rest=dt;
  for(let i=0;i<4&&rest>1e-5;i++){const dx=b.vx*rest,dy=b.vy*rest,w=rayWalls(b.x,b.y,dx,dy,b.r);if(!w){b.x+=dx;b.y+=dy;break;}
   b.x+=dx*w.t+w.nx*.08;b.y+=dy*w.t+w.ny*.08;if(w.nx)b.vx=-b.vx;if(w.ny)b.vy=-b.vy;b.bounces++;rest*=1-w.t;
  }left-=dt;
 }return b;
}
function grantPower(t,type){
 if(!POWER[type])return;
 if(type==='shield'){t.shieldCharges=Math.min(5,shieldCount(t)+1);t.shield=POWER_EFFECT_DURATION;}
 else if(type==='speed'){t.speedStacks=Math.min(MAX_SPEED_STACKS,speedCount(t)+1);t.speedTime=POWER_EFFECT_DURATION;}
 else if(type==='scope')t.scopeTime=SCOPE_DURATION;
 else if(type==='ghost')t.ghostTime=GHOST_DURATION;
 else{t.power=type;if(type==='rapid'){t.cooldown=0;t.cooldownTotal=0;}t.powerTime=POWER_EFFECT_DURATION;t.charges=['homing','grenade','laser','cannon'].includes(type)?3:5;}
}
function pickupMessage(type){return type==='ghost'?'GHOST · THROUGH WALLS · 10 SECONDS':type==='cannon'?'CANNON · EDGE RICOCHETS · 4× SIZE / SPEED':type==='scope'?'SCOPE · LONG AIM GUIDE · 10 SECONDS':type==='laser'?'LASER · RICOCHETS · MAZE-PERIMETER RANGE':type==='homing'?'HOMING · RICOCHETS · HALF-PERIMETER RANGE':type==='grenade'?'GRENADE · IMPACT / TAP AGAIN / 10s FUSE':type==='speed'?'SUPER SPEED · +1 STACK · 10 SECONDS':POWER[type].name+' · 10 SECONDS';}
function localPilotIndex(id){if(id===localPlayerID())return 0;const second=secondaryID();return second!==undefined&&id===second?1:-1;}
function setPilotFeedback(index,text,duration=2.5){if(index<0||index>1)return;pilotFeedback[index].text=text;pilotFeedback[index].until=performance.now()+duration*1000;}
function showStartingControls(){
 if(!isSpectating())setPilotFeedback(0,touchUI?'CONTROLS · DRAG TO STEER · HOLD FIRE':'CONTROLS · '+controlSummary(0,false),3);
 if(secondaryID()!==undefined)setPilotFeedback(1,'CONTROLS · '+controlSummary(1,false),3);
 updateHUD(true);
}
function hurt(t,b){
 if(!t.alive||t.invulnerable>0||!canDamage(b.owner,t)||(['scatter','rapid'].includes(b.kind)&&b.owner===t.id))return;
 if(t.shield>0){t.shieldCharges=shieldCount(t)-1;if(!t.shieldCharges)t.shield=0;t.invulnerable=.35;burst(t.x,t.y,POWER.shield.color,20,125);addRing(t.x,t.y,POWER.shield.color,58);tone(680,160,.2,.05,'sine');if(t.id===0)toast('SHIELD SAVED YOU',1.7);return;}
 recordLocalDeath(t,b.owner);
 t.alive=false;if(objectiveMode()){t.respawnTime=suddenDeath()?0:currentRules().respawnSeconds;dropLocalFlags(t.id);}t.vx=t.vy=0;burst(t.x,t.y,t.color,34,190);burst(t.x,t.y,'#f7ecbb',16,130);addRing(t.x,t.y,t.color,70);shake=reduceMotion?0:.18;boom();
 const owner=tanks.find(p=>p.id===b.owner);addLog(b.owner===t.id?t.name+(b.kind==='grenade'?' was caught in their own blast.':' caught their own ricochet.'):(owner?.name||'PILOT')+' eliminated '+t.name+'.');
 if(t.id===0&&mode==='solo'){toast(b.owner===t.id?(b.kind==='grenade'?'YOUR OWN GRENADE!':'YOUR OWN RICOCHET!'):'TANK DOWN · SQUAD WINS',2.4);if(touchUI&&navigator.vibrate)navigator.vibrate(35);}
 updateHUD(true);
}
function updateBullets(dt){
 for(const b of bullets){if(b.dead)continue;
  if(b.kind==='homing')b.rangeLeft??=W+H;
  const span=Math.min(dt,Math.max(0,b.life),b.kind==='homing'?b.rangeLeft/MISSILE_SPEED:Infinity),lifeBefore=b.life;b.age+=span;b.life-=span;
  if(b.kind==='homing')steerMissile(b,span);
  if(b.kind==='grenade'){const drag=grenadeDragFactor(lifeBefore,b.life);b.vx*=drag;b.vy*=drag;}
  if(b.kind!=='rapid'){b.trail.push({x:b.x,y:b.y});if(b.trail.length>11)b.trail.shift();}let remaining=span;
  for(let step=0;step<4&&remaining>.00001&&!b.dead;step++){
   if(b.kind==='homing')remaining=Math.min(remaining,Math.max(0,b.rangeLeft)/MISSILE_SPEED);
   const dx=b.vx*remaining,dy=b.vy*remaining,wall=projectileWall(b.kind,b.x,b.y,dx,dy,b.r),tank=tankHit(b.x,b.y,dx,dy,b.r,b.owner,b.age<.20||b.kind==='scatter'||b.kind==='rapid',b.kind==='grenade');
   if(tank&&(!wall||tank.at<=wall.t)){spendMissileRange(b,Math.hypot(dx,dy)*tank.at);b.x+=dx*tank.at;b.y+=dy*tank.at;if(b.kind==='grenade')detonate(b);else{b.dead=true;if(b.kind==='homing'||b.kind==='cannon')impactEffect(b.x,b.y,b.color,b.kind==='cannon'?32:25);hurt(tank.tank,b);}break;}
   if(wall){b.x+=dx*wall.t;b.y+=dy*wall.t;spendMissileRange(b,Math.hypot(dx,dy)*wall.t);
    missileWallNudge(b,wall);remaining*=1-wall.t;burst(b.x,b.y,b.color,2,36);
    if(time-lastBounceSound>.07){tone(650,420,.045,.009);lastBounceSound=time;}
    if((b.kind!=='homing'&&b.kind!=='rapid'&&b.bounces>22)||b.bounces>128){if(b.kind==='grenade')detonate(b);else b.dead=true;}
   }else{b.x+=dx;b.y+=dy;spendMissileRange(b,Math.hypot(dx,dy));remaining=0;}
  }
  if(!b.dead&&(b.life<=1e-9||(b.kind==='homing'&&b.rangeLeft<=1e-7))){if(b.kind==='grenade')detonate(b);else{b.dead=true;if(b.kind==='homing')impactEffect(b.x,b.y,b.color,20);else burst(b.x,b.y,b.color,3,25);}}
  if(b.x<-15||b.x>W+15||b.y<-15||b.y>H+15)b.dead=true;
 }
 compactNotDead(bullets);
}
// Prediction is used by bots and the player's short aiming guide.
function shotPrediction(t,angle,maxBounces=1,maxLength=CELL*7){let x=t.x,y=t.y,ux=Math.cos(angle),uy=Math.sin(angle),remaining=maxLength;const points=[{x,y}];for(let bounce=0;bounce<=maxBounces;bounce++){const dx=ux*remaining,dy=uy*remaining,w=rayWalls(x,y,dx,dy,3.5);let closest=null;for(const other of tanks){if(!other.alive||!canDamage(t.id,other)||(other.id===t.id&&(bounce===0||t.power==='scatter'||t.power==='rapid')))continue;const at=circleHit(x,y,dx,dy,other.x,other.y,other.r+2);if(at!==null&&(!w||at<w.t)&&(!closest||at<closest.at))closest={at,tank:other};}if(closest){points.push({x:x+dx*closest.at,y:y+dy*closest.at});return{tank:closest.tank,points};}const f=w?w.t:1;x+=dx*f;y+=dy*f;points.push({x,y});remaining*=1-f;if(!w||remaining<1)break;if(w.nx)ux=-ux;if(w.ny)uy=-uy;x+=w.nx*.12;y+=w.ny*.12;}return{tank:null,points};}

function humanControl(t,dt){
 const single=mode==='solo'||mode==='room'&&!secondLocal(),p1=mode==='room'?t.localIndex!==1:t.id===0,n=speedCount(t),speedScale=1+BOOST_SPEED_PER_STACK*n,turnScale=1+BOOST_TURN_PER_STACK*n;
 const forward=heldAction(p1?0:1,'forward');
 const reverse=heldAction(p1?0:1,'reverse');
 const left=heldAction(p1?0:1,'left');
 const right=heldAction(p1?0:1,'right');
 let throttle=(forward?1:0)-(reverse?.72:0);
 if(p1&&stick.mag>.10){const desired=Math.atan2(stick.y,stick.x),diff=angleDelta(t.angle,desired);t.angle+=clamp(diff,-5.8*turnScale*dt,5.8*turnScale*dt);throttle=stick.mag*Math.max(0,Math.cos(diff));}else t.angle+=((right?1:0)-(left?1:0))*3.65*turnScale*dt;
 const speed=128*speedScale;moveTank(t,Math.cos(t.angle)*speed*throttle*dt,Math.sin(t.angle)*speed*throttle*dt);
 const held=p1?primaryFireHeld():heldAction(1,'fire');
 const pressed=firePresses.delete(t.id)||(held&&!t.fireHeld);t.fireHeld=held;
 weaponControl(t,held,pressed);
}
// Bots share a team: the sole human is their only target, never another bot.
// Planning is throttled; steering still runs at the fixed physics rate.
function targetMotion(enemy,lead=1){
 const vx=enemy.vx*lead,vy=enemy.vy*lead,horizon=2.5;
 const obstruction=rayWalls(enemy.x,enemy.y,vx*horizon,vy*horizon,enemy.r+.5);
 const stop=obstruction?Math.max(0,obstruction.t*horizon-.01):horizon;
 return{at:s=>({x:enemy.x+vx*Math.min(s,stop),y:enemy.y+vy*Math.min(s,stop)}),stop};
}
function leadPoint(t,enemy,d,travel=null){
 const speed=projectileSpec(t.power).speed,motion=targetMotion(enemy,d.lead);
 let seconds=travel===null?Math.max(0,distance(t,enemy)-28)/speed:travel;
 let point=motion.at(seconds);
 for(let i=0;i<3&&travel===null;i++){seconds=Math.max(0,distance(t,point)-28)/speed;point=motion.at(seconds);}
 return point;
}
// Verify the real muzzle position and wall faces, not an infinitely thin maze line.
// The target moves during bullet flight. A shot is accepted only for this human.
function evaluateBotShot(t,angle,enemy,d,maxBounces=1){
 if(!enemy||!enemy.alive||!isEnemy(t,enemy))return null;
 if(t.power==='laser'){const beam=laserTrace(t,angle);return beam.target?.id===enemy.id?{angle,target:enemy.id,flight:0,bounces:beam.bounces}:null;}
 if(t.power==='homing'){
  const b=muzzleProjectile(t,angle),direct=Math.atan2(enemy.y-t.y,enemy.x-t.x);
  return !b.bounces&&distance(t,enemy)<CELL*6&&Math.abs(angleDelta(angle,direct))<.4&&!rayWalls(t.x,t.y,enemy.x-t.x,enemy.y-t.y,b.r)?{angle,target:enemy.id,flight:distance(t,enemy)/MISSILE_SPEED,bounces:0}:null;
 }
 if(t.power==='grenade'){
  // An early detonation is an option; don't aim only at the five-second endpoint.
  for(const flight of [.4,.8,1.3,2,3.5,GRENADE_FUSE]){
   const b=grenadeForecast(muzzleProjectile(t,angle),flight),p=targetMotion(enemy,d.lead).at(flight);
   if(distance(b,p)<BLAST_RADIUS+enemy.r-5&&!rayWalls(b.x,b.y,p.x-b.x,p.y-b.y,0))return{angle,target:enemy.id,flight,bounces:b.bounces};
  }return null;
 }
 const spec=projectileSpec(t.power),speed=spec.speed,r=spec.r,piercing=t.power==='cannon';
 if(piercing)maxBounces=22;
 const launch=piercing?Math.max(28,t.r+spec.r+1):28;
 let ux=Math.cos(angle),uy=Math.sin(angle),x=t.x+ux*launch,y=t.y+uy*launch;
 let remaining=piercing?speed*spec.life:t.power==='rapid'?(W+H)/2:CELL*7,elapsed=0,bounces=0;
 const muzzle=projectileWall(t.power,t.x,t.y,ux*launch,uy*launch,r);
 if(muzzle){x=t.x+ux*launch*muzzle.t+muzzle.nx*.12;y=t.y+uy*launch*muzzle.t+muzzle.ny*.12;if(muzzle.nx)ux=-ux;if(muzzle.ny)uy=-uy;bounces++;}
 const motion=targetMotion(enemy,d.lead);
 for(let part=0;part<(piercing?24:3)&&bounces<=maxBounces&&remaining>1;part++){
  const w=projectileWall(t.power,x,y,ux*remaining,uy*remaining,r),length=remaining*(w?w.t:1),duration=length/speed;
  // Split where predicted motion stops against a wall, so collision timing stays consistent.
  const cuts=[0];if(motion.stop>elapsed&&motion.stop<elapsed+duration)cuts.push(motion.stop-elapsed);cuts.push(duration);
  for(let i=1;i<cuts.length;i++){
   const start=cuts[i-1],span=cuts[i]-start,p=motion.at(elapsed+start),q=motion.at(elapsed+cuts[i]);
   const at=circleHit(x+ux*speed*start-p.x,y+uy*speed*start-p.y,ux*speed*span-(q.x-p.x),uy*speed*span-(q.y-p.y),0,0,enemy.r+r-1.2);
   if(at!==null)return{angle,target:enemy.id,flight:elapsed+start+span*at,bounces};
  }
  if(!w)break;
  x+=ux*length+w.nx*.12;y+=uy*length+w.ny*.12;elapsed+=duration;remaining-=length;
  if(w.nx)ux=-ux;if(w.ny)uy=-uy;bounces++;
 }
 return null;
}
function findBankAim(t,enemy,d=DIFFICULTY[difficulty]){
 const nearby=walls.filter(w=>Math.hypot(clamp(t.x,w.x,w.x+w.w)-t.x,clamp(t.y,w.y,w.y+w.h)-t.y)<CELL*3)
  .sort((a,b)=>Math.hypot(a.x-t.x,a.y-t.y)-Math.hypot(b.x-t.x,b.y-t.y)).slice(0,24);
 let best=null;
 for(const w of nearby){
  // The bullet reflects at an expanded rectangle face (including its own radius).
  const r=t.power==='laser'?LASER_RADIUS:3.5,face=w.axis==='v'?(t.x<w.x?w.x-r:w.x+w.w+r):(t.y<w.y?w.y-r:w.y+w.h+r);
  let p={x:enemy.x,y:enemy.y},a=0;
  for(let i=0;i<3;i++){
   const mirror=w.axis==='v'?{x:2*face-p.x,y:p.y}:{x:p.x,y:2*face-p.y};
   a=Math.atan2(mirror.y-t.y,mirror.x-t.x);
   p=t.power==='laser'?{x:enemy.x,y:enemy.y}:leadPoint(t,enemy,d,Math.max(0,distance(t,mirror)-28)/projectileSpec(t.power).speed);
  }
  const result=evaluateBotShot(t,a,enemy,d,1);
  if(result&&result.bounces>0){const cost=result.flight+Math.abs(angleDelta(t.angle,a))*.18;if(!best||cost<best.cost)best={angle:a,cost};}
 }
 return best?best.angle:null;
}
function chooseBotAim(t,enemy,d){
 if(t.power==='laser'){
  const direct=Math.atan2(enemy.y-t.y,enemy.x-t.x);if(evaluateBotShot(t,direct,enemy,d,0))return direct+rnd(-d.aim,d.aim);
  if(d.bank&&t.ai.bankClock<=0){t.ai.bankClock=.65;t.ai.bankAim=findBankAim(t,enemy,d);}
  return d.bank&&t.ai.bankAim!==null&&evaluateBotShot(t,t.ai.bankAim,enemy,d,1)?t.ai.bankAim:null;
 }
 const a=t.ai,p=leadPoint(t,enemy,d,t.power==='grenade'?GRENADE_FUSE:null),direct=Math.atan2(p.y-t.y,p.x-t.x);
 const options=[direct,Math.atan2(enemy.y-t.y,enemy.x-t.x)];
 if(a.aim!==null)options.push(a.aim);
 if(t.power==='grenade')options.push(direct-.25,direct+.25);
 if(!['homing','grenade','cannon'].includes(t.power)&&d.bank&&a.bankClock<=0){a.bankClock=(t.difficulty||difficulty)==='hard'?.42:.65;a.bankAim=findBankAim(t,enemy,d);}
 if(!['homing','grenade','cannon'].includes(t.power)&&d.bank&&a.bankAim!==null)options.push(a.bankAim);
 let best=null;
 for(const angle of options){const result=evaluateBotShot(t,angle,enemy,d,d.bank?1:0);if(!result)continue;
  const cost=result.flight+result.bounces*.28+Math.abs(angleDelta(t.angle,angle))*.2;
  if(!best||cost<best.cost)best={angle,cost};
 }
 if(!best)return null;
 return best.angle+rnd(-d.aim,d.aim);
}
// Weighted A*: allies reserve their route, encouraging a second approach when
// the maze offers one. Only the player's position is a goal; no pickup detours.
function planBotPath(t,enemy){
 const from=cellAt(t.x,t.y),goal=cellAt(enemy.x,enemy.y),a=pathScratch(t.ai);
 if(from===goal){a.pathScratch.length=0;return a.pathScratch;}
 const ally=tanks.find(o=>o.alive&&o.id!==t.id&&!isEnemy(t,o)),allyCell=ally?cellAt(ally.x,ally.y):-1;
 const reserved=a.pathReserved,danger=a.pathDanger,cost=a.pathCost,prev=a.pathPrev,closed=a.pathClosed,open=a.pathOpen;
 reserved.fill(0);danger.fill(0);cost.fill(Infinity);prev.fill(-1);closed.fill(0);open.length=0;
 if(ally)for(const cell of ally.ai.path)if(cell>=0&&cell<reserved.length)reserved[cell]=1;
 for(const b of bullets){if(!b.dead&&canDamage(b.owner,t)){
  danger[cellAt(b.x,b.y)]=1;const hit=projectileWall(b.kind,b.x,b.y,b.vx*.42,b.vy*.42,b.r),f=hit?hit.t:1;
  danger[cellAt(b.x+b.vx*.42*f,b.y+b.vy*.42*f)]=1;
 }}
 cost[from]=0;open.push(from);
 const heuristic=i=>Math.abs(i%cols-goal%cols)+Math.abs(Math.floor(i/cols)-Math.floor(goal/cols));
 while(open.length){let chosen=0;for(let k=1;k<open.length;k++)if(cost[open[k]]+heuristic(open[k])<cost[open[chosen]]+heuristic(open[chosen]))chosen=k;
  const at=open[chosen];for(let k=chosen+1;k<open.length;k++)open[k-1]=open[k];open.length--;if(closed[at])continue;if(at===goal)break;closed[at]=1;
  for(const next of grid[at].neighbors){
   const teamPenalty=ally&&next!==goal&&reserved[next]?(t.id>ally.id?1.65:.32):0;
   const nextCost=cost[at]+1+teamPenalty+(danger[next]?1.8:0)+(ally&&allyCell===next?.8:0);
   if(nextCost>=cost[next])continue;cost[next]=nextCost;prev[next]=at;open.push(next);
  }
 }
 if(prev[goal]<0)return bfs(from,goal,a);
 return tracePath(from,goal,prev,a);
}
function routeControl(t,enemy){
 const a=t.ai;
 while(a.path.length&&distance(t,center(a.path[0]))<10)a.path.shift();
 if(!a.path.length)return{angle:Math.atan2(enemy.y-t.y,enemy.x-t.x),drive:distance(t,enemy)>CELL*.9?.8:0};
 let point=center(a.path[0]);
 // Skip a waypoint only if the full tank fits through the shortcut.
 for(let i=1;i<Math.min(a.path.length,4);i++){
  const next=center(a.path[i]);if(rayWalls(t.x,t.y,next.x-t.x,next.y-t.y,t.r+2))break;point=next;
 }
 const here=center(cellAt(t.x,t.y));
 if(rayWalls(t.x,t.y,point.x-t.x,point.y-t.y,t.r+1)&&distance(t,here)>5)point=here;
 let angle=Math.atan2(point.y-t.y,point.x-t.x),drive=1;
 const ally=tanks.find(o=>o.alive&&o.id!==t.id&&!isEnemy(t,o)&&distance(t,o)<CELL*.95);
 if(ally){
  const parallel=Math.cos(angleDelta(t.angle,ally.angle))>.25;
  const side=parallel?(t.id<ally.id?1:-1):1;
  const shifted={x:point.x-Math.sin(angle)*18*side,y:point.y+Math.cos(angle)*18*side};
  if(!rayWalls(t.x,t.y,shifted.x-t.x,shifted.y-t.y,t.r+.6))angle=Math.atan2(shifted.y-t.y,shifted.x-t.x);
  else if(distance(t,ally)<t.r*2+8&&Math.cos(Math.atan2(ally.y-t.y,ally.x-t.x)-angle)>.7)drive=.15;
 }
 return{angle,drive};
}
// Short, wall-aware projectile forecasts. Friendly bot rounds are never threats.
function forecastThreats(t,horizon){
 const segments=[];
 for(const b of bullets){if(b.dead||!canDamage(b.owner,t)||(['scatter','rapid'].includes(b.kind)&&b.owner===t.id)||distance(t,b)>Math.hypot(b.vx,b.vy)*horizon+140)continue;
  if(b.kind==='grenade')continue; // Body avoidance is separate; do not flee the entire blast radius.

  if(b.kind==='homing'){
   const p={...b,rangeLeft:b.rangeLeft??W+H};const duration=Math.min(horizon,b.life);
   for(let start=0;start<duration&&p.rangeLeft>1e-7;){
    const dt=Math.min(1/60,duration-start,p.rangeLeft/MISSILE_SPEED);p.age+=dt;steerMissile(p,dt);
    let rest=dt,elapsed=0;
    for(let i=0;i<4&&rest>1e-5&&p.rangeLeft>1e-7;i++){
     rest=Math.min(rest,p.rangeLeft/MISSILE_SPEED);const w=rayWalls(p.x,p.y,p.vx*rest,p.vy*rest,p.r),span=rest*(w?w.t:1);
     segments.push({x:p.x,y:p.y,vx:p.vx,vy:p.vy,start:start+elapsed,end:start+elapsed+span,r:p.r});
     p.x+=p.vx*span;p.y+=p.vy*span;spendMissileRange(p,Math.hypot(p.vx,p.vy)*span);elapsed+=span;rest-=span;
     if(!w)break;missileWallNudge(p,w);
    }
    start+=dt;
   }continue;
  }
  let x=b.x,y=b.y,vx=b.vx,vy=b.vy,start=0,left=Math.min(horizon,b.life);
  for(let step=0;step<4&&left>.001;step++){
   const w=projectileWall(b.kind,x,y,vx*left,vy*left,b.r),span=left*(w?w.t:1);
   segments.push({x,y,vx,vy,start,end:start+span,r:b.r});
   if(!w)break;x+=vx*span+w.nx*.12;y+=vy*span+w.ny*.12;if(w.nx)vx=-vx;if(w.ny)vy=-vy;left-=span;start+=span;
  }
 }
 return segments;
}
function movementRisk(t,angle,drive,d,segments,horizon){
 let x=t.x,y=t.y,heading=t.angle,risk=0,moved=0;const step=horizon/8;
 for(let k=0;k<8;k++){
  const start=k*step,end=start+step,diff=angleDelta(heading,angle);heading+=clamp(diff,-d.turn*step,d.turn*step);
  const speed=d.speed*drive*Math.max(0,Math.cos(diff)),dx=Math.cos(heading)*speed*step,dy=Math.sin(heading)*speed*step;
  const wall=movementWall(t.ghostTime>end,x,y,dx,dy,t.r+.5),f=wall?Math.max(0,wall.t-.01):1,nx=x+dx*f,ny=y+dy*f;
  for(const s of segments){const lo=Math.max(start,s.start),hi=Math.min(end,s.end);if(hi<=lo)continue;
   if(s.blast){const f=clamp((s.start-start)/step,0,1),px=x+(nx-x)*f,py=y+(ny-y)*f;if(Math.hypot(px-s.x,py-s.y)<s.r+t.r&&!rayWalls(s.x,s.y,px-s.x,py-s.y,0))risk+=2000;continue;}
   const f0=(lo-start)/step,f1=(hi-start)/step;
   const rx=x+(nx-x)*f0-s.x-s.vx*(lo-s.start),ry=y+(ny-y)*f0-s.y-s.vy*(lo-s.start);
   const rdx=(nx-x)*(f1-f0)-s.vx*(hi-lo),rdy=(ny-y)*(f1-f0)-s.vy*(hi-lo),den=rdx*rdx+rdy*rdy;
   const closest=den?clamp(-(rx*rdx+ry*rdy)/den,0,1):0,clearance=Math.hypot(rx+rdx*closest,ry+rdy*closest)-(t.r+s.r);
   if(clearance<0)risk+=1400+(horizon-lo)*600;else if(clearance<11)risk+=(11-clearance)*9;
  }
  moved+=Math.hypot(nx-x,ny-y);x=nx;y=ny;
 }
 for(const ally of tanks){if(ally.id!==t.id&&ally.alive&&!isEnemy(t,ally)&&Math.hypot(x-ally.x,y-ally.y)<t.r+ally.r+2)risk+=90;}
 return{risk,moved};
}

function forecastGrenadeBodies(t,d,horizon){
 const segments=[];
 for(const b of bullets){
  if(b.dead||b.kind!=='grenade'||b.life<=0)continue;
  if(b.owner!==t.id&&!canDamage(b.owner,t))continue; // harmless friendly grenade when FF is off
  const reach=d.speed*horizon+Math.hypot(b.vx,b.vy)*horizon+t.r+b.r+GRENADE_AVOID_PADDING+24;
  if(distance(t,b)>reach)continue;
  const p={...b};let elapsed=0;
  while(elapsed<horizon-1e-9&&p.life>1e-9){
   const dt=Math.min(1/30,horizon-elapsed,p.life),before=p.life;p.life=Math.max(0,p.life-dt);
   const drag=grenadeDragFactor(before,p.life);p.vx*=drag;p.vy*=drag;let rest=dt,segmentStart=elapsed;
   for(let step=0;step<4&&rest>1e-6;step++){
    const dx=p.vx*rest,dy=p.vy*rest,w=rayWalls(p.x,p.y,dx,dy,p.r),fraction=w?w.t:1,span=rest*fraction;
    segments.push({x:p.x,y:p.y,vx:p.vx,vy:p.vy,start:segmentStart,end:segmentStart+span,r:p.r+GRENADE_AVOID_PADDING});
    p.x+=dx*fraction;p.y+=dy*fraction;segmentStart+=span;rest-=span;
    if(!w)break;p.x+=w.nx*.08;p.y+=w.ny*.08;if(w.nx)p.vx=-p.vx;if(w.ny)p.vy=-p.vy;
   }
   elapsed+=dt;
  }
 }
 return segments;
}
function chooseGrenadeAvoid(t,control,d){
 const horizon=(t.difficulty||difficulty)==='hard'?.85:.7,segments=forecastGrenadeBodies(t,d,horizon);if(!segments.length)return null;
 const baseline=movementRisk(t,control.angle,control.drive,d,segments,horizon);if(baseline.risk<20)return null;
 let nearest=segments[0],nearestDist=distance(t,nearest);for(let i=1;i<segments.length;i++){const s=segments[i],n=distance(t,s);if(n<nearestDist){nearest=s;nearestDist=n;}}
 const away=Math.atan2(t.y-nearest.y,t.x-nearest.x),cross=Math.hypot(nearest.vx,nearest.vy)>5?Math.atan2(nearest.vy,nearest.vx)+Math.PI/2:away+Math.PI/2;
 const options=[{...control},{angle:control.angle,drive:0},{angle:t.angle,drive:-.7},{angle:away,drive:1},{angle:cross,drive:1},{angle:cross+Math.PI,drive:1},{angle:control.angle+.8,drive:1},{angle:control.angle-.8,drive:1}];
 let best=options[0],cost=baseline.risk;
 for(const option of options.slice(1)){const result=movementRisk(t,option.angle,option.drive,d,segments,horizon);let score=result.risk+Math.abs(angleDelta(control.angle,option.angle))*3+(option.drive===0?4:0)-Math.min(result.moved,55)*.03;if(score<cost){cost=score;best=option;}}
 return cost<baseline.risk-5?best:null;
}
function chooseDodge(t,control,d){
 const horizon=d.dodgeLook,segments=forecastThreats(t,horizon);if(!segments.length)return null;
 const baseline=movementRisk(t,control.angle,control.drive,d,segments,horizon);if(baseline.risk<35)return null;
 const s=segments.reduce((a,b)=>distance(t,a)<distance(t,b)?a:b),cross=Math.atan2(s.vy,s.vx)+Math.PI/2;
 const options=[{...control},{angle:t.angle,drive:-.8},{angle:t.angle,drive:1},{angle:control.angle,drive:0},
  {angle:cross,drive:1},{angle:cross+Math.PI,drive:1},{angle:control.angle+.8,drive:1},{angle:control.angle-.8,drive:1}];
 let best=options[0],cost=Infinity;
 for(const option of options){const result=movementRisk(t,option.angle,option.drive,d,segments,horizon);
  const score=result.risk+Math.abs(angleDelta(control.angle,option.angle))*4+(option.drive===0?8:0)-Math.min(result.moved,60)*.05;
  if(score<cost){cost=score;best=option;}
 }
 return cost<baseline.risk-10?best:null;
}
function botControl(t,dt){
 const a=t.ai,difficultyKey=t.difficulty||difficulty,base=DIFFICULTY[difficultyKey],n=speedCount(t);
 let d=base;
 if(n){const tuneKey=difficultyKey+':'+n;if(a.tuneKey!==tuneKey){a.tuneKey=tuneKey;a.tune={...base,speed:base.speed*(1+BOOST_SPEED_PER_STACK*n),turn:base.turn*(1+BOOST_TURN_PER_STACK*n)};}d=a.tune;}
 let enemy=null,bestEnemy=Infinity;
 for(const o of tanks){if(!o.alive||!isEnemy(t,o))continue;const cost=distance(t,o)*(o.id===a.target?.85:1);if(cost<bestEnemy){bestEnemy=cost;enemy=o;}}
 const objective=objectiveGoal(t);if(!enemy&&!objective){a.target=-1;a.aim=null;a.path=[];return;}
 if(!enemy)enemy={...objective,id:-1,alive:false,invulnerable:1,vx:0,vy:0,r:RADIUS};
 a.target=enemy.id;
 a.think-=dt;a.pathClock-=dt;a.shotClock-=dt;a.bankClock-=dt;a.dodgeTime-=dt;a.dodgeClock-=dt;a.recoverTime-=dt;
 if(a.think<=0){
  a.think=d.think*rnd(.9,1.1);
  if(enemy.invulnerable<=0&&ownedGrenades(t).some(b=>distance(b,enemy)<=BLAST_RADIUS+enemy.r-5&&!rayWalls(b.x,b.y,enemy.x-b.x,enemy.y-b.y,0))){detonateOwned(t);a.shotClock=Math.max(.25,d.reaction);}
  if(!enemy.alive&&!objective){a.aim=null;return;}
  a.aim=enemy.alive?chooseBotAim(t,enemy,d):null;
  const goal=cellAt((objective||enemy).x,(objective||enemy).y);
  if(t.ghostTime<=0&&(a.pathClock<=0||goal!==a.goal||!a.path.length)){a.pathClock=.55+(t.id%2)*.06;a.goal=goal;a.path=objective?bfs(cellAt(t.x,t.y),goal,a):planBotPath(t,enemy);}
 }
 let control;
 if(a.aim!==null&&(!objective||distance(t,objective)<26||(Math.floor(time*2)+t.id)%5===0&&distance(t,enemy)<CELL*2)){const range=distance(t,enemy);control={angle:a.aim,drive:range<CELL*.95?-.65:range>CELL*2.7?.42:0};}
 else if(t.ghostTime>0){const dest=objective||enemy;control={angle:Math.atan2(dest.y-t.y,dest.x-t.x),drive:distance(t,dest)>12?1:0};}
 else control=objective?objectiveRoute(t,objective):routeControl(t,enemy);
 if(d.dodge&&a.dodgeClock<=0){a.dodgeClock=(t.difficulty||difficulty)==='hard'?.10:.16;const dodge=chooseDodge(t,control,d);
  if(dodge){a.dodgeAngle=dodge.angle;a.dodgeDrive=dodge.drive;a.dodgeTime=.24;}
 }
 if(a.dodgeTime>0)control={angle:a.dodgeAngle,drive:a.dodgeDrive};
 if(a.recoverTime>0)control={angle:a.recoverAngle,drive:a.recoverDrive};
 const grenadeAvoid=chooseGrenadeAvoid(t,control,d);if(grenadeAvoid)control=grenadeAvoid;
 const diff=angleDelta(t.angle,control.angle);t.angle+=clamp(diff,-d.turn*dt,d.turn*dt);
 const throttle=control.drive*Math.max(0,Math.cos(diff));
 moveTank(t,Math.cos(t.angle)*d.speed*throttle*dt,Math.sin(t.angle)*d.speed*throttle*dt);
 // A final prediction at the barrel's actual angle prevents blind firing mid-turn.
 if(a.aim!==null&&a.shotClock<=0&&a.recoverTime<=0&&enemy.invulnerable<=.05&&!ownedGrenades(t).length){
  a.shotClock=.09;
  if(Math.abs(angleDelta(t.angle,a.aim))<.13&&evaluateBotShot(t,t.angle,enemy,d,d.bank?1:0)){
   if(fire(t))a.shotClock=t.power==='rapid'?0:d.reaction*rnd(.9,1.15);
  }
 }
 if(Math.abs(throttle)>.25&&Math.hypot(t.x-a.lastX,t.y-a.lastY)<.12)a.stuck+=dt;else a.stuck=Math.max(0,a.stuck-dt*1.5);
 if(a.stuck>.55){
  a.pathClock=0;a.aim=null;a.bankAim=null;a.recoverTime=.38;a.stuck=0;
  const back=rayWalls(t.x,t.y,-Math.cos(t.angle)*30,-Math.sin(t.angle)*30,t.r+1);
  a.recoverAngle=back?Math.atan2(center(cellAt(t.x,t.y)).y-t.y,center(cellAt(t.x,t.y)).x-t.x):t.angle;
  a.recoverDrive=back?1:-.8;
 }
 a.lastX=t.x;a.lastY=t.y;
}

function finishRound(winner){
 if(phase!=='playing')return;
 if(mode==='solo'&&winner>0)winner=1;
 roundWinner=winner;phase='roundOver';phaseTime=2.7;clearInput();
 if(winner>=0){scores[winner]++;if(mode==='room'){const winning=tanks.find(t=>t.id===winner);if(winning?.team>0)for(const t of tanks)if(t.team===winning.team)scores[t.id]=scores[winner];}if(mode==='solo'&&winner===1)scores[2]=scores[1];
  addLog(winnerName(winner)+' wins round '+round+'.');tone(430,550,.12,.04,'triangle');tone(650,800,.19,.04,'triangle',.13);
 }else{addLog('Round '+round+' is a draw. No points.');tone(230,160,.25,.04,'triangle');}
 updateHUD(true);
}
function finishMatch(winner){finishLocalMatchStats(winner);if(mode==='room'){const winning=tanks.find(t=>t.id===winner),me=controlledTank();if(winning&&me&&teamKey(winning)===teamKey(me)){bestWins++;save('wins',bestWins);$('recordLabel').textContent=bestWins+' MATCH WIN'+(bestWins===1?'':'S')+' ON THIS DEVICE';}phase='matchOver';roundWinner=winner;clearInput();setScreen('room');renderOnlineRoom();$('announcer').hidden=true;updateHUD(true);showVictory(winner);return;}phase='matchOver';setScreen('match');$('announcer').hidden=true;const won=winner===0;$('matchTitle').innerHTML=mode==='duel'?`PLAYER ${winner+1}<br><em>WINS.</em>`:won?'CLEAN<br><em>VICTORY.</em>':'GOOD<br><em>FIGHT.</em>';$('matchSubtitle').textContent=mode==='duel'?'One keyboard. One champion. Time for a rematch?':won?'You ruled the maze. The ricochets were on your side.':winnerName(winner)+' takes the arena. Another round of revenge?';$('matchResults').replaceChildren(...scoreboardEntries().map(t=>{const d=document.createElement('div');d.className='match-result';const name=document.createElement('span');name.style.color=paintColor(t.color);name.textContent=t.name;const score=document.createElement('strong');score.textContent=scores[t.id];score.style.color=paintColor(t.color);d.append(name,score);return d;}));if(won){bestWins++;save('wins',bestWins);$('recordLabel').textContent=bestWins+' MATCH WIN'+(bestWins===1?'':'S')+' ON THIS DEVICE';}clearInput();$('rematchBtn').focus({preventScroll:true});updateHUD();}
function update(dt){
 if(mode==='online'){onlineUpdate(dt);return;}
 fxTime+=dt;
 if(phase==='paused'||phase==='menu'||phase==='matchOver')return;
 updateTraces(dt);
 time+=dt;phaseTime-=dt;
 if(toastTime>0){toastTime-=dt;if(toastTime<=0)$('toast').hidden=true;}
 const drag=Math.exp(-3*dt);for(const p of particles){p.life-=dt;p.x+=p.vx*dt;p.y+=p.vy*dt;p.vx*=drag;p.vy*=drag;}compactLife(particles);for(const r of rings)r.life-=dt;compactLife(rings);shake=Math.max(0,shake-dt);
 if(phase==='countdown'){if(phaseTime<=0){phase='playing';phaseTime=.55;goUntil=performance.now()+550;tone(800,950,.15,.04);if(round===1)showStartingControls();}uiClock-=dt;if(uiClock<=0){updateHUD();uiClock=.08;}return;}
 if(phase==='roundOver'){if(phaseTime<=0){if(roundWinner>=0&&scores[roundWinner]>=currentRules().scoreTarget)finishMatch(roundWinner);else{round++;startRound();}}uiClock-=dt;if(uiClock<=0){updateHUD();uiClock=.08;}return;}
 if(objectiveMode()&&!suddenDeath()){
  if(roundClock<=0){const leader=objectiveLeader();if(leader>=0)endLocalObjective(leader);else beginLocalSuddenDeath();return;}
  dt=Math.min(dt,roundClock);
 }
 if(liveLocalStats())localMatchStats.duration+=dt;
 roundClock=Math.max(0,roundClock-dt);spawnClock-=dt;if(spawnClock<=0){spawnPower();spawnClock=rnd(...pickupInterval());}
 if(objectiveMode())respawnLocalPlayers(dt);
 for(const t of tanks){if(!t.alive)continue;t.cooldown=Math.max(0,t.cooldown-dt);t.invulnerable=Math.max(0,t.invulnerable-dt);t.shield=Math.max(0,t.shield-dt);if(t.shield<=0)t.shieldCharges=0;t.scopeTime=Math.max(0,(t.scopeTime||0)-dt);t.speedTime=Math.max(0,(t.speedTime||0)-dt);if(t.speedTime<=0)t.speedStacks=0;advanceGhost(t,dt);t.recoil=Math.max(0,t.recoil-dt*9);if(t.power){t.powerTime-=dt;if(t.powerTime<=0){t.power=null;t.powerTime=0;}}
  const x=t.x,y=t.y;if(t.human)humanControl(t,dt);else botControl(t,dt);t.vx=(t.x-x)/dt;t.vy=(t.y-y)/dt;t.track+=Math.hypot(t.x-x,t.y-y);
 }
 for(let i=0;i<tanks.length;i++)for(let j=i+1;j<tanks.length;j++){const a=tanks[i],b=tanks[j];if(!a.alive||!b.alive)continue;let dx=b.x-a.x,dy=b.y-a.y,dist=Math.hypot(dx,dy);const over=a.r+b.r-dist;if(over>0){if(dist<.001){dx=1;dy=0;dist=1;}moveTank(a,-dx/dist*over*.5,-dy/dist*over*.5);moveTank(b,dx/dist*over*.5,dy/dist*over*.5);}}
 updateBullets(dt);
 for(const p of pickups){p.age+=dt;p.life-=dt;if(p.life<=0)continue;for(const t of tanks){if(t.alive&&distance(t,p)<t.r+13){p.life=0;const def=POWER[p.type];grantPower(t,p.type);addRing(p.x,p.y,def.color,44);burst(p.x,p.y,def.color,13,90);pickupSound();const localIndex=localPilotIndex(t.id);if(localIndex>=0)setPilotFeedback(localIndex,pickupMessage(p.type),2.5);addLog(t.name+' picked up '+def.name.toLowerCase()+'.');break;}}}compactLife(pickups);
 if(mode==='room'&&objectiveMode()){stepLocalObjectives(dt);}
  else if(mode==='room'){
   let owner=null,winner=-1,multiple=false;for(const t of tanks){if(!t.alive)continue;const side=teamKey(t);if(owner===null){owner=side;winner=t.id;}else if(side!==owner){multiple=true;break;}}
   if(!multiple)finishRound(winner);else if(roundClock<=0)finishRound(-1);
  }else if(mode==='solo'){
   let playerAlive=false,botsAlive=false;for(const t of tanks)if(t.alive){if(t.human)playerAlive=true;else botsAlive=true;}
   if(!playerAlive||!botsAlive)finishRound(playerAlive?0:botsAlive?1:-1);else if(roundClock<=0)finishRound(-1);
  }else{
   let liveCount=0,winner=-1;for(const t of tanks)if(t.alive){liveCount++;winner=t.id;if(liveCount>1)break;}
   if(liveCount<=1)finishRound(winner);else if(roundClock<=0)finishRound(-1);
  }
 uiClock-=dt;if(uiClock<=0){updateHUD();uiClock=.08;}
}
function tankSvg(){return '<svg viewBox="0 0 28 28" fill="none" aria-hidden="true"><path d="M6 10v12m16-12v12" stroke="currentColor" stroke-width="4" stroke-linecap="round"/><rect x="10" y="9" width="8" height="14" rx="2" fill="currentColor"/><path d="M14 4v10" stroke="currentColor" stroke-width="3" stroke-linecap="round"/><circle cx="14" cy="16" r="2.7" fill="#182229"/></svg>';}
let lastRoster='';
function renderPilotLoadout(player,num,force=false){
 const suffix=num===1?'':'2',panel=$('pilotLoadout'+num),dots=$('ammoDots'+suffix);
 if(!player){panel.hidden=true;return null;}panel.hidden=false;
 const rosterPilot=roomData()?.players.find(p=>p.id===player.id);
 const name=rosterPilot?.name||player.name;panel.style.setProperty('--loadout-color',paintColor(player.color));
 setText('loadoutName'+num,name);$('loadoutName'+num).title=name;
 const capacity=powerCapacity(player),available=Math.max(0,capacity-activeAmmo(player)),key=[player.id,player.power,capacity,available,player.alive].join(':');
 if(force||dots.dataset.state!==key){
  dots.dataset.state=key;dots.innerHTML=Array.from({length:Math.min(capacity,12)},(_,i)=>`<i class="ammo-dot ${i>=Math.ceil(available/capacity*Math.min(capacity,12))||!player.alive?'empty':''}"></i>`).join('');
 }
 const quantity=player.power==='laser'?'laser charges':'active projectile slots';
 dots.setAttribute('aria-label',name+': '+(player.alive?available:0)+' of '+capacity+' '+quantity+' available');
 panel.setAttribute('aria-label','Player '+num+', '+name+', ammunition and power-ups');
 const liveGrenades=ownedGrenades(player),remoteReady=player.alive&&liveGrenades.length>0;
 const power=POWER[player.power],charges=['scatter','homing','grenade','laser','cannon'].includes(player.power)?' ×'+player.charges:'';
 const label=$('weaponLabel'+suffix);setText('weaponLabel'+suffix,!player.alive?'TANK DOWN':remoteReady?'DETONATE · '+Math.max(0,...liveGrenades.map(b=>b.life)).toFixed(1)+'s':power?(power.short||power.name)+charges+' · '+Math.ceil(player.powerTime)+'s':'STANDARD');
 label.title=label.textContent;
 label.style.color=paintColor(remoteReady?POWER.grenade.color:power?.color||player.color||COLORS[0]);
 setStyle(label,'--weapon-color',label.style.color);
 const buffs=[];if(player.shield>0)buffs.push('SHD×'+shieldCount(player)+' '+Math.ceil(player.shield)+'s');if(player.speedTime>0)buffs.push('SPD×'+speedCount(player)+' '+Math.ceil(player.speedTime)+'s');if(player.scopeTime>0)buffs.push('SCP '+Math.ceil(player.scopeTime)+'s');if(player.ghostTime>0)buffs.push('GHO '+Math.ceil(player.ghostTime)+'s');
 const buffText=buffs.length>2?buffs.map(b=>b.startsWith('SHD')?b.split(' ')[0]:b.replace(/ (\d+)s$/,'$1')).join(' '):buffs.join(' · '),feedback=pilotFeedback[num-1],feedbackText=feedback?.until>performance.now()?feedback.text:'';
 const detailText=player.alive?(feedbackText||buffText):'',detail=$('buffLabel'+suffix);setText('buffLabel'+suffix,detailText);detail.hidden=!detailText;detail.title=feedbackText||('Speed: '+speedCount(player)+' stacks, '+Math.ceil(player.speedTime||0)+'s · Shield: '+shieldCount(player)+' charges, '+Math.ceil(player.shield||0)+'s · Scope: '+Math.ceil(player.scopeTime||0)+'s · Ghost: '+Math.ceil(player.ghostTime||0)+'s');
 return {power,remoteReady};
}
function updateHUD(force=false){
 setText('arenaStatus',phase==='menu'?'READY ROOM':phase==='paused'?'PAUSED':phase==='countdown'?'GET READY':phase==='roundOver'?'ROUND COMPLETE':phase==='matchOver'?'MATCH COMPLETE':'LIVE ARENA');
 setText('roundLabel','ROUND '+String(round).padStart(2,'0'));const secs=Math.ceil(roundClock);setText('clock',String(Math.floor(secs/60)).padStart(2,'0')+':'+String(secs%60).padStart(2,'0'));$('clock').classList.toggle('urgent',secs<=15);
 const entries=scoreboardEntries();document.body.classList.toggle('many-sides',entries.length>4);const rosterKey=entries.map(t=>[t.name,t.color,t.alive,t.meta,scores[t.id]].join()).join('|');if(force||rosterKey!==lastRoster){lastRoster=rosterKey;$('roster').innerHTML=entries.map(t=>`<div class="roster-row ${!t.alive?'out':''}" style="--player:${paintColor(t.color)}"><div class="avatar">${tankSvg()}</div><div class="player-info"><div class="player-name">${escapeHTML(t.name)}</div><div class="player-meta">${escapeHTML(t.meta)}</div><div class="score-pips">${Array.from({length:Math.min(10,currentRules().scoreTarget)},(_,n)=>`<i class="${n<Math.ceil(scores[t.id]/currentRules().scoreTarget*Math.min(10,currentRules().scoreTarget))?'on':''}"></i>`).join('')}</div></div><div class="score">${scores[t.id]}</div></div>`).join('');$('miniScores').innerHTML=entries.map(t=>`<span class="mini-score" style="--player:${paintColor(t.color)};opacity:${t.alive?1:.4}" title="${escapeHTML(t.name)}" aria-label="${escapeHTML(t.name)}: ${scores[t.id]} points"><i></i>${mode==='solo'?(t.id===0?'YOU ':'BOTS '):''}${scores[t.id]}</span>`).join('');}
 const player=controlledTank(),p2=tanks.find(t=>t.id===secondaryID());
 $('localLoadouts').classList.toggle('two-pilots',!!p2);document.body.classList.toggle('two-local-pilots',!!p2);
 const state=renderPilotLoadout(player,1,force);renderPilotLoadout(p2,2,force);
 if(player&&state){const {power,remoteReady}=state;
  // Weapon button text, state and progress are written only by updateCombatFeedback().
  setText('touchStatus',phase==='menu'?'GOOD LUCK':!player.alive?'TANK DOWN':player.ghostTime>0?'GHOST ACTIVE':player.speedTime>0?'SUPER SPEED':power?(power.short||power.name):player.shield>0?'SHIELDED':player.scopeTime>0?'SCOPE ACTIVE':'STAY SHARP');
 }
 const announce=$('announcer');announce.classList.toggle('round-result',phase==='roundOver');
 if(phase==='countdown'){announce.hidden=false;setText('announceTop','ROUND '+String(round).padStart(2,'0'));const number=Math.ceil(phaseTime);if($('announceMain').textContent!==String(number)){tone(330,300,.07,.03,'triangle');}setText('announceMain',number);$('announceMain').style.color=paintColor(COLORS[0]);setText('announceSub',mode==='solo'?'You vs. the bot squad. Take out both bots.':'Last side standing takes the point.');}
 else if(phase==='playing'&&performance.now()<goUntil&&!suddenDeath()){announce.hidden=false;setText('announceTop','WEAPONS LIVE');setText('announceMain','GO');setText('announceSub','');}
 else if(phase==='roundOver'){announce.hidden=false;setText('announceTop',roundWinner>=0?'ONE POINT CLOSER':'NO POINTS AWARDED');setText('announceMain',roundWinner<0?'ROUND DRAW':mode==='solo'&&roundWinner===0?'YOU TAKE THE ROUND':winnerName(roundWinner)+' WINS');$('announceMain').style.color=paintColor(roundWinner<0?'#eff2df':(tanks.find(t=>t.id===roundWinner)?.color||COLORS[roundWinner]||COLORS[0]));setText('announceSub',roundWinner>=0&&scores[roundWinner]>=currentRules().scoreTarget?'Match complete.':'New maze in '+Math.ceil(phaseTime)+'…');}
 else announce.hidden=true;
 if(mode==='online')onlineHUD();
 updateObjectiveHUD();updateCombatFeedback(force);syncSpectatingHUD();
}
// Bounded sprite cache: only the static hull / four tread frames are cached.
// Recoil, turret, buffs, labels and missile warnings remain dynamic. There are
// normally 32 sprites (8 colors x 4 tread frames); no texture upload per frame.
const tankHullCache=new Map(),labelWidthCache=new Map();
const renderStats={hullHits:0,hullMisses:0};
let useHullCache=true;
function guideInk(color){return paintColor(color);}
function measureLabel(label){const key=ctx.font+'\0'+label;let width=labelWidthCache.get(key);if(width!==undefined)return width;width=ctx.measureText(label).width;if(labelWidthCache.size>=192)labelWidthCache.delete(labelWidthCache.keys().next().value);labelWidthCache.set(key,width);return width;}
function paintTankHull(c,t){
 const hullColor=paintColor(t.color);
 c.fillStyle='#02080ba8';roundRect(c,-20,-15+4,40,31,6);c.fill();
 for(const side of [-1,1]){c.fillStyle='#0b1116';roundRect(c,-19,side<0?-17:9,37,9,3);c.fill();c.strokeStyle='#849392';c.globalAlpha=.65;c.lineWidth=1;for(let n=0;n<7;n++){const x=-16+n*5+(Math.floor(t.track/2)%4);c.beginPath();c.moveTo(x,side<0?-16:10);c.lineTo(x,side<0?-10:16);c.stroke();}c.globalAlpha=1;}
 c.fillStyle=hullColor;roundRect(c,-17,-12,34,24,5);c.fill();c.fillStyle='#00000030';roundRect(c,-15,-10,7,20,2);c.fill();c.strokeStyle='#ffffff58';c.lineWidth=1;c.beginPath();c.moveTo(-12,-10);c.lineTo(12,-10);c.stroke();c.fillStyle='#0c151866';c.fillRect(-12,-6,3,12);

}
function drawCachedTankHull(t){
 const hullColor=paintColor(t.color);
 if(!useHullCache){paintTankHull(ctx,t);return;}
 const q=Math.max(2,Math.min(3,Math.ceil(scale*dpr))),step=((Math.floor(t.track/2)%4)+4)%4,key=hullColor+':'+step+':'+q;
 let image=tankHullCache.get(key);
 if(!image){
  image=document.createElement('canvas');image.width=image.height=48*q;const c=image.getContext('2d');
  if(!c){paintTankHull(ctx,t);return;}
  c.setTransform(q,0,0,q,24*q,24*q);paintTankHull(c,{color:hullColor,track:step*2});
  if(tankHullCache.size>=96)tankHullCache.delete(tankHullCache.keys().next().value);
  tankHullCache.set(key,image);renderStats.hullMisses++;
 }else renderStats.hullHits++;
 ctx.drawImage(image,-24,-24,48,48);
}
const tankPowerBadgeCache=new Map(),tankPowerBadgeScratch=[];
function activeTankPowerBadges(t,out=[]){
 out.length=0;
 if(t?.power&&t.powerTime>0&&POWER[t.power])out.push(t.power);
 if(shieldCount(t)>0)out.push('shield');
 if(speedCount(t)>0)out.push('speed');
 if((t?.scopeTime||0)>0)out.push('scope');
 if((t?.ghostTime||0)>0)out.push('ghost');
 return out;
}
function tankPowerBadgeImage(kind){
 let image=tankPowerBadgeCache.get(kind);if(image)return image;
 image=document.createElement('canvas');image.width=image.height=64;const c=image.getContext('2d');if(!c)return image;
 const def=POWER[kind];c.translate(32,32);c.fillStyle='#0b141be8';c.strokeStyle=def.color;c.lineWidth=3;c.beginPath();c.arc(0,0,27,0,TAU);c.fill();c.stroke();c.save();c.scale(1.38,1.38);powerIcon(kind,c);c.restore();
 if(tankPowerBadgeCache.size>=16)tankPowerBadgeCache.delete(tankPowerBadgeCache.keys().next().value);tankPowerBadgeCache.set(kind,image);return image;
}
function drawTankPowerBadges(t){
 if(!t?.alive)return;
 // Local pilots already have the full loadout HUD. Bots and remote online tanks get larger cached on-tank icons.
 const remoteOrBot=mode==='online'?(t.id!==localPlayerID()&&t.id!==secondaryID()):!t.human;if(!remoteOrBot)return;
 const kinds=activeTankPowerBadges(t,tankPowerBadgeScratch);if(!kinds.length)return;
 const z=Math.max(1,.82/Math.max(.05,scale)),size=26*z;
 // Start at the top-right corner, then move clockwise around the hull.
 const pos=[[24,-20],[24,20],[-24,20],[-24,-20],[0,-31],[32,0],[0,31],[-32,0]];
 ctx.save();for(let i=0;i<Math.min(kinds.length,pos.length);i++){const [dx,dy]=pos[i],image=tankPowerBadgeImage(kinds[i]);ctx.drawImage(image,t.x+dx*z-size/2,t.y+dy*z-size/2,size,size);}ctx.restore();
}
function drawTank(t){
 if(!t.alive){ctx.save();ctx.translate(t.x,t.y);ctx.rotate(t.angle);ctx.globalAlpha=.6;ctx.fillStyle=paintColor('#091116');roundRect(ctx,-18,-16,36,32,5);ctx.fill();ctx.strokeStyle=paintColor('#46545a');ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(-8,-8);ctx.lineTo(8,8);ctx.moveTo(8,-8);ctx.lineTo(-8,8);ctx.stroke();ctx.restore();return;}
 const inv=t.invulnerable>0;
 ctx.save();ctx.translate(t.x,t.y);
 if(t.shield>0){
  ctx.strokeStyle=paintColor(POWER.shield.color);ctx.lineWidth=1.6;
  const count=shieldCount(t),pulse=reduceMotion?0:Math.sin(fxTime*4)*.6;
  for(let ring=0;ring<count;ring++){ctx.globalAlpha=.78;ctx.beginPath();ctx.arc(0,0,26+ring*4+pulse,0,TAU);ctx.stroke();}
  ctx.globalAlpha=.035;ctx.fillStyle=paintColor(POWER.shield.color);ctx.beginPath();ctx.arc(0,0,26+Math.max(0,count-1)*4,0,TAU);ctx.fill();ctx.globalAlpha=1;
 }else if(inv){ctx.strokeStyle=paintColor(theme.protection);ctx.lineWidth=1.5;ctx.globalAlpha=.35;ctx.beginPath();ctx.arc(0,0,27,0,TAU);ctx.stroke();ctx.globalAlpha=1;}
 // Player halo keeps the controlled tank easy to find on a phone.
 if(t.id===localPlayerID()){ctx.strokeStyle=paintColor(t.color);ctx.globalAlpha=.15;ctx.lineWidth=1;ctx.setLineDash([3,6]);ctx.beginPath();ctx.arc(0,0,23,0,TAU);ctx.stroke();ctx.setLineDash([]);ctx.globalAlpha=1;}
 ctx.rotate(t.angle);
 if(t.speedTime>0){ctx.save();ctx.strokeStyle=paintColor(POWER.speed.color);ctx.lineWidth=2;ctx.globalAlpha=.65;const stacks=speedCount(t);for(let n=0;n<stacks;n++)for(const side of [-1,1]){const y=side*(8+n*2.2);ctx.beginPath();ctx.moveTo(-22,y);ctx.lineTo(-34-n*3-(reduceMotion?0:Math.sin(fxTime*22+n)*5),y);ctx.stroke();}ctx.restore();}
 if(t.ghostTime>0){ctx.save();ctx.strokeStyle=paintColor(POWER.ghost.color);ctx.lineWidth=1.5;ctx.setLineDash([3,4]);roundRect(ctx,-23,-21,46,42,9);ctx.stroke();ctx.restore();ctx.globalAlpha=.58;}
 drawCachedTankHull(t);
 const recoil=t.recoil*4;ctx.fillStyle=paintColor('#0a121a');roundRect(ctx,4-recoil,-4.5,26,9,2);ctx.fill();ctx.fillStyle=paintColor(t.color);ctx.fillRect(5-recoil,-3,23,6);ctx.fillStyle=paintColor('#e4f0d98a');ctx.fillRect(26-recoil,-3.5,3,7);
 ctx.fillStyle=paintColor('#00000042');ctx.beginPath();ctx.arc(0,2,9.5,0,TAU);ctx.fill();ctx.fillStyle=paintColor(t.color);ctx.beginPath();ctx.arc(0,0,9,0,TAU);ctx.fill();ctx.strokeStyle=paintColor('#09121970');ctx.lineWidth=2;ctx.stroke();ctx.fillStyle=paintColor('#172124');ctx.beginPath();ctx.arc(-1,0,3.2,0,TAU);ctx.fill();ctx.restore();
 drawTankPowerBadges(t);
 ctx.save();ctx.font='bold '+Math.max(9,7/scale)+'px ui-monospace,SFMono-Regular,Consolas,monospace';ctx.textAlign='center';const label=t.name;const width=measureLabel(label)+10,labelY=t.y-Math.max(40,shieldCount(t)*4+26);ctx.fillStyle=paintColor('#0e171ddb');roundRect(ctx,t.x-width/2,labelY,width,13,3);ctx.fill();ctx.fillStyle=paintColor(t.color);ctx.fillText(label,t.x,labelY+9.5);ctx.restore();
}
function powerIcon(kind,c=ctx){
 const def=POWER[kind];if(!def)return;c.fillStyle=def.color;c.strokeStyle=def.color;
 c.lineWidth=2;c.lineJoin='round';c.lineCap='round';
 if(kind==='rapid'){for(let i=0;i<3;i++){const y=-6+i*6;c.beginPath();c.moveTo(-9,y);c.lineTo(-3,y);c.stroke();c.beginPath();c.moveTo(0,y-1.7);c.lineTo(6,y-1.7);c.lineTo(9,y);c.lineTo(6,y+1.7);c.lineTo(0,y+1.7);c.closePath();c.fill();}}
 else if(kind==='scatter'){
  // Readable three-way spread: one fast shot fans into three pellets to the right.
  c.lineWidth=2.4;c.beginPath();c.moveTo(-10,0);c.lineTo(-3,0);c.lineTo(10,-7);c.moveTo(-3,0);c.lineTo(10,0);c.moveTo(-3,0);c.lineTo(10,7);c.stroke();
  c.lineWidth=1.5;c.globalAlpha=.55;c.beginPath();c.moveTo(-12,-4);c.lineTo(-7,-4);c.moveTo(-12,4);c.lineTo(-7,4);c.stroke();c.globalAlpha=1;
  for(const y of [-7,0,7]){c.beginPath();c.arc(10,y,1.35,0,TAU);c.fill();}
 }
 else if(kind==='homing'){c.beginPath();c.moveTo(0,-9);c.lineTo(4,-2);c.lineTo(3,5);c.lineTo(0,3);c.lineTo(-3,5);c.lineTo(-4,-2);c.closePath();c.stroke();c.beginPath();c.moveTo(-3,2);c.lineTo(-7,7);c.moveTo(3,2);c.lineTo(7,7);c.moveTo(0,6);c.lineTo(0,9);c.stroke();}
 else if(kind==='laser'){c.strokeRect(-10,-5,5,10);c.beginPath();c.moveTo(-5,-2);c.lineTo(6,-2);c.moveTo(-5,2);c.lineTo(6,2);c.stroke();c.beginPath();c.moveTo(6,-7);c.lineTo(6,7);c.moveTo(1,0);c.lineTo(11,0);c.moveTo(2,-5);c.lineTo(10,5);c.moveTo(2,5);c.lineTo(10,-5);c.stroke();}
 else if(kind==='grenade'){c.beginPath();c.arc(0,2,6,0,TAU);c.stroke();c.strokeRect(-2,-7,4,3);c.beginPath();c.moveTo(1,-8);c.quadraticCurveTo(6,-11,8,-5);c.stroke();c.fillRect(-1,0,2,4);}
 else if(kind==='ghost'){c.beginPath();c.moveTo(-8,9);c.lineTo(-8,-2);c.bezierCurveTo(-8,-12,8,-12,8,-2);c.lineTo(8,9);c.lineTo(4,6);c.lineTo(0,9);c.lineTo(-4,6);c.closePath();c.stroke();for(const x of [-3,3]){c.beginPath();c.arc(x,-1,1.2,0,TAU);c.fill();}}
 else if(kind==='cannon'){c.beginPath();c.arc(4,0,5,0,TAU);c.fill();c.beginPath();c.moveTo(-10,-4);c.lineTo(-5,-4);c.moveTo(-12,0);c.lineTo(-4,0);c.moveTo(-10,4);c.lineTo(-5,4);c.stroke();}
 else if(kind==='scope'){c.beginPath();c.arc(0,0,6,0,TAU);c.moveTo(-10,0);c.lineTo(-4,0);c.moveTo(4,0);c.lineTo(10,0);c.moveTo(0,-10);c.lineTo(0,-4);c.moveTo(0,4);c.lineTo(0,10);c.stroke();c.beginPath();c.arc(0,0,1.4,0,TAU);c.fill();}
 else if(kind==='speed'){for(const x of [-5,2]){c.beginPath();c.moveTo(x-2,-7);c.lineTo(x+4,0);c.lineTo(x-2,7);c.stroke();}}
 else{c.beginPath();c.moveTo(0,-8);c.lineTo(7,-5);c.lineTo(6,3);c.quadraticCurveTo(4,7,0,9);c.quadraticCurveTo(-4,7,-6,3);c.lineTo(-7,-5);c.closePath();c.stroke();}
}
function renderPowerLegend(){
 for(const icon of document.querySelectorAll('canvas[data-power-icon]')){
  const kind=icon.dataset.powerIcon,def=POWER[kind];if(!def)continue;
  const pixelRatio=Math.min(window.devicePixelRatio||1,WEBKIT_ENGINE?2:3),size=Math.round(26*pixelRatio);
  const stamp=kind+':dark';if(icon.width===size&&icon.dataset.drawn===stamp)continue;
  icon.width=icon.height=size;icon.dataset.drawn=stamp;
  icon.parentElement.style.color=paintColor(def.color);
  const c=icon.getContext('2d');if(!c)continue;
  c.setTransform(size/26,0,0,size/26,size/2,size/2);powerIcon(kind,c);
 }
}
function drawPickup(p){
 const def=POWER[p.type];if(!def)return;const pulse=reduceMotion?.5:Math.sin(fxTime*3+p.x)*.5+.5;
 ctx.save();ctx.translate(p.x,p.y);ctx.globalAlpha=p.life<3?.5+.4*Math.sin(fxTime*12):1;ctx.shadowColor=paintColor(def.color);ctx.shadowBlur=combatPrefs.performance||WEBKIT_ENGINE?0:(7+pulse*4);ctx.fillStyle=paintColor('#152126');ctx.strokeStyle=paintColor(def.color);ctx.lineWidth=1.5;roundRect(ctx,-13,-13,26,26,6);ctx.fill();ctx.stroke();ctx.shadowBlur=combatPrefs.performance?0:(0);ctx.globalAlpha*=.20;roundRect(ctx,-18-pulse,-18-pulse,36+pulse*2,36+pulse*2,9);ctx.stroke();ctx.globalAlpha=p.life<3?.7:1;ctx.fillStyle=paintColor(def.color);powerIcon(p.type);ctx.restore();
}
function drawBullet(b){
 if(b.kind==='rapid'){
  ctx.save();ctx.strokeStyle=paintColor(b.color);ctx.lineWidth=b.r*2;ctx.lineCap='round';
  const v=Math.hypot(b.vx,b.vy)||1;ctx.globalAlpha=.55;ctx.beginPath();ctx.moveTo(b.x-b.vx/v*8,b.y-b.vy/v*8);ctx.lineTo(b.x,b.y);ctx.stroke();ctx.globalAlpha=1;ctx.fillStyle=paintColor(b.color);ctx.beginPath();ctx.arc(b.x,b.y,b.r,0,TAU);ctx.fill();ctx.restore();return;
 }
 ctx.save();ctx.lineWidth=b.kind==='cannon'?12:b.kind==='homing'?4:3;ctx.lineCap='round';ctx.strokeStyle=paintColor(b.color);
 for(let i=1;i<b.trail.length;i++){ctx.globalAlpha=i/b.trail.length*.23;ctx.beginPath();ctx.moveTo(b.trail[i-1].x,b.trail[i-1].y);ctx.lineTo(b.trail[i].x,b.trail[i].y);ctx.stroke();}
 ctx.globalAlpha=1;ctx.translate(b.x,b.y);ctx.shadowColor=paintColor(b.color);ctx.shadowBlur=combatPrefs.performance||WEBKIT_ENGINE?0:12;ctx.fillStyle=paintColor(b.color);
 if(b.kind==='homing'){
  ctx.rotate(Math.atan2(b.vy,b.vx));ctx.beginPath();ctx.moveTo(10,0);ctx.lineTo(-4,-5);ctx.lineTo(-8,-8);ctx.lineTo(-6,0);ctx.lineTo(-8,8);ctx.lineTo(-4,5);ctx.closePath();ctx.fill();ctx.shadowBlur=combatPrefs.performance?0:(0);ctx.fillStyle=paintColor('#fff6e5');ctx.fillRect(-1,-1.5,6,3);
  ctx.fillStyle=paintColor(POWER.homing.color);ctx.globalAlpha=.8;ctx.beginPath();ctx.moveTo(-7,-3);ctx.lineTo(-16-(reduceMotion?0:Math.sin(fxTime*30)*4),0);ctx.lineTo(-7,3);ctx.fill();
 }else if(b.kind==='grenade'){
  ctx.fillStyle=paintColor('#253039');ctx.strokeStyle=paintColor(b.color);ctx.lineWidth=2;ctx.beginPath();ctx.arc(0,0,6,0,TAU);ctx.fill();ctx.stroke();ctx.shadowBlur=combatPrefs.performance?0:(0);
  ctx.strokeStyle=paintColor(POWER.grenade.color);ctx.beginPath();ctx.arc(0,0,10,-Math.PI/2,-Math.PI/2+TAU*clamp(b.life/GRENADE_FUSE,0,1));ctx.stroke();
  ctx.fillStyle=paintColor(b.life<.5?'#fff5da':POWER.grenade.color);ctx.beginPath();ctx.arc(0,-2,b.life<.5?3:2,0,TAU);ctx.fill();
 }else{ctx.beginPath();ctx.arc(0,0,b.r+(b.kind==='cannon'?4:1),0,TAU);ctx.fill();ctx.shadowBlur=combatPrefs.performance?0:(0);ctx.fillStyle=paintColor('#fbffe8');ctx.beginPath();ctx.arc(0,0,b.r*.6,0,TAU);ctx.fill();}
 ctx.restore();
}
function render(){
 ctx.setTransform(dpr,0,0,dpr,0,0);ctx.fillStyle=paintColor(theme.arena);ctx.fillRect(0,0,cssW,cssH);
 // Subtle registration marks in the letterbox area.
 ctx.strokeStyle=paintColor(theme.registration);ctx.lineWidth=1;const mx=offsetX-6,my=offsetY-6,mw=W*scale+12,mh=H*scale+12;for(const [x,y,sx,sy]of[[mx,my,1,1],[mx+mw,my,-1,1],[mx,my+mh,1,-1],[mx+mw,my+mh,-1,-1]]){ctx.beginPath();ctx.moveTo(x+sx*9,y);ctx.lineTo(x,y);ctx.lineTo(x,y+sy*9);ctx.stroke();}
 let sx=0,sy=0;if(shake>0){sx=rnd(-1,1)*shake*12;sy=rnd(-1,1)*shake*12;}
 ctx.translate(offsetX+sx,offsetY+sy);ctx.scale(scale,scale);if(mapCanvas)ctx.drawImage(mapCanvas,0,0,W,H);
 ctx.save();ctx.beginPath();ctx.rect(0,0,W,H);ctx.clip();
 drawObjectives();
 for(const p of pickups)drawPickup(p);
 drawAimingGuides();
 drawFlags();for(const t of tanks)drawTank(t);
 drawMissileWarnings();
 for(const b of bullets)drawBullet(b);
 drawLasers();
 for(const r of rings){const progress=1-r.life/r.maxLife;ctx.strokeStyle=paintColor(r.color);ctx.lineWidth=2*(1-progress)+.5;
  if(r.outline){ctx.save();ctx.translate(r.x,r.y);ctx.beginPath();r.outline.forEach((p,i)=>{if(i)ctx.lineTo(p.x,p.y);else ctx.moveTo(p.x,p.y);});ctx.closePath();ctx.globalAlpha=(1-progress)*.19;ctx.fillStyle=paintColor(r.color);ctx.fill();ctx.globalAlpha=(1-progress)*.75;ctx.stroke();ctx.restore();}
  else{ctx.globalAlpha=(1-progress)*.75;ctx.beginPath();ctx.arc(r.x,r.y,10+progress*r.max,0,TAU);ctx.stroke();}
 }
 for(const p of particles){ctx.globalAlpha=Math.max(0,p.life/p.max);ctx.fillStyle=paintColor(p.color);ctx.fillRect(p.x-p.size/2,p.y-p.size/2,p.size,p.size);}
 ctx.globalAlpha=1;ctx.restore();
}
function frame(now){const workStart=performance.now();if(!lastFrame)lastFrame=now;const elapsed=clamp((now-lastFrame)/1000,0,.10);lastFrame=now;
 if(mode==='online'){accumulator=0;onlineUpdate(elapsed);renderOnlineMotion(elapsed,now);}
 else{accumulator+=elapsed;let steps=0;while(accumulator>=1/120&&steps<12){update(1/120);accumulator-=1/120;steps++;}}
 updateCombatFeedback();render();sampleFrame(now,performance.now()-workStart);requestAnimationFrame(frame);}
// Online play: the server owns the world. This client sends controls only.
// Remote entities interpolate snapshots; the local tank predicts movement and
// reconciles to authoritative positions. Predictions never award hits or points.
function setNetStatus(text,error=false){$('netStatus').textContent=text;$('netStatus').classList.toggle('error',error);}
function netBusy(busy){$('createRoomBtn').disabled=busy;$('joinRoomBtn').disabled=busy;}
const MAX_ROOM_RUNES=128;
function cleanRoomCode(value){
 const code=String(value??'').replace(/^[\s\u0085]+|[\s\u0085]+$/gu,'');
 return /^[A-HJ-NP-Z2-9]{6}$/i.test(code)?code.toUpperCase():code;
}
function validRoomCode(code){
 return typeof code==='string'&&[...code].length>0&&[...code].length<=MAX_ROOM_RUNES&&
 !/[\u0000-\u001f\u007f-\u009f\u2028\u2029\p{Cs}]/u.test(code)&&/[^\s\p{Cf}]/u.test(code);
}
function onlineInviteURL(watch=false){const url=new URL(location.href);url.search='';url.hash='';url.searchParams.set('room',online.code);if(watch)url.searchParams.set('spectate','1');return url;}
function syncOnlineURL(){
 if(!online.connected||!online.code)return;
 // Change the address without navigation, socket reconnect, or a new history entry.
 try{const url=onlineInviteURL(!!online.spectating);history.replaceState(history.state,'',url.href);}catch(_){}
}

function storeOnlineSession(){if(!online.connected||!online.code||!online.token)return;try{sessionStorage.setItem('leqra.session',JSON.stringify({code:online.code,token:online.token,name:roomMember(online.id)?.name||$('pilotName').value,spectating:!!online.spectating,at:Date.now()}));}catch(_){}}
function forgetOnlineSession(){try{sessionStorage.removeItem('leqra.session');}catch(_){}}
function acceptOnlineRoomCode(code,announce=true,rerender=true){
 code=cleanRoomCode(code);if(!validRoomCode(code)||code===online.code)return;const old=online.code;online.code=code;if(online.roomData)online.roomData.code=code;if(roomChat.code===old)roomChat.code=code;online.roomRenamePending=false;
 $('roomCodeDisplay').textContent=code;$('joinCode').value=code;if($('onlineRoomCode')&&document.activeElement!==$('onlineRoomCode'))$('onlineRoomCode').value=code;syncOnlineURL();storeOnlineSession();if(rerender)renderOnlineRoom();if(announce)toast('ROOM RENAMED · '+code,2.4);
}
function submitRoomRename(e){
 e?.preventDefault();if(mode!=='online'||!online.connected||online.roomRenamePending)return;const r=roomData(),me=r?roomMember(localPlayerID(),r):null;if(!r||r.host!==localPlayerID()||r.queue||r.matchmaking||r.awayMatch)return;
 const code=cleanRoomCode($('onlineRoomCode').value);if(!validRoomCode(code)){$('roomStatus').textContent='Use a room name of 1–128 characters on one line.';$('onlineRoomCode').focus();return;}if(code===online.code){$('roomStatus').textContent='That is already this room’s code.';return;}
 online.roomRenamePending=true;$('renameRoomBtn').disabled=true;$('roomStatus').textContent='Renaming room…';if(!sendOnline({type:'rename_room',code})){online.roomRenamePending=false;$('renameRoomBtn').disabled=false;$('roomStatus').textContent='Connection unavailable. Room was not renamed.';}
}
function sendOnline(value){const ws=online.socket;if(!ws||ws.readyState!==WebSocket.OPEN||ws.bufferedAmount>4096)return false;try{ws.send(JSON.stringify(value));return true;}catch(_){return false;}}
// Host moderation is only UI here: the Go server independently checks identity,
// host authority, room scope, and the seat incarnation again on every request.
function cancelKick(){
 const pending=online.kickPending;if(pending)clearTimeout(pending.timer);
 online.kickPending=null;
 if($('kickDialog').open)$('kickDialog').close();
 $('confirmKickBtn').disabled=false;$('confirmKickBtn').textContent='KICK PLAYER';
 document.querySelectorAll('[data-kick-target]').forEach(b=>b.disabled=mode==='online'&&!online.connected);
}
function requestKick(player){
 const r=roomData(),self=localPlayerID();if(!r||r.host!==self||player.id===self||online.kickPending)return;
 const current=roomMembers(r).find(p=>p.id===player.id&&p.member===player.member);if(!current)return;
 clearInput();sendOnlineInput(true);online.kickPending={id:current.id,member:current.member,name:current.name,timer:0,sent:false};
 if(current.kind==='bot'){confirmKick();return;}
 $('kickDescription').textContent='Remove '+current.name+' from this room?';
 $('kickNotice').textContent=current.kind==='bot'||current.kind==='local'?'This removes this participant. You can add another in the room.':(current.spectating?'This removes the spectator and stops automatic reconnection. It is not a permanent ban.':'This removes their tank and stops automatic reconnection. It is not a permanent ban.');
 $('confirmKickBtn').disabled=false;$('confirmKickBtn').textContent=current.kind==='human'?'KICK PLAYER':'REMOVE';$('kickDialog').showModal();$('cancelKickBtn').focus({preventScroll:true});
}
function confirmKick(){
 if(mode==='room'){const pending=online.kickPending;if(!pending)return;const removed=localRoom.players.find(p=>p.id===pending.id&&p.member===pending.member);if(removed&&!removed.spectating)clearLocalSeat(removed.id);localRoom.players=localRoom.players.filter(p=>p!==removed);cancelKick();refreshLocalRoles();return;}
 const pending=online.kickPending,r=online.roomData;
 if(!pending||pending.sent)return;
 if(!online.connected||!r||r.host!==online.id||!roomMembers(r).some(p=>p.id===pending.id&&p.member===pending.member)){
  cancelKick();toast('The room changed. Check the current roster.',3);return;
 }
 if(!sendOnline({type:'kick',target:pending.id,member:pending.member})){
  cancelKick();toast('Could not send the kick. Check your connection.',3);return;
 }
 pending.sent=true;$('confirmKickBtn').disabled=true;$('confirmKickBtn').textContent='REMOVING…';
 document.querySelectorAll('[data-kick-target]').forEach(b=>b.disabled=true);
 pending.timer=setTimeout(()=>{
  if(online.kickPending!==pending)return;
  cancelKick();toast('No confirmation received. Check the roster before trying again.',3);
 },5000);
}
function receiveKick(msg){
 const code=msg.room||online.code;
 // Mark this tab so a stale invite URL/refresh cannot immediately auto-join again.
 // Explicit Create/Join still works: kicking is removal, not an identity/IP ban.
 try{sessionStorage.setItem('leqra.kicked',code);}catch(_){}
 leaveOnline();openOnline();online.manual=true;
 $('joinCode').value=code;
 setNetStatus(msg.message||'You were removed from the room by the host. Automatic reconnection has stopped.',true);
}
function makeKickButton(player){
 const button=document.createElement('button');button.type='button';button.className='kick-button';
 button.textContent=player.kind==='bot'||player.kind==='local'?'REMOVE':'KICK';button.dataset.kickTarget=player.id;button.dataset.kickMember=player.member;
 button.setAttribute('aria-label','Kick '+player.name);button.title='Remove '+player.name+' from this room';
 button.disabled=mode==='online'&&!online.connected||!!online.kickPending;
 button.addEventListener('click',()=>requestKick(player));return button;
}
function makeColorSelect(value,onchange,label,inherit=false,id=null){
 const box=document.createElement('div');box.className='palette-select';box.title=label;
 const chip=document.createElement('i');chip.className='palette-chip';chip.setAttribute('aria-hidden','true');
 const select=document.createElement('select');select.setAttribute('aria-label',label);if(id!==null)select.dataset.tankColor=id;
 if(inherit){const o=document.createElement('option');o.value=-1;o.textContent='Default';select.append(o);}
 Theme.colorNames.forEach((name,i)=>{const o=document.createElement('option');o.value=i;o.textContent=name;select.append(o);});
 select.value=String(value);const update=()=>{const i=Number(select.value);chip.style.background=i<0?paintColor(roomMember(id)?.color||teamColor(id??0,roomMember(id)?.team||0)):Theme.colors[i];};update();
 select.onchange=()=>{update();onchange(Number(select.value));};box.append(chip,select);return box;
}
function canEditTankPaint(player,r){
 const rules=r.rules||currentRules();if(rules.teamMode!=='ffa'||!['lobby','matchOver'].includes(r.phase))return false;
 const me=localPlayerID(),host=r.host===me;
 if(player.id===me)return true;
 if(player.kind==='local'&&player.owner===me)return true;
 return host&&player.kind==='bot';
}
function makeRoomPlayerRow(player,r,moderationOnly=false){
 const host=r.host===localPlayerID(),editable=host&&['lobby','matchOver'].includes(r.phase)&&!r.queue&&!r.matchmaking&&!r.awayMatch,self=player.id===localPlayerID();
 const row=document.createElement('div');row.className='seat-row'+(self?' is-self':'');row.dataset.seat=player.id;row.style.setProperty('--player',paintColor(player.color));
 const heading=document.createElement('div');heading.className='seat-heading';const dot=document.createElement('span');dot.className='pilot-dot';
 let name;
 if(editable&&!moderationOnly&&(player.kind==='bot'||player.kind==='local'&&player.owner!==localPlayerID())){name=document.createElement('input');name.className='seat-name-input';name.value=player.name;name.maxLength=16;name.setAttribute('aria-label','Name for '+player.name);name.addEventListener('change',()=>changeSeat(player,{name:name.value}));}
 else{name=document.createElement('span');name.className='pilot-name';name.textContent=player.name;}
 const status=document.createElement('small');status.className='seat-kind';
 status.textContent=player.away?'IN MATCH':player.kind==='bot'?'BOT':player.kind==='local'?'LOCAL P2':self?'YOU · '+(host?'HOST':'PILOT'):!player.connected?'RECONNECTING':player.ready?'READY ✓':player.id===r.host?'HOST':'PILOT';
 heading.append(dot,name,status);row.append(heading);
 const controls=document.createElement('div');controls.className='seat-controls';
 if(editable&&!moderationOnly){
  if((r.rules||currentRules()).teamMode!=='ffa'){const team=document.createElement('select');team.dataset.team=player.id;team.setAttribute('aria-label','Team for '+player.name);for(let i=1;i<=4;i++){const o=document.createElement('option');o.value=i;o.textContent=teamName(i,r.rules);o.selected=i===player.team;team.append(o);}team.addEventListener('change',()=>changeSeat(player,{team:Number(team.value)}));controls.append(team);}
  if(player.kind==='bot'){const d=document.createElement('select');d.dataset.botDifficulty=player.id;d.setAttribute('aria-label','Difficulty for '+player.name);
   for(const [value,label]of[['easy','Chill'],['normal','Normal'],['hard','Fierce']]){const o=document.createElement('option');o.value=value;o.textContent=label;o.selected=value===player.difficulty;d.append(o);}
   d.addEventListener('change',()=>changeSeat(player,{difficulty:d.value}));controls.append(d);}
 }else{const badge=document.createElement('span');badge.className='team-badge';badge.textContent=player.team>0?teamName(player.team):'FREE-FOR-ALL';if(player.kind==='bot')badge.textContent+=' · '+(player.difficulty||'normal').toUpperCase();controls.append(badge);}
 if(!moderationOnly&&canEditTankPaint(player,r))controls.append(makeColorSelect(player.colorIndex??-1,value=>changeTankColor(player,value),'Tank color for '+player.name,true,player.id));
 if(player.kind==='local'&&player.owner===localPlayerID()){const watch=document.createElement('button');watch.type='button';watch.className='secondary';watch.textContent='SPECTATE';watch.dataset.spectatePlayer=player.id;watch.onclick=()=>setPlayerSpectating(player,true);controls.append(watch);}
 if(host&&!self&&(mode==='online'||editable))controls.append(makeKickButton(player));row.append(controls);return row;
}
// Callsigns are server-approved room metadata, not a new player/session.
function rememberCallsign(name){
 $('pilotName').value=name;
 try{localStorage.setItem('leqra.name',name);}catch(_){}
 if(online.code&&online.token)storeOnlineSession();
}
function rememberLocalCallsign(name){try{localStorage.setItem('leqra.local2Name',name);}catch(_){}}
function savedLocalCallsign(){try{return cleanPilotName(localStorage.getItem('leqra.local2Name')||'')||'PLAYER 2';}catch(_){return 'PLAYER 2';}}
function callsignForms(){return [$('roomCallsignForm'),$('menuCallsignForm'),$('roomP2CallsignForm'),$('menuP2CallsignForm')];}
function editorPilot(form){return form.dataset.pilot==='secondary'?secondaryMember():roomMember(localPlayerID());}
function callsignStatus(form,text,error=false){
 const status=form.querySelector('.callsign-status');status.textContent=text;status.hidden=!text;status.classList.toggle('error',error);
}
function syncCallsignEditors(force=false){
 for(const form of callsignForms()){
  const player=editorPilot(form),secondary=form.dataset.pilot==='secondary';form.hidden=secondary&&!player;
  if(secondary&&!player){delete form.dataset.member;delete form.dataset.currentName;callsignStatus(form,'');continue;}
  const name=player?.name||$('pilotName').value||'PILOT',member=String(player?.member||0);
  const field=form.elements.callsign,old=form.dataset.currentName;
  if(force||form.dataset.member!==member||old===undefined||field.value===old)field.value=name;
  form.dataset.member=member;form.dataset.currentName=name;
  field.disabled=mode==='online'&&!online.connected;
  form.querySelector('button').disabled=mode==='online'&&!online.connected||!!online.renamePending||!field.value.trim()||field.value.trim()===name;
 }
}
function cancelCallsignSave(message=''){
 const pending=online.renamePending;if(!pending)return;
 clearTimeout(pending.timer);online.renamePending=null;
 callsignStatus(pending.form,message,!!message);syncCallsignEditors();
}
function submitCallsign(form){
 if(online.renamePending)return;
 const player=editorPilot(form);if(!player){callsignStatus(form,'That local player is no longer in this room.',true);return;}
 const secondary=form.dataset.pilot==='secondary',name=cleanPilotName(form.elements.callsign.value);
 if(!name){callsignStatus(form,'Enter letters or numbers for your callsign.',true);return;}
 if(mode==='room'){
  player.name=name;if(secondary)rememberLocalCallsign(name);else rememberCallsign(name);
  // Update the source room participant, not the temporary display copy.
  const p=localRoom.players.find(p=>p.id===player.id);if(p)p.name=name;
  const t=tanks.find(t=>t.id===player.id);if(t)t.name=name;
  syncCallsignEditors();form.elements.callsign.value=name;callsignStatus(form,'Saved.');renderOnlineRoom();updateHUD(true);return;
 }
 if(!online.connected){callsignStatus(form,'Reconnect before changing your callsign.',true);return;}
 callsignStatus(form,'');
 const message=secondary?{type:'rename_local',target:player.id,member:player.member,name}:{type:'rename',name};
 if(!sendOnline(message)){callsignStatus(form,'Could not send. Please try Save again.',true);return;}
 const pending={form,id:player.id,member:player.member,timer:0};online.renamePending=pending;
 pending.timer=setTimeout(()=>{if(online.renamePending===pending)cancelCallsignSave('Not confirmed yet. Check your connection and try again.');},6000);
 callsignStatus(form,'Saving…');syncCallsignEditors();
}
function acceptCallsign(msg){
 const secondary=secondaryMember(),primary=msg.id===online.id;
 if(typeof msg.name!=='string'||!primary&&(!secondary||msg.id!==secondary.id||msg.member!==secondary.member))return;
 const pending=online.renamePending,form=pending?.id===msg.id?pending.form:null;
 if(form)cancelCallsignSave();
 const p=roomMember(msg.id,online.roomData);if(p)p.name=msg.name;
 if(primary)rememberCallsign(msg.name);else rememberLocalCallsign(msg.name);
 if(form)form.elements.callsign.value=msg.name;
 syncCallsignEditors();if(form)callsignStatus(form,'Saved as '+msg.name+'.');
 renderOnlineRoom();updateHUD(true);
}
// An invite is an explicit request to join. Expired credentials from an older
// visit may fall back to a new seat (or create a missing room), but never take
// over another live pilot. Background reconnects never use this fallback.
function joinInviteAsNewPilot(ws){
 const code=online.inviteCode,name=$('pilotName').value.trim()||'PILOT';
 online.socket=null;ws.close();clearTimeout(online.retryTimer);cancelCallsignSave();
 online.connecting=online.connected=false;online.code=online.token='';online.id=-1;online.roomData=null;online.menu=false;
 online.retryAt=0;online.retries=0;forgetOnlineSession();setScreen('online');
 connectOnline({type:'join',code,name,spectating:!!online.inviteWatch});
}
function onlineControls(second=false){
 const pilot=second?secondLocal()?.id:online.id;
 const active=online.connected&&!online.menu&&!roomChat.open&&!document.querySelector('.feature-dialog[open]')&&!document.hidden&&phase==='playing'&&performance.now()-(online.snapshots.at(-1)?.received||0)<450&&tanks.find(t=>t.id===pilot)?.alive;
 if(!active)return{forward:false,reverse:false,left:false,right:false,fire:false,stickX:0,stickY:0};
 return{forward:heldAction(second?1:0,'forward'),reverse:heldAction(second?1:0,'reverse'),left:heldAction(second?1:0,'left'),right:heldAction(second?1:0,'right'),fire:second?heldAction(1,'fire'):primaryFireHeld(),stickX:second?0:stick.x,stickY:second?0:stick.y};
}
function resetOnlineMotion(){
 online.shots=new Net.ShotPresentation();online.localBullets=new Map();online.effectQueue=[];online.presentationMetrics={previews:0,confirmed:0,suppressedSounds:0};
 online.predictor=new Net.Predictor(moveTank);online.secondary={predictor:new Net.Predictor(moveTank),seq:online.secondary?.seq||0,lastControl:null,lastControlStep:-10,lastSend:0};online.buffer=new Net.SnapshotBuffer();
 online.snapshots=online.buffer.items;online.predicted=null;online.lastControl=null;online.lastControlStep=-10;
 online.trails=new Map();
}
function sendOnlineInput(force=false,controls=onlineControls(),second=false){
 if(mode!=='online'||!online.connected)return;
 const seat=second?secondLocal():null;if(second&&!seat)return;
 if(!second&&(online.spectating||online.id<0||online.id>=MAX_TANKS)){if(force&&secondLocal())sendOnlineInput(true,onlineControls(true),true);return;}
 const channel=second?online.secondary:online;if(!channel)return;
 const now=performance.now(),step=(channel.predictor?.stepID||0)+1;
 let send=!(force&&Net.controlsEqual(channel.lastControl,controls)&&now-(channel.lastSend||0)<200);
 if(!force){if(phase==='playing'){if(Net.controlsEqual(channel.lastControl,controls)&&step-channel.lastControlStep<2)send=false;if(now-(channel.lastSend||0)<10)send=false;}else if(now-(channel.lastSend||0)<250)send=false;}
 if(send){const seq=channel.seq+1,message={type:'input',room:online.code,seq,player:second?seat.id:online.id,...controls};
 if(sendOnline(message)){channel.seq=seq;channel.lastSend=now;channel.lastControl={...controls};channel.lastControlStep=step;if(phase==='playing')channel.predictor?.sentInput(seq);previewOnlineFire(second,controls,now);}}
 if(force&&!second&&secondLocal())sendOnlineInput(true,onlineControls(true),true);
}
function openOnline(){
 if(online.connected&&online.code){toggleOnlineMenu();return;}
 if(!$('joinDialog').open)$('joinDialog').showModal();netBusy(false);
 setNetStatus(location.protocol==='file:'?'Online sharing needs the Go server. Run go run . and open its webpage.':'Missing rooms are created with you as host.',location.protocol==='file:');
}
function connectOnline(request,reconnecting=false){
 if(!['http:','https:'].includes(location.protocol)){setNetStatus('Online play needs the Go server. Run go run . and open the address it prints.',true);return;}
 if(online.connecting||online.connected)return;mode='online';phase='menu';document.body.classList.add('online-mode');
 if(!reconnecting&&!online.inviteCode){try{sessionStorage.removeItem('leqra.kicked');}catch(_){}}
 online.manual=false;online.connecting=true;netBusy(true);
 if(!reconnecting)setNetStatus(request.type==='create'?'Creating your room…':'Joining or creating your room…');
 const wsURL=new URL('/ws',location.href);wsURL.protocol=location.protocol==='https:'?'wss:':'ws:';
 let ws;try{ws=new WebSocket(wsURL.href);}catch(_){online.connecting=false;netBusy(false);if(online.publishing){online.publishing=false;mode='room';phase='menu';document.body.classList.remove('online-mode');setScreen('room');renderOnlineRoom();$('roomStatus').textContent='Could not connect to the Go server. Your local room is unchanged.';}else setNetStatus('Could not open a connection to the Go server.',true);return;}
 const old=online.socket;online.socket=ws;if(old&&old.readyState<2)old.close();
 const timeout=setTimeout(()=>{if(online.socket===ws&&online.connecting)ws.close();},8000);
 ws.onopen=()=>{if(online.socket!==ws)return;sendOnline(request);};
 ws.onmessage=e=>{
  if(online.socket!==ws||mode!=='online')return;
  let msg;try{msg=JSON.parse(e.data);}catch(_){ws.close(1007,'Invalid server data');return;}
  online.lastMessage=performance.now();
  switch(msg.type){
  case 'queue_catalog':case 'queue_status':case 'queue_cancelled':matchmakingPacket(msg);break;
  case 'chat':case 'chat_history':chatPacket(msg);break;
  case 'welcome':
   matchmakingWelcome(msg);matchmaking.rematchPending=false;online.lastMatch=-1;online.roomData=null;clearInput();closeVictory();
   watchInvite=false;watchResume=null;online.inviteWatch=false;resetWatchDialog();
   if($('joinDialog').open)$('joinDialog').close();online.publishing=false;
   clearTimeout(timeout);online.connecting=false;online.connected=true;online.code=msg.room;online.id=msg.id;online.member=msg.member;online.spectating=!!msg.spectating;online.token=msg.token;rolePending=false;online.seq=0;online.menu=false;online.retries=0;online.retryAt=0;resetOnlineMotion();online.generation=-1;online.eventsInitialized=false;online.lastEvent=0;online.lastSend=0;online.trails=new Map();
   if(roomChat.code!==online.code)clearRoomChat(online.code);syncChatStatus();
   online.inviteCode='';online.inviteResumeRetries=0;clearTimeout(online.retryTimer);netBusy(false);syncOnlineURL();document.documentElement.style.setProperty('--pilot',paintColor(COLORS[online.id%MAX_TANKS]));storeOnlineSession();$('roomBtn').hidden=false;$('roomCodeDisplay').textContent=online.code;$('joinCode').value=online.code;setScreen('room');
   sendOnline({type:'ping',t:performance.now()});online.lastPing=performance.now();initAudio();addLog(msg.resumed?'Reconnected. Same pilot, same room.':msg.created?'Room '+online.code+' created. You are the host.':msg.full?'Arena full — joined as a spectator.':msg.spectating?'Spectating room '+online.code+'.':'Online room '+online.code+' connected.');break;
  case 'identity': {
   const local=secondaryMember(),changed=online.id!==msg.id||online.spectating!==!!msg.spectating||(local?.id??-1)!==msg.localId||(local?.member??0)!==msg.localMember;
   online.id=msg.id;online.member=msg.member;online.spectating=!!msg.spectating;
   // Never reset sequence numbers on a live socket. Unaffected controllers keep
   // their held controls/prediction even when someone else joins or watches.
   if(changed){cancelCallsignSave();clearInput();resetOnlineMotion();online.generation=-1;}
   rolePending=false;syncOnlineURL();break; }
  case 'swapped':cancelSwap();toast(msg.message,3);break;
  case 'room':{if(msg.code&&msg.code!==online.code)acceptOnlineRoomCode(msg.code,false,false);if(matchmaking.pending&&!matchmaking.pendingKey){clearTimeout(matchmaking.pendingTimer);matchmaking.pending=false;}online.roomData=msg;rolePending=false;if(rulesPending){rulesPending=false;closeFeature($('rulesDialog'));}if(presetsPending){presetsPending=false;closeFeature($('presetsDialog'));}const own=roomMember(online.id,msg);if(own){online.spectating=!!own.spectating;matchmaking.rematchPending=!!own.rematch;rememberCallsign(own.name);storeOnlineSession();}const local=secondaryMember();if(local)rememberLocalCallsign(local.name);syncCallsignEditors();renderOnlineRoom();updateHUD(true);break;}
  case 'renamed':acceptCallsign(msg);break;
  case 'kicked':clearTimeout(timeout);receiveKick(msg);break;
  case 'player_kicked':
   if(online.kickPending?.id===msg.id&&online.kickPending?.member===msg.member)cancelKick();
   toast(msg.name+' was removed from the room.',3);break;
  case 'state':receiveOnlineState(msg);break;
  case 'pong':{const sample=clamp(performance.now()-msg.t,0,5000);online.latency=Math.round(online.latency?online.latency*.7+sample*.3:sample);break;}
  case 'error':
   if(msg.action==='rematch'){matchmaking.rematchPending=false;syncResultActions();toast(msg.message,3);break;}
   if(msg.action?.startsWith('queue_')||msg.action==='return_party'){matchmakingError(msg.message);break;}
   if(msg.action==='chat'){const st=chatState(msg.channel);st.pending=false;if(roomChat.open&&roomChat.channel===(msg.channel||'room'))$('chatError').textContent=msg.message;syncChatStatus();break;}
   if(msg.action==='rename_room'){online.roomRenamePending=false;$('renameRoomBtn').disabled=false;$('roomStatus').textContent=msg.message;toast(msg.message,3);break;}
   if(msg.action==='rules'||msg.action==='preset'){rulesPending=presetsPending=false;featureNotice(msg.action==='rules'?'rulesNotice':'presetsNotice',msg.message,true);break;}
   if(online.publishing&&!online.connected){if(matchmaking.pending||matchmaking.pendingKey)matchmakingError(msg.message);clearTimeout(timeout);online.publishing=false;online.manual=true;online.socket=null;ws.close();online.connecting=false;netBusy(false);mode='room';phase='menu';document.body.classList.remove('online-mode');setScreen('room');renderOnlineRoom();$('roomStatus').textContent=msg.message;break;}
   if(msg.action==='spectate'||msg.action==='swap'){rolePending=false;cancelSwap();syncSpectators();$('roomStatus').textContent=msg.message;toast(msg.message,4);break;}
   if(msg.action==='kick'){cancelKick();$('roomStatus').textContent=msg.message;toast(msg.message,3);break;}
   if(msg.code==='kicked'){clearTimeout(timeout);receiveKick(msg);break;}
   if(msg.code==='bad_name'||msg.action==='rename_local'){cancelCallsignSave(msg.message);break;}
   if(request.token&&online.inviteCode&&(msg.code==='resume_expired'||msg.code==='room_missing'||msg.code==='session_active'&&++online.inviteResumeRetries>=3)){clearTimeout(timeout);joinInviteAsNewPilot(ws);break;}
   if(online.connected&&!['resume_expired','room_missing','session_active'].includes(msg.code)){ $('roomStatus').textContent=msg.message;toast(msg.message,3);break; }
   if(msg.code==='session_active'&&request.token){clearTimeout(timeout);online.connecting=false;ws.close();break;}
   clearTimeout(timeout);online.inviteCode='';cancelCallsignSave();online.manual=true;online.connected=false;online.connecting=false;online.code='';online.id=-1;online.token='';online.roomData=null;clearTimeout(online.retryTimer);forgetOnlineSession();ws.close();netBusy(false);phase='menu';online.menu=false;setScreen('online');setNetStatus(msg.message,true);break;
  case 'left':break;
  }
 };
 ws.onerror=()=>{}; // onclose handles both failed upgrades and transport loss.
 ws.onclose=()=>{
  clearTimeout(timeout);if(online.socket!==ws)return;online.connected=false;online.connecting=false;rolePending=false;cancelSwap();cancelKick();cancelCallsignSave('Connection lost. Check your callsign after reconnecting.');syncCallsignEditors();netBusy(false);clearInput();
  syncChatStatus();if(mode!=='online'||online.manual)return;
  if(online.code&&online.token){showReconnecting();scheduleReconnect();}
  else {if(online.publishing){online.publishing=false;mode='room';phase='menu';document.body.classList.remove('online-mode');setScreen('room');renderOnlineRoom();$('roomStatus').textContent='Could not reach the Go server. Local play is still available.';return;}phase='menu';setScreen('online');setNetStatus('Could not reach the Go game server. Start it with go run . and open its webpage.',true);}
 };
}
function showReconnecting(){
 for(const st of Object.values(roomChat.channels))st.pending=false;online.roomRenamePending=false;syncChatStatus();
 cancelKick();$('hostControls').hidden=true;online.menu=true;setScreen('onlineMenu');$('announcer').hidden=true;$('onlineMenuEyebrow').textContent='CONNECTION INTERRUPTED';$('onlineMenuMessage').textContent='Reconnecting to room '+online.code+'… '+(online.spectating?'You will return as a spectator. Your membership is reserved for 20 seconds.':'Your tank remains in the match. The server reserves your seat for 20 seconds.');$('onlineReturnBtn').disabled=true;$('onlineReturnBtn').firstElementChild.textContent='RECONNECTING…';
}
function scheduleReconnect(){
 if(online.manual||mode!=='online')return;
 if(!online.retryAt)online.retryAt=performance.now();
 if(performance.now()-online.retryAt>18000){online.manual=true;online.code='';online.token='';online.id=-1;forgetOnlineSession();phase='menu';online.menu=false;setScreen('online');setNetStatus('The connection could not be restored. Rejoin with the room code when the server is reachable.',true);return;}
 const delay=Math.min(3000,450*2**Math.min(online.retries++,3));clearTimeout(online.retryTimer);
 online.retryTimer=setTimeout(()=>{if(mode==='online'&&!online.manual)connectOnline({type:'join',code:online.code,token:online.token,name:$('pilotName').value},true);},delay);
}
function leaveOnline(){
 resetMatchmaking();
 closeChat();clearRoomChat();
 cancelSwap();rolePending=false;watchInvite=false;watchResume=null;online.inviteWatch=false;online.spectating=false;resetWatchDialog();
 cancelKick();cancelCallsignSave();online.inviteCode='';online.inviteResumeRetries=0;callsignForms().forEach(f=>{delete f.dataset.currentName;callsignStatus(f,'');});
 online.manual=true;clearTimeout(online.retryTimer);online.menu=true;clearInput();sendOnlineInput(true);sendOnline({type:'leave'});
 const ws=online.socket;online.socket=null;if(ws&&ws.readyState<2)ws.close(1000,'Left room');
 online.connected=online.connecting=false;online.code=online.token='';online.id=-1;online.roomData=null;resetOnlineMotion();online.generation=-1;online.menu=false;online.lastMatch=-1;forgetOnlineSession();
 document.body.classList.remove('online-mode');document.documentElement.style.removeProperty('--pilot');$('roomBtn').hidden=true;$('bestInline').textContent='';$('barHint').textContent='Your own shots can take you out.';
 try{const url=new URL(location.href);url.searchParams.delete('room');url.searchParams.delete('spectate');history.replaceState(null,'',url);}catch(_){}
 mode='room';phase='menu';createLocalRoom();
}
function toggleOnlineMenu(){
 if($('restartLocalBtn'))$('restartLocalBtn').hidden=true;
 if(!online.code)return;
 if(!online.connected){showReconnecting();return;}
 if(['onlineLobby','matchOver'].includes(phase)){setScreen('room');return;}
 online.menu=!online.menu;clearInput();sendOnlineInput(true);setScreen(online.menu?'onlineMenu':null);
 $('onlineMenuEyebrow').textContent='ROOM '+online.code+' · '+online.latency+' MS';$('onlineMenuMessage').textContent=online.spectating?'You are spectating. The match keeps running while this menu is open.':'The match keeps running. Your tank is still vulnerable while this menu is open.';$('onlineReturnBtn').disabled=false;$('onlineReturnBtn').firstElementChild.textContent='BACK TO THE ARENA';
 if(online.menu){$('copyInGameBtn').disabled=false;renderOnlineRoom();}else{cancelKick();canvas.focus({preventScroll:true});}
}
function renderOnlineRoom(){
 if($('chatBtn'))syncChatStatus();
 const r=roomData();if(!r)return;syncCallsignEditors();
 const isOnline=mode==='online',host=r.host===localPlayerID(),editable=['lobby','matchOver'].includes(r.phase)&&!r.queue&&!r.matchmaking&&!r.awayMatch,own=roomMember(localPlayerID(),r);
 const count=r.players.length,sides=new Set(r.players.filter(p=>p.connected).map(teamKey)).size;
 document.documentElement.style.setProperty('--pilot',paintColor(own?.color||COLORS[0]));
 $('roomCallsignForm').querySelector('label').textContent=host?'YOUR CALLSIGN · HOST':'YOUR CALLSIGN';
 $('localRoomName').hidden=isOnline;$('localRoomName').disabled=!host;
 if(!isOnline&&document.activeElement!==$('localRoomName'))$('localRoomName').value=localRoom.code;
 const canRenameRoom=isOnline&&host&&editable;$('roomCodeEditor').hidden=!canRenameRoom;$('roomCodeDisplay').hidden=!isOnline||canRenameRoom;$('roomCodeDisplay').textContent=isOnline?online.code:localRoom.code;
 if(canRenameRoom&&document.activeElement!==$('onlineRoomCode'))$('onlineRoomCode').value=online.code;$('renameRoomBtn').disabled=online.roomRenamePending;
 $('copyInviteBtn').textContent=isOnline?'COPY INVITE LINK ↗':'SHARE ROOM ONLINE ↗';$('copyInviteBtn').disabled=!!online.connecting;
 $('seatCount').textContent=count+' / '+MAX_TANKS;$('rosterTools').hidden=!host||!editable;
 $('addLocalBtn').disabled=count>=MAX_TANKS||roomMembers(r).some(p=>p.kind==='local');$('addBotBtn').disabled=count>=MAX_TANKS;
 const p2=secondaryMember();$('localControlsNote').hidden=!p2;
 $('roomRoster').classList.remove('host-roster');$('roomRoster').replaceChildren(...r.players.map(p=>makeRoomPlayerRow(p,r)));
 if(count<MAX_TANKS){const free=document.createElement('div');free.className='free-seats';free.textContent=(MAX_TANKS-count)+' OPEN SEAT'+(count===MAX_TANKS-1?'':'S')+' · ADD A PILOT, BOT, OR FRIEND';$('roomRoster').append(free);}
 const pending=online.kickPending;if(pending&&!roomMembers(r).some(p=>p.id===pending.id&&p.member===pending.member))cancelKick();
 $('hostControls').hidden=!isOnline||!host||!online.connected;
 $('menuKickRoster').replaceChildren(...r.players.filter(p=>p.id!==localPlayerID()).map(p=>makeRoomPlayerRow(p,r,true)));
 $('returnRoomBtn').hidden=!host;$('returnRoomBtn').textContent='End match';$('copyInGameBtn').hidden=!isOnline;$('copyInGameBtn').disabled=false;if(isOnline)$('copyInGameBtn').textContent='Copy invite link';
 $('onlineLeaveBtn').hidden=!isOnline;if(isOnline)$('onlineLeaveBtn').textContent='Leave online room';
 $('readyBtn').hidden=!isOnline||host||!!own?.spectating;$('readyBtn').classList.toggle('is-ready',!!own?.ready);$('readyBtn').textContent=own?.ready?'READY ✓ · CLICK TO UNREADY':'I’M READY';$('readyBtn').disabled=!online.connected;
 const canStart=isOnline?r.canStart:sides>=2;
 $('startRoomBtn').hidden=isOnline&&!host;$('startRoomBtn').disabled=!host||!canStart||isOnline&&!online.connected;
 $('startRoomBtn').firstElementChild.textContent=r.phase==='matchOver'?'PLAY AGAIN':'START MATCH';
 $('readyHint').textContent=sides<2?'CHOOSE AT LEAST TWO OPPOSING SIDES':isOnline&&!canStart?'WAITING FOR CONNECTED GUESTS TO READY UP':isOnline&&!host?'READY UP · THE HOST STARTS THE MATCH':'FIRST SIDE TO 5 · START WHEN YOU’RE READY';
 const complete=r.phase==='matchOver';$('roomEyebrow').textContent=complete?'MATCH COMPLETE':isOnline?'ONLINE ROOM · '+(host?'YOU ARE THE HOST':'CONNECTED'):'LOCAL ROOM · YOU ARE THE HOST';
 $('roomTitle').innerHTML=complete?'GOOD<br><em>GAME.</em>':'YOUR<br><em>ARENA.</em>';
 $('roomStatus').textContent=complete?(roundWinner<0?'Draw — scores tied.':winnerName(roundWinner)+' wins!')+' Adjust the room or play again.':isOnline?(count===MAX_TANKS?'Eight tanks are assigned. New visitors can still join as spectators.':'Room is online. Share the invite link to bring in friends.'):'Local play is ready. Sharing keeps this roster and these teams.';
 $('leaveRoomBtn').textContent=isOnline?'Leave room':'New local room';
 $('roomBtn').hidden=false;$('roomBtn').textContent=isOnline?online.code:'MY ROOM';
 $('manualContent').innerHTML='<div class="manual-line"><span>Player 1</span><kbd>'+(p2?'WASD + Q':'WASD / ARROWS + Q / SPACE')+'</kbd></div>'+(p2?'<div class="manual-line"><span>Local player 2</span><kbd>ARROWS + SPACE</kbd></div>':'')+'<div class="warning"><b>Last side standing wins.</b><br>Teammates share points and cannot hurt each other. Your own ricochets and grenades are still dangerous.</div>';
 syncFeatureSummary();syncSpectators();renderMatchmaking();
}
async function copyOnlineInvite(watch=false){
 watch=watch===true;
 if(mode==='room'){shareLocalRoom();return;}
 const url=onlineInviteURL(watch);
 // A localhost URL is never offered as a working invitation to another device.
 const loopback=['localhost','127.0.0.1','[::1]'].includes(url.hostname);
 if(loopback&&!watch){
  const text='Room '+online.code+' — open the server’s Wi-Fi or public address, then join with this code.';
  try{await navigator.clipboard.writeText(text);$('roomStatus').textContent='Room code copied. Friends must open the server’s Wi-Fi or public address.';}catch(_){$('inviteFallback').hidden=false;$('inviteFallback').value=text;$('inviteFallback').select();$('roomStatus').textContent='Copy the code below. localhost only works on this computer.';}
  if(phase!=='onlineLobby'&&phase!=='matchOver')toast('ROOM '+online.code+' · USE SERVER’S WI-FI ADDRESS',3);
  return;
 }
 try{if(!navigator.clipboard)throw Error('Clipboard unavailable');await navigator.clipboard.writeText(url.href);$('roomStatus').textContent=watch?(loopback?'Spectator link copied, but localhost only works on this device. Open the server’s Wi-Fi/public address before sharing with other devices.':'Spectator link copied. Visitors choose a callsign, then start spectating.'):'Invite link copied. Send it to your friends.';toast(watch?(loopback?'SPECTATOR LINK COPIED · LOCALHOST ONLY':'SPECTATOR LINK COPIED'):'INVITE LINK COPIED',loopback?4:1.8);}catch(_){$('inviteFallback').hidden=false;$('inviteFallback').value=url.href;$('inviteFallback').select();$('roomStatus').textContent='Select and copy the invite link above.';if(online.menu){$('onlineMenuMessage').textContent='Invite: '+url.href;}}
}
function netTank(t){return{...t,human:!t.bot,team:t.team??0,ai:{target:-1}};}
function receiveOnlineState(s){
 if(!online.connected)return;
 const now=performance.now(),previousPhase=phase,newMap=s.generation!==online.generation;
 // Never apply a new generation to an old maze while its reliable map is pending.
 if(newMap&&s.generation>0&&!s.world)return;
 if(!newMap&&s.tick<=(online.snapshots.at(-1)?.tick??-1))return;
 if(s.world){cols=s.world.cols;rows=s.world.rows;W=s.world.width;H=s.world.height;walls=s.world.walls;grid=[];cacheMap();resize();}
 if(newMap){goUntil=0;online.generation=s.generation;resetOnlineMotion();particles=[];rings=[];traces=[];bullets=[];pickups=[];clearInput();}
 s.bullets=(s.bullets||[]).concat(Net.expandMachineBullets(s.machineBullets,COLORS));delete s.machineBullets;
 s.received=now;s.tanks=s.tanks.map(netTank);s.tankMap=new Map(s.tanks.map(t=>[t.id,t]));s.bulletMap=new Map(s.bullets.map(b=>[b.id,b]));
 online.buffer.push(s,now);
 phase=s.phase==='lobby'?'onlineLobby':s.phase;round=s.round;roundClock=s.roundClock;phaseTime=s.phaseTime;roundWinner=s.winner;scores=s.scores;
 if(phase==='playing'&&previousPhase==='countdown'){goUntil=now+550;if(round===1)showStartingControls();}
 if(s.objectives?.suddenDeath)goUntil=0;
 if(previousPhase==='playing'&&phase!=='playing'){clearInput();sendOnlineInput(true);online.localBullets.clear();}
 const ownedIDs=online.ownedIDs,activeIDs=online.activeIDs;ownedIDs.clear();activeIDs.clear();ownedIDs.add(online.id);const local2=secondaryID();if(local2!==undefined)ownedIDs.add(local2);
 for(const t of s.tanks)if(ownedIDs.has(t.id)){online.shots.sync(t,phase,now);if(t.alive)activeIDs.add(t.id);}
 online.shots.prune(now,activeIDs);
 if(phase!=='matchOver')closeVictory();
 const p2=secondLocal();if(p2){const t2=s.tankMap.get(p2.id);if(t2)online.secondary.predictor.reconcile(t2,newMap||phase!=='playing'||t2.spawnSerial!==online.secondary.predictor.state?.spawnSerial);}
 const me=s.tankMap.get(online.id);
 if(me){
  online.predictor.reconcile(me,newMap||phase!=='playing'||me.spawnSerial!==online.predictor.state?.spawnSerial);
  online.predicted=online.predictor.state;
 }
 if(!s.tanks.length)tanks=[];
 if(['onlineLobby','matchOver'].includes(phase)){
  online.menu=false;
  if(phase!==previousPhase||newMap){setScreen('room');renderOnlineRoom();}
 }else if(['onlineLobby','matchOver','menu'].includes(previousPhase)||newMap&&s.round===1){online.menu=false;setScreen(null);}
 else if(!online.menu&&phase!==previousPhase)setScreen(null);
 if(phase==='matchOver'&&online.lastMatch!==s.generation){online.lastMatch=s.generation;showVictory(s.winner,s.tanks,s.matchStats);if(me&&s.tankMap.get(s.winner)&&teamKey(me)===teamKey(s.tankMap.get(s.winner))){bestWins++;save('wins',bestWins);$('recordLabel').textContent=bestWins+' MATCH WINS ON THIS DEVICE';}}
 const events=s.events||[];
 if(!online.eventsInitialized){online.lastEvent=events.at(-1)?.id||0;online.eventsInitialized=true;}
 else for(const e of events){if(e.id<=online.lastEvent)continue;online.lastEvent=e.id;const own=e.player===online.id||e.player===secondaryID();if(!own&&['shot','laser'].includes(e.type)&&phase==='playing'&&Number.isFinite(e.tick)){online.effectQueue.push({e,s});if(online.effectQueue.length>64)online.effectQueue.shift();}else onlineEffect(e,s);}
 gameStarted=s.generation>0;
 // Normal snapshots don't rebuild the entire scoreboard/ammo DOM every 33 ms.
 if(newMap||phase!==previousPhase)updateHUD(true);
}
function onlineEffect(e,s){
 if(e.generation!==undefined&&e.generation!==s.generation)return;
 if(e.type==='laser'){const key=online.shots.key(e.player,e.spawnSerial,e.shotSerial);
  if(online.shots.heard(e.player,e.spawnSerial,e.shotSerial)){
   const preview=traces.find(t=>t.previewKey===key);if(preview){preview.x=e.x;preview.y=e.y;preview.endX=e.endX;preview.endY=e.endY;if(e.points)preview.points=e.points.map(p=>({...p}));}
   // Correct any remaining visual; do not restart its lifetime or flash twice.
  }else laserEffect(e.x,e.y,e.endX,e.endY,e.color,e.points);
 }
  else if(e.type==='blast')blastEffect(e.x,e.y,e.color,e.radius||BLAST_RADIUS);
 if(e.type==='impact')impactEffect(e.x,e.y,e.color,e.radius||25);
 const t=s.tankMap.get(e.player),color=e.color||COLORS[e.player]||COLORS[0];
 if(e.type==='shot'){if(online.shots.heard(e.player,e.spawnSerial,e.shotSerial)){online.presentationMetrics.suppressedSounds++;return;}const angle=e.angle??t?.angle??0;burst(e.x+Math.cos(angle)*27,e.y+Math.sin(angle)*27,color,3,40);shotSound(e.text,e.player===online.id||e.player===secondaryID());}
 if(e.type==='suddenDeath'){goUntil=0;clearInput();toast(e.text||'SUDDEN DEATH · NO RESPAWNS',3);addLog(e.text||'Sudden death');}
 if(e.type==='objective'){if(e.text){addLog(e.text);toast(e.text,2);}pickupSound();}
 if(e.type==='respawn'){addRing(e.x,e.y,color,38);}
 if(e.type==='hit'){burst(e.x,e.y,color,34,190);burst(e.x,e.y,'#f7ecbb',12,130);addRing(e.x,e.y,color,70);boom();if(e.player===online.id||e.player===secondaryID())eventShake(e.x,e.y,.12);if(e.text)addLog(e.text);if(e.player===online.id)toast(objectiveMode()&&!suddenDeath()?'TANK DOWN · RESPAWNING':'TANK DOWN',2.3);}
 if(e.type==='shield'){burst(e.x,e.y,POWER.shield.color,18,120);addRing(e.x,e.y,POWER.shield.color,58);tone(680,160,.2,.035);if(e.player===online.id)toast('SHIELD SAVED YOU',1.8);}
 if(e.type==='pickup'){const def=POWER[e.text];if(def){burst(e.x,e.y,def.color,12,90);addRing(e.x,e.y,def.color,44);const localIndex=localPilotIndex(e.player);if(localIndex>=0){pickupSound();setPilotFeedback(localIndex,pickupMessage(e.text),2.5);}}}
 if(e.type==='roundEnd'){addLog(e.owner<0?'Round draw. No points.':winnerName(e.owner)+' takes the round.');tone(e.owner===online.id?600:300,450,.16,.035,'triangle');}
}
function predictOnlineTank(dt){
 if(!online.predictor||phase!=='playing'||!online.connected)return;
 if(!online.spectating){online.predictor.advance(dt,onlineControls(),input=>sendOnlineInput(false,input));online.predicted=online.predictor.state;}
 if(secondLocal())online.secondary.predictor.advance(dt,onlineControls(true),input=>sendOnlineInput(false,input,true));
}
function onlineUpdate(dt){
 updateTraces(dt);
 fxTime+=dt;time+=dt;
 if(toastTime>0){toastTime-=dt;if(toastTime<=0)$('toast').hidden=true;}
 const drag=Math.exp(-3*dt);for(const p of particles){p.life-=dt;p.x+=p.vx*dt;p.y+=p.vy*dt;p.vx*=drag;p.vy*=drag;}compactLife(particles);for(const r of rings)r.life-=dt;compactLife(rings);shake=Math.max(0,shake-dt);
 if(online.connected&&performance.now()-online.lastMessage>4500){online.socket?.close(4000,'Connection stalled');return;}
 predictOnlineTank(dt);
 if(online.connected){previewOnlineFire(false,onlineControls(),performance.now());if(secondLocal())previewOnlineFire(true,onlineControls(true),performance.now());}
 uiClock-=dt;if(uiClock<=0){updateHUD();uiClock=.08;}
}
function projectOnlineBullet(b,dt,maxAhead=.12){
 const copy={...b};if(copy.kind==='homing')copy.rangeLeft??=W+H;
 let left=Math.min(clamp(maxAhead,0,.35),Math.max(0,dt),Math.max(0,b.life));
 // Visual-only, short, wall-aware extrapolation. Do not choose a target locally.
 while(left>.00001){
  const step=Math.min(1/60,left,copy.kind==='homing'?copy.rangeLeft/MISSILE_SPEED:Infinity);if(step<=1e-9)break;
  left-=step;const lifeBefore=copy.life;copy.life=Math.max(0,copy.life-step);copy.age+=step;
  if(copy.kind==='grenade'){const drag=grenadeDragFactor(lifeBefore,copy.life);copy.vx*=drag;copy.vy*=drag;}
  let rest=step;for(let i=0;i<4&&rest>.00001;i++){
   if(copy.kind==='homing')rest=Math.min(rest,copy.rangeLeft/MISSILE_SPEED);
   const hit=projectileWall(copy.kind,copy.x,copy.y,copy.vx*rest,copy.vy*rest,copy.r),span=rest*(hit?hit.t:1);
   copy.x+=copy.vx*span;copy.y+=copy.vy*span;spendMissileRange(copy,Math.hypot(copy.vx,copy.vy)*span);
   if(!hit)break;missileWallNudge(copy,hit);rest-=span;
  }
 }return copy;
}

function previewOnlineFire(second,controls,now){
 const id=second?secondaryID():online.id,channel=second?online.secondary:online;
 const auth=online.snapshots.at(-1)?.tankMap.get(id),pose=channel?.predictor?.state;
 if(!online.shots||!auth||!pose)return;
 const t={...auth,x:pose.x,y:pose.y,angle:pose.angle,ghostTime:pose.ghostTime};
 const active=phase==='playing'&&online.connected&&controls.fire&&!online.menu&&now-(online.snapshots.at(-1)?.received||0)<450;
 const grenade=ownedGrenades(t).length>0||online.shots.pendingGrenade(id),power=t.power||'';
 const v=online.shots.tryFire(t,!!controls.fire,now,{active,grenade,
  blocked:t.ghostTime>0&&power!=='cannon'&&!clearTankAt(t.x,t.y,0),
  // Lasers bypass the projectile-slot cap, matching authoritative fireLaser.
  free:power==='laser'?Infinity:powerCapacity(t)-activeAmmo(t),need:power==='laser'?0:power==='scatter'?3:1,
  charged:['laser','cannon','homing','grenade','scatter'].includes(power),cooldown:cooldownDuration(power),
  ttl:Math.max(350,online.latency*2+120)});
 if(!v)return;
 online.presentationMetrics.previews++;
 // Use the corrected visual pose for the muzzle; movement state is never changed.
 const visual=tanks.find(n=>n.id===id);if(visual&&visual.spawnSerial===auth.spawnSerial){t.x=visual.x;t.y=visual.y;t.angle=visual.angle;}
 if(power==='laser'){const beam=laserTrace(t);laserEffect(beam.x,beam.y,beam.endX,beam.endY,POWER.laser.color,beam.points);if(traces.length)traces.at(-1).previewKey=v.key;}
 else v.shells=(power==='scatter'?[-.21,0,.21]:[0]).map((offset,pellet)=>({...muzzleProjectile(t,t.angle+offset),pellet,shotSerial:v.shot,spawnSerial:v.life,preview:true}));
 if(power!=='rapid'||v.shot%4===1)burst(t.x+Math.cos(t.angle)*27,t.y+Math.sin(t.angle)*27,t.color,3,40);shotSound(power,true);
 if(power!=='rapid')updateCombatFeedback(true);
}
function localBulletVisual(n,now,since){
 const key=online.shots.key(n.owner,n.spawnSerial,n.shotSerial),v=online.shots.previews.get(key),source=v?.shells[n.pellet||0];
 let state=online.localBullets.get(n.id);
 if(!state){
  // Keep a locally predicted shot on its forward timeline on confirmation.
  // Never draw it at a future point then rewind into the remote buffer.
  const bornAt=source?v.at:now-(n.age||0)*1000;
  state={bornAt,age:n.age||0};online.localBullets.set(n.id,state);
  if(v){v.confirmed.add(n.pellet||0);online.presentationMetrics.confirmed++;}
 }
 // An absolute local birth clock, NOT time since the newest packet: packet
 // jitter must not restart projectile animation on every arrival.
 state.age=Math.max(state.age,(now-state.bornAt)/1000,n.age||0);
 const item=projectOnlineBullet(n,clamp(state.age-(n.age||0),0,.35),.35);
 if(v){v.confirmed.add(n.pellet||0);}
 return item;
}
function projectileOnTimeline(n,sample){
 const a=sample?.a.bulletMap.get(n.id),b=sample?.b.bulletMap.get(n.id);
 // Wait for the first authoritative sample to reach the playback cursor. The
 // previous path drew latest immediately, then jumped BACK to buffered samples.
 if(!a)return null;
 if(!b){return projectOnlineBullet(a,Math.max(0,sample.time-sample.a.netTime)/1000);}
 if(a.bounces!==b.bounces)return projectOnlineBullet(a,Math.max(0,sample.time-sample.a.netTime)/1000);
 const f=sample.alpha,item={...b,x:a.x+(b.x-a.x)*f,y:a.y+(b.y-a.y)*f,vx:a.vx+(b.vx-a.vx)*f,vy:a.vy+(b.vy-a.vy)*f,
  life:a.life+(b.life-a.life)*f,age:a.age+(b.age-a.age)*f,rangeLeft:typeof a.rangeLeft==='number'?a.rangeLeft+(b.rangeLeft-a.rangeLeft)*f:undefined};
 return sample.extrapolate>0?projectOnlineBullet(item,sample.extrapolate):item;
}
// One render pass per animation frame. Own fire is cosmetic-predicted; other
// weapons share their shooter's buffered timeline. Go still owns every hit.
function renderOnlineMotion(dt,now){
 const s=online.snapshots.at(-1);if(!s||s.generation<=0)return;
 const sample=online.buffer.advance(dt),local2ID=secondaryID(),since=clamp((now-s.received)/1000,0,.25),ownIDs=online.ownedIDs,activeIDs=online.activeIDs,present=online.trailIDs;
 ownIDs.clear();activeIDs.clear();present.clear();ownIDs.add(online.id);if(local2ID!==undefined)ownIDs.add(local2ID);
 tanks=s.tanks.map(n=>phase!=='playing'?{...n}:n.id===online.id&&online.predictor.state
  ?online.predictor.visual(dt,phase==='playing')
  :n.id===local2ID&&online.secondary?.predictor.state?online.secondary.predictor.visual(dt,phase==='playing')
  :online.buffer.tank(n.id,sample,moveTank));
 if(phase==='playing'&&online.connected)for(const t of tanks)if(t.alive&&ownIDs.has(t.id))activeIDs.add(t.id);
 online.shots.prune(now,activeIDs);
 bullets.length=0;
 for(const n of s.bullets){
  let item=phase!=='playing'?{...n}:ownIDs.has(n.owner)?localBulletVisual(n,now,since):projectileOnTimeline(n,sample);
  if(!item)continue;
  if(n.kind==='rapid'){online.trails.delete(n.id);item.trail=[];present.add(n.id);bullets.push(item);continue;}
  const trail=online.trails.get(n.id)||[];
  if(phase==='playing'&&(!trail.length||Math.hypot(trail.at(-1).x-item.x,trail.at(-1).y-item.y)>.01))trail.push({x:item.x,y:item.y});
  if(trail.length>(WEBKIT_ENGINE?7:11))trail.shift();online.trails.set(n.id,trail);present.add(n.id);item.trail=trail;bullets.push(item);
 }
 for(const id of online.trails.keys())if(!present.has(id))online.trails.delete(id);
 for(const id of online.localBullets.keys())if(!s.bulletMap.has(id))online.localBullets.delete(id);
 for(const v of online.shots.previews.values()){
  if(v.accepted)continue; // A shot destroyed before the first snapshot must not linger.
  for(const shell of v.shells){if(v.confirmed.has(shell.pellet))continue;
   const age=Math.max(0,(now-v.at)/1000),item=projectOnlineBullet(shell,Math.min(age,.35),.35);
   // In a prolonged outage, don't let an unconfirmed projectile drift forever.
   if(age>.35)continue;
   item.trail=[];item.preview=true;bullets.push(item);
  }
 }
 for(const t of tanks){const source=s.tankMap.get(t.id),live=phase==='playing'&&t.alive;
  t.scopeTime=Math.max(0,(source?.scopeTime||0)-(live?since:0));
  t.recoil=live?Math.max(0,(source?.recoil||0)-since*9):0;
  if(ownIDs.has(t.id)){if(online.shots.heard(t.id,source?.spawnSerial,source?.shotSerial))t.recoil=0;for(const v of online.shots.previews.values())if(v.owner===t.id)t.recoil=Math.max(t.recoil,Math.max(0,1-(now-v.at)/1000*9));}
 }
 while(online.effectQueue.length&&(phase!=='playing'||online.effectQueue[0].e.tick*Net.STEP_MS<=(sample?.time??Infinity))){const {e,s:origin}=online.effectQueue.shift();onlineEffect(e,origin);}
 const tickAge=phase==='playing'?since:0;
 pickups=s.pickups.map(p=>({...p,age:p.age+tickAge,life:p.life-tickAge})).filter(p=>p.life>0);phaseTime=Math.max(0,s.phaseTime-(phase==='countdown'||phase==='roundOver'?since:0));roundClock=Math.max(0,s.roundClock-tickAge);
}

function onlineHUD(){
 $('arenaStatus').textContent=phase==='onlineLobby'?'ROOM LOBBY':phase==='playing'?'ONLINE ARENA':phase==='countdown'?'GET READY':phase==='roundOver'?'ROUND COMPLETE':phase==='matchOver'?'MATCH COMPLETE':'ONLINE';
 $('roomBtn').textContent=online.code||'ROOM';$('roomBtn').title='Room '+online.code+' · '+online.latency+' ms';$('roomBtn').hidden=!online.code;
 const stale=performance.now()-(online.snapshots.at(-1)?.received||0)>250;
 $('bestInline').textContent=online.connected?(stale?'WEAK LINK · ':'')+(online.latency||'—')+' MS':'CONNECT';
 $('bestInline').title='Round-trip latency. Smoothing buffer: '+Math.round(online.buffer?.delay||0)+' ms. Moving closer to the server reduces network delay.';
 const me=controlledTank();if(me){$('weaponLabel').style.color=paintColor(POWER[me.power]?POWER[me.power].color:me.shield>0?POWER.shield.color:me.color);if(!me.alive)$('weaponLabel').textContent='TANK DOWN';}
 $('barHint').textContent='Menus do not pause online matches.';
 if(!online.connected||online.menu)$('announcer').hidden=true;
}
function initOnlineUI(){
 $('confirmKickBtn').addEventListener('click',confirmKick);
 $('cancelKickBtn').addEventListener('click',cancelKick);
 $('kickDialog').addEventListener('cancel',e=>{e.preventDefault();cancelKick();});
 try{$('pilotName').value=localStorage.getItem('leqra.name')||'';}catch(_){}
 const saveName=()=>{try{localStorage.setItem('leqra.name',$('pilotName').value.trim());}catch(_){}};
 for(const form of callsignForms()){form.addEventListener('submit',e=>{e.preventDefault();initAudio();submitCallsign(form);});form.elements.callsign.addEventListener('input',()=>{callsignStatus(form,'');syncCallsignEditors();});}
 $('createRoomBtn').addEventListener('click',()=>{const code=cleanRoomCode($('joinCode').value);if(code&&!validRoomCode(code)){setNetStatus('Use a room name of 1–128 characters on one line.',true);$('joinCode').focus();return;}initAudio();saveName();connectOnline({type:'create',code,name:$('pilotName').value});});
 const join=()=>{const code=cleanRoomCode($('joinCode').value);if(watchInvite){joinWatchInvite(code);return;}if(!validRoomCode(code)){setNetStatus('Enter a room name of 1–128 characters to join or create it.',true);$('joinCode').focus();return;}initAudio();saveName();connectOnline({type:'join',code,name:$('pilotName').value});};
 $('joinRoomBtn').addEventListener('click',join);$('joinCode').addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();join();}});$('pilotName').addEventListener('keydown',e=>{if(watchInvite&&e.key==='Enter'){e.preventDefault();join();}});
 $('onlineBackBtn').addEventListener('click',()=>{if(online.connecting)return;watchInvite=false;watchResume=null;online.inviteCode='';online.inviteWatch=false;resetWatchDialog();if($('joinDialog').open)$('joinDialog').close();if(!online.connected){mode='room';phase='menu';document.body.classList.remove('online-mode');setScreen('room');renderOnlineRoom();}});
 $('joinDialog').addEventListener('cancel',e=>{if(online.connecting){e.preventDefault();return;}watchInvite=false;watchResume=null;online.inviteWatch=false;online.inviteCode='';resetWatchDialog();if(!online.connected){mode='room';phase='menu';document.body.classList.remove('online-mode');setScreen('room');renderOnlineRoom();}});
 const leave=()=>{if(mode==='online')leaveOnline();else createLocalRoom();};
 $('leaveRoomBtn').addEventListener('click',leave);$('onlineLeaveBtn').addEventListener('click',leave);
 $('joinOtherBtn').addEventListener('click',openJoinDialog);$('addLocalBtn').addEventListener('click',()=>addRoomSeat('local'));$('addBotBtn').addEventListener('click',()=>addRoomSeat('bot'));
 $('localRoomName').addEventListener('input',()=>{localRoom.code=$('localRoomName').value;});$('roomCodeEditor').addEventListener('submit',submitRoomRename);$('onlineRoomCode').addEventListener('input',()=>{$('roomStatus').textContent='Press Rename room to update invite links for everyone.';});
 $('returnRoomBtn').addEventListener('click',returnToRoom);$('restartLocalBtn').addEventListener('click',restartLocalMatch);
 $('readyBtn').addEventListener('click',()=>{initAudio();const p=online.roomData?.players.find(p=>p.id===online.id);sendOnline({type:'ready',ready:!p?.ready});});
 $('startRoomBtn').addEventListener('click',()=>{initAudio();if(mode==='room')startMatch();else sendOnline({type:'start'});});
 $('copyInviteBtn').addEventListener('click',copyOnlineInvite);$('copyInGameBtn').addEventListener('click',copyOnlineInvite);$('roomBtn').addEventListener('click',toggleRoomMenu);$('onlineReturnBtn').addEventListener('click',toggleRoomMenu);
 setInterval(()=>{if(mode!=='online')return;if(phase!=='playing'){sendOnlineInput();if(secondLocal())sendOnlineInput(false,onlineControls(true),true);}const now=performance.now();if(online.connected&&now-online.lastPing>2000){online.lastPing=now;sendOnline({type:'ping',t:now});storeOnlineSession();}},250);
 window.addEventListener('pagehide',()=>{if(mode==='online'){clearInput();sendOnlineInput(true);storeOnlineSession();}});
 window.addEventListener('online',()=>{if(mode==='online'&&online.code&&!online.connected&&!online.connecting&&!online.manual){clearTimeout(online.retryTimer);connectOnline({type:'join',code:online.code,token:online.token,name:$('pilotName').value},true);}});
 const params=new URLSearchParams(location.search),invite=cleanRoomCode(params.get('room')||'');
 let session=null;try{session=JSON.parse(sessionStorage.getItem('leqra.session')||'null');}catch(_){}
 const validInvite=validRoomCode(invite);
 let lastKicked='';try{lastKicked=sessionStorage.getItem('leqra.kicked')||'';}catch(_){}
 if(validInvite&&lastKicked===invite){openOnline();online.manual=true;$('joinCode').value=invite;setNetStatus('You were removed from this room. Automatic joining has stopped. Joining again requires pressing Join.',true);return;}
 if(params.has('room')&&!validInvite){openOnline();setNetStatus('This invite needs a room name of 1–128 characters on one line. Enter a name or ask for a new link.',true);return;}
 const canResume=typeof session?.code==='string'&&typeof session?.token==='string'&&session.token&&validRoomCode(session.code)&&Number.isFinite(session.at)&&Date.now()-session.at>=0&&Date.now()-session.at<20000&&(!validInvite||invite===session.code);
 if(validInvite&&params.get('spectate')==='1'){
  openWatchInvite(invite,canResume?session:null);return;
 }
 if(canResume){
  openOnline();online.inviteCode=validInvite?invite:'';online.inviteResumeRetries=0;
  online.code=session.code;online.token=session.token;online.retryAt=performance.now();$('pilotName').value=typeof session.name==='string'?session.name:$('pilotName').value;
  showReconnecting();connectOnline({type:'join',code:session.code,token:session.token,name:$('pilotName').value},true);
 }else if(validInvite){
  openOnline();online.inviteCode=invite;$('joinCode').value=invite;
  connectOnline({type:'join',code:invite,name:$('pilotName').value.trim()||'PILOT'});
 }
}

// v3: one room model for local play and server-backed sessions.
function cleanPilotName(value){return [...String(value).trim()].filter(c=>/[\p{L}\p{N} _-]/u.test(c)).slice(0,16).join('').replace(/\s+/g,' ').trim();}
function createLocalRoom(){
 localRoom.self=0;localRoom.nextViewer=MAX_TANKS;
 let name='PILOT';try{name=localStorage.getItem('leqra.name')||name;}catch(_){}
 mode='room';phase='menu';online.menu=false;gameStarted=false;document.body.classList.remove('online-mode');
 localRoom.rules=loadLocalRoomRules();localRoom.code='';localRoom.players=[{id:0,member:++localRoom.nextMember,kind:'human',name,owner:0,team:localRoom.rules.teamMode==='ffa'?0:1},
  {id:1,member:++localRoom.nextMember,kind:'bot',name:'RUST',owner:0,team:0,difficulty:'normal'},
  {id:2,member:++localRoom.nextMember,kind:'bot',name:'VAPOR',owner:0,team:0,difficulty:'normal'},
  {id:3,member:++localRoom.nextMember,kind:'bot',name:'EMBER',owner:0,team:0,difficulty:'normal'}];
 if(localRoom.rules.teamMode==='teams')for(const p of localRoom.players)if(p.id!==localRoom.self)p.team=2;
 $('pilotName').value=name;$('localRoomName').value='';$('inviteFallback').hidden=true;
 document.documentElement.style.removeProperty('--pilot');$('roomBtn').hidden=false;$('roomBtn').textContent='MY ROOM';
 callsignForms().forEach(f=>delete f.dataset.currentName);readyRoom();
}
function resetPreviewIfLobby({regenerateMaze=false,resetPickups=false}={}){
 if(mode==='room'&&['menu','matchOver'].includes(phase)){
  localObjectives=null;if(regenerateMaze)makeMaze();resetTanks();bullets=[];particles=[];rings=[];traces=[];
  if(regenerateMaze||resetPickups){pickups=[];seedPickups();}
  if(!gameStarted)scores=Array(MAX_TANKS).fill(0);updateHUD(true);return;
 }
 for(const t of tanks){const p=localRoom.players.find(p=>p.id===t.id);if(p){t.name=p.name;t.team=p.team;t.color=teamColor(p.id,p.team,p.colorIndex);t.difficulty=p.difficulty||t.difficulty;}}
}
function changeTankColor(player,value){
 if(!Number.isInteger(value)||value< -1||value>7||currentRules().teamMode!=='ffa')return;
 if(mode==='online'){
  const me=localPlayerID(),host=isRoomHost();
  if(player.id===me||player.kind==='local'&&player.owner===me||host&&player.kind==='bot')sendOnline({type:'paint',target:player.id,member:player.member,colorIndex:value});
  return;
 }
 if(!['menu','matchOver'].includes(phase))return;
 const p=localRoom.players.find(p=>p.id===player.id&&p.member===player.member);if(!p)return;
 const me=localPlayerID(),host=isRoomHost();if(!(p.id===me||p.kind==='local'&&p.owner===me||host&&p.kind==='bot'))return;
 p.colorIndex=value;resetPreviewIfLobby();renderOnlineRoom();
}
function changeSeat(player,changes){
 if(changes.colorIndex!==undefined){changeTankColor(player,changes.colorIndex);return;}
 if(changes.team!==undefined&&currentRules().teamMode==='teams'&&(!Number.isInteger(changes.team)||changes.team<1||changes.team>4)){toast('Choose one of the four teams.',2);return;}
 if(currentRules().teamMode==='ffa'&&changes.team!==undefined&&changes.team!==0){toast('Free-for-all is locked by the host.',2);return;}
 if(mode==='online'){sendOnline({type:'configure',target:player.id,member:player.member,...changes});return;}
 if(!isRoomHost()||!['menu','matchOver'].includes(phase))return;
 const p=localRoom.players.find(p=>p.id===player.id&&p.member===player.member);if(!p)return;
 if(changes.team!==undefined){p.team=changes.team;if(p.team>0)delete p.colorIndex;}
 if(changes.difficulty&&DIFFICULTY[changes.difficulty])p.difficulty=changes.difficulty;
 if(changes.name){const name=cleanPilotName(changes.name);if(name)p.name=name;}
 resetPreviewIfLobby();renderOnlineRoom();
}
function addRoomSeat(kind){
 const data=roomData();if(!data||data.host!==localPlayerID())return;
 if(data.players.length>=MAX_TANKS){toast('All 8 seats are occupied. Remove a participant first.',3);return;}
 if(kind==='local'&&roomMembers(data).some(p=>p.kind==='local'))return;
 const difficulty=$('newBotDifficulty').value,team=currentRules().teamMode==='ffa'?0:kind==='local'?(roomMember(localPlayerID(),data)?.team||1):2;
 const name=kind==='local'?savedLocalCallsign():['RUST','VAPOR','EMBER','NOVA','COMET','ONYX','BLITZ'].find(n=>!data.players.some(p=>p.name===n))||'BOT';
 if(mode==='online'){sendOnline({type:'add',kind,difficulty,team,name});return;}
 let id=0;while(localRoom.players.some(p=>p.id===id))id++;
 localRoom.players.push({id,member:++localRoom.nextMember,kind,owner:localRoom.self,name,team,difficulty:kind==='bot'?difficulty:undefined});localRoom.players.sort((a,b)=>a.id-b.id);
 resetPreviewIfLobby();renderOnlineRoom();
}
function shareLocalRoom(){
 if(mode==='online'){copyOnlineInvite();return;}
 if(!['menu','matchOver'].includes(phase)){toast('Return to the room before sharing.',3);return;}
 if(!['http:','https:'].includes(location.protocol)){$('roomStatus').textContent='To share online, run the included Go server and open its webpage. Local play works here without a server.';return;}
 const code=cleanRoomCode($('localRoomName').value);
 if(code&&!validRoomCode(code)){$('roomStatus').textContent='Use a room name of 1–128 characters on one line.';return;}
 localRoom.code=code;online.publishing=true;online.roomData=null;
 const ffa=localRoom.rules.teamMode==='ffa';const roster=[localRoom.players.find(p=>p.id===localRoom.self),...localRoom.players.filter(p=>p.id!==localRoom.self)].map(({name,kind,team,difficulty,spectating,colorIndex})=>({name,kind,team,difficulty,...(ffa?{colorIndex}:{ }),spectating:!!spectating}));
 $('roomStatus').textContent='Sharing this roster with the Go server…';
 connectOnline({type:'publish',code,roster,rules:localRoom.rules});
}
function toggleRoomMenu(){
 if(mode==='online'){toggleOnlineMenu();return;}
 if(mode!=='room')return;
 if(['menu','matchOver'].includes(phase)){setScreen('room');return;}
 if(phase==='paused'){
  phase=pausedFrom;online.menu=false;clearInput();lastFrame=performance.now();accumulator=0;setScreen(null);canvas.focus({preventScroll:true});return;
 }
 pausedFrom=phase;phase='paused';online.menu=true;clearInput();setScreen('onlineMenu');$('announcer').hidden=true;if($('restartLocalBtn')){$('restartLocalBtn').hidden=false;$('restartLocalBtn').textContent=currentRules().mode==='elimination'?'Restart round ↻':'Restart match ↻';}
 $('onlineMenuEyebrow').textContent='LOCAL ROOM · PAUSED';$('onlineMenuMessage').textContent=currentRules().mode==='elimination'?'Local play is paused. Restarting the round keeps the current match score.':'Local play is paused. Return to the room to change teams, add participants, or share online.';
 $('onlineReturnBtn').disabled=false;$('onlineReturnBtn').firstElementChild.textContent='BACK TO THE ARENA';
 renderOnlineRoom();
}
function restartLocalMatch(){
 if(mode!=='room')return;
 online.menu=false;clearInput();setScreen(null);
 if(currentRules().mode==='elimination'){addLog('Round '+round+' restarted. Scores preserved.');startRound();canvas.focus({preventScroll:true});return;}
 startMatch();
}
function returnToRoom(){
 if(mode==='online'){
  if(online.roomData?.host!==online.id)return;
  if(!confirm('End this match for everyone and return to the room? Scores will reset.'))return;
  sendOnline({type:'lobby'});return;
 }
 if(mode==='room'){online.menu=false;readyRoom();}
}
function openJoinDialog(){
 watchInvite=false;watchResume=null;online.inviteWatch=false;online.inviteCode='';resetWatchDialog();
 if(mode==='online'&&online.connected){if(!confirm('Leave this online room to join another one?'))return;leaveOnline();}
 openOnline();
}

// v3.2 room rules, local presets, keyboard bindings, combat feedback and objectives.
// All game state below is local-only unless it is received in a server snapshot.
function defaultRoomRules(){return{mode:'elimination',teamMode:'ffa',teamNames:['Team 1','Team 2','Team 3','Team 4'],teamColors:[0,1,2,3],mapSize:'large',scoreTarget:5,timeLimit:75,respawnSeconds:3,pickupRate:'superfast',friendlyFire:false,weapons:Object.keys(POWER)};}
const LOCAL_RULES_KEY='leqra.roomRules.v1';
function loadLocalRoomRules(){
 try{
  const saved=JSON.parse(localStorage.getItem(LOCAL_RULES_KEY)||'null');if(!saved)return defaultRoomRules();
  const raw=saved.version===1?saved.rules:saved.rules||saved;if(!raw||typeof raw!=='object')return defaultRoomRules();
  // Merge before validation so a future release can add a rule without making an
  // otherwise valid older local configuration unusable.
  return validateRoomRules({...defaultRoomRules(),...raw});
 }catch(_){return defaultRoomRules();}
}
function persistLocalRoomRules(r=localRoom.rules){
 try{localStorage.setItem(LOCAL_RULES_KEY,JSON.stringify({version:1,rules:validateRoomRules(r)}));return true;}catch(_){return false;}
}
function currentRules(){return mode==='online'?(online.roomData?.rules||online.snapshots.at(-1)?.rules||defaultRoomRules()):localRoom.rules||defaultRoomRules();}
function objectiveMode(){return currentRules().mode!=='elimination';}
function suddenDeath(){return !!objectiveState()?.suddenDeath;}
function validateRoomRules(r){
 if(!r||!['elimination','ctf','koth'].includes(r.mode)||!['teams','ffa'].includes(r.teamMode)||!['compact','standard','large','huge','giant','ultrawide'].includes(r.mapSize)||!['superfast','fast','normal','slow','off'].includes(r.pickupRate))throw Error('Choose valid mode, format, map and pickup settings.');
 if(r.mode==='ctf'&&r.teamMode!=='teams')throw Error('Capture the Flag needs two numbered teams.');
 if(!Number.isInteger(r.scoreTarget)||r.scoreTarget<1||r.scoreTarget>(r.mode==='koth'?300:20))throw Error('Score target: 1–20, or 1–300 in Hill.');
 if(!Number.isInteger(r.timeLimit)||r.timeLimit<30||r.timeLimit>600)throw Error('Time limit must be 30–600 seconds.');
 if(!Number.isInteger(r.respawnSeconds)||r.respawnSeconds<1||r.respawnSeconds>10)throw Error('Respawn delay must be 1–10 seconds.');
 if(!Array.isArray(r.weapons)||r.weapons.length>Object.keys(POWER).length||new Set(r.weapons).size!==r.weapons.length||r.weapons.some(w=>!POWER[w]))throw Error('Invalid power-up selection.');
 if(r.friendlyFire!==undefined&&typeof r.friendlyFire!=='boolean')throw Error('Friendly fire must be on or off.');
 const teamNames=validateTeamNames(r.teamNames);const teamColors=r.teamColors??[0,1,2,3];if(!Array.isArray(teamColors)||teamColors.length!==4||teamColors.some(i=>!Number.isInteger(i)||i<0||i>7))throw Error('Choose a palette color for each team.');
 return {...JSON.parse(JSON.stringify(r)),teamNames,teamColors:[...teamColors],friendlyFire:r.friendlyFire??false};
}
function validateTeamNames(names){
 if(names===undefined||names===null)return ['Team 1','Team 2','Team 3','Team 4'];
 if(!Array.isArray(names)||names.length!==4)throw Error('Name all four teams.');
 return names.map(value=>{if(typeof value!=='string'||/[\u0000-\u001f\u007f-\u009f\u2028\u2029\p{Cs}]/u.test(value))throw Error('Team names must be on one line without control characters.');const name=value.trim();if(!name||[...name].length>24||!/[^\s\p{Cf}]/u.test(name))throw Error('Team names must contain 1–24 visible characters.');return name;});
}
const MAZE_SIZES={compact:[7,7],standard:[9,8],large:[12,10],huge:[14,12],giant:[16,14],ultrawide:[24,14]};
function mapDimensions(size=currentRules().mapSize){return MAZE_SIZES[size]||MAZE_SIZES.standard;}
function pickupCap(c=cols,r=rows){return c>0&&r>0?Math.round(c*r/9.8):0;}
function startingPickups(c=cols,r=rows){const area=c*r;return area>0?2+[49,72,120,168,224].filter(n=>area>n).length:0;}
// Whole-second expiry follows the design example: Giant cap 23 -> 61 seconds.
function pickupLifetime(c=cols,r=rows){const cap=pickupCap(c,r);return cap>0?Math.floor(cap*8/3):0;}
function seedPickups(){for(let i=0;i<startingPickups();i++)spawnPower();}
function pickupLimitText(size=currentRules().mapSize){const [c,r]=mapDimensions(size);return startingPickups(c,r)+' starting pickups · '+pickupCap(c,r)+' maximum on this maze.';}
function syncControlsPickupInfo(){const el=$('controlsPickupInfo');if(!el)return;const [c,r]=mapDimensions();el.replaceChildren(document.createTextNode(pickupLimitText()),document.createElement('br'),document.createTextNode('Uncollected power-ups expire after '+pickupLifetime(c,r)+' seconds.'));}
function pickupInterval(){return currentRules().pickupRate==='off'?[Infinity,Infinity]:currentRules().pickupRate==='superfast'?[1,2]:currentRules().pickupRate==='normal'?[4,6]:currentRules().pickupRate==='slow'?[7,10]:[2,3.5];}
function roomStartError(data=roomData()){
 const players=data?.players.filter(p=>p.connected!==false)||[],r=data?.rules||currentRules();
 if(new Set(players.map(teamKey)).size<2)return 'Choose at least two opposing sides.';
 if(r.mode==='ctf'&&(players.some(p=>!p.team)||new Set(players.map(p=>p.team)).size!==2))return 'Capture the Flag needs exactly two numbered teams. Assign every participant.';
 return '';
}
function setLocalRules(value){
 const previous=localRoom.rules||defaultRoomRules(),rules=validateRoomRules(value),wasFFA=previous.teamMode==='ffa',mapChanged=previous.mapSize!==rules.mapSize,pickupSetupChanged=previous.pickupRate!==rules.pickupRate||previous.weapons.join('|')!==rules.weapons.join('|');localRoom.rules=rules;roundClock=rules.timeLimit;
 for(const p of localRoom.players){if(rules.teamMode==='ffa')p.team=0;else{if(wasFFA||p.team<1||p.team>4)p.team=p.id===localRoom.self||p.kind==='local'?1:2;delete p.colorIndex;}}
 persistLocalRoomRules(rules);
 resetPreviewIfLobby({regenerateMaze:mapChanged,resetPickups:pickupSetupChanged});renderOnlineRoom();
}
function modeLabel(){return {elimination:'ELIMINATION',ctf:'CAPTURE THE FLAG',koth:'KING OF THE HILL'}[currentRules().mode];}
function modeInstructions(){return currentRules().mode==='ctf'?'Steal an enemy flag and bring it to your base. Your own flag must be home.':currentRules().mode==='koth'?'Hold the hill alone or with allies. Opposing sides contest it; nobody scores.':'Eliminate every opposing side to win the round.';}
function displayScoreTarget(){const r=currentRules();return r.mode==='koth'?r.scoreTarget+' HILL POINTS':r.mode==='ctf'?r.scoreTarget+' CAPTURES':'FIRST TO '+r.scoreTarget;}
function isRoomHost(){return roomData()?.host===localPlayerID();}
function isRoomEditable(){const r=roomData();return isRoomHost()&&!r?.queue&&!r?.matchmaking&&!r?.awayMatch&&['menu','onlineLobby','matchOver'].includes(phase);}
function featureNotice(id,text,error=false){const n=$(id);n.textContent=text;n.classList.toggle('error',error);}
function openFeature(kind){
 closeChat();clearInput();if(mode==='online')sendOnlineInput(true);
 if(kind==='rules')fillRulesForm();if(kind==='presets')renderPresets();if(kind==='controls')renderBindings();
 const d=$(kind+'Dialog');if(!d.open)d.showModal();
}
function closeFeature(d){bindingCapture=null;d.close();clearInput();if(mode==='online')sendOnlineInput(true);}
function syncFeatureSummary(){
 if(!$('rulesSummary'))return;
 const r=currentRules(),host=isRoomHost();
 $('rulesSummary').textContent=modeLabel()+' · '+(r.teamMode==='ffa'?'FREE-FOR-ALL':'TEAMS')+' · '+displayScoreTarget();
 $('rulesSummary').textContent+=' · FRIENDLY FIRE '+(r.friendlyFire?'ON':'OFF');
 $('rulesSummary').title=modeInstructions();$('roomRulesBtn').textContent=host?'RULES & MODE':'VIEW RULES';
 $('roomPresetsBtn').disabled=!host;
 $('readyHint').textContent=roomStartError()|| (mode==='online'&&!online.roomData?.canStart?'WAITING FOR GUESTS TO READY UP':displayScoreTarget()+' · START WHEN READY');
 $('startRoomBtn').disabled=!isRoomEditable()||!!roomStartError()||mode==='online'&&!online.roomData?.canStart;
 $('localControlsNote').textContent=controlSummary(0)+' · '+controlSummary(1)+'. Player 2 needs a keyboard.';
 $('manualContent').innerHTML=fieldManualHTML();
 if($('rulesDialog').open){$('rulesFields').disabled=!isRoomEditable();$('applyRulesBtn').disabled=!isRoomEditable();updateRuleHelp();}
 if($('presetsDialog').open){$('loadPresetBtn').disabled=!canLoadPreset();$('savePresetBtn').disabled=!host;}
}
function fillRulesForm(){
 const r=currentRules();for(const k of ['mode','teamMode','mapSize','scoreTarget','timeLimit','respawnSeconds','pickupRate'])$('rule-'+k).value=r[k];
 $('rule-friendlyFire').checked=!!r.friendlyFire;
 for(let i=1;i<=4;i++){$('rule-teamName'+i).value=teamName(i,r);const box=$('rule-teamName'+i).parentElement;if(!box.querySelector('[data-team-palette]')){const picker=makeColorSelect(r.teamColors?.[i-1]??i-1,()=>{},'Color for team '+i);picker.querySelector('select').id='rule-teamColor'+i;picker.dataset.teamPalette=i;box.append(picker);}const sel=$('rule-teamColor'+i);sel.value=r.teamColors?.[i-1]??i-1;sel.previousElementSibling.style.background=Theme.colors[+sel.value];}
 for(const c of document.querySelectorAll('[data-weapon-toggle]'))c.checked=r.weapons.includes(c.dataset.weaponToggle);
 $('rulesFields').disabled=!isRoomEditable();$('applyRulesBtn').disabled=!isRoomEditable();
 featureNotice('rulesNotice',isRoomEditable()?'Changes reset guest readiness. Rules are fixed for the match.':'Only the host can change rules, between matches.');updateRuleHelp();renderPowerLegend();
}
function updateRuleHelp(){
 const m=$('rule-mode').value;
 $('rule-teamMode').disabled=m==='ctf'||!isRoomEditable();if(m==='ctf')$('rule-teamMode').value='teams';
 $('rule-scoreTarget').max=m==='koth'?300:20;$('rule-respawnSeconds').disabled=m==='elimination'||!isRoomEditable();
 $('ruleScoreLabel').textContent=m==='koth'?'HILL POINTS TO WIN':m==='ctf'?'CAPTURES TO WIN':'ROUND WINS TO WIN';
 const [mc,mr]=mapDimensions($('rule-mapSize').value);$('rule-pickup-density').textContent=$('rule-pickupRate').value==='off'?'Pickups disabled.':pickupLimitText($('rule-mapSize').value)+' Uncollected power-ups expire after '+pickupLifetime(mc,mr)+' seconds.';
 $('rule-help').textContent=m==='ctf'?'Two numbered teams. Carry the enemy flag home; your own flag must be at base. Dropped flags return after 12s. Respawns are enabled. A tied time limit triggers sudden death: last side surviving wins.':m==='koth'?'Teams or Free-for-all. Hold the marked hill for 1 point per second. Contested hills give no points. Respawns are enabled. A tied time limit triggers sudden death: last side surviving wins.':'Last side standing wins a round. No respawns until the next round.';
}
function submitRules(e){
 e.preventDefault();if(!isRoomEditable())return;
 try{const r={};for(const k of ['mode','teamMode','mapSize','pickupRate'])r[k]=$('rule-'+k).value;for(const k of ['scoreTarget','timeLimit','respawnSeconds'])r[k]=Number($('rule-'+k).value);r.teamNames=Array.from({length:4},(_,i)=>$('rule-teamName'+(i+1)).value);r.teamColors=Array.from({length:4},(_,i)=>Number($('rule-teamColor'+(i+1)).value));r.friendlyFire=$('rule-friendlyFire').checked;r.weapons=[...document.querySelectorAll('[data-weapon-toggle]:checked')].map(c=>c.dataset.weaponToggle);validateRoomRules(r);
  if(mode==='online'){if(!sendOnline({type:'rules',rules:r}))throw Error('Connection unavailable. Rules were not sent.');featureNotice('rulesNotice','Waiting for the server…');rulesPending=true;}
  else{setLocalRules(r);closeFeature($('rulesDialog'));}
 }catch(e){featureNotice('rulesNotice',e.message,true);}
}
// Binding conflicts are rejected across both local players, even with P2 absent.
function defaultBindings(){return[{forward:'KeyW',reverse:'KeyS',left:'KeyA',right:'KeyD',fire:'KeyQ'},{forward:'ArrowUp',reverse:'ArrowDown',left:'ArrowLeft',right:'ArrowRight',fire:'Space'}];}
function validBinding(code){return /^(Key[A-Z]|Digit[0-9]|Arrow(Up|Down|Left|Right)|Space|Enter|Shift(Left|Right)|Control(Left|Right)|Numpad[0-9]|Numpad(Enter|Add|Subtract|Multiply|Divide)|Comma|Period|Slash|Semicolon|Quote|Bracket(Left|Right)|Backslash|Minus|Equal)$/.test(code)&&!['KeyP','KeyM','KeyF','ControlLeft','ControlRight'].includes(code);}
function validateBindings(value){const actions=['forward','reverse','left','right','fire'],seen=new Set();if(!Array.isArray(value)||value.length!==2)return null;for(const p of value){for(const a of actions){const c=p?.[a];if(!validBinding(c)||seen.has(c))return null;seen.add(c);}}return value.map(p=>Object.fromEntries(actions.map(a=>[a,p[a]])));}
function loadBindings(){try{const data=JSON.parse(localStorage.getItem('leqra.bindings.v1')),raw=data?.bindings;if(!Array.isArray(raw)||raw.length!==2)return defaultBindings();const migrated=raw.map(p=>({...p})),defaults=defaultBindings(),used=new Set();for(const p of migrated)for(const a of ['forward','reverse','left','right','fire'])if(p?.[a]&&p[a]!=='KeyF')used.add(p[a]);let changed=false;for(let i=0;i<2;i++)for(const a of ['forward','reverse','left','right','fire'])if(migrated[i]?.[a]==='KeyF'){let replacement=defaults[i][a];if(used.has(replacement))replacement=['KeyQ','KeyE','KeyR','KeyT','KeyG','KeyV','KeyB','KeyN','KeyX','KeyC','KeyZ','Enter'].find(k=>validBinding(k)&&!used.has(k))||replacement;migrated[i][a]=replacement;used.add(replacement);changed=true;}const old=validateBindings(migrated);if(!old)return defaultBindings();if(changed)try{localStorage.setItem('leqra.bindings.v1',JSON.stringify({version:3,bindings:old}));}catch(_){}return old;}catch(_){return defaultBindings();}}
function keyLabel(code){return code==='Space'?'SPACE':code==='ArrowUp'?'↑':code==='ArrowDown'?'↓':code==='ArrowLeft'?'←':code==='ArrowRight'?'→':code.replace(/^Key/,'').replace(/^Digit/,'').replace(/^Numpad/,'NUM ').replace(/Left$/,' L').replace(/Right$/,' R').toUpperCase();}
function defaultPrimary(){const b=bindings[0];return b.forward==='KeyW'&&b.reverse==='KeyS'&&b.left==='KeyA'&&b.right==='KeyD'&&b.fire==='KeyQ';}
function aliasesActive(){return !hasLocalP2()&&defaultPrimary();}
function keyForAction(index,action,code){return bindings[index][action]===code||(index===0&&aliasesActive()&&({forward:'ArrowUp',reverse:'ArrowDown',left:'ArrowLeft',right:'ArrowRight',fire:'Space'})[action]===code);}
function heldAction(index,action){if(keys.has(bindings[index][action]))return true;if(index!==0||!aliasesActive())return false;const a={forward:'ArrowUp',reverse:'ArrowDown',left:'ArrowLeft',right:'ArrowRight',fire:'Space'};return keys.has(a[action]);}
function isWeaponKey(code){return keyForAction(0,'fire',code)||hasLocalP2()&&keyForAction(1,'fire',code);}
function isControlKey(code){return ['forward','reverse','left','right','fire'].some(a=>keyForAction(0,a,code)||hasLocalP2()&&keyForAction(1,a,code));}
function controlSummary(index,prefix=true){const b=bindings[index],moves=[b.forward,b.left,b.reverse,b.right].map(keyLabel).join(' ');return(prefix?'P'+(index+1)+': ':'')+moves+' + '+keyLabel(b.fire)+(index===0&&aliasesActive()?' / SPACE':'');}
function manualKeyRow(codes){return '<div class="keys">'+codes.map(code=>'<kbd>'+escapeHTML(keyLabel(code))+'</kbd>').join('')+'</div>';}
function fieldManualHTML(){
 let html='';
 if(!hasLocalP2()&&aliasesActive()){
  html+='<div class="manual-line manual-move-line"><span>Move &amp; steer</span><div class="manual-key-options">'+manualKeyRow(['ArrowUp','ArrowLeft','ArrowDown','ArrowRight'])+'<span class="manual-or">OR</span>'+manualKeyRow(['KeyW','KeyA','KeyS','KeyD'])+'</div></div>';
  html+='<div class="manual-line"><span>Fire / detonate</span><div class="keys"><kbd>Q</kbd><span class="manual-or">OR</span><kbd>SPACE</kbd></div></div>';
 }else{
  html+='<div class="manual-line"><span>Player 1</span><kbd>'+escapeHTML(controlSummary(0,false))+'</kbd></div>';
  if(hasLocalP2())html+='<div class="manual-line"><span>Player 2</span><kbd>'+escapeHTML(controlSummary(1,false))+'</kbd></div>';
 }
 html+='<div class="manual-line"><span>Fullscreen</span><kbd>F</kbd></div><div class="warning"><b>'+escapeHTML(modeLabel())+'</b><br>'+escapeHTML(modeInstructions())+'<br>Use Controls menu to change keys.</div>';
 return html;
}
function renderBindings(){
 const grid=$('bindingGrid');grid.replaceChildren();
 for(let p=0;p<2;p++){const section=document.createElement('section');section.className='binding-player';section.innerHTML='<h3>PLAYER '+(p+1)+'</h3>';
  for(const [action,label]of [['forward','Forward'],['reverse','Reverse'],['left','Turn left'],['right','Turn right'],['fire','Fire / detonate']]){const row=document.createElement('div');row.className='binding-row';const span=document.createElement('span');span.textContent=label;const button=document.createElement('button');button.type='button';button.className='secondary binding-key';button.dataset.bind=p+':'+action;button.textContent=keyLabel(bindings[p][action]);button.setAttribute('aria-label','Rebind player '+(p+1)+' '+label);button.onclick=()=>{bindingCapture={p,action};for(const b of grid.querySelectorAll('button'))b.classList.remove('capturing');button.classList.add('capturing');button.textContent='PRESS KEY';featureNotice('controlsNotice','Press a key. Escape cancels. P, M, F, Tab and system shortcuts are reserved.');};row.append(span,button);section.append(row);}grid.append(section);
 }
 $('missileVisuals').checked=combatPrefs.visual;$('missileAudio').checked=combatPrefs.audio;if($('showFPS'))$('showFPS').checked=combatPrefs.fps;if($('performanceMode'))$('performanceMode').checked=combatPrefs.performance;
 syncControlsPickupInfo();featureNotice('controlsNotice','Click a binding to change it. Conflicts are rejected. Settings are saved on this device.');
}
function captureBinding(e){
 if(!bindingCapture||!$('controlsDialog').open)return;
 e.preventDefault();e.stopImmediatePropagation();if(e.repeat)return;
 if(e.code==='Escape'){bindingCapture=null;renderBindings();return;}
 if(e.ctrlKey||e.metaKey||e.altKey||!validBinding(e.code)){featureNotice('controlsNotice','That key is reserved or unsupported. Choose a letter, number, arrow, Shift, or Space.',true);return;}
 const next=bindings.map(b=>({...b})),{p,action}=bindingCapture;next[p][action]=e.code;
 if(!validateBindings(next)){featureNotice('controlsNotice','That key is already assigned. Change the other binding first.',true);return;}
 bindings=next;bindingCapture=null;clearInput();let saved=true;try{localStorage.setItem('leqra.bindings.v1',JSON.stringify({version:1,bindings}));}catch(_){saved=false;}
 renderBindings();syncFeatureSummary();updateHUD(true);featureNotice('controlsNotice',saved?'Binding saved.':'Binding changed for this session; storage is unavailable.',!saved);
}
function readCombatPrefs(){try{const p=JSON.parse(localStorage.getItem('leqra.feedback.v1'));return{visual:p?.visual!==false,audio:p?.audio!==false,fps:p?.fps===true,performance:p?.performance===true};}catch(_){return{visual:true,audio:true,fps:false,performance:false};}}
function loadPresets(){try{const p=JSON.parse(localStorage.getItem('leqra.presets.v1'));return p?.version===1&&Array.isArray(p.items)?p.items.slice(0,12).filter(x=>typeof x?.name==='string'&&x.name.length<=40):[];}catch(_){return[];}}
function builtinPresets(){
 const human={kind:'human',name:roomMember(localPlayerID())?.name||'PILOT',team:1},bot=(name,team,difficulty='normal')=>({kind:'bot',name,team,difficulty}),local={kind:'local',name:savedLocalCallsign(),team:1};
 const ffaBots=['RUST','VAPOR','EMBER','NOVA','COMET','ONYX','BLITZ'];
 return [{name:'Solo practice',rules:{...defaultRoomRules(),mapSize:'compact'},roster:[human,bot('RUST',2,'easy')]},
 {name:'Local duel',rules:{...defaultRoomRules(),teamMode:'ffa'},roster:[{...human,team:0},{...local,team:0}]},
 {name:'4-tank Free-for-all',rules:{...defaultRoomRules(),teamMode:'ffa',mapSize:'large'},roster:[{...human,team:0},...ffaBots.slice(0,3).map(n=>bot(n,0))]},
 {name:'8-tank Free-for-all',rules:{...defaultRoomRules(),teamMode:'ffa',mapSize:'giant'},roster:[{...human,team:0},...ffaBots.map(n=>bot(n,0))]},
 {name:'Two humans vs. bots',rules:{...defaultRoomRules(),teamMode:'teams'},roster:[human,local,bot('RUST',2),bot('VAPOR',2)]},
 {name:'Capture the Flag',rules:{...defaultRoomRules(),teamMode:'teams',mode:'ctf',scoreTarget:3,timeLimit:180},roster:[human,bot('EMBER',1),bot('RUST',2),bot('VAPOR',2)]},
 {name:'King of the Hill',rules:{...defaultRoomRules(),mode:'koth',teamMode:'ffa',scoreTarget:60,timeLimit:180},roster:[{...human,team:0},bot('RUST',0),bot('VAPOR',0),bot('EMBER',0)]}];
}
function validatePreset(p){
 const rules=validateRoomRules(p.rules);if(!Array.isArray(p.roster)||p.roster.length<1||p.roster.length>MAX_TANKS)throw Error('Invalid preset roster.');let local=0;
 const roster=p.roster.map((s,i)=>{if((i===0?s.kind!=='human':!['bot','local'].includes(s.kind))||!Number.isInteger(s.team)||s.team<0||s.team>4||!cleanPilotName(s.name)||s.kind==='bot'&&!DIFFICULTY[s.difficulty])throw Error('Invalid preset participant.');if(s.kind==='local')local++;if(s.colorIndex!=null&&(!Number.isInteger(s.colorIndex)||s.colorIndex< -1||s.colorIndex>7))throw Error('Invalid tank color.');return{kind:s.kind,name:cleanPilotName(s.name),colorIndex:rules.teamMode==='ffa'?(s.colorIndex??-1):undefined,team:rules.teamMode==='ffa'?0:s.team>0?s.team:i===0||s.kind==='local'?1:2,...(s.kind==='bot'?{difficulty:s.difficulty}:{})};});
 if(local>1)throw Error('Only one secondary local player is supported.');return{rules,roster};
}
function snapshotPreset(){const r=roomData(),me=roomMember(localPlayerID(),r);const ffa=currentRules().teamMode==='ffa';return{rules:validateRoomRules(currentRules()),roster:[{name:me.name,kind:'human',team:me.team,...(ffa?{colorIndex:me.colorIndex??-1}:{})},...r.players.filter(p=>p.kind==='bot'||p.kind==='local'&&p.owner===me.id).map(({name,kind,team,difficulty,colorIndex})=>({name,kind,team,difficulty,...(ffa?{colorIndex:colorIndex??-1}:{})}))]};}
function canLoadPreset(){return isRoomEditable()&&!roomData()?.spectators?.length&&(mode!=='online'||!roomData().players.some(p=>p.id!==online.id&&p.kind!=='bot'&&p.kind!=='local'));}
function renderPresets(){
 const select=$('presetSelect');const chosen=select.value;select.replaceChildren();const builtins=builtinPresets();for(const [group,items,prefix]of [['QUICK SETUPS',builtins,'builtin'],['SAVED ON THIS DEVICE',savedPresets,'saved']]){const opt=document.createElement('optgroup');opt.label=group;items.forEach((p,i)=>{const o=document.createElement('option');o.value=prefix+':'+i;o.textContent=p.name;opt.append(o);});select.append(opt);}
 if([...select.options].some(o=>o.value===chosen))select.value=chosen;
 $('loadPresetBtn').disabled=!canLoadPreset();$('savePresetBtn').disabled=!isRoomHost();$('deletePresetBtn').disabled=!select.value.startsWith('saved:');
 featureNotice('presetsNotice',canLoadPreset()?'Presets save names, local seats, bots, teams and rules. Online guests and credentials are never saved.':'Loading requires a host-only lobby without spectators or online guests, including reconnecting members. It never replaces someone else’s place.');
}
function applyLocalPreset(p){
 const valid=validatePreset(p),mapChanged=(localRoom.rules?.mapSize||'')!==valid.rules.mapSize;localRoom.self=0;localRoom.nextViewer=MAX_TANKS;localRoom.rules=valid.rules;roundClock=valid.rules.timeLimit;round=1;localRoom.players=valid.roster.map((s,id)=>({...s,id,member:++localRoom.nextMember,owner:0}));
 persistLocalRoomRules(valid.rules);
 rememberCallsign(localRoom.players[0].name);const p2=localRoom.players.find(p=>p.kind==='local');if(p2)rememberLocalCallsign(p2.name);
 phase='menu';gameStarted=false;online.menu=false;scores=Array(MAX_TANKS).fill(0);clearInput();resetPreviewIfLobby({regenerateMaze:mapChanged,resetPickups:true});setScreen('room');renderOnlineRoom();
}
function selectedPreset(){const [type,index]=$('presetSelect').value.split(':');return(type==='builtin'?builtinPresets():savedPresets)[Number(index)];}
function applySelectedPreset(){try{if(!canLoadPreset())throw Error('Presets cannot replace spectators, online guests, or an active match.');const p=validatePreset(selectedPreset());if(mode==='online'){if(!sendOnline({type:'preset',...p}))throw Error('Connection unavailable.');presetsPending=true;featureNotice('presetsNotice','Waiting for the server…');}else{applyLocalPreset(p);closeFeature($('presetsDialog'));}}catch(e){featureNotice('presetsNotice',e.message,true);}}
function saveCurrentPreset(){try{if(!isRoomHost())throw Error('Only the host can save the room setup.');const name=$('presetName').value.trim().slice(0,40);if(!name)throw Error('Give this preset a name.');const preset={...validatePreset(snapshotPreset()),name},next=savedPresets.slice(),index=next.findIndex(p=>p.name===name);if(index>=0){if(!confirm('Replace the saved preset “'+name+'”?'))return;next[index]=preset;}else{if(next.length>=12)throw Error('Delete a preset first (12 saved presets maximum).');next.push(preset);}localStorage.setItem('leqra.presets.v1',JSON.stringify({version:1,items:next}));savedPresets=next;renderPresets();$('presetSelect').value='saved:'+(index>=0?index:next.length-1);$('deletePresetBtn').disabled=false;featureNotice('presetsNotice','Preset saved on this device. Online guests were omitted.');}catch(e){featureNotice('presetsNotice',e.message||'Browser storage is unavailable.',true);}}
function deleteSelectedPreset(){const [kind,n]=$('presetSelect').value.split(':');if(kind!=='saved')return;const item=savedPresets[+n];if(!item||!confirm('Delete preset “'+item.name+'”?'))return;try{const next=savedPresets.filter((_,i)=>i!==+n);localStorage.setItem('leqra.presets.v1',JSON.stringify({version:1,items:next}));savedPresets=next;renderPresets();}catch(_){featureNotice('presetsNotice','Could not save the deletion; browser storage is unavailable.',true);}}

// Local objective simulation mirrors the authoritative Go rules. Network clients
// only render the objective state sent by the server; they never award points.
function initObjectives(){
 localObjectives=null;if(!objectiveMode())return;
 const p=center(Math.floor(rows/2)*cols+Math.floor(cols/2));localObjectives={mode:currentRules().mode,flags:[],hillX:p.x,hillY:p.y,radius:32,owner:0,contested:false,hold:0};
 if(localObjectives.mode==='ctf'){const teams=[...new Set(tanks.map(t=>t.team).filter(t=>t>0))].sort((a,b)=>a-b);localObjectives.flags=teams.slice(0,2).map((team,i)=>{const x=i?W-CELL*1.5:CELL*1.5,y=i?CELL*1.5:H-CELL*1.5;return{team,homeX:x,homeY:y,x,y,carrier:-1,home:true,returnIn:0};});for(const t of tanks)if(t.alive)respawnLocalTank(t);}
}
function objectiveState(){return mode==='online'?online.snapshots.at(-1)?.objectives:localObjectives;}
function resetLocalFlag(f){Object.assign(f,{x:f.homeX,y:f.homeY,carrier:-1,home:true,returnIn:0});}
function dropLocalFlags(id){if(!localObjectives)return;for(const f of localObjectives.flags){if(f.carrier!==id)continue;const t=tanks.find(t=>t.id===id);if(t){f.x=t.x;f.y=t.y;}Object.assign(f,{carrier:-1,home:false,returnIn:12});addLog('Flag dropped · touch to return');}}
function flagSafeSpawn(t,cell,p){return !localObjectives||localObjectives.mode!=='ctf'||localObjectives.flags.every(f=>f.team!==t.team||(cell!==cellAt(f.homeX,f.homeY)&&distance(p,f)>=t.r+32));}
function respawnLocalTank(t){
 const home=localObjectives?.flags.find(f=>f.team===t.team),corners=spawnCells(),base=home?cellAt(home.homeX,home.homeY):corners[t.id%MAX_TANKS];
 const q=[base],seen=new Set(q);let best=-Infinity,point=null;
 for(let k=0;k<q.length;k++){
  const cell=q[k];for(const n of grid[cell]?.neighbors||[])if(!seen.has(n)){seen.add(n);q.push(n);}
  const p=center(cell);if(!flagSafeSpawn(t,cell,p))continue;
  let clearance=500;for(const o of tanks)if(o.id!==t.id&&o.alive)clearance=Math.min(clearance,distance(p,o)-o.r-t.r);for(const b of bullets)if(!b.dead)clearance=Math.min(clearance,distance(p,b)-50);
  if(clearance>best){best=clearance;point=p;}if(clearance>70)break;
 }
 if(!point){for(let cell=0;cell<cols*rows;cell++){const p=center(cell);if(flagSafeSpawn(t,cell,p)){point=p;break;}}}
 if(!point){t.alive=false;t.respawnTime=.1;return;}
 const fresh=newTank(t.id,base),serial=(t.spawnSerial||0)+1;Object.assign(t,fresh,point,{spawnSerial:serial,invulnerable:1.2,respawnTime:0,cooldownTotal:0,fireBlocked:false,fireHeld:false});firePresses.delete(t.id);addRing(t.x,t.y,t.color,38);
}
function respawnLocalPlayers(dt){if(!localObjectives||suddenDeath())return;for(const t of tanks){if(t.alive)continue;t.respawnTime=Math.max(0,(t.respawnTime||0)-dt);if(t.respawnTime<=0)respawnLocalTank(t);}}
function endLocalObjective(winner){if(phase!=='playing')return;bullets=[];finishMatch(winner);}
function addObjectivePoint(t){if(suddenDeath()||phase!=='playing'||!tanks.includes(t))return;scores[t.id]=Math.max(scores[t.id]||0,...tanks.filter(o=>teamKey(o)===teamKey(t)).map(o=>scores[o.id]||0))+1;if(t.team>0)for(const o of tanks)if(o.team===t.team)scores[o.id]=scores[t.id];if(scores[t.id]>=currentRules().scoreTarget)endLocalObjective(t.id);}
function objectiveLeader(){const groups=new Map();for(const t of tanks)if(!groups.has(teamKey(t)))groups.set(teamKey(t),t);let top=-1,winner=-1,tie=false;for(const t of groups.values()){const s=scores[t.id];if(s>top){top=s;winner=t.id;tie=false;}else if(s===top)tie=true;}return tie?-1:winner;}
function stepLocalObjectives(dt){
 const o=localObjectives;if(!o||phase!=='playing')return;if(o.suddenDeath){stepLocalSuddenDeath();return;}
 for(const f of o.flags){if(f.carrier>=0){const t=tanks.find(t=>t.id===f.carrier);if(!t?.alive)dropLocalFlags(f.carrier);else{f.x=t.x;f.y=t.y;}}if(!f.home&&f.carrier<0){f.returnIn-=dt;if(f.returnIn<=0)resetLocalFlag(f);}}
 const touching=(t,f)=>distance(t,f)<t.r+14&&!rayWalls(t.x,t.y,f.x-t.x,f.y-t.y,0);
 if(o.mode==='ctf'){
  for(const t of tanks)if(t.alive&&t.invulnerable<=0)for(const f of o.flags)if(f.team===t.team&&!f.home&&f.carrier<0&&touching(t,f)){recordLocalObjective(t,'flagReturns');resetLocalFlag(f);addLog(t.name+' returned the flag.');}
  for(const t of tanks){if(!t.alive||t.invulnerable>0)continue;const own=o.flags.find(f=>f.team===t.team);if(!own)continue;let carried=o.flags.find(f=>f.carrier===t.id);
   if(!carried){const enemy=o.flags.find(f=>f.team!==t.team&&f.carrier<0&&touching(t,f));if(enemy){Object.assign(enemy,{carrier:t.id,home:false,returnIn:0,x:t.x,y:t.y});carried=enemy;addLog(t.name+' took the enemy flag.');}}
   if(carried&&own.home&&distance(t,{x:own.homeX,y:own.homeY})<t.r+17&&!rayWalls(t.x,t.y,own.homeX-t.x,own.homeY-t.y,0)){recordLocalObjective(t,'captures');resetLocalFlag(carried);addObjectivePoint(t);pickupSound();toast(teamName(t.team)+' CAPTURED · +1',2);if(phase!=='playing')return;}
  }
 }else if(o.mode==='koth'){
  let side=0,owner=null,sideCount=0;for(const t of tanks)if(t.alive&&t.invulnerable<=0&&Math.hypot(t.x-o.hillX,t.y-o.hillY)<=o.radius&&!rayWalls(o.hillX,o.hillY,t.x-o.hillX,t.y-o.hillY,0)){const key=t.team>0?t.team:-t.id-1;if(!sideCount){side=key;owner=t;sideCount=1;}else if(key!==side){sideCount=2;break;}}
  o.contested=sideCount>1;if(sideCount!==1){o.owner=0;o.hold=0;}else{for(const pilot of tanks)if(pilot.alive&&pilot.invulnerable<=0&&(pilot.team>0?pilot.team:-pilot.id-1)===side&&Math.hypot(pilot.x-o.hillX,pilot.y-o.hillY)<=o.radius&&!rayWalls(o.hillX,o.hillY,pilot.x-o.hillX,pilot.y-o.hillY,0))recordLocalObjective(pilot,'hillSeconds',dt);if(o.owner!==side)o.hold=0;o.owner=side;o.hold+=dt;while(o.hold>=1-1e-9){o.hold=Math.max(0,o.hold-1);addObjectivePoint(owner);if(phase!=='playing')return;}}
 }
 if(roundClock<=0){const leader=objectiveLeader();if(leader>=0)endLocalObjective(leader);else beginLocalSuddenDeath();}
}
function objectiveGoal(t){const o=localObjectives;if(!o||o.suddenDeath)return null;if(o.mode==='koth')return{x:o.hillX,y:o.hillY};const own=o.flags.find(f=>f.team===t.team),enemy=o.flags.find(f=>f.team!==t.team),carried=o.flags.find(f=>f.carrier===t.id);if(!own||!enemy)return null;if(!own.home&&(carried||t.id%2===0))return own;if(carried)return{x:own.homeX,y:own.homeY};if(enemy.carrier>=0){const c=tanks.find(t=>t.id===enemy.carrier);if(c?.team===t.team)return !own.home?own:{x:own.homeX,y:own.homeY};}return enemy;}
function objectiveRoute(t,point){const a=t.ai,goal=cellAt(point.x,point.y);if(a.goal!==goal||a.pathClock<=0||!a.path.length){a.goal=goal;a.pathClock=.45;a.path=bfs(cellAt(t.x,t.y),goal,a);}const v=routeControl(t,{...point,r:RADIUS});if(distance(t,point)<10)v.drive=0;return v;}
function shortTeamName(team){const s=Array.from(teamName(team));return s.length>14?s.slice(0,13).join('')+'…':s.join('');}
function drawObjectives(){
 const o=objectiveState();if(!o||!objectiveMode()||o.suddenDeath||['menu','onlineLobby','matchOver'].includes(phase))return;
 ctx.save();ctx.font='bold '+Math.max(10,9/scale)+'px ui-monospace,monospace';ctx.textAlign='center';
 if(o.mode==='koth'){
  const owner=o.owner>0?teamColor(0,o.owner):o.owner<0?(tanks.find(t=>t.id===-o.owner-1)?.color||COLORS[-o.owner-1]):null;ctx.fillStyle=paintColor(o.contested?'#ff96792b':owner?owner+'2b':theme.neutralHillFill);ctx.strokeStyle=paintColor(o.contested?'#ff9679':owner||theme.neutralHill);ctx.lineWidth=2;ctx.beginPath();ctx.arc(o.hillX,o.hillY,o.radius,0,TAU);ctx.fill();ctx.stroke();ctx.fillStyle=paintColor(ctx.strokeStyle);ctx.fillText(o.contested?'CONTESTED':'HILL',o.hillX,o.hillY+4);ctx.lineWidth=4;ctx.beginPath();ctx.arc(o.hillX,o.hillY,o.radius+4,-Math.PI/2,-Math.PI/2+TAU*(o.hold||0));ctx.stroke();
 }else for(const f of o.flags){
  const color=teamColor(0,f.team);ctx.strokeStyle=paintColor(color);ctx.fillStyle=paintColor(color+'28');ctx.lineWidth=3;ctx.beginPath();ctx.arc(f.homeX,f.homeY,32,0,TAU);ctx.fill();ctx.setLineDash([5,4]);ctx.stroke();ctx.setLineDash([]);
 }
 ctx.restore();
}
// Ground layer: flags and tethers are rendered BEFORE every tank.
// A tank can never be hidden under its own flag; minimum marker size is retained.
function drawFlags(){
 const o=objectiveState();if(!o||o.mode!=='ctf'||o.suddenDeath||['menu','onlineLobby','matchOver'].includes(phase))return;
 for(const f of o.flags){
  const t=f.carrier>=0?tanks.find(t=>t.id===f.carrier):null,color=teamColor(0,f.team);
  const anchor={x:t?.x??f.x,y:t?.y??f.y},z=Math.max(1.35,1/scale);
  const x=clamp(anchor.x,40*z,W-40*z),y=clamp(anchor.y-(t?44*z:12*z),26*z,H-36*z);
  ctx.save();ctx.strokeStyle=paintColor(color);ctx.lineWidth=2/scale;ctx.globalAlpha=.8;
  ctx.beginPath();ctx.arc(anchor.x,anchor.y,24+(reduceMotion?0:Math.sin(fxTime*3)*2),0,TAU);ctx.stroke();
  ctx.beginPath();ctx.moveTo(anchor.x,anchor.y);ctx.lineTo(x,y+12*z);ctx.stroke();ctx.globalAlpha=1;
  ctx.translate(x,y);ctx.scale(z,z);ctx.fillStyle=paintColor('#101a24ee');ctx.strokeStyle=paintColor(color);ctx.lineWidth=1.7;
  roundRect(ctx,-21,-23,42,43,8);ctx.fill();ctx.stroke();
  ctx.lineCap='round';ctx.strokeStyle=paintColor('#050b13');ctx.lineWidth=5;ctx.beginPath();ctx.moveTo(-9,13);ctx.lineTo(-9,-17);ctx.stroke();ctx.strokeStyle=paintColor('#fffef2');ctx.lineWidth=2.5;ctx.stroke();
  ctx.fillStyle=paintColor(color);ctx.strokeStyle=paintColor('#fffef2');ctx.lineWidth=1.4;ctx.beginPath();ctx.moveTo(-7,-17);ctx.lineTo(15,-13);ctx.lineTo(9,0);ctx.lineTo(-7,-3);ctx.closePath();ctx.fill();ctx.stroke();
  ctx.fillStyle=paintColor('#0d1823');ctx.font='900 10px ui-monospace,monospace';ctx.textAlign='center';ctx.fillText(String(f.team),2,-6);
  // Keep the team number on the pennant; no caption or caption backing below it.
  // Home, dropped and carried flags share this same renderer.
  ctx.restore();
 }
}
function updateObjectiveHUD(){
 const o=objectiveState(),on=objectiveMode()&&!['menu','onlineLobby','matchOver'].includes(phase);$('objectiveBar').hidden=!on;
 if(on&&o){$('objectiveModeLabel').textContent=o.mode==='ctf'?'CAPTURE THE FLAG':'KING OF THE HILL';$('objectiveStatus').textContent=o.mode==='ctf'?o.flags.map(f=>shortTeamName(f.team)+': '+(f.home?'HOME':f.carrier>=0?'TAKEN':'DROPPED')).join(' · '):o.contested?'CONTESTED · NO POINTS':o.owner>0?teamName(o.owner)+' CONTROLS':o.owner<0?(tanks.find(t=>t.id===-o.owner-1)?.name||'PILOT')+' CONTROLS':'ENTER THE HILL';}
 if(on&&o?.suddenDeath){$('objectiveModeLabel').textContent='SUDDEN DEATH';$('objectiveStatus').textContent='LAST SIDE STANDING · NO RESPAWNS';$('clock').textContent='SD';$('clock').classList.add('urgent');$('announcer').hidden=true;}
 $('objectiveBar').classList.toggle('sudden-death',!!o?.suddenDeath);
 if(mode!=='online')setText('bestInline','');document.querySelector('.sidebar .target').textContent=displayScoreTarget();
 if(objectiveMode()){$('roundLabel').textContent=currentRules().mode==='ctf'?'FLAGS':'HILL';if(phase==='countdown')$('announceSub').textContent=modeInstructions();}
}
function liveFeedbackTank(t){
 if(mode!=='online')return t;
 const s=online.snapshots.at(-1),auth=s?.tankMap.get(t.id);if(!auth)return t;
 const now=performance.now(),live=phase==='playing',age=live?clamp((now-s.received)/1000,0,.25):0;
 return {...auth,cooldown:live&&auth.alive?(online.shots?.cooldown(auth,now)??Math.max(0,auth.cooldown-age)):auth.cooldown,
  cooldownTotal:online.shots?.pilots.get(t.id)?.total||auth.cooldownTotal,respawnTime:Math.max(0,(auth.respawnTime||0)-age)};
}
function missileLocks(t){const bs=mode==='online'?online.snapshots.at(-1)?.bullets||[]:bullets;return bs.filter(b=>b.kind==='homing'&&!b.dead&&b.target===t.id&&b.owner!==t.id&&canDamage(b.owner,t));}
let feedbackAt=-Infinity;
function setText(id,value){const el=$(id);if(el.textContent!==String(value))el.textContent=value;}
function setStyle(el,key,value){if(el.style.getPropertyValue(key)!==String(value))el.style.setProperty(key,String(value));}
function setAttr(el,key,value){if(el.getAttribute(key)!==String(value))el.setAttribute(key,value);}
function updateCombatFeedback(force=false){
 const now=performance.now();if(!force&&now-feedbackAt<1000/30)return;feedbackAt=now;
 for(const [num,source]of [[1,controlledTank()],[2,tanks.find(t=>t.id===secondaryID())]]){
  if(!source)continue;const t=liveFeedbackTank(source),active=phase==='playing'&&t.alive,locked=active&&missileLocks(t).length>0;
  const warning=$('missileWarning'+num);warning.hidden=!combatPrefs.visual||!locked;if(warning.textContent!=='⚠ MISSILE LOCK')warning.textContent='⚠ MISSILE LOCK';
  const panel=$('pilotLoadout'+num);panel.classList.toggle('missile-locked',combatPrefs.visual&&locked);
  if(locked&&!lastLocks[num]&&combatPrefs.audio&&time-(lastLockTone[num]||-10)>1.5){tone(850,1050,.07,.025,'sine');tone(850,1150,.08,.025,'sine',.11);lastLockTone[num]=time;}lastLocks[num]=locked;
  const remote=t.alive&&ownedGrenades(t).length>0,cap=powerCapacity(t),free=t.power==='laser'?t.charges:cap-activeAmmo(t),need=t.power==='scatter'?3:1;
  const inWallBlocked=t.ghostTime>0&&t.power!=='cannon'&&!clearTankAt(t.x,t.y,0);
  let text='READY',ready=1;if(phase!=='playing'){text=phase==='roundOver'?'ROUND COMPLETE':phase==='matchOver'?'MATCH COMPLETE':phase==='countdown'?'GET READY':phase==='paused'?'PAUSED':'READY';ready=phase==='countdown'?0:1;}else if(!t.alive){text=objectiveMode()&&!suddenDeath()?'RESPAWN '+(t.respawnTime||0).toFixed(1)+'s':'TANK DOWN';ready=0;}else if(remote)text='DETONATE READY';else{
   // Keep the colored cooldown/ammo bar stable while Ghost crosses a wall. Only
   // the text/button message changes; actual cooldown and ammo still animate.
   if(t.cooldown>0)ready=1-clamp(t.cooldown/(t.cooldownTotal||cooldownDuration(t.power)),0,1);else if(free<need)ready=0;
   if(inWallBlocked)text='IN WALL · MOVE TO FIRE';else if(t.cooldown>0)text='COOLDOWN '+Math.max(.1,Math.round(t.cooldown*10)/10).toFixed(1)+'s';else if(free<need)text='WAITING FOR AMMO';else if(t.power==='rapid')text='READY · CONTINUOUS';
  }
  setText('cooldownText'+num,text);setStyle($('cooldownFill'+num),'transform','scaleX('+Number(ready.toFixed(3))+')');setAttr($('cooldownTrack'+num),'aria-valuenow',String(Math.round(ready*100)));setAttr($('cooldownTrack'+num),'aria-label',text);panel.classList.toggle('ammo-blocked',text==='WAITING FOR AMMO');
  if(num===1){const detonate=active&&remote;setStyle($('fireBtn'),'--ready',ready.toFixed(3));$('fireBtn').classList.toggle('detonate-ready',detonate);
   const label=!active?(phase==='playing'?'OUT':phase==='roundOver'||phase==='matchOver'?'DONE':phase==='paused'?'PAUSED':'FIRE'):detonate?'BOOM':text.startsWith('IN WALL')?'MOVE':t.cooldown>.001?Math.max(.1,Math.round(t.cooldown*10)/10).toFixed(1)+'s':free<need?'WAIT':'FIRE';
   setText('fireLabel',label);setText('fireHint',detonate?'TAP TO DETONATE':t.power==='grenade'?'TAP TO THROW':'HOLD TO FIRE');
   setAttr($('fireBtn'),'aria-label',detonate?'Press to detonate your grenade':text==='READY'?(t.power==='grenade'?'Press to throw a grenade':'Hold to fire'):text);
  }
 }
}
function cooldownDuration(power){return power==='cannon'?CANNON_COOLDOWN:power==='laser'?.85:power==='rapid'?0:power==='scatter'?.54:power==='homing'?.72:power==='grenade'?.8:.34;}
function drawMissileWarnings(){
 if(!combatPrefs.visual||phase!=='playing')return;ctx.save();
 for(const t of [controlledTank(),tanks.find(t=>t.id===secondaryID())]){if(!t?.alive)continue;for(const b of missileLocks(t).slice(0,3)){
  const a=Math.atan2(b.y-t.y,b.x-t.x);ctx.save();ctx.translate(t.x,t.y);ctx.rotate(a);ctx.strokeStyle=paintColor('#ff83bd');ctx.fillStyle=paintColor('#ff83bd');ctx.lineWidth=2.5;ctx.beginPath();ctx.moveTo(41,-6);ctx.lineTo(35,0);ctx.lineTo(41,6);ctx.stroke();ctx.restore();
 }}ctx.restore();
}
function initFeatures(){
 const toolbar=document.createElement('div');toolbar.className='room-config-actions';toolbar.innerHTML='<button class="secondary" type="button" id="roomRulesBtn">RULES & MODE</button><button class="secondary" type="button" id="roomPresetsBtn">PRESETS</button><button class="secondary" type="button" id="roomControlsBtn">CONTROLS</button>';
 const summary=document.querySelector('.room-rules');summary.id='rulesSummary';summary.before(toolbar);
 const menuControl=document.createElement('button');menuControl.className='secondary';menuControl.textContent='Controls';menuControl.type='button';menuControl.id='menuControlsBtn';$('returnRoomBtn').before(menuControl);
 const objectiveBar=document.createElement('div');objectiveBar.id='objectiveBar';objectiveBar.className='objective-bar';objectiveBar.hidden=true;objectiveBar.innerHTML='<strong id="objectiveModeLabel"></strong><span id="objectiveStatus"></span>';$('arenaWrap').before(objectiveBar);
 for(let n=1;n<=2;n++){const p=$('pilotLoadout'+n),warning=document.createElement('span');warning.id='missileWarning'+n;warning.className='lock-status';warning.hidden=true;p.querySelector('.loadout-identity').append(warning);const line=document.createElement('div');line.className='cooldown-line';line.innerHTML='<span id="cooldownText'+n+'">READY</span><div class="cooldown-track" id="cooldownTrack'+n+'" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="100"><i id="cooldownFill'+n+'"></i></div>';p.append(line);}
 const dialogs=document.createElement('div');dialogs.innerHTML=`
 <dialog class="feature-dialog" id="rulesDialog" aria-labelledby="rulesTitle"><form id="rulesForm"><header class="feature-header"><div><div class="eyebrow">HOST CONFIGURATION</div><h2 id="rulesTitle">Your match. Your rules.</h2></div><button type="button" class="dialog-close" data-close-dialog="rulesDialog" aria-label="Close match rules">×</button></header><div class="feature-body"><fieldset id="rulesFields"><div class="rules-grid">
 <label>GAME MODE<select id="rule-mode"><option value="elimination">Elimination</option><option value="ctf">Capture the Flag</option><option value="koth">King of the Hill</option></select></label>
 <label>BATTLE FORMAT<select id="rule-teamMode"><option value="teams">Teams · host assigns sides</option><option value="ffa">Free-for-all · no teams</option></select></label>
 <label>MAP SIZE<select id="rule-mapSize"><option value="compact">Compact · 7 × 7</option><option value="standard">Standard · 9 × 8</option><option value="large">Large · 12 × 10 (default)</option><option value="huge">Huge · 14 × 12</option><option value="giant">Giant · 16 × 14</option><option value="ultrawide">Ultra Wide · 24 × 14</option></select></label>
 <label><span id="ruleScoreLabel">ROUND WINS TO WIN</span><input id="rule-scoreTarget" type="number" min="1" max="20" step="1" required></label>
 <label>TIME LIMIT (SECONDS)<input id="rule-timeLimit" type="number" min="30" max="600" step="1" required></label>
 <div class="team-names-editor"><div class="field-label">TEAM NAMES & COLORS · 24 CHARACTERS EACH</div><div class="team-names-grid">${[1,2,3,4].map(i=>'<label>TEAM '+i+'<input id="rule-teamName'+i+'" type="text" autocomplete="off" required aria-label="Team '+i+' name"></label>').join('')}</div><p class="mode-help">Teams mode has exactly these four teams. Free-for-all makes every tank an opponent; names and colors remain saved for your next team game. Individual tank colors can override the team color without changing membership.</p></div>
 <label>RESPAWN DELAY (SECONDS)<input id="rule-respawnSeconds" type="number" min="1" max="10" step="1" required></label>
 <label class="pickup-frequency">POWER-UP FREQUENCY<select id="rule-pickupRate"><option value="superfast">Super fast · every 1–2s (default)</option><option value="fast">Fast · every 2–3.5s</option><option value="normal">Normal · every 4–6s</option><option value="slow">Slow · every 7–10s</option><option value="off">Off · no pickups</option></select></label></div>
 <label class="check-label"><input id="rule-friendlyFire" type="checkbox">Allow friendly fire (teammate damage)</label><p class="mode-help">Your own shells, missiles and grenades can hit you in either setting.</p><p class="mode-help" id="rule-help"></p><p class="mode-help" id="rule-pickup-density"></p><h3>AVAILABLE POWER-UPS</h3><div class="weapon-checks">${Object.entries(POWER).map(([key,p])=>'<label><input type="checkbox" data-weapon-toggle="'+key+'"><canvas data-power-icon="'+key+'" width="26" height="26" aria-hidden="true"></canvas><span>'+p.name+'</span></label>').join('')}</div></fieldset><p class="feature-notice" id="rulesNotice" role="status"></p></div><footer class="feature-footer"><button class="primary" type="submit" id="applyRulesBtn">APPLY RULES <span>→</span></button></footer></form></dialog>
 <dialog class="feature-dialog" id="presetsDialog" aria-labelledby="presetsTitle"><header class="feature-header"><div><div class="eyebrow">YOUR SAVED SETUPS</div><h2 id="presetsTitle">A room in one click.</h2></div><button type="button" class="dialog-close" data-close-dialog="presetsDialog" aria-label="Close presets">×</button></header><div class="feature-body"><label class="feature-label">QUICK SETUP OR SAVED PRESET<select id="presetSelect"></select></label><div class="preset-actions"><button class="primary" id="loadPresetBtn" type="button">LOAD SETUP →</button><button class="secondary" id="deletePresetBtn" type="button">Delete saved</button></div><hr><h3>SAVE THIS ROOM</h3><label class="feature-label">PRESET NAME<input class="net-input" id="presetName" maxlength="40" placeholder="Friday night squad" autocomplete="off"></label><button class="secondary" id="savePresetBtn" type="button">SAVE CURRENT SETUP</button><p class="feature-notice" id="presetsNotice" role="status"></p></div></dialog>
 <dialog class="feature-dialog" id="controlsDialog" aria-labelledby="controlsTitle"><header class="feature-header"><div><div class="eyebrow">THIS DEVICE ONLY</div><h2 id="controlsTitle">Make it feel right.</h2></div><button type="button" class="dialog-close" data-close-dialog="controlsDialog" aria-label="Close controls">×</button></header><div class="feature-body"><div id="bindingGrid" class="binding-grid"></div><p class="feature-notice" id="controlsNotice" role="status"></p><p class="mode-help">Bindings use physical keys. P / Esc opens the menu; M toggles sound; F toggles fullscreen. With the default P1 keys and no local P2, arrows and Space also work. Touch controls are unchanged.</p><button class="secondary" id="resetBindingsBtn" type="button">RESET DEFAULT KEYS</button><hr><h3>MAZE POWER-UPS</h3><p class="mode-help" id="controlsPickupInfo"></p><hr><h3>COMBAT FEEDBACK</h3><label class="check-label"><input id="missileVisuals" type="checkbox"> Directional missile warnings</label><label class="check-label"><input id="missileAudio" type="checkbox"> Missile-lock warning sound</label><p class="mode-help">Both local players have their own warnings and cooldown bars. Muting the game also mutes warnings.</p></div></dialog>`;
 document.body.append(dialogs);$('roomRulesBtn').onclick=()=>openFeature('rules');$('roomPresetsBtn').onclick=()=>openFeature('presets');$('roomControlsBtn').onclick=$('menuControlsBtn').onclick=()=>openFeature('controls');
 for(const b of document.querySelectorAll('[data-close-dialog]'))b.onclick=()=>closeFeature($(b.dataset.closeDialog));for(const d of document.querySelectorAll('.feature-dialog'))d.addEventListener('close',()=>{bindingCapture=null;clearInput();});
 $('rulesForm').onsubmit=submitRules;$('rule-mode').onchange=()=>{const m=$('rule-mode').value;$('rule-scoreTarget').value=m==='koth'?60:m==='ctf'?3:5;$('rule-timeLimit').value=m==='elimination'?75:180;updateRuleHelp();};
 $('rule-mapSize').onchange=$('rule-pickupRate').onchange=updateRuleHelp;
 $('loadPresetBtn').onclick=applySelectedPreset;$('savePresetBtn').onclick=saveCurrentPreset;$('deletePresetBtn').onclick=deleteSelectedPreset;$('presetSelect').onchange=()=>$('deletePresetBtn').disabled=!$('presetSelect').value.startsWith('saved:');
 $('presetName').addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();saveCurrentPreset();}});
 $('resetBindingsBtn').onclick=()=>{bindings=defaultBindings();bindingCapture=null;clearInput();try{localStorage.setItem('leqra.bindings.v1',JSON.stringify({version:1,bindings}));}catch(_){}renderBindings();syncFeatureSummary();updateHUD(true);};
 for(const id of ['missileVisuals','missileAudio'])$(id).onchange=()=>{combatPrefs={...combatPrefs,visual:$('missileVisuals').checked,audio:$('missileAudio').checked};try{localStorage.setItem('leqra.feedback.v1',JSON.stringify(combatPrefs));}catch(_){}initAudio();};
 window.addEventListener('keydown',captureBinding,true);
}


// v3.3 spectator membership. A spectator is never represented by a hidden tank.
function resetWatchDialog(){
 if(!$('joinTitle'))return;
 $('joinDialog').querySelector('.eyebrow').textContent='JOIN OR CREATE';$('joinTitle').textContent='Find your room.';$('joinRoomBtn').textContent='JOIN →';$('createRoomBtn').hidden=false;$('joinCode').readOnly=false;
}
function openWatchInvite(code,session=null){
 watchInvite=true;watchResume=session;online.inviteCode=code;online.inviteWatch=true;
 openOnline();$('joinDialog').querySelector('.eyebrow').textContent='SPECTATOR INVITE';$('joinTitle').textContent='Spectate this room.';$('joinRoomBtn').textContent='START SPECTATING →';$('createRoomBtn').hidden=true;
 $('joinCode').value=code;$('joinCode').readOnly=true;
 setNetStatus('Choose your callsign, then start spectating. You will not take a tank seat.');
 $('pilotName').focus({preventScroll:true});$('pilotName').select();
}
function joinWatchInvite(code){
 const name=cleanPilotName($('pilotName').value);
 if(!name){setNetStatus('Choose a callsign before entering as a spectator.',true);$('pilotName').focus();return;}
 if(!validRoomCode(code)){setNetStatus('This spectator link does not contain a valid room name.',true);return;}
 rememberCallsign(name);online.inviteCode=code;online.inviteWatch=true;
 const request={type:'join',code,name,spectating:true};if(watchResume?.code===code)request.token=watchResume.token;
 connectOnline(request);
}
function setPlayerSpectating(player,value){
 if(!player||rolePending)return;
 if(mode==='online'){
  const r=roomData();if(r?.awayMatch||r?.matchmaking&&!value){toast(r?.awayMatch?'Wait for your party to return.':'This matchmaking battle is spectating-only for new tank entries.',3);return;}
  clearInput();sendOnlineInput(true);
  if(!sendOnline({type:'spectate',target:player.id,member:player.member,spectating:value})){toast('Reconnect before changing your role.',3);return;}
  rolePending=true;syncSpectators();setTimeout(()=>{if(rolePending){rolePending=false;syncSpectators();}},6000);return;
 }
 const p=localRoom.players.find(p=>p.id===player.id&&p.member===player.member);if(!p||p.kind==='bot'||p.spectating===value)return;
 const id=value?localRoom.nextViewer++:Array.from({length:MAX_TANKS},(_,n)=>n).find(n=>!localRoom.players.some(p=>!p.spectating&&p.id===n));
 if(id===undefined){toast('All eight tank seats are occupied. Keep spectating or swap players.',3);return;}
 moveLocalMember(p,id,value);refreshLocalRoles();
}
function clearLocalSeat(id){
 dropLocalFlags(id);tanks=tanks.filter(t=>t.id!==id);bullets=bullets.filter(b=>b.owner!==id);
 for(const b of bullets)if(b.target===id)b.target=-1;
}
function moveLocalMember(p,id,watch,team=p.team,score=null){
 const old=p.id;if(!p.spectating)clearLocalSeat(old);
 p.id=id;p.spectating=watch;p.team=team;
 if(localRoom.self===old)localRoom.self=id;
 if(p.kind==='human')for(const other of localRoom.players)if(other.kind==='local'&&other.owner===old)other.owner=id;
 if(!watch){
  const allies=localRoom.players.filter(other=>!other.spectating&&other!==p&&p.team>0&&other.team===p.team);
  scores[id]=score===null?Math.max(0,...allies.map(a=>scores[a.id]||0)):score;
  if(!['menu','matchOver'].includes(phase)){
   const t=newTank(id,0);t.alive=false;t.invulnerable=0;t.respawnTime=objectiveMode()&&!suddenDeath()?currentRules().respawnSeconds:0;t.spawnSerial=++localRoom.nextMember*10000;bindLocalTankStats(t);tanks.push(t);
  }
 }
}
function refreshLocalRoles(){
 clearInput();if(['menu','matchOver'].includes(phase))resetPreviewIfLobby();
 renderOnlineRoom();updateHUD(true);resize();
}
function toggleMyRole(){setPlayerSpectating(roomMember(localPlayerID()),!isSpectating());}
function cancelSwap(){swapPending=null;if($('swapDialog')?.open)$('swapDialog').close();if($('confirmSwapBtn'))$('confirmSwapBtn').disabled=false;}
function requestSwap(viewer){
 const r=roomData();if(!isRoomHost()||!viewer?.spectating)return;
 const targets=r.players.filter(p=>p.kind!=='bot');if(!targets.length){toast('Remove a bot to open a seat for this spectator.',3);return;}
 clearInput();sendOnlineInput(true);swapPending={id:viewer.id,member:viewer.member};
 $('swapViewerName').textContent=viewer.name+' will take the selected seat. That player will become a spectator.';
 const sel=$('swapTarget');sel.replaceChildren(...targets.map(p=>{const o=document.createElement('option');o.value=p.id+':'+p.member;o.textContent=p.name+(p.id===r.host?' · HOST':'')+' · '+(p.team?teamName(p.team):'FREE-FOR-ALL');return o;}));
 $('swapNotice').textContent=suddenDeath()?'Sudden death is in progress. The incoming pilot waits for the next match; no extra life is granted.':objectiveMode()?'The incoming pilot respawns after the usual delay. No weapons or active tank are transferred.':'During a round, the incoming pilot waits until the next round. No weapons or extra life are transferred.';
 $('confirmSwapBtn').disabled=false;$('swapDialog').showModal();
}
function confirmSwap(){
 const r=roomData(),pending=swapPending;if(!pending||!isRoomHost())return;
 const [id,member]=$('swapTarget').value.split(':').map(Number),target=r.players.find(p=>p.id===id&&p.member===member),viewer=r.spectators?.find(p=>p.id===pending.id&&p.member===pending.member);
 if(!target||!viewer){cancelSwap();toast('The room changed. Choose the players again.',3);return;}
 if(mode==='online'){
  if(sendOnline({type:'swap',target:id,member,spectator:viewer.id,spectatorMember:viewer.member})){$('confirmSwapBtn').disabled=true;setTimeout(()=>{if(swapPending===pending){cancelSwap();toast('Check the latest room lineup before retrying.',3);}},6000);}
  return;
 }
 const active=localRoom.players.find(p=>p.member===member),incoming=localRoom.players.find(p=>p.member===viewer.member),team=active.team,score=scores[id]||0;
 moveLocalMember(active,localRoom.nextViewer++,true);moveLocalMember(incoming,id,false,team,score);cancelSwap();refreshLocalRoles();
}
function spectatorRow(p,r){
 const row=document.createElement('div');row.className='spectator-row';row.dataset.spectator=p.id;
 const info=document.createElement('div');info.className='spectator-person';
 const name=document.createElement('strong');name.textContent=p.name;const note=document.createElement('span');
 note.textContent=(p.kind==='local'?'LOCAL P2 · ':'')+(p.id===r.host?'HOST · ':'')+(p.id===localPlayerID()?'YOU · ':'')+(p.connected?'SPECTATING':'RECONNECTING');info.append(name,note);row.append(info);
 const actions=document.createElement('div');actions.className='spectator-actions';
 if(p.id===localPlayerID()||p.kind==='local'&&p.owner===localPlayerID()){
  const play=document.createElement('button');play.type='button';play.className='secondary';play.textContent='PLAY';play.dataset.spectatorPlay=p.id;play.disabled=!!r.matchmaking||!!r.awayMatch||r.players.length>=MAX_TANKS||rolePending||mode==='online'&&!online.connected;if(r.matchmaking)play.textContent='SPECTATING ONLY';play.onclick=()=>setPlayerSpectating(p,false);actions.append(play);
 }
 if(isRoomHost()){
  const swap=document.createElement('button');swap.type='button';swap.className='secondary';swap.textContent='SWAP';swap.dataset.swapViewer=p.id;swap.setAttribute('aria-label','Swap '+p.name+' with an active player');swap.disabled=!p.connected||!r.players.some(p=>p.kind!=='bot')||mode==='online'&&!online.connected;swap.onclick=()=>requestSwap(p);actions.append(swap);
  if(p.id!==localPlayerID())actions.append(makeKickButton(p));
 }
 row.append(actions);return row;
}
function syncSpectatingHUD(){
 if(!$('spectatorBanner'))return;
 const spectating=isSpectating(),changed=document.body.classList.contains('spectating')!==spectating;
 document.body.classList.toggle('spectating',spectating);
 const live=!['menu','onlineLobby','matchOver'].includes(phase),r=roomData();
 $('spectatorBanner').hidden=!spectating||!live;
 $('watchingCaption').textContent=secondaryMember()&&!secondaryMember().spectating?'P1 SPECTATING · P2 IS PLAYING':'SPECTATING';
 $('spectatorPlayBtn').disabled=!!r?.matchmaking||!!r?.awayMatch||(r?.players.length||0)>=MAX_TANKS||rolePending||mode==='online'&&!online.connected;
 $('spectatorPlayBtn').textContent=r?.matchmaking?'SPECTATING ONLY':r?.awayMatch?'PARTY AWAY':(r?.players.length||0)>=MAX_TANKS?'ARENA FULL':'JOIN PLAY';
 if(changed)resize();
}
function syncSpectators(){
 if(!$('roomSpectators'))return;const r=roomData();if(!r)return;
 const me=roomMember(localPlayerID(),r),spectating=!!me?.spectating,spectators=r.spectators||[];
 for(const id of ['toggleSpectateBtn','menuSpectateBtn']){
  $(id).textContent=rolePending?'UPDATING…':spectating&&r.matchmaking?'SPECTATING ONLY':spectating?'JOIN AS PLAYER':'SPECTATE';$(id).disabled=!!r.awayMatch||!!r.matchmaking&&spectating||rolePending||spectating&&r.players.length>=MAX_TANKS||mode==='online'&&!online.connected;$(id).setAttribute('aria-pressed',String(spectating));
 }
 $('roomRoleLabel').textContent=spectating?'YOU ARE SPECTATING':'YOU HAVE A TANK SEAT';
 $('roomRoleHelp').textContent=r.awayMatch?'This lineup is reserved until the party returns.':r.matchmaking&&spectating?'Queue matches do not admit replacement tanks. Stay spectating, or return to your party.':spectating?(r.players.length>=MAX_TANKS?'Arena full. You can keep spectating, or ask the host to swap you in.':'Your role stays spectator until you choose to play.'):'Switch to spectating without leaving the room.';
 $('copySpectateBtn').hidden=$('copyWatchInGameBtn').hidden=mode!=='online';
 $('roomSpectators').hidden=!spectators.length;$('spectatorSummary').textContent='SPECTATORS · '+spectators.length;
 $('spectatorsBtn').textContent='SPECTATORS '+spectators.length;$('spectatorsBtn').setAttribute('aria-label','Show '+spectators.length+' spectators');
 const key=JSON.stringify([spectators,!!r.matchmaking,!!r.awayMatch,r.host,r.players.map(p=>[p.id,p.member,p.name,p.kind,p.team]),localPlayerID(),rolePending,online.connected]);
 if(key!==lastSpectatorUI){lastSpectatorUI=key;
  $('roomSpectatorList').replaceChildren(...spectators.map(p=>spectatorRow(p,r)));
  $('spectatorList').replaceChildren(...spectators.map(p=>spectatorRow(p,r)));
  $('noSpectators').hidden=!!spectators.length;
 }
 if(swapPending&&!spectators.some(p=>p.id===swapPending.id&&p.member===swapPending.member))cancelSwap();
 if($('spectatorsDialog').open&&!isRoomHost())cancelSwap();
 $('spectatorLimit').textContent='Up to 8 tanks + '+(r.maxSpectators||16)+' spectators. Spectating does not use a tank seat.';
 syncSpectatingHUD();
}
function initSpectators(){
 const actions=document.createElement('div');actions.className='room-role-strip';actions.innerHTML='<div><strong id="roomRoleLabel">YOU HAVE A TANK SEAT</strong><p id="roomRoleHelp">Switch to spectating without leaving the room.</p></div><button id="toggleSpectateBtn" type="button" class="secondary">SPECTATE</button>';
 $('roomCallsignForm').after(actions);
 const copy=document.createElement('button');copy.type='button';copy.id='copySpectateBtn';copy.className='secondary share-room watch-link';copy.textContent='COPY SPECTATOR LINK ↗';copy.hidden=true;$('copyInviteBtn').after(copy);
 const list=document.createElement('details');list.id='roomSpectators';list.className='room-spectators';list.hidden=true;list.innerHTML='<summary id="spectatorSummary">SPECTATORS · 0</summary><div id="roomSpectatorList" class="spectator-list"></div>';$('rosterTools').after(list);
 const head=document.createElement('button');head.id='spectatorsBtn';head.type='button';head.className='spectators-button';head.textContent='SPECTATORS 0';$('soundBtn').before(head);
 const menu=document.createElement('button');menu.id='menuSpectateBtn';menu.type='button';menu.className='secondary';menu.textContent='Spectate';$('onlineReturnBtn').after(menu);
 const inGame=document.createElement('button');inGame.id='copyWatchInGameBtn';inGame.type='button';inGame.className='secondary';inGame.textContent='Copy spectator link';$('copyInGameBtn').after(inGame);
 const banner=document.createElement('div');banner.id='spectatorBanner';banner.className='spectator-banner';banner.hidden=true;banner.innerHTML='<span id="watchingCaption">SPECTATING</span><button id="spectatorPlayBtn" class="secondary" type="button">JOIN PLAY</button>';document.querySelector('.underbar').prepend(banner);
 const dialogs=document.createElement('div');dialogs.innerHTML=`<dialog id="spectatorsDialog" class="spectator-dialog" aria-labelledby="spectatorsTitle"><div class="dialog-heading"><div><div class="eyebrow">ROOM MEMBERS</div><h2 id="spectatorsTitle">Spectators.</h2></div><button class="secondary" type="button" id="closeSpectatorsBtn">CLOSE</button></div><p id="spectatorLimit"></p><p id="noSpectators">Nobody is spectating yet. Share the spectator link to invite spectators.</p><div id="spectatorList" class="spectator-list"></div></dialog><dialog id="swapDialog" class="spectator-dialog swap-dialog" aria-labelledby="swapTitle"><div class="eyebrow">HOST CONTROLS</div><h2 id="swapTitle">Swap a player.</h2><p id="swapViewerName"></p><label class="field-label" for="swapTarget">ACTIVE PLAYER TO MOVE TO SPECTATORS</label><select id="swapTarget" class="net-input"></select><p id="swapNotice"></p><div class="kick-actions"><button id="cancelSwapBtn" type="button" class="secondary">CANCEL</button><button id="confirmSwapBtn" type="button" class="primary">SWAP PLAYERS</button></div></dialog>`;
 document.body.append(dialogs);
 $('toggleSpectateBtn').onclick=$('menuSpectateBtn').onclick=$('spectatorPlayBtn').onclick=toggleMyRole;
 $('copySpectateBtn').onclick=$('copyWatchInGameBtn').onclick=()=>copyOnlineInvite(true);
 $('spectatorsBtn').onclick=()=>{clearInput();sendOnlineInput(true);syncSpectators();$('spectatorsDialog').showModal();};
 $('closeSpectatorsBtn').onclick=()=>$('spectatorsDialog').close();
 $('cancelSwapBtn').onclick=cancelSwap;$('confirmSwapBtn').onclick=confirmSwap;$('swapDialog').addEventListener('cancel',e=>{e.preventDefault();cancelSwap();});
}

// All input paths (keyboard, multi-touch, focus loss) share the same cleanup.
window.addEventListener('keydown',e=>{
 if($('swapDialog')?.open||$('spectatorsDialog')?.open||$('kickDialog').open||$('joinDialog').open||[...document.querySelectorAll('.feature-dialog')].some(d=>d.open))return;
 if((e.ctrlKey||e.metaKey||e.altKey)||['SELECT','INPUT','TEXTAREA'].includes(e.target.tagName)||e.target.isContentEditable)return;
 if(['Escape','KeyP'].includes(e.code)){e.preventDefault();if(!e.repeat)togglePause();return;}
 if(e.code==='KeyM'){if(!e.repeat)toggleSound();return;}
 if(e.code==='KeyF'){e.preventDefault();if(!e.repeat)toggleFullscreen();return;}
 if(['menu','matchOver','paused','onlineLobby'].includes(phase)||(mode==='online'&&online.menu))return;
 if(isControlKey(e.code)){
  e.preventDefault();if(e.repeat&&!keys.has(e.code)&&isWeaponKey(e.code))return;
  const fresh=!keys.has(e.code),wasFire=primaryFireHeld(),wasSecond=heldAction(1,'fire');keys.add(e.code);
  if(fresh&&isWeaponKey(e.code)){
   if(primaryFireKey(e.code)&&!wasFire)firePresses.add(localPlayerID());
   const second=secondaryID();if(second!==undefined&&keyForAction(1,'fire',e.code)&&!wasSecond)firePresses.add(second);
   if(mode==='online')sendOnlineInput(true);
  }
 }
});
window.addEventListener('keyup',e=>{const was=keys.delete(e.code);if(was&&isWeaponKey(e.code)&&mode==='online')sendOnlineInput(true);if(isControlKey(e.code)&&!['menu','paused','matchOver','onlineLobby'].includes(phase))e.preventDefault();});
function cacheStickGeometry(){const r=$('stickBase').getBoundingClientRect();stick.cx=r.left+r.width/2;stick.cy=r.top+r.height/2;stick.max=Math.max(24,Math.min(r.width,r.height)*.375);}
function stickMove(e){if(!stick.cx&&!stick.cy)cacheStickGeometry();const dx=e.clientX-stick.cx,dy=e.clientY-stick.cy,length=Math.hypot(dx,dy),max=stick.max||36,factor=length>max?max/length:1;stick.x=dx*factor/max;stick.y=dy*factor/max;stick.mag=Math.min(1,length/max);$('stickKnob').style.transform=`translate(${dx*factor}px,${dy*factor}px)`;}
function capturePointer(el,id){try{el.setPointerCapture?.(id);return el.hasPointerCapture?.(id)!==false;}catch(_){return false;}}
$('stickZone').addEventListener('pointerdown',e=>{if(stick.id!==null)return;e.preventDefault();initAudio();stick.id=e.pointerId;cacheStickGeometry();capturePointer($('stickZone'),e.pointerId);stickMove(e);});
$('stickZone').addEventListener('pointermove',e=>{if(e.pointerId===stick.id){e.preventDefault();stickMove(e);}});
function endStick(e){if(e.pointerId!==stick.id)return;stick.id=null;stick.x=stick.y=stick.mag=0;stick.cx=stick.cy=0;$('stickKnob').style.transform='translate(0,0)';}
$('stickZone').addEventListener('pointerup',endStick);$('stickZone').addEventListener('pointercancel',endStick);$('stickZone').addEventListener('lostpointercapture',endStick);
$('fireBtn').addEventListener('pointerdown',e=>{e.preventDefault();initAudio();const was=primaryFireHeld();firePointers.add(e.pointerId);if(!was)firePresses.add(localPlayerID());capturePointer($('fireBtn'),e.pointerId);$('fireBtn').classList.add('held');if(!was&&mode==='online')sendOnlineInput(true);});
function endFire(e){const was=firePointers.delete(e.pointerId);if(!firePointers.size)$('fireBtn').classList.remove('held');if(was&&mode==='online')sendOnlineInput(true);}
$('fireBtn').addEventListener('pointerup',endFire);$('fireBtn').addEventListener('pointercancel',endFire);$('fireBtn').addEventListener('lostpointercapture',endFire);
// WebKit occasionally loses element-level pointer capture during a two-finger
// joystick + fire gesture. Window-level release handlers prevent stuck inputs.
window.addEventListener('pointerup',e=>{endStick(e);endFire(e);},true);window.addEventListener('pointercancel',e=>{endStick(e);endFire(e);},true);
$('touchControls').addEventListener('contextmenu',e=>e.preventDefault());canvas.addEventListener('contextmenu',e=>e.preventDefault());
if(WEBKIT_ENGINE){for(const el of [$('touchControls'),canvas])for(const type of ['gesturestart','gesturechange','gestureend'])el.addEventListener(type,e=>e.preventDefault(),{passive:false});}
$('playBtn').addEventListener('click',startMatch);$('rematchBtn').addEventListener('click',startMatch);$('menuBtn').addEventListener('click',readyRoom);$('quitBtn').addEventListener('click',readyRoom);$('resumeBtn').addEventListener('click',togglePause);$('pauseBtn').addEventListener('click',togglePause);$('soundBtn').addEventListener('click',toggleSound);
for(const b of document.querySelectorAll('[data-mode]'))b.addEventListener('click',()=>setMode(b.dataset.mode));for(const b of document.querySelectorAll('[data-difficulty]'))b.addEventListener('click',()=>setDifficulty(b.dataset.difficulty));
async function toggleFullscreen(){try{if(document.fullscreenElement){await document.exitFullscreen();}else if(document.documentElement.requestFullscreen){await document.documentElement.requestFullscreen();}else toast('Fullscreen is not available in this browser.',3);}catch(_){toast('Fullscreen is not available in this browser.',3);}}
$('fullscreenBtn').addEventListener('click',toggleFullscreen);
if(!document.documentElement.requestFullscreen){$('fullscreenBtn').hidden=true;}
document.addEventListener('fullscreenchange',()=>{document.body.classList.toggle('game-fullscreen',!!document.fullscreenElement);$('fullscreenBtn').setAttribute('aria-label',document.fullscreenElement?'Exit fullscreen':'Enter fullscreen');setLayout();});
function focusLost(){clearInput();if(mode==='online')sendOnlineInput(true);}
window.addEventListener('blur',focusLost);document.addEventListener('visibilitychange',()=>{if(document.hidden)focusLost();else if(audio?.state==='suspended')audio.resume().catch(()=>{});});
function scheduleLayout(){clearTimeout(resizeTimer);resizeTimer=setTimeout(setLayout,WEBKIT_ENGINE?110:70);}
window.addEventListener('resize',scheduleLayout,{passive:true});
if(window.visualViewport){window.visualViewport.addEventListener('resize',scheduleLayout,{passive:true});window.visualViewport.addEventListener('scroll',()=>{if(IOS_WEBKIT)scheduleArenaResize();},{passive:true});}
if(WEBKIT_ENGINE){window.addEventListener('orientationchange',scheduleLayout,{passive:true});window.addEventListener('pageshow',()=>{clearInput();lastFrame=performance.now();accumulator=0;scheduleLayout();});}
if('ResizeObserver'in window)new ResizeObserver(scheduleArenaResize).observe(wrap);
// v3.4 presentation and final-life objective tiebreaker.
// Match-wide counters, separate from team scores and disposable tank bodies.
// No counters are inferred from cosmetic events; online reports come from Go.
function beginLocalMatchStats(){localMatchStats={rows:[],members:new Map(),duration:0,limited:false};localMatchReport=null;}
function bindLocalTankStats(t){
 if(!localMatchStats||localMatchReport)return;
 const participant=localRoom.players.find(p=>!p.spectating&&p.id===t.id);
 const key=participant||('legacy:'+t.id);let row=localMatchStats.members.get(key);
 if(!row){
  if(localMatchStats.rows.length>=256){localMatchStats.limited=true;return;}
  row={id:localMatchStats.rows.length+1,member:participant?.member||0,seat:t.id,name:t.name,team:t.team,kind:participant?.kind||(t.human?'human':'bot'),eliminations:0,deaths:0,selfDestructs:0,teamKills:0,captures:0,flagReturns:0,hillSeconds:0,active:false,winner:false,mixedTeams:false,participant};
  localMatchStats.members.set(key,row);localMatchStats.rows.push(row);
 }else if(row.team!==t.team)row.mixedTeams=true;
 row.seat=t.id;row.team=t.team;row.name=t.name;row.color=t.color;t.statsRow=row;
}
function liveLocalStats(){return mode!=='online'&&phase==='playing'&&localMatchStats&&!localMatchReport;}
function recordLocalDeath(t,owner){
 if(!liveLocalStats()||!t.alive)return;
 if(t.statsRow)t.statsRow.deaths++;
 if(t.id===owner){if(t.statsRow)t.statsRow.selfDestructs++;return;}
 const shooter=tanks.find(p=>p.id===owner);if(!shooter?.statsRow)return;
 if(t.team>0&&shooter.team===t.team)shooter.statsRow.teamKills++;else shooter.statsRow.eliminations++;
}
function recordLocalObjective(t,field,value=1){if(liveLocalStats()&&!suddenDeath()&&t?.statsRow)t.statsRow[field]+=value;}
function finishLocalMatchStats(winner){
 if(!localMatchStats||localMatchReport)return;
 const winning=tanks.find(t=>t.id===winner);
 const players=localMatchStats.rows.map(row=>{
  const {participant,...copy}=row;copy.name=participant?.name||row.name;copy.hillSeconds=Math.round(copy.hillSeconds*100)/100;
  const tank=tanks.find(t=>t.statsRow===row);copy.active=!!tank;
  if(tank){copy.seat=tank.id;copy.team=tank.team;copy.winner=!!winning&&teamKey(tank)===teamKey(winning);}
  return Object.freeze(copy);
 });
 localMatchReport=Object.freeze({mode:currentRules().mode,duration:Math.round(localMatchStats.duration*100)/100,rounds:round,players:Object.freeze(players),limited:localMatchStats.limited});
}
function matchDuration(value,decimal=false){
 const seconds=Math.max(0,Number(value)||0);
 if(decimal&&seconds<60)return seconds.toFixed(1)+'s';
 const whole=Math.floor(seconds);return Math.floor(whole/60)+':'+String(whole%60).padStart(2,'0');
}
function renderMatchStats(report){
 const section=$('victoryStats');section.replaceChildren();
 if(!report?.players?.length){section.hidden=true;$('victorySummary').textContent='';return;}
 section.hidden=false;
 const rows=report.players,mode=report.mode||'elimination',eliminations=rows.reduce((n,p)=>n+p.eliminations,0);
 const modeName=mode==='ctf'?'CAPTURE THE FLAG':mode==='koth'?'KING OF THE HILL':'ELIMINATION';
 $('victorySummary').textContent=modeName+' · '+matchDuration(report.duration)+' LIVE'+(mode==='elimination'?' · '+report.rounds+' ROUND'+(report.rounds===1?'':'S'):'');
 const head=document.createElement('div');head.className='match-stats-heading';
 const title=document.createElement('h3');title.id='matchStatsTitle';title.textContent='PLAYER RESULTS';
 const count=document.createElement('span');count.textContent=rows.length+' PILOTS · '+eliminations+' ELIMINATIONS';head.append(title,count);section.append(head);
 const columns=[['eliminations','Eliminations','Enemy tanks destroyed'],['deaths','Deaths','All combat deaths, including self-destructs and friendly fire'],['selfDestructs','Self-destructs','Deaths caused by your own weapons; also included in Deaths']];
 if(rows.some(p=>p.teamKills>0)||currentRules().friendlyFire)columns.push(['teamKills','Team kills','Allies destroyed with friendly fire; not enemy eliminations']);
 if(mode==='ctf')columns.push(['captures','Captures','Flags personally delivered to your base'],['flagReturns','Returns','Dropped friendly flags personally returned; automatic returns do not count']);
 if(mode==='koth')columns.push(['hillSeconds','Hill time','Time alive and unprotected inside an uncontested friendly hill. Allies earn their own time; team scoring is not multiplied.']);
 const table=document.createElement('table');table.className='match-stats-table';table.setAttribute('aria-labelledby','matchStatsTitle');table.setAttribute('role','table');
 const thead=document.createElement('thead'),tr=document.createElement('tr'),pilotHead=document.createElement('th');pilotHead.scope='col';pilotHead.textContent='Pilot';tr.append(pilotHead);
 for(const [key,label,help] of columns){const th=document.createElement('th');th.scope='col';th.textContent=label;th.title=help;tr.append(th);}thead.append(tr);table.append(thead);
 const tbody=document.createElement('tbody');
 // Stable room order rather than a kill-only ranking: objective contributions
 // matter too. Winner markers distinguish both human and bot team members.
 for(const p of rows){
  const row=document.createElement('tr');row.dataset.statId=String(p.id);row.dataset.member=String(p.member);row.className=p.winner?'stat-winner':'';
  const pilot=document.createElement('th');pilot.scope='row';pilot.className='stat-pilot';
  const top=document.createElement('div');top.className='stat-pilot-name';
  const dot=document.createElement('i');dot.style.background=paintColor(p.color||teamColor(p.seat,p.team));dot.setAttribute('aria-hidden','true');top.append(dot);
  const name=document.createElement('span');name.textContent=p.name;top.append(name);
  if(p.winner){const badge=document.createElement('span');badge.className='stat-win-badge';badge.textContent='WIN';badge.setAttribute('aria-label','Winning side');top.append(badge);}
  const meta=document.createElement('span');meta.className='stat-pilot-meta';
  meta.textContent=(p.team>0?teamName(p.team):'FREE-FOR-ALL')+' · '+(p.kind==='bot'?'BOT':p.kind==='local'?'LOCAL P2':'PLAYER')+(!p.active?' · PLAYED EARLIER':'')+(p.mixedTeams?' · CHANGED TEAMS':'');
  pilot.append(top,meta);row.append(pilot);
  for(const [key,label,help] of columns){const td=document.createElement('td');td.dataset.label=label;td.dataset.metric=key;td.title=help;td.textContent=key==='hillSeconds'?matchDuration(p[key],true):String(p[key]||0);row.append(td);}
  tbody.append(row);
 }
 table.append(tbody);section.append(table);
 const note=document.createElement('p');note.id='matchStatsNote';note.className='match-stats-note';
 note.textContent='Enemy eliminations only. Deaths include self-destructs. '+(mode==='ctf'?'Captures and returns credit the pilot who performed them—not every teammate.':mode==='koth'?'Hill time excludes contested time and spawn protection. Each ally earns time independently; it does not multiply team points.':'Counters cover the whole match, not just the final round.')+' Leaving a tank or switching to spectating is not a combat death.';
 if(rows.some(p=>p.mixedTeams))note.textContent+=' Changed-team pilots keep their personal totals; the label shows their last team.';
 if(report.limited)note.textContent+=' Participant limit reached: only the first 256 distinct combat participants are shown.';
 section.append(note);
}

function quickReplay(){
 const r=roomData();
 if(mode==='room'){startMatch();return;}
 if(mode!=='online'||!r||r.matchmaking||r.awayMatch)return;
 const me=roomMember(localPlayerID(),r);
 if(!me||me.spectating)return;
 if(r.host===localPlayerID()){
  if(r.canStart){closeVictory();sendOnline({type:'start'});}
  else{closeVictory();setScreen('room');toast('WAITING FOR GUESTS TO READY UP',2.4);}
 }else{sendOnline({type:'ready',ready:true});closeVictory();setScreen('room');toast('READY FOR THE NEXT MATCH',2.2);}
}
function requestQueueRematch(){
 const r=roomData(),me=r?roomMember(localPlayerID(),r):null;
 if(mode!=='online'||phase!=='matchOver'||!r?.matchmaking||!me?.hasParty||matchmaking.rematchPending)return;
 matchmaking.rematchPending=true;syncResultActions();
 if(!sendOnline({type:'rematch'})){matchmaking.rematchPending=false;syncResultActions();toast('Connection unavailable. Try again after reconnecting.',3);}
}
function closeVictory(){if($('victoryDialog')?.open)$('victoryDialog').close();}
function resultBackToRoom(){
 const r=roomData(),me=r?roomMember(localPlayerID(),r):null;
 if(mode==='online'&&r?.matchmaking&&me?.hasParty){returnToMatchParty();return;}
 closeVictory();
}
function syncResultActions(){
 const replay=$('victoryAgainBtn'),back=$('victoryCloseBtn');if(!replay||!back)return;
 const r=roomData(),me=r?roomMember(localPlayerID(),r):null,queued=mode==='online'&&phase==='matchOver'&&!!r?.matchmaking,queuedParticipant=queued&&!!me?.hasParty;
 replay.classList.toggle('queue-rematch',queuedParticipant);
 replay.onclick=queuedParticipant?requestQueueRematch:quickReplay;
 if(queuedParticipant){
  replay.hidden=false;replay.disabled=!online.connected||!!me?.rematch||matchmaking.rematchPending;replay.firstChild.textContent=(me?.rematch||matchmaking.rematchPending)?'REMATCH REQUESTED ':'REMATCH ';
 }else{
  const blocked=mode==='online'&&!!(r?.matchmaking||r?.awayMatch),viewer=mode==='online'&&!!me?.spectating;replay.hidden=blocked||viewer||!['room','online'].includes(mode);replay.disabled=mode==='online'&&!online.connected;replay.firstChild.textContent=mode==='online'&&r?.host!==localPlayerID()?'READY FOR NEXT ':'PLAY AGAIN ';
 }
 back.firstChild.textContent='BACK TO ROOM ';
}
function showVictory(winner,matchTanks=tanks,report=mode==='online'?online.snapshots.at(-1)?.matchStats:localMatchReport){
 const d=$('victoryDialog');if(!d)return;
 const r=roomData(),me=r?roomMember(localPlayerID(),r):null;
 syncResultActions();
 const winning=matchTanks.find(t=>t.id===winner)||roomData()?.players.find(t=>t.id===winner);
 const entries=roomData()?.players||matchTanks,team=winning?.team||0;
 const members=winning?entries.filter(t=>team>0?t.team===team:t.id===winner):[];
 const name=winning?(team>0?teamName(team):winning.name):'NO SURVIVORS';
 const localMembers=[me,secondaryMember()].filter((p,i,a)=>p&&!p.spectating&&a.findIndex(n=>n.id===p.id)===i);
 const localWon=!!winning&&localMembers.some(p=>teamKey(p)===teamKey(winning)),localLost=winner>=0&&localMembers.length>0&&!localWon;
 d.classList.toggle('is-defeat',localLost);$('victoryEyebrow').textContent='MATCH RESULTS';
 $('victoryTitle').textContent=localLost?'DEFEAT':winner>=0?name+' WINS!':'MATCH DRAW';
 $('victoryTitle').style.color=localLost?'#ff4f5f':paintColor(team>0?teamColor(0,team):winning?.color||COLORS[0]);
 $('victoryEmblem').textContent=localLost?'☠':'★';
 $('victoryMembers').textContent=localLost?(name+' WINS'):(members.map(p=>p.name).join(' · '));
 if(winner<0)$('victoryMessage').textContent='No side survived or remained in the room.';
 else if(localLost)$('victoryMessage').textContent=name+' takes the match. Ready for another battle?';
 else if(!localWon)$('victoryMessage').textContent=name+' takes the match.';
 else $('victoryMessage').textContent=suddenDeath()?'Your side survived sudden death.':objectiveMode()?(currentRules().mode==='ctf'?'Your flag squad takes the match!':'The hill belongs to your side!'):'Your side ruled the maze!';
 const groups=new Map();for(const t of entries){const key=teamKey(t);if(!groups.has(key))groups.set(key,t);}
 $('victoryScores').replaceChildren(...[...groups.values()].map(t=>{const row=document.createElement('div');row.className='match-result';row.style.setProperty('--result-color',paintColor(t.team>0?teamColor(t.id,t.team,t.colorIndex):t.color||teamColor(t.id,0,t.colorIndex)));const label=document.createElement('span');label.textContent=t.team>0?teamName(t.team):t.name;const points=document.createElement('strong');points.textContent=String(scores[t.id]||0);row.append(label,points);return row;}));
 renderMatchStats(report);
 clearInput();goUntil=0;
 // Completion is modal once per match, including for spectators. It never
 // auto-starts a rematch, changes a role or seizes the host's controls.
 for(const other of document.querySelectorAll('dialog[open]'))if(other!==d)other.close();
 if(!d.open){d.showModal();$('victoryTitle').tabIndex=-1;$('victoryTitle').focus({preventScroll:true});d.scrollTop=0;}
}
function initPresentation(){
 const sidebar=document.querySelector('.sidebar');sidebar.id='gameSidebar';
 const button=document.createElement('button');button.id='sidebarBtn';button.type='button';button.className='icon-btn sidebar-toggle';button.setAttribute('aria-controls','gameSidebar');button.innerHTML='<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M15 4v16m3-11h.1M18 12h.1M18 15h.1"/></svg>';
 $('fullscreenBtn').before(button);
 const apply=hidden=>{document.body.classList.toggle('sidebar-hidden',hidden);button.setAttribute('aria-expanded',String(!hidden));button.setAttribute('aria-label',hidden?'Show sidebar':'Hide sidebar');button.title=hidden?'Show sidebar':'Hide sidebar';resize();};
 let hidden=false;try{hidden=localStorage.getItem('leqra.sidebarHidden')==='1';}catch(_){}apply(hidden);
 button.onclick=()=>{const hidden=!document.body.classList.contains('sidebar-hidden');apply(hidden);save('sidebarHidden',hidden?'1':'0');};
 const dialog=document.createElement('dialog');dialog.id='victoryDialog';dialog.className='feature-dialog victory-dialog';dialog.setAttribute('aria-labelledby','victoryTitle');dialog.innerHTML='<div class="feature-body"><div class="eyebrow" id="victoryEyebrow">MATCH RESULTS</div><h2 id="victoryTitle"></h2><div class="victory-emblem" id="victoryEmblem" aria-hidden="true">★</div><p id="victoryMembers"></p><p id="victoryMessage"></p><div id="victorySummary" class="victory-summary"></div><div id="victoryScores" aria-label="Final scores"></div><section id="victoryStats" hidden></section></div><footer class="feature-footer victory-actions"><button class="primary" id="victoryCloseBtn" type="button">BACK TO ROOM <span>→</span></button><button class="secondary" id="victoryAgainBtn" type="button">PLAY AGAIN <span>↻</span></button></footer>';
 document.body.append(dialog);$('victoryCloseBtn').onclick=resultBackToRoom;$('victoryAgainBtn').onclick=quickReplay;dialog.addEventListener('cancel',e=>{e.preventDefault();resultBackToRoom();});
}
function beginLocalSuddenDeath(replay=false){
 const o=localObjectives;if(!o||phase!=='playing')return;
 o.suddenDeath=true;o.showdown=(o.showdown||0)+1;o.owner=0;o.hold=0;o.contested=false;
 goUntil=0;phaseTime=0;roundClock=0;bullets=[];pickups=[];spawnClock=pickupInterval()[0];clearInput();
 for(const f of o.flags)resetLocalFlag(f);
 for(const t of tanks){if(!replay)t.suddenLife=true;t.alive=false;t.respawnTime=0;}
 for(const t of tanks)if(t.suddenLife)respawnLocalTank(t);
 const message=replay?'MUTUAL DESTRUCTION · FINAL LIVES RESET':'SUDDEN DEATH · FINAL LIVES · NO RESPAWNS';
 toast(message,3);addLog(message);stepLocalSuddenDeath();updateHUD(true);
}
function stepLocalSuddenDeath(){
 if(!suddenDeath()||phase!=='playing')return;
 let liveSide='',livePilot=null,multipleLive=false,contenderSide='',contenderPilot=null,multipleContenders=false;
 for(const t of tanks){if(!t.suddenLife)continue;const key=teamKey(t);contenderPilot??=t;if(!contenderSide)contenderSide=key;else if(key!==contenderSide)multipleContenders=true;if(!t.alive)continue;livePilot??=t;if(!liveSide)liveSide=key;else if(key!==liveSide)multipleLive=true;}
 if(livePilot&&!multipleLive){endLocalObjective(livePilot.id);return;}
 if(multipleLive)return;
 if(multipleContenders)beginLocalSuddenDeath(true);else endLocalObjective(contenderPilot?.id??-1);
}
// Online chat is a floating region, never part of arena sizing. The ordinary
// room channel remains visible to everyone; matchmaking adds an opponent-only
// channel beside it without mixing histories or unread counts.
const roomChat={open:false,code:'',channel:'room',channels:{room:{messages:[],lastID:0,unread:0,pending:false},opponent:{messages:[],lastID:0,unread:0,pending:false}}};
function chatState(channel='room'){return roomChat.channels[channel==='opponent'?'opponent':'room'];}
function opponentChatEnabled(){const r=roomData(),me=r?roomMember(localPlayerID(),r):null;return mode==='online'&&!!online.code&&!!r?.matchmaking&&!!me?.hasParty&&!me?.spectating;}
function syncChatStatus(){
 const enabled=mode==='online'&&!!online.code,oppEnabled=enabled&&opponentChatEnabled(),active=chatState(roomChat.channel);
 const roomState=chatState('room'),oppState=chatState('opponent');
 $('chatBtn').hidden=!enabled;$('enemyChatBtn').hidden=!oppEnabled;
 $('chatBtn').setAttribute('aria-expanded',String(roomChat.open&&roomChat.channel==='room'));$('enemyChatBtn').setAttribute('aria-expanded',String(roomChat.open&&roomChat.channel==='opponent'));
 $('chatBtn').classList.toggle('has-unread',roomState.unread>0);$('enemyChatBtn').classList.toggle('has-unread',oppState.unread>0);
 $('chatBadge').textContent=roomState.unread?String(Math.min(99,roomState.unread)):'';$('enemyChatBadge').textContent=oppState.unread?String(Math.min(99,oppState.unread)):'';
 $('chatBtn').setAttribute('aria-label','Room chat'+(roomState.unread?', '+roomState.unread+' unread messages':''));$('enemyChatBtn').setAttribute('aria-label','Opponent chat'+(oppState.unread?', '+oppState.unread+' unread messages':''));
 $('chatSendBtn').disabled=!online.connected||active.pending;$('chatInput').disabled=!online.connected;
 const opp=roomChat.channel==='opponent';$('chatTitle').textContent=opp?'Opponent chat':'Room chat';$('chatConnection').textContent=!online.connected?'RECONNECTING · MESSAGES NOT SENT':opp?'YOU + THE ENEMY SIDE':'EVERYONE IN THIS ROOM';
 $('chatInput').placeholder=opp?'Message the enemy side…':'Say something…';$('chatInput').setAttribute('aria-label',opp?'Message to the opposing matchmaking side':'Message to everyone in this room');
 $('chatPanel').classList.toggle('opponent-chat-panel',opp);
 if(!enabled&&roomChat.open)closeChat();else if(roomChat.open&&roomChat.channel==='opponent'&&!oppEnabled)openChat('room');
 document.body.classList.toggle('matchmaking-chat',oppEnabled);
}
function clearRoomChat(code=''){
 roomChat.code=code;roomChat.open=false;roomChat.channel='room';for(const st of Object.values(roomChat.channels)){st.messages=[];st.lastID=0;st.unread=0;st.pending=false;}
 $('chatPanel').hidden=true;$('chatMessages').replaceChildren();$('chatInput').value='';$('chatError').textContent='';syncChatStatus();
}
function renderChatMessage(m){
 const row=document.createElement('div');row.className='chat-message';row.dataset.chatId=m.id;
 const head=document.createElement('div');head.className='chat-message-head';const name=document.createElement('strong');name.textContent=m.name;
 const role=document.createElement('span');role.textContent=m.spectating?'SPECTATING':m.team>0?teamName(m.team):'PLAYER';
 const date=new Date(m.at),when=document.createElement('time');when.dateTime=date.toISOString();when.textContent=date.toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'});
 const text=document.createElement('p');text.textContent=m.text;head.append(name,role,when);row.append(head,text);const self=roomMember(localPlayerID());if(m.member===self?.member)row.classList.add('chat-self');return row;
}
function renderActiveChat(){const st=chatState(),list=$('chatMessages'),frag=document.createDocumentFragment();for(const m of st.messages)frag.append(renderChatMessage(m));list.replaceChildren(frag);list.scrollTop=list.scrollHeight;}
function openChat(channel='room'){
 if(mode!=='online'||!online.code||channel==='opponent'&&!opponentChatEnabled())return;if(roomChat.open&&roomChat.channel===channel){closeChat();return;}
 roomChat.open=true;roomChat.channel=channel;const st=chatState();st.unread=0;$('chatPanel').hidden=false;$('chatError').textContent='';renderActiveChat();
 clearInput();sendOnlineInput(true);syncChatStatus();positionChatPanel();if(online.connected)$('chatInput').focus({preventScroll:true});
}
function closeChat(){
 roomChat.open=false;$('chatPanel').hidden=true;clearInput();if(mode==='online')sendOnlineInput(true);syncChatStatus();if(document.activeElement?.closest('#chatPanel'))document.activeElement.blur();
}
function appendChat(m,history=false,channel='room',render=true){
 const st=chatState(channel);if(!m||!Number.isSafeInteger(m.id)||m.id<=st.lastID||typeof m.text!=='string')return false;st.lastID=m.id;st.messages.push(m);if(st.messages.length>60)st.messages.shift();
 const self=roomMember(localPlayerID()),active=roomChat.open&&roomChat.channel===channel;
 if(render&&active){const list=$('chatMessages'),bottom=list.scrollHeight-list.clientHeight-list.scrollTop<48;list.append(renderChatMessage(m));while(list.children.length>60)list.firstElementChild.remove();if(bottom)list.scrollTop=list.scrollHeight;}
 if(!history&&!active&&m.member!==self?.member){st.unread++;chatNotificationSound();}
 if(m.member===self?.member&&st.pending){st.pending=false;if(active){$('chatInput').value='';$('chatError').textContent='';}}
 return true;
}
function chatPacket(m){
 if(m.room!==online.code)return;const channel=m.channel==='opponent'?'opponent':'room';if(roomChat.code!==m.room)clearRoomChat(m.room);const st=chatState(channel);
 if(m.type==='chat_history'){const pending=st.pending;st.messages=[];st.lastID=0;for(const item of m.messages||[])appendChat(item,true,channel,false);st.pending=pending;if(roomChat.open&&roomChat.channel===channel)renderActiveChat();}
 else appendChat(m.message,false,channel,true);syncChatStatus();
}
function submitChat(e){
 e.preventDefault();const st=chatState();if(!online.connected||st.pending)return;const text=$('chatInput').value.trim();if(!text||[...text].length>280){$('chatError').textContent='Use 1–280 characters.';return;}
 if(sendOnline({type:'chat',channel:roomChat.channel,text})){st.pending=true;$('chatError').textContent='Sending…';syncChatStatus();}else $('chatError').textContent='Connection unavailable. Your message was not sent.';
}
function positionChatPanel(){
 if(!roomChat.open)return;const panel=$('chatPanel'),v=window.visualViewport;if(v&&v.height<innerHeight-40){panel.style.bottom=Math.max(10,innerHeight-v.height-v.offsetTop+10)+'px';panel.style.height=Math.max(160,Math.min(435,v.height-20))+'px';}else{panel.style.removeProperty('bottom');panel.style.removeProperty('height');}
}
function initRoomChat(){
 const button=document.createElement('button');button.id='chatBtn';button.type='button';button.className='icon-btn chat-toggle';button.hidden=true;button.title='Room chat (Enter when unbound)';button.setAttribute('aria-label','Room chat');button.setAttribute('aria-controls','chatPanel');button.setAttribute('aria-expanded','false');button.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h16v12H9l-5 4V4Z"/><path d="M8 8h8M8 12h5"/></svg><span id="chatBadge"></span>';
 const enemy=document.createElement('button');enemy.id='enemyChatBtn';enemy.type='button';enemy.className='icon-btn chat-toggle enemy-chat-toggle';enemy.hidden=true;enemy.title='Opponent chat';enemy.setAttribute('aria-label','Opponent chat');enemy.setAttribute('aria-controls','chatPanel');enemy.setAttribute('aria-expanded','false');enemy.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h16v12H9l-5 4V4Z"/><path d="M8 8h8M8 12h5"/></svg><span id="enemyChatBadge"></span>';
 $('soundBtn').before(button);button.after(enemy);
 document.body.insertAdjacentHTML('beforeend','<section id="chatPanel" class="chat-panel" aria-labelledby="chatTitle" hidden><header><div><h2 id="chatTitle">Room chat</h2><span id="chatConnection">EVERYONE IN THIS ROOM</span></div><button class="icon-btn" type="button" id="chatCloseBtn" aria-label="Close chat">×</button></header><div id="chatMessages" class="chat-messages" role="log" aria-live="polite" aria-relevant="additions" tabindex="0" aria-label="Chat messages"></div><div class="chat-compose"><p id="chatError" role="status"></p><form id="chatForm"><input id="chatInput" type="text" autocomplete="off" maxlength="280" placeholder="Say something…" aria-label="Message to everyone in this room"><button class="primary" id="chatSendBtn" type="submit">SEND</button></form><small>Enter sends · Esc closes<br>Typing stops your controls, not the online match.</small></div></section>');
 if(window.visualViewport){visualViewport.addEventListener('resize',positionChatPanel);visualViewport.addEventListener('scroll',positionChatPanel);}window.addEventListener('resize',positionChatPanel);
 button.onclick=()=>openChat('room');enemy.onclick=()=>openChat('opponent');$('chatCloseBtn').onclick=closeChat;$('chatForm').onsubmit=submitChat;
 $('chatInput').addEventListener('keydown',e=>{if(e.code==='Escape'){e.preventDefault();e.stopPropagation();closeChat();}else e.stopPropagation();});
 window.addEventListener('keydown',e=>{if(bindingCapture||e.ctrlKey||e.metaKey||e.altKey||e.repeat||mode!=='online')return;if(roomChat.open&&e.code==='Escape'){e.preventDefault();e.stopImmediatePropagation();closeChat();return;}if(e.code==='Enter'&&!isControlKey(e.code)&&!['INPUT','TEXTAREA','SELECT','BUTTON'].includes(e.target.tagName)&&!document.querySelector('dialog[open]')){e.preventDefault();e.stopImmediatePropagation();openChat('room');}},true);
}

// Sampling measures RAF cadence (not server tick rate); no HTML/layout work per frame.
const frameStats={fps:0,frameMs:0,workMs:0,worstMs:0,count:0,elapsed:0,work:0,worst:0,last:0,at:0};
function sampleFrame(now,work){
 if(!combatPrefs.fps){frameStats.last=now;return;}
 if(frameStats.last){const delta=now-frameStats.last;if(delta>0&&delta<1000){frameStats.count++;frameStats.elapsed+=delta;frameStats.work+=work;frameStats.worst=Math.max(frameStats.worst,delta);}}
 frameStats.last=now;if(now-frameStats.at<750||frameStats.count<2)return;
 frameStats.fps=frameStats.count*1000/frameStats.elapsed;frameStats.frameMs=frameStats.elapsed/frameStats.count;frameStats.workMs=frameStats.work/frameStats.count;frameStats.worstMs=frameStats.worst;
 const el=$('fpsIndicator');el.textContent=Math.round(frameStats.fps)+' FPS · '+frameStats.frameMs.toFixed(1)+' ms';el.classList.toggle('fps-low',frameStats.fps<45);
 el.title='Browser frame interval: '+frameStats.frameMs.toFixed(1)+' ms. Worst recent frame: '+frameStats.worstMs.toFixed(1)+' ms. JS update/render work: '+frameStats.workMs.toFixed(1)+' ms per frame (excludes GPU).'+(mode==='online'?' Network round trip: '+online.latency+' ms.':'');
 frameStats.count=0;frameStats.elapsed=0;frameStats.work=0;frameStats.worst=0;frameStats.at=now;
}
function initFrameSettings(){
 wrap.insertAdjacentHTML('beforeend','<div id="fpsIndicator" class="fps-indicator" aria-label="Rendering frames per second" hidden>Measuring FPS…</div>');
 const host=$('controlsDialog').querySelector('.feature-body');host.insertAdjacentHTML('beforeend','<hr><h3>PERFORMANCE</h3><label class="check-label"><input id="showFPS" type="checkbox"> Show FPS and frame time</label><label class="check-label"><input id="performanceMode" type="checkbox"> Performance graphics (lower pixel density, reduced glow)</label><p class="mode-help">FPS measures browser rendering, not network latency. Graphics quality never changes tank speed, physics, hitboxes, or game rules.</p><hr><p class="mode-help game-version">leqra v'+GAME_VERSION+'</p>');
 const refresh=()=>{$('fpsIndicator').hidden=!combatPrefs.fps;if(combatPrefs.fps){frameStats.last=0;frameStats.at=0;frameStats.count=0;frameStats.elapsed=0;}resize();};
 $('showFPS').onchange=()=>{combatPrefs.fps=$('showFPS').checked;storePerformancePrefs();refresh();};
 $('performanceMode').onchange=()=>{combatPrefs.performance=$('performanceMode').checked;storePerformancePrefs();refresh();};
 refresh();document.addEventListener('visibilitychange',()=>{frameStats.last=0;frameStats.count=0;frameStats.elapsed=0;frameStats.work=0;frameStats.worst=0;});
}
function storePerformancePrefs(){try{localStorage.setItem('leqra.feedback.v1',JSON.stringify(combatPrefs));featureNotice('controlsNotice','Settings saved on this device.');}catch(_){featureNotice('controlsNotice','Changed for this session; browser storage is unavailable.',true);}}


// Matchmaking uses the existing WebSocket and room renderer. No queue polling
// or DOM updates are added to the animation/physics loops.
const MATCH_QUEUES=[
 {key:'elimination-1',name:'Elimination',detail:'1 versus 1',mode:'elimination',teamSize:1,players:2,cols:7,rows:7,target:5,seconds:75},
 {key:'elimination-2',name:'Elimination',detail:'2 versus 2',mode:'elimination',teamSize:2,players:4,cols:12,rows:10,target:5,seconds:75},
 {key:'elimination-3',name:'Elimination',detail:'3 versus 3',mode:'elimination',teamSize:3,players:6,cols:14,rows:12,target:5,seconds:75},
 {key:'ctf-3',name:'Capture the Flag',detail:'3 versus 3',mode:'ctf',teamSize:3,players:6,cols:14,rows:12,target:3,seconds:180},
 {key:'koth-3',name:'King of the Hill',detail:'3 versus 3',mode:'koth',teamSize:3,players:6,cols:14,rows:12,target:60,seconds:180},
 {key:'ffa-8',name:'Free-for-all',detail:'8 solo players',mode:'elimination',teamSize:0,players:8,cols:16,rows:14,target:5,seconds:120}
];
const matchmaking={selected:'elimination-1',catalog:[],pendingKey:'',pending:false,pendingTimer:0,seenInvite:0,lastPoll:0,capacityBlocked:false,error:'',rematchPending:false};
function realParty(r=roomData()){return (r?.players||[]).filter(p=>p.kind!=='bot'&&!p.spectating);}
function queueEligibility(d,r=roomData()){
 const people=realParty(r);
 if(r?.matchmaking)return 'Return to your party before searching again.';
 if(r?.awayMatch)return 'Wait for the rest of your party to return.';
 if(!isRoomHost())return 'Your room host chooses the queue.';
 if(!['menu','onlineLobby','matchOver'].includes(phase))return 'Return to the room before queueing.';
 if(!people.length)return 'Join as a player first. Bots and spectators do not fill queue slots.';
 if(people.some(p=>p.connected===false))return 'Wait for all participating players to reconnect.';
 if(people.length>3)return 'A party can have at most 3 real players, including local Player 2.';
 if(d.teamSize===0&&people.length!==1)return 'Free-for-all is solo-entry so there are no allied parties.';
 if(d.teamSize>0&&people.length>d.teamSize)return 'Choose a queue with a team large enough for your party.';
 return '';
}
function resetMatchmaking(){
 clearTimeout(matchmaking.pendingTimer);matchmaking.pending= false;matchmaking.pendingKey='';matchmaking.error='';matchmaking.seenInvite=0;
 if($('queueDialog')?.open)$('queueDialog').close();
}
function matchmakingNotice(text,error=false){matchmaking.error=error?text:'';if($('queueNotice')){$('queueNotice').textContent=text;$('queueNotice').classList.toggle('error',error);}}
function matchmakingError(text){
 clearTimeout(matchmaking.pendingTimer);matchmaking.pending=false;matchmaking.pendingKey='';matchmakingNotice(text,true);renderMatchmaking();
}
function setMatchmakingPending(){
 matchmaking.pending=true;matchmaking.error='';clearTimeout(matchmaking.pendingTimer);
 matchmaking.pendingTimer=setTimeout(()=>{matchmaking.pending=false;matchmaking.pendingKey='';matchmakingNotice('No confirmation received. Check the connection and the current queue status.',true);renderMatchmaking();},10000);
}
function openMatchmaking(){
 closeChat();clearInput();if(mode==='online')sendOnlineInput(true);
 if(!roomData()?.queue){const current=MATCH_QUEUES.find(d=>d.key===matchmaking.selected);if(queueEligibility(current)){const eligible=MATCH_QUEUES.find(d=>!queueEligibility(d));if(eligible)matchmaking.selected=eligible.key;}}
 renderMatchmaking();const d=$('queueDialog');if(!d.open)d.showModal();
 if(online.connected)sendOnline({type:'queue_info'});
}
function beginMatchmaking(){
 const d=MATCH_QUEUES.find(d=>d.key===matchmaking.selected);const error=queueEligibility(d);
 if(error){matchmakingNotice(error,true);return;}
 if(matchmaking.pending)return;
 if(!['http:','https:'].includes(location.protocol)){matchmakingNotice('Matchmaking requires the Go server. Open its LAN or public webpage; local HTML files cannot queue.',true);return;}
 initAudio();setMatchmakingPending();
 if(mode==='online'){
  if(!sendOnline({type:'queue_join',queue:d.key})){matchmakingError('Connection unavailable. Your party has not entered the queue.');return;}
 }else{
  // Publish the real configured home lobby first; its bots remain there, not in
  // the match pool. Queue only after the server acknowledges room membership.
  matchmaking.pendingKey=d.key;shareLocalRoom();
  if(!online.connecting&&!online.connected){matchmakingError($('roomStatus').textContent);return;}
 }
 matchmakingNotice(mode==='online'&&!online.connecting?'Requesting a battle…':'Connecting your party to the Go server…');renderMatchmaking();
}
function queueAction(type){
 const q=online.roomData?.queue;if(!q||matchmaking.pending)return;
 setMatchmakingPending();
 if(!sendOnline({type,queueId:q.id,ready:true})){matchmakingError('Connection unavailable. Check the queue after reconnecting.');return;}
 renderMatchmaking();
}
function matchmakingPacket(msg){
 if(msg.queues)matchmaking.catalog=msg.queues;
 if(msg.type==='queue_status'&&online.roomData){online.roomData.queue=msg.queue;matchmaking.capacityBlocked=!!msg.capacityBlocked;}
 if(msg.type==='queue_cancelled'){
  if(online.roomData)online.roomData.queue=null;
  matchmaking.pending=false;matchmaking.pendingKey='';clearTimeout(matchmaking.pendingTimer);
  matchmakingNotice(msg.message);toast(msg.message,3);
 }
 renderMatchmaking();
}
function matchmakingWelcome(msg){
 if(msg.transfer){
  clearTimeout(matchmaking.pendingTimer);matchmaking.pending=false;matchmaking.pendingKey='';matchmaking.error='';
  if($('queueDialog')?.open)$('queueDialog').close();
  for(const d of document.querySelectorAll('dialog[open]'))d.close();
  online.roomData=null;online.menu=false;
 }
}
function returnToMatchParty(){
 if(!online.connected||!roomMember(online.id)?.hasParty)return;
 if(phase!=='matchOver'&&!confirm('Return to your party? Your tanks (including local Player 2) will leave this battle. Your teammates can keep playing.'))return;
 clearInput();sendOnlineInput(true);
 if(!sendOnline({type:'return_party'})){toast('Connection unavailable. Try again after reconnecting.',3);return;}
 closeVictory();
}
function renderMatchmaking(){
 if(!$('queueDialog'))return;
 const r=roomData();if(!r)return;
 const q=r.queue,matched=!!r.matchmaking,away=!!r.awayMatch,people=realParty(r),host=isRoomHost(),own=roomMember(localPlayerID(),r);
 $('matchmakingBtn').textContent=q?'VIEW QUEUE · '+(q.stage==='searching'?'SEARCHING':'CONFIRM PARTY'):matched?'MATCHMAKING BATTLE':away?'PARTY IN A MATCH':'FIND ONLINE BATTLE';
 $('matchmakingBtn').disabled=matched||away;
 syncResultActions();
 $('partyAwayLink').hidden=!away;
 if(away){const u=new URL(location.href);u.search='';u.hash='';u.searchParams.set('room',r.awayMatch);u.searchParams.set('spectate','1');$('partyAwayLink').href=u.href;}
 // Override only queue-specific controls after the ordinary room has rendered.
 if(q||matched||away){
  $('startRoomBtn').hidden=true;$('readyBtn').hidden=true;$('rosterTools').hidden=true;$('hostControls').hidden=true;$('returnRoomBtn').hidden=true;
  document.querySelectorAll('#roomRoster select,#menuKickRoster select,#roomRoster [data-kick-target]').forEach(e=>e.disabled=true);
  $('readyHint').textContent=matched?'FIXED QUEUE RULES · NO PLAYER HOST':away?'PRIVATE LINEUP RESERVED · WAITING FOR YOUR PARTY':q.stage==='confirming'?'EACH REMOTE FRIEND MUST CONFIRM THIS QUEUE':'FINDING OPPONENTS · YOUR PARTY WILL STAY ON ONE TEAM';
  $('roomStatus').textContent=matched?'Return to your original party to change the setup or queue another battle.':away?'Your party is playing a matchmaking battle. This private lobby, bots and chat are reserved.':q.stage==='confirming'?'Open the queue panel to accept or decline the party search.':'Searching for real players on this server. You can cancel without losing your lobby.';
  if(away)document.querySelectorAll('[data-spectate-player]').forEach(e=>e.disabled=true);
  if(matched){$('roomEyebrow').textContent='MATCHMAKING · '+r.matchmaking.name;$('roomTitle').innerHTML='BATTLE<br><em>READY.</em>';}
 }
 $('queuePartyText').textContent=people.length+' REAL PLAYER'+(people.length===1?'':'S')+' · '+people.map(p=>p.name).join(' + ');
 $('queuePartyHint').textContent='Up to 3 real players; local Player 2 counts. Bots stay in your private lobby. Spectators may spectate through its match link.';
 for(const d of MATCH_QUEUES){
  const button=document.querySelector('[data-queue="'+d.key+'"]');const selected=(q?.key||matchmaking.selected)===d.key;
  button.classList.toggle('selected',selected);button.setAttribute('aria-pressed',String(selected));button.disabled=!!q||matchmaking.pending;
  const row=matchmaking.catalog.find(x=>x.definition.key===d.key);button.querySelector('.queue-count').textContent=row?row.waitingPlayers+' waiting · '+d.cols+'×'+d.rows+' maze':d.cols+'×'+d.rows+' maze';
 }
 $('queueActive').hidden=!q;$('queueChoose').hidden=!!q;
 const participation=q?.members?.some(p=>p.controller===own?.member),accepted=q?.members?.filter(p=>p.controller===own?.member).every(p=>p.accepted);
 $('queueAcceptBtn').hidden=!q||q.stage!=='confirming'||!participation||accepted;
 $('queueCancelBtn').hidden=!q||!participation&&!host;
 $('queueStartBtn').hidden=!!q;
 $('queueStartBtn').disabled=matchmaking.pending||!!queueEligibility(MATCH_QUEUES.find(d=>d.key===matchmaking.selected),r);
 $('queueStartBtn').textContent=matchmaking.pending?'CONNECTING…':people.length===1?'FIND MATCH →':'QUEUE ROOM · '+people.length+' PLAYERS →';
 $('queueAcceptBtn').disabled=matchmaking.pending;$('queueCancelBtn').disabled=matchmaking.pending;
 if(q){
  $('queueActiveTitle').textContent=q.stage==='confirming'?'Confirm your party':'Finding your next battle';
  $('queueActiveMode').textContent=q.name;
  $('queuePeople').replaceChildren(...q.members.map(p=>{const el=document.createElement('div');el.className='queue-member';const name=document.createElement('span');name.textContent=p.name+(p.kind==='local'?' · LOCAL P2':'');const badge=document.createElement('strong');badge.textContent=p.accepted?'READY':'CONFIRMING';badge.className=p.accepted?'accepted':'';el.append(name,badge);return el;}));
  const row=matchmaking.catalog.find(x=>x.definition.key===q.key);
  $('queueProgress').textContent=q.stage==='searching'?(row?row.waitingPlayers+' players in this queue · ':'')+q.required+' needed in a compatible lineup':'No matching happens until every participating controller confirms.';
  const elapsed=Math.max(0,Math.floor((Date.now()-q.since)/1000));$('queueElapsed').textContent=q.stage==='searching'?'Searching · '+Math.floor(elapsed/60)+':'+String(elapsed%60).padStart(2,'0'):'Party invitation';
  if(matchmaking.capacityBlocked)matchmakingNotice('The server is at its room limit. Your party is waiting for a match slot.');
  else if(!matchmaking.error)matchmakingNotice('Parties are never split. Team-size constraints can mean waiting even when enough individual players are listed.');
  if(matchmaking.seenInvite!==q.id){matchmaking.seenInvite=q.id;if(participation&&!$('queueDialog').open){closeChat();clearInput();$('queueDialog').showModal();}}
 }else if(!matchmaking.error&&!matchmaking.pending){
  const d=MATCH_QUEUES.find(d=>d.key===matchmaking.selected),error=queueEligibility(d,r);
  matchmakingNotice(error||((d.mode==='ctf'?'First to 3 captures':d.mode==='koth'?'First to 60 hill points':'First to 5 round wins')+' · '+d.seconds+'s '+(d.mode==='elimination'?'per round':'match')+' · All power-ups · Friendly fire off'));
 }
 if(matchmaking.pendingKey&&online.connected&&!q){
  const key=matchmaking.pendingKey;matchmaking.pendingKey='';
  if(!sendOnline({type:'queue_join',queue:key}))matchmakingError('Could not enter the queue. Your online party is still intact.');
 }
}
function initMatchmaking(){
 const launcher=document.createElement('button');launcher.id='matchmakingBtn';launcher.type='button';launcher.className='primary queue-launch';launcher.textContent='FIND ONLINE BATTLE';
 $('copyInviteBtn').after(launcher);launcher.onclick=openMatchmaking;
 const watch=document.createElement('a');watch.id='partyAwayLink';watch.className='secondary queue-watch';watch.textContent='SPECTATE PARTY’S MATCH ↗';watch.target='_blank';watch.rel='noopener';watch.hidden=true;launcher.after(watch);
 const dialog=document.createElement('dialog');dialog.id='queueDialog';dialog.className='feature-dialog queue-dialog';dialog.setAttribute('aria-labelledby','queueTitle');
 dialog.innerHTML='<header class="feature-header"><div><div class="eyebrow">ONLINE · REAL PLAYERS · THIS SERVER</div><h2 id="queueTitle">Find your next battle.</h2></div><button id="queueCloseBtn" type="button" class="dialog-close" aria-label="Close matchmaking panel">×</button></header><div class="feature-body"><div class="queue-party"><strong id="queuePartyText"></strong><p id="queuePartyHint"></p></div><div id="queueChoose"><div class="queue-grid">'+MATCH_QUEUES.map(d=>'<button type="button" class="queue-card" data-queue="'+d.key+'" aria-pressed="false"><span class="queue-mode">'+d.name+'</span><strong>'+d.detail+'</strong><span class="queue-count">'+d.cols+'×'+d.rows+' maze</span></button>').join('')+'</div><p class="mode-help">Random compatible opponents, not ranked matchmaking. Solo players fill open team positions. A match starts automatically only when its full human lineup is ready.</p></div><section id="queueActive" hidden aria-live="polite"><div class="queue-search-mark" aria-hidden="true">⌕</div><h3 id="queueActiveTitle"></h3><p id="queueActiveMode"></p><div id="queuePeople"></div><p id="queueProgress"></p><strong id="queueElapsed"></strong></section><p id="queueNotice" class="feature-notice" role="status"></p></div><footer class="feature-footer"><button id="queueStartBtn" class="primary" type="button">FIND MATCH →</button><button id="queueAcceptBtn" class="primary" type="button" hidden>JOIN THIS SEARCH →</button><button id="queueCancelBtn" class="secondary" type="button" hidden>CANCEL PARTY SEARCH</button><p class="queue-footnote">Closing this panel does not cancel a search. Everyone must use the same running Go server; this is not a global hosted service.</p></footer>';
 document.body.append(dialog);
 $('queueCloseBtn').onclick=()=>dialog.close();dialog.addEventListener('close',()=>clearInput());
 for(const button of dialog.querySelectorAll('[data-queue]'))button.onclick=()=>{matchmaking.selected=button.dataset.queue;matchmaking.error='';renderMatchmaking();};
 $('queueStartBtn').onclick=beginMatchmaking;$('queueAcceptBtn').onclick=()=>queueAction('queue_accept');$('queueCancelBtn').onclick=()=>queueAction('queue_cancel');
 setInterval(()=>{if(!dialog.open)return;const q=online.roomData?.queue;if(q&&q.stage==='searching'){const elapsed=Math.max(0,Math.floor((Date.now()-q.since)/1000));$('queueElapsed').textContent='Searching · '+Math.floor(elapsed/60)+':'+String(elapsed%60).padStart(2,'0');}if(online.connected&&!q&&performance.now()-matchmaking.lastPoll>2000){matchmaking.lastPoll=performance.now();sendOnline({type:'queue_info'});}},1000);
}

// Read-only public state is handy for embedding and smoke testing.
window.leqra=Object.freeze({version:GAME_VERSION,getState:()=>({appearance:{resolved:'dark'},matchStats:mode==='online'?online.snapshots.at(-1)?.matchStats||null:localMatchReport,phase,mode,difficulty,round,scores:[...scores],roundClock,rules:currentRules(),objectives:objectiveState(),room:roomData(),teamScores:mode==='solo'?{player:scores[0],bots:scores[1]}:null,world:{width:W,height:H,cols,rows},tanks:tanks.map(t=>({id:t.id,name:t.name,x:t.x,y:t.y,angle:t.angle,alive:t.alive,respawnTime:t.respawnTime||0,spawnSerial:t.spawnSerial||0,team:t.team,target:t.ai?.target??-1,power:t.power,powerTime:t.powerTime,charges:t.charges,shield:t.shield,shieldCharges:shieldCount(t),speedTime:t.speedTime||0,speedStacks:speedCount(t),scopeTime:t.scopeTime||0,ghostTime:t.ghostTime||0})),bulletCount:bullets.length,pickupCount:pickups.length,touchUI,touchLandscape,online:mode==='online'?{connected:online.connected,code:online.code,id:online.id,spectating:!!online.spectating,spectators:online.roomData?.spectators||[],latency:online.latency,serverTick:online.snapshots.at(-1)?.tick||0,players:online.roomData?.players||[],smoothing:{bufferMs:Math.round(online.buffer?.delay||0),jitterMs:Math.round(online.buffer?.jitter||0),playbackTick:(online.buffer?.time||0)/Net.STEP_MS,pendingFrames:online.predictor?.metrics.replayed||0,correction:online.predictor?.metrics.lastError||0,underruns:online.buffer?.underruns||0}}:null})});
// Deterministic hooks are only present in explicit development/test mode.
if(new URLSearchParams(location.search).has('test'))window.__test={platform:{webkit:WEBKIT_ENGINE,safari:SAFARI_BROWSER,ios:IOS_WEBKIT},renderPixelRatio,drawBullet,snapshotPreset,fillRulesForm,shieldCount,choosePickup,paintColor,teamColor,makeColorSelect,changeTankColor,canEditTankPaint,liveFeedbackTank,previewOnlineFire,projectileOnTimeline,resetOnlineMotion,onlineEffect,sendOnlineInput,get presentationMetrics(){return online.presentationMetrics;},rayBounds,projectileWall,advanceGhost,finishGhost,clearTankAt,cannonGuide,aimingGuide,drawAimingGuides,pickupCap,startingPickups,pickupLifetime,pickupLimitText,syncControlsPickupInfo,seedPickups,mapDimensions,setPilotFeedback,showStartingControls,get matchStats(){return localMatchStats;},get matchReport(){return localMatchReport;},beginLocalMatchStats,bindLocalTankStats,finishLocalMatchStats,renderMatchStats,setHullCache:on=>useHullCache=!!on,get renderStats(){return{...renderStats,hullEntries:tankHullCache.size,labelEntries:labelWidthCache.size}},drawTank,paintTankHull,addObjectivePoint,beginLocalSuddenDeath,stepLocalSuddenDeath,receiveOnlineState,showVictory,quickReplay,closeVictory,restartLocalMatch,drawFlags,resize,get view(){return{cssW,cssH,scale,offsetX,offsetY,goUntil}},setPlayerSpectating,toggleMyRole,requestSwap,confirmSwap,syncSpectators,get online(){return online;},setWorld:world=>{W=world.width;H=world.height;cols=world.cols||Math.round(W/CELL);rows=world.rows||Math.round(H/CELL);walls=world.walls.map(w=>({...w}));resize();},currentRules,setLocalRules,validateRoomRules,defaultRoomRules,validateBindings,get bindings(){return bindings;},get localObjectives(){return localObjectives;},initObjectives,stepLocalObjectives,respawnLocalPlayers,respawnLocalTank,objectiveGoal,updateCombatFeedback,missileLocks,applyLocalPreset,validatePreset,roomStartError,createLocalRoom,addRoomSeat,changeSeat,returnToRoom,shareLocalRoom,get localRoom(){return localRoom;},get walls(){return walls;},get grid(){return grid;},get tanks(){return tanks;},get bullets(){return bullets;},get pickups(){return pickups;},get phase(){return phase;},setPhase:v=>phase=v,update,fire,clearInput,weaponControl,detonateOwned,ownedGrenades,updateHUD,laserTrace,fireLaser,spawnPower,validRoomCode,cleanRoomCode,onlineInviteURL,get traces(){return traces;},grantPower,powerIcon,activeTankPowerBadges,drawTankPowerBadges,renderPowerLegend,projectOnlineBullet,steerMissile,grenadeForecast,grenadeDragFactor,detonate,projectileSpec,muzzleProjectile,humanControl,renderOnlineMotion,rayWalls,resolveWalls,moveTank,shotPrediction,bfs,canDamage,isEnemy,tankHit,updateBullets,botControl,evaluateBotShot,findBankAim,leadPoint,planBotPath,forecastThreats,forecastGrenadeBodies,chooseGrenadeAvoid,chooseDodge,setMode,setDifficulty,finishRound,finishMatch,startRound,hurt,resetPreview,chatNotificationSound,get lastChatNotify(){return lastChatNotify;},appendChat,chatPacket,openChat,closeChat,syncChatStatus,get roomChat(){return roomChat;},acceptOnlineRoomCode,addBullet:b=>bullets.push(b),clearBullets:()=>bullets=[],setClock:v=>roundClock=v,render};
initFeatures();initPresentation();initSpectators();initRoomChat();initFrameSettings();initMatchmaking();syncSound();setDifficulty(difficulty);setLayout();$('recordLabel').textContent=bestWins+' MATCH WIN'+(bestWins===1?'':'S')+' ON THIS DEVICE';createLocalRoom();initOnlineUI();requestAnimationFrame(frame);
})();
