'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const {assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8'),infinite=readFileSync(assetPath('infinite.js'),'utf8'),html=readFileSync(path.join(__dirname,'../web/index.html'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'('),end=source.indexOf('\n',start),line=source.slice(start,end);assert.ok(start>=0,name);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const nodes=new Map(),rules={mode:'elimination',teamMode:'teams',mapSize:'compact',scoreTarget:15,pickupRate:'superfast',weapons:[]};
 const $=id=>{if(!nodes.has(id))nodes.set(id,{textContent:'',value:'',checked:false,parentElement:{},replaceChildren(...children){this.textContent=children.map(child=>child.textContent).join('');}});return nodes.get(id);};
 const s={$,rules,CELL:84,window:{},selection:'',currentRules:()=>rules,infinityPlayMode:()=>s.selection,isRoomEditable:()=>true,mapDimensions:()=>[7,7],powerEffectDuration:()=>10,starmanDuration:()=>4,pickupLifetime:()=>30,document:{createTextNode:text=>({textContent:text}),createElement:()=>({textContent:''})}};
 vm.createContext(s);vm.runInContext(infinite.match(/^const POWER_DURATION = .*$/m)[0]+'\n'+infinite.match(/^const pickupHelp = .*$/m)[0]+'\nglobalThis.infinityPickupHelp=pickupHelp;',s);
 s.window.leqraInfinity={pickupHelp:s.infinityPickupHelp};for(const name of ['activeTeamCount','modeLabel','pickupCap','startingPickups','pickupLimitText','syncControlsPickupInfo','updateRuleHelp'])vm.runInContext(declaration(name),s);
 return{s,$,rules};
}

test('shared power cards avoid weapon-specific immunity and finite-map claims in Infinity',()=>{
 const sidebar=html.slice(html.indexOf('<aside class="sidebar"'),html.indexOf('</aside>'));
 assert.doesNotMatch(sidebar,/Grenades cannot hurt their thrower|shooter-safe|horizontal spread|perimeter range|Edge bounces/);
 assert.match(sidebar,/Cannon<span>Pierces walls\. 4× size and speed\./);assert.match(sidebar,/Homing missile<span>Guided missiles that ricochet\./);assert.match(sidebar,/Shotgun<span>Fast, ricocheting spread\./);
 const note=sidebar.match(/<p class="power-note">([^<]*)<\/p>/)[1];assert.doesNotMatch(note,/Most timed|Huge maps|within that time/);assert.match(note,/Walls stop blasts/);
 assert.match(html,/Every tank is immune to its own weapons\./);assert.match(source,/add\(generalTips,'owner-immunity','Every tank is immune to its own weapons\.'\)/);
 assert.match(html,/Grenade<\/strong>, Homes in and explodes on tank impact, another fire press, or after 10 seconds\./);
});

test('tour, sidebar, Controls and Rules consistently call collectible items power-ups',()=>{
 const visibleHTML=html.replace(/<[^>]*>/g,' ');assert.doesNotMatch(visibleHTML,/\bpick[ -]?ups?\b/i);
 assert.match(visibleHTML,/10 POWER-UPS/);assert.match(visibleHTML,/Speed activates when collected/);assert.match(visibleHTML,/glowing power-up/);
 const {s,$}=boot();s.syncControlsPickupInfo();const fixed=$('controlsPickupInfo').textContent;
 assert.match(fixed,/2 starting power-ups, 5 maximum/);assert.match(fixed,/10 seconds once collected/);assert.doesNotMatch(fixed,/\bpick[ -]?ups?\b/i);
 s.selection='online';s.syncControlsPickupInfo();assert.match($('controlsPickupInfo').textContent,/15 seconds once collected/);assert.doesNotMatch($('controlsPickupInfo').textContent,/\bpick[ -]?ups?\b/i);
 $('rule-pickupRate').value='off';s.updateRuleHelp();assert.equal($('rule-pickup-density').textContent,'Power-ups disabled.');
 assert.match(source,/<option value="off">Off, no power-ups<\/option>/);
});

test('Controls shows Infinity timing before entry and restores fixed-map timing when selection changes',()=>{
 const {s,$,rules}=boot();s.syncControlsPickupInfo();assert.match($('controlsPickupInfo').textContent,/Most power-ups last 10 seconds/);assert.match($('controlsPickupInfo').textContent,/Starman: 4 seconds/);
 s.selection='online';s.syncControlsPickupInfo();assert.equal($('controlsPickupInfo').textContent,s.infinityPickupHelp);assert.match(s.infinityPickupHelp,/Most last 15 seconds/);assert.match(s.infinityPickupHelp,/Starman lasts 8 seconds/);
 s.selection='';rules.infinity=true;s.syncControlsPickupInfo();assert.equal($('controlsPickupInfo').textContent,s.infinityPickupHelp);
 rules.infinity=false;$('infiniteArena').open=true;s.syncControlsPickupInfo();assert.equal($('controlsPickupInfo').textContent,s.infinityPickupHelp);
 $('infiniteArena').open=false;s.syncControlsPickupInfo();assert.match($('controlsPickupInfo').textContent,/Most power-ups last 10 seconds/);
});

test('rules help describes two initial teams and only reachable Survival bosses from the current draft',()=>{
 const {s,$,rules}=boot();s.updateRuleHelp();assert.match($('rule-team-help').textContent,/evenly split between Team 1 and Team 2/);assert.doesNotMatch($('rule-team-help').textContent,/all four teams/);
 rules.mode='survival';
 for(const target of [3,5,10,15]){
  $('rule-scoreTarget').value=String(target);s.updateRuleHelp();const text=$('rule-help').textContent;
  assert.match(text,/Between waves, a two-second break leads to a new maze and a three-second countdown/);assert.doesNotMatch(text,/Each cleared wave/);
  assert.equal(text.includes('Normal debuts'),target>=5);assert.equal(text.includes('Fierce at wave 10'),target>=10);assert.equal(text.includes('Godlike at wave 15'),target>=15);
  assert.equal(rules.scoreTarget,15,'editing explanatory copy does not apply draft rules');
 }
 assert.match(source,/\$\('rule-scoreTarget'\)\.oninput=updateRuleHelp/);
});
