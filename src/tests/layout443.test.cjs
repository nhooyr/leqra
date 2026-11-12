'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const identityFixture=require('./identity_fixture.cjs');
const source=fs.readFileSync(process.env.LEQRA_LAYOUT_SOURCE||assetPath('game.js'),'utf8');
const css=fs.readFileSync(process.env.LEQRA_LAYOUT_CSS||assetPath('style.css'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function node(){const classes=new Set();return{hidden:false,textContent:'',open:false,disabled:false,classList:{toggle:(k,on)=>on?classes.add(k):classes.delete(k),contains:k=>classes.has(k)},setAttribute(){},replaceChildren(){},querySelectorAll:()=>[]};}
function boot(width,height,coarse=false){
 const nodes=new Map(),$=id=>{if(!nodes.has(id))nodes.set(id,node());return nodes.get(id);};
 const s={$,escapeHTML:v=>String(v),innerWidth:width,innerHeight:height,window:{visualViewport:{height},matchMedia:()=>({matches:coarse})},navigator:{maxTouchPoints:coarse?1:0},IOS_WEBKIT:false,document:{body:node()},renderPowerLegend(){},clearMatchSelection(){},controlPairActive:()=>false,pilotControlHint:()=>'',controlKeyMap:()=>({}),controlHintHTML:()=>'',controlSummary:()=>'',modeInstructions:()=>'',hasLocalP2:()=>false,focusLost(){},
  wrap:{getBoundingClientRect:()=>({width:width-20,height:height-180})},stick:{},renderPixelRatio:()=>1,cssW:0,cssH:0,dpr:1,scale:0,offsetX:0,offsetY:0,W:588,H:588,touchUI:false,touchLandscape:false,watching:false,isSpectating:()=>s.watching};
 vm.createContext(s);identityFixture(s,source);vm.runInContext(declaration('resize')+'\n'+declaration('setLayout'),s);return s;
}

test('startup callsign editors are top-level before collapsed room settings and player rosters',()=>{
 const html=fs.readFileSync(require('node:path').join(__dirname,'../web/index.html'),'utf8'),stack=[],elements=[],voidTags=new Set(['area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr']);
 for(const match of html.matchAll(/<\/?([a-z][a-z0-9]*)\b(?:[^>"']|"[^"]*"|'[^']*')*>/gi)){
  const tag=match[1].toLowerCase(),raw=match[0];
  if(raw.startsWith('</')){const index=stack.findLastIndex(node=>node.tag===tag);if(index>=0)stack.length=index;continue;}
  const element={tag,raw,id:raw.match(/\bid="([^"]+)"/)?.[1],parent:stack.at(-1),position:match.index};elements.push(element);
  if(!voidTags.has(tag)&&!raw.endsWith('/>'))stack.push(element);
 }
 const find=id=>{const found=elements.filter(element=>element.id===id);assert.equal(found.length,1,id+' remains a single existing element');return found[0];};
 const primary=find('roomCallsignForm'),secondary=find('roomP2CallsignForm'),settings=find('roomSettings'),players=find('roomPlayers'),controls=find('roomControlsBtn');
 for(const form of [primary,secondary]){
  assert.equal(form.tag,'form');assert.equal(form.parent,settings.parent);assert.equal(form.parent,players.parent);
  assert.match(form.parent.raw,/class="net-content"/);assert.ok(form.position<settings.position&&form.position<players.position);
  assert.equal(form.parent.parent.id,'roomScreen','callsigns remain in the startup card');
 }
 assert.match(secondary.raw,/\bhidden\b/,'secondary callsign remains conditional on a second local tank');
 assert.doesNotMatch(settings.raw,/\bopen\b/);assert.doesNotMatch(players.raw,/\bopen\b/);
 const roster=find('roomRoster');assert.equal(roster.parent.parent,players,'role controls and roster remain inside Players and bots');
 assert.match(declaration('initSpectators'),/\$\('roomRoster'\)\.before\(actions\)/,'one primary role strip precedes the roster inside Players and bots');
 assert.doesNotMatch(declaration('initSpectators'),/\$\('roomCallsignForm'\)\.after\(actions\)/);
 assert.equal(controls.parent,primary.parent);assert.ok(controls.position>players.position);assert.match(controls.raw,/type="button"/);
 const toolbar=declaration('initFeatures').split('\n').find(line=>line.includes('toolbar.innerHTML'));
 assert.match(toolbar,/roomRulesBtn/);assert.match(toolbar,/roomPresetsBtn/);assert.doesNotMatch(toolbar,/roomControlsBtn/,'Room settings no longer creates a duplicate Controls launcher');
 const nodes={roomControlsBtn:{},menuControlsBtn:{}},opened=[];
 const binding=source.match(/\$\('roomControlsBtn'\)\.onclick=\$\('menuControlsBtn'\)\.onclick=\(\)=>openFeature\('controls'\);/);assert.ok(binding);
 vm.runInNewContext(binding[0],{$:id=>nodes[id],openFeature:name=>opened.push(name)});nodes.roomControlsBtn.onclick();assert.deepEqual(opened,['controls']);
 for(const id of ['infiniteCallsignForm','infiniteP2CallsignForm']){
  const form=find(id);assert.match(form.raw,/data-arena="infinity"/);assert.match(form.parent.raw,/class="online-menu-actions"/);
  let ancestor=form.parent;while(ancestor&&ancestor.id!=='infinitePauseMenu')ancestor=ancestor.parent;assert.ok(ancestor,'Infinity pause contains both callsign editors');
 }
});

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

test('Infinity startup covers every viewport without changing fixed match fit or stretching the maze',()=>{
 for(const [width,height,coarse]of [[1440,900,false],[390,844,true],[320,568,true],[844,390,true]]){
  const s=boot(width,height,coarse);s.phase='menu';s.setLayout();s.W=2016;s.H=1176;s.resize();const fit=[s.scale,s.offsetX,s.offsetY];
  s.document.body.classList.toggle('infinity-preview',true);s.resize();
  assert.ok(s.W*s.scale>=s.cssW-1e-8&&s.H*s.scale>=s.cssH-1e-8,width+'x'+height+' has no letterbox');
  assert.equal(s.scale,Math.max(s.cssW/s.W,s.cssH/s.H),'one uniform cover scale preserves the maze aspect ratio');assert.ok(s.offsetX<=0&&s.offsetY<=0);
  s.phase='playing';s.resize();assert.deepEqual([s.scale,s.offsetX,s.offsetY],fit,'a started fixed match never inherits the preview cover scale');
  s.phase='menu';s.document.body.classList.toggle('infinity-preview',false);s.resize();assert.deepEqual([s.scale,s.offsetX,s.offsetY],fit,'switching Infinity off restores the original fit');
 }
});

test('a phone keyboard cannot change the layout orientation or maze transform',()=>{
 for(const [width,height]of [[390,844],[844,390]]){
  const s=boot(width,height,true);s.W=2016;s.H=1176;s.setLayout();const before=[s.touchLandscape,s.scale,s.offsetX,s.offsetY];
  for(const visualHeight of [height,330,220,height]){s.window.visualViewport.height=visualHeight;s.setLayout();assert.deepEqual([s.touchLandscape,s.scale,s.offsetX,s.offsetY],before);}
 }
});

test('rotation releases both arenas’ controls and invalidates the old joystick center',()=>{
 const s=boot(390,844,true),cleared=[];
 s.focusLost=()=>cleared.push('fixed');
 s.window.leqraInfinity={resetControls:()=>cleared.push('Infinity')};
 s.setLayout();assert.deepEqual(cleared,[]);
 s.stick.cx=48;s.stick.cy=750;
 s.innerWidth=844;s.innerHeight=390;s.setLayout();
 assert.deepEqual(cleared,['fixed','Infinity']);
 assert.deepEqual(s.stick,{cx:0,cy:0});
 s.setLayout();assert.equal(cleared.length,2);
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
