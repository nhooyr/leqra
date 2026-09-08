'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(process.env.LEQRA_LAYOUT_SOURCE||path.join(__dirname,'../web/game.js'),'utf8');
const css=fs.readFileSync(process.env.LEQRA_LAYOUT_CSS||path.join(__dirname,'../web/style.css'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function node(){const classes=new Set();return{hidden:false,textContent:'',open:false,disabled:false,classList:{toggle:(k,on)=>on?classes.add(k):classes.delete(k),contains:k=>classes.has(k)},setAttribute(){},replaceChildren(){},querySelectorAll:()=>[]};}
function boot(width,height,coarse=false){
 const nodes=new Map(),$=id=>{if(!nodes.has(id))nodes.set(id,node());return nodes.get(id);};
 const s={$,innerWidth:width,innerHeight:height,window:{visualViewport:{height},matchMedia:()=>({matches:coarse})},navigator:{maxTouchPoints:coarse?1:0},IOS_WEBKIT:false,document:{body:node()},renderPowerLegend(){},clearMatchSelection(){},controlSummary:()=>'',modeInstructions:()=>'',hasLocalP2:()=>false,
  wrap:{getBoundingClientRect:()=>({width:width-20,height:height-180})},renderPixelRatio:()=>1,cssW:0,cssH:0,dpr:1,scale:0,offsetX:0,offsetY:0,W:588,H:588,touchUI:false,touchLandscape:false,watching:false,isSpectating:()=>s.watching};
 vm.createContext(s);vm.runInContext(declaration('resize')+'\n'+declaration('setLayout'),s);return s;
}

test('every maze size retains its transform when switching between pilot and spectator',()=>{
 const sizes=vm.runInNewContext('('+source.match(/const MAZE_SIZES=([^;]+);/)[1]+')');
 for(const [width,height,coarse]of [[1440,900,false],[390,844,true],[844,390,true],[844,590,true]]){
  const s=boot(width,height,coarse);s.setLayout();
  for(const [name,[cols,rows]]of Object.entries(sizes)){
   s.W=cols*84;s.H=rows*84;s.watching=false;s.resize();const expected=[s.cssW,s.cssH,s.scale,s.offsetX,s.offsetY];
   for(const watching of [true,false]){
    s.watching=watching;s.resize();
    assert.deepEqual([s.cssW,s.cssH,s.scale,s.offsetX,s.offsetY],expected,`${width}x${height} ${name} ${watching?'spectator':'pilot'}`);
   }
  }
 }
});

test('a phone keyboard cannot change the layout orientation or maze transform',()=>{
 for(const [width,height]of [[390,844],[844,390]]){
  const s=boot(width,height,true);s.W=2016;s.H=1176;s.setLayout();const before=[s.touchLandscape,s.scale,s.offsetX,s.offsetY];
  for(const visualHeight of [height,330,220,height]){s.window.visualViewport.height=visualHeight;s.setLayout();assert.deepEqual([s.touchLandscape,s.scale,s.offsetX,s.offsetY],before);}
 }
});

test('role CSS retains touch controls and cockpit slots, with the banner outside normal flow',()=>{
 assert.doesNotMatch(css,/body\.spectating[^{}]*(?:\.touch-controls|#pilotLoadout1|#localLoadouts)\{[^{}]*display\s*:\s*none/,'spectating cannot collapse reserved control or cockpit space');
 assert.match(css,/body\.spectating \.touch-controls\{[^}]*visibility:hidden/);
 assert.match(css,/#pilotLoadout1\[hidden\][^{}]*#pilotLoadout2\[hidden\]\{[^}]*display:grid!important;visibility:hidden/);
 assert.match(css,/\.local-loadouts>\.spectator-banner\{[^}]*position:absolute;grid-area:1 \/ 1 \/ 2 \/ 2/);
 assert.match(declaration('initSpectators'),/\$\('localLoadouts'\)\.prepend\(banner\)/,'spectator JOIN PLAY occupies the primary cockpit grid cell');
 // Existing fixed row geometry: one pilot is 14+30+12+2*4=64px;
 // stacked pilots are (30+10+3)*2 + 5px padding + 1px border + 5px gap = 97px.
 assert.match(css,/\.local-loadouts\{[^}]*min-height:64px;align-content:start/);
 assert.match(css,/@media\(max-width:560px\)\{\.local-loadouts\{min-height:97px\}\}/,'adding/removing P2 cannot alter narrow-screen cockpit height');
 assert.doesNotMatch(css,/body\.spectating\.two-local-pilots \.underbar\{[^}]*flex-wrap:wrap/);
});

test('changing the number of teams or players cannot enlarge the arena header',()=>{
 assert.doesNotMatch(css,/[^{}]*many-sides[^{}]*\.arena-bar\{[^}]*(?:height|padding)/);
 assert.match(css,/body\.many-sides \.mobile-scores\{\s*display:flex;/,'eight-side scores remain a single row');
 assert.match(css,/\.objective-bar\[hidden\]\{display:flex!important;visibility:hidden\}/,'Elimination keeps the objective modes’ reserved status row');
});

test('the header Spectators action appears only in established online rooms while local role controls stay usable',()=>{
 const s=boot(390,844,true),me={id:0,member:1,kind:'human',spectating:true},r={players:[],spectators:[me],host:0,rules:{mode:'elimination'}};
 Object.assign(s,{mode:'room',phase:'playing',online:{roomData:null,connected:false},roomData:()=>r,roomMember:()=>me,localPlayerID:()=>0,secondaryMember:()=>null,isSpectating:()=>me.spectating,
  rolePending:false,swapPending:null,lastSpectatorUI:'',roomCapacity:()=>8,survivalSeatLocked:()=>false,roomKickDisabled:()=>false,spectatorRow:()=>node(),isRoomHost:()=>true,cancelSwap(){},currentRules:()=>r.rules});
 vm.runInContext(declaration('syncSpectatingHUD')+'\n'+declaration('syncSpectators'),s);
 for(const [mode,room,connected,hidden]of [['room',null,false,true],['online',null,false,true],['online',r,true,false],['online',r,false,false],['room',null,false,true]]){
  s.mode=mode;s.online.roomData=room;s.online.connected=connected;s.syncSpectators();assert.equal(s.$('spectatorsBtn').hidden,hidden,mode+' '+connected);
  assert.equal(s.$('toggleSpectateBtn').textContent,'JOIN AS PLAYER');assert.equal(s.$('menuSpectateBtn').textContent,'JOIN AS PLAYER');assert.equal(s.$('spectatorBanner').hidden,false);
  assert.equal(s.$('spectatorPlayBtn').disabled,mode==='online'&&!connected);
 }
});
