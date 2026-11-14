'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot({online=false,survival=false,ffa=false}={}){
 const rules={mode:survival?'survival':'elimination',teamMode:ffa?'ffa':'teams',scoreTarget:5,teamNames:['SQUAD','RAIDERS','THREE','FOUR']};
 const players=[{id:0,name:'PILOT',kind:'human',team:ffa?0:1,color:'#00ff00'},{id:1,name:'RUST',kind:'bot',difficulty:'hard',team:ffa?0:1,color:'#ff0000'}];
 const elements=new Map(),$=id=>{if(!elements.has(id))elements.set(id,{writes:0,html:'',set innerHTML(v){this.html=v;this.writes++;},get innerHTML(){return this.html;}});return elements.get(id);};
 const s={mode:online?'online':'room',phase:'playing',difficulty:'normal',COLORS:['#00ff00','#ff0000'],online:{snapshots:[]},tanks:players.map(p=>({...p,human:p.kind!=='bot',alive:true})),scores:[2,2,0,0,0,0,0,0],lastRoster:'',currentRules:()=>rules,infinityPlayMode:()=>s.publicInfinity?'online':'',roomData:()=>({rules,players}),teamName:t=>rules.teamNames[t-1],teamColor:(id,t)=>t===1?'#00ff00':'#ff0000',teamKey:p=>p.team?'team'+p.team:'pilot'+p.id,localPlayerID:()=>0,paintColor:c=>c,tankSvg:()=>'<svg></svg>',$,document:{body:{classList:{toggle(k,v){s[k]=v;}}}}};
 vm.createContext(s);require('./identity_fixture.cjs')(s,source);vm.runInContext(declaration('orderedRoster'),s);vm.runInContext(source.match(/^const escapeHTML=.*$/m)[0],s);
 for(const name of ['botLevelName','lineupMember','scoreboardEntries','sidebarRules','renderLineup'])vm.runInContext(declaration(name),s);
 return {s,$,rules,players};
}
function enemy(id,difficulty,{alive=true,boss=false,name='RAIDER '+id}={}){return{id,name,difficulty,alive,team:2,color:'#ff0000',bot:true,survivalEnemy:true,survivalBoss:boss,spawnSerial:1};}
function memberLines(html){return Array.from(html.matchAll(/<div class="lineup-member [^"]*">(.*?)<\/div>/g),m=>m[1]);}
test('only the device primary and owned co-pilot are bold in FFA and team lineups',()=>{
 for(const ffa of [false,true]){
  const {s,$,players}=boot({online:true,ffa});
  players.push({id:2,name:'OWN <WING>',kind:'local',owner:0,team:ffa?0:1,color:'#123456'},
   {id:3,name:'FRIEND',kind:'human',team:ffa?0:1,color:'#654321'},
   {id:4,name:'REMOTE WING',kind:'local',owner:3,team:ffa?0:1,color:'#abcdef'});
  players[1].owner=0;const original=JSON.stringify(players);s.renderLineup();
  const html=$('roster').innerHTML,entries=s.scoreboardEntries(),rows=ffa?entries:entries[0].members;
  assert.deepEqual(Array.from(rows,p=>[p.id,p.local]),[[0,true],[1,false],[2,true],[3,false],[4,false]]);
  const names=Array.from(html.matchAll(ffa?/<div class="player-name([^"]*)">([^<]*)<\/div>/g:/<div class="lineup-member([^"]*)">([^<]*)<\/div>/g),match=>({local:match[1].includes('local-pilot'),name:match[2]}));
  assert.deepEqual(names.map(p=>p.local),[true,false,true,false,false]);
  assert.equal(names[2].name,'OWN &lt;WING&gt; (P2)');assert.equal(names[4].name,'REMOTE WING (P2)');
  assert.equal(JSON.stringify(players),original,'ownership styling never annotates raw room members');
  const writes=$('roster').writes;s.localPlayerID=()=>3;s.renderLineup();
  assert.equal($('roster').writes,writes+1,'identity ownership participates in the presentation cache');
  const updated=Array.from($('roster').innerHTML.matchAll(ffa?/<div class="player-name([^"]*)">/g:/<div class="lineup-member([^"]*)">/g),match=>match[1].includes('local-pilot'));
  assert.deepEqual(updated,[false,false,false,true,true]);
 }
 const css=readFileSync(assetPath('style.css'),'utf8');
 assert.match(css,/\.roster \.player-name:not\(\.lineup-group-name\)\{font-weight:400\}/);
 assert.match(css,/\.roster \.lineup-member\{[^}]*font-weight:400\}/);
 assert.match(css,/\.roster \.player-name\.local-pilot,\.roster \.lineup-member\.local-pilot\{font-weight:700\}/);
 assert.match(css,/\.callsign-label \.pilot-identity\{font-weight:700\}/,'callsign editor identity labels are bold without changing all identity spans');
});
test('team lineup renders every tank on its own escaped line with bot strength',()=>{
 const {s,$,players}=boot();players[0].name='<PILOT & CO>';players[1].name='RUST + "VAPOR"';
 s.renderLineup();const html=$('roster').innerHTML,lines=memberLines(html);
 assert.deepEqual(lines,['&lt;PILOT &amp; CO&gt; (P1)','RUST + &quot;VAPOR&quot; (Fierce bot)']);
 assert.equal((html.match(/class="player-name lineup-group-name"/g)||[]).length,1);assert.match(html,/>SQUAD<\/div>/);
 assert.match(html,/<div class="score">2<\/div>/);assert.equal((html.match(/<i class="on">/g)||[]).length,2);
 assert.doesNotMatch(html,/<PILOT|<script|&gt; \+ RUST/);
});
test('free-for-all preserves one individual heading, strength label, and score per tank',()=>{
 const {s,$}=boot({ffa:true});s.renderLineup();const html=$('roster').innerHTML;
 assert.equal(memberLines(html).length,0);assert.match(html,/>PILOT \(P1\)<\/div>/);assert.match(html,/>RUST<\/div>/);
 assert.match(html,/>HUMAN PILOT<\/div>/);assert.match(html,/>FIERCE BOT<\/div>/);
 assert.equal((html.match(/class="score"/g)||[]).length,2);assert.equal(($('miniScores').innerHTML.match(/class="mini-score"/g)||[]).length,2);
});
test('local Survival lists current enemies with all strength levels and marks a fallen boss',()=>{
 const {s,$,players}=boot({survival:true});s.tanks.push(enemy(2,'easy'),enemy(3,'normal'),enemy(4,'hard'),enemy(5,'godlike',{boss:true,alive:false,name:'GODLIKE BOSS'}));
 s.renderLineup();const html=$('roster').innerHTML,lines=memberLines(html);
 assert.equal(players.length,2,'generated bots must remain outside room seats');
 assert.equal(lines.length,6);assert.match(lines[2],/Chill bot/);assert.match(lines[3],/Normal bot/);assert.match(lines[4],/Fierce bot/);assert.match(lines[5],/Godlike boss.*aria-label="Eliminated"/);
 assert.match(html,/class="lineup-member out">GODLIKE BOSS/);assert.match(html,/>RAIDERS<\/div>/);
 assert.equal((html.match(/class="score"/g)||[]).length,1,'enemy side does not have a fabricated score');
 assert.equal((html.match(/class="score-pips"/g)||[]).length,1);assert.equal(($('miniScores').innerHTML.match(/class="mini-score"/g)||[]).length,1);
 assert.doesNotMatch(html,/undefined|NaN/);
});
test('online Survival uses authoritative bodies and replaces reused enemy seats when waves change',()=>{
 const {s,$}=boot({online:true,survival:true});s.tanks.push(enemy(2,'easy',{name:'OLD DRAWN WAVE'}));
 s.online.snapshots=[{tanks:[...s.tanks.slice(0,2),enemy(2,'normal',{name:'CURRENT RAIDER'})]}];
 s.renderLineup();assert.match($('roster').innerHTML,/CURRENT RAIDER \(Normal bot\)/);assert.doesNotMatch($('roster').innerHTML,/OLD DRAWN WAVE/);
 s.online.snapshots.push({tanks:[...s.tanks.slice(0,2),enemy(2,'godlike',{name:'GODLIKE BOSS',boss:true})]});
 s.renderLineup();assert.match($('roster').innerHTML,/GODLIKE BOSS \(Godlike boss\)/);assert.doesNotMatch($('roster').innerHTML,/CURRENT RAIDER|OLD DRAWN WAVE/);
 s.online.snapshots.at(-1).tanks[2].alive=false;s.renderLineup();assert.match($('roster').innerHTML,/lineup-member out">GODLIKE BOSS/);
});
test('removed enemies disappear immediately during local and online wave breaks and fresh runs',()=>{
 for(const online of [false,true]){
  const {s,$}=boot({online,survival:true}),squad=s.tanks.slice();s.tanks.push(enemy(2,'hard',{name:'OLD WAVE'}));if(online)s.online.snapshots=[{tanks:s.tanks.slice()}];
  s.renderLineup();assert.match($('roster').innerHTML,/OLD WAVE/);
  if(online)s.online.snapshots.push({tanks:squad});else s.tanks=squad;
  s.renderLineup();assert.doesNotMatch($('roster').innerHTML,/OLD WAVE|survival-enemies/);
  const next=[...squad,enemy(2,'easy',{name:'NEW RUN'})];if(online)s.online.snapshots.push({tanks:next});else s.tanks=next;
  s.renderLineup();assert.match($('roster').innerHTML,/NEW RUN \(Chill bot\)/);assert.doesNotMatch($('roster').innerHTML,/OLD WAVE/);
 }
});
test('lobby and other modes never show stale generated bodies',()=>{
 for(const online of [false,true]){
  const {s,$,rules}=boot({online,survival:true});s.tanks.push(enemy(2,'hard'));if(online)s.online.snapshots=[{tanks:s.tanks}];
  s.phase=online?'onlineLobby':'menu';s.renderLineup();assert.doesNotMatch($('roster').innerHTML,/survival-enemies|RAIDER 2/);
  s.phase='playing';rules.mode='ctf';s.renderLineup();assert.doesNotMatch($('roster').innerHTML,/survival-enemies|RAIDER 2/);
 }
});
test('lineup cache avoids idle DOM writes but catches member deaths, strength edits, and target changes',()=>{
 const {s,$,rules,players}=boot();s.renderLineup();const initial=$('roster').writes;s.renderLineup();assert.equal($('roster').writes,initial);
 s.tanks[1].alive=false;s.renderLineup();assert.equal($('roster').writes,initial+1);assert.match($('roster').innerHTML,/lineup-member out">RUST/);assert.doesNotMatch($('roster').innerHTML,/class="roster-row out/);
 players[1].difficulty='godlike';s.renderLineup();assert.match($('roster').innerHTML,/Godlike bot/);
 rules.scoreTarget=8;s.renderLineup();assert.equal(($('roster').innerHTML.match(/<i class=/g)||[]).length,8);
 s.renderLineup(true);assert.equal($('roster').writes,initial+4);
});
test('solo practice keeps its bot squad score and gives each bot a separate strength line',()=>{
 const {s,$}=boot();s.mode='solo';s.tanks.push({...enemy(2,'easy',{alive:false}),human:false,survivalEnemy:false});
 s.renderLineup();const lines=memberLines($('roster').innerHTML);
 assert.equal(lines.length,2);assert.match(lines[0],/RUST \(Fierce bot\)/);assert.match(lines[1],/RAIDER 2 \(Chill bot\).*Eliminated/);
 assert.match($('miniScores').innerHTML,/PILOT \(P1\) 2/);assert.match($('miniScores').innerHTML,/BOT SQUAD 2/);
});


test('Infinity lineup has no fixed-round score pips and switching back restores them',()=>{
 const {s,$,rules}=boot({ffa:true});s.phase='menu';s.publicInfinity=true;
 s.renderLineup();assert.doesNotMatch($('roster').innerHTML,/score-pips/);
 s.publicInfinity=false;s.renderLineup();assert.match($('roster').innerHTML,/score-pips/);
 rules.infinity=true;rules.infinityTarget=25;s.renderLineup();
 assert.doesNotMatch($('roster').innerHTML,/score-pips/);
});


test('online public Infinity selection uses the endless lineup without changing private rules',()=>{
 const {s,$,rules}=boot({online:true,ffa:true});s.phase='onlineLobby';s.online.roomData={infinityPublic:true};
 s.renderLineup();assert.doesNotMatch($('roster').innerHTML,/score-pips/);
 assert.equal(s.sidebarRules().infinityTarget,0);assert.equal(rules.infinity,undefined);
 s.online.roomData.infinityPublic=false;s.renderLineup();assert.match($('roster').innerHTML,/score-pips/);
});


test('public Infinity lineup excludes configured bots and presents room friends as independent tanks',()=>{
 const {s,$,players,rules}=boot();s.phase='menu';s.publicInfinity=true;
 players.push({id:2,name:'FRIEND',kind:'human',team:1,color:'#00ff00'});
 s.renderLineup();const html=$('roster').innerHTML;
 assert.doesNotMatch(html,/RUST|SQUAD|score-pips/);
 assert.match(html,/>PILOT \(P1\)<\/div>/);assert.match(html,/>FRIEND \(P1\)<\/div>/);
 assert.equal((html.match(/class="roster-row /g)||[]).length,2);
 assert.equal(rules.teamMode,'teams');assert.equal(players[0].team,1);
});
