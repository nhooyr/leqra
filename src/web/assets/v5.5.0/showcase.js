(() => {
'use strict';
const dialog=document.createElement('dialog');
dialog.id='showcaseDialog';dialog.className='showcase-dialog';dialog.setAttribute('aria-label','Frozen showcase battle');
const canvas=document.createElement('canvas');canvas.className='showcase-canvas';canvas.setAttribute('aria-label','Tanks battling in the Infinity maze');
const stage=document.createElement('div');stage.className='infinite-stage showcase-stage';stage.append(canvas);
dialog.append(stage);document.body.append(dialog);
const prefix='showcase-';
let render=null,wasHidden=false,previousFocus=null,variant='',mobile=false;
function visualClone(source){
 const clone=source.cloneNode(true);
 for(const node of [clone,...clone.querySelectorAll('[id]')])if(node.id){const id=node.id;node.dataset.showcaseSource=id;node.id=prefix+(id==='infiniteFire'?'fireBtn':id);}
 for(const node of clone.querySelectorAll('button,a,input,select')){node.tabIndex=-1;node.removeAttribute('aria-controls');if(node.tagName==='A')node.removeAttribute('href');}
 return clone;
}
function setText(root,id,text){const node=root.querySelector('[data-showcase-source="'+id+'"]');if(node)node.textContent=text;return node;}
function buildLeaderboard(scene){
 const panel=visualClone(document.getElementById('infiniteLeaderboardPanel'));panel.open=true;
 const teams=panel.querySelector('[data-showcase-source="infiniteTeamScores"]');teams.hidden=true;teams.replaceChildren();
 const list=panel.querySelector('[data-showcase-source="infiniteLeaderboard"]');
 list.replaceChildren(...scene.leaderboard.slice(0,10).map(tank=>{
  const row=document.createElement('li'),local=tank.id===scene.localID,color=window.leqraInfinityArt.colors[tank.colorIndex];
  row.value=tank.rank;row.style.setProperty('--tank-color',color);
  if(local){row.dataset.local='p1';row.style.setProperty('--local-highlight',color);}
  const content=document.createElement('span');content.className='leaderboard-row';
  const identity=document.createElement('span');identity.className='leaderboard-identity';
  const name=document.createElement('span');name.className='leaderboard-name';
  name.textContent=local?tank.name+' (P1)':window.leqraInfinityArt.botName(tank.name,tank.bot);
  const score=document.createElement('strong');score.className='leaderboard-score';score.textContent=tank.score;
  identity.append(name);content.append(identity,score);row.append(content);return row;
 }));
 return panel;
}
function buildChrome(scene){
 for(const node of [...dialog.children])if(node!==stage)node.remove();
 stage.querySelector('.infinite-touch-controls')?.remove();
 stage.querySelector('.infinite-leaderboard')?.remove();
 const header=document.createElement('div');header.className='infinite-header showcase-header';header.append(visualClone(document.getElementById('gameHeader')));
 for(const id of ['roomBtn','chatBtn']){const node=header.querySelector('[data-showcase-source="'+id+'"]');if(node)node.hidden=mobile||id==='chatBtn';}
 const room=header.querySelector('[data-showcase-source="roomBtn"]');if(room){room.textContent='ROOM';room.className='room-badge';}
 header.querySelector('[data-showcase-source="soundBtn"]').setAttribute('aria-pressed','true');
 const pause=header.querySelector('[data-showcase-source="pauseBtn"]');if(pause)pause.hidden=false;
 const bar=visualClone(document.getElementById('infiniteStatusbar'));
 setText(bar,'infiniteArenaTitle',mobile?'Public Infinity':'Infinity');setText(bar,'infiniteOnlineCount',(scene.players||1)+' online').hidden=false;
 bar.querySelector('[data-showcase-source="infiniteScoreboardBtn"]').setAttribute('aria-expanded',String(!mobile));
 const fps=document.createElement('span');fps.className='fps-indicator';fps.textContent='fps: '+scene.fps+', ping: '+scene.ping+' ms';bar.querySelector('.fps-indicator')?.remove();bar.insertBefore(fps,bar.querySelector('.bar-right'));
 const hero=scene.tanks.find(tank=>tank.id===scene.localID),scores=bar.querySelector('.infinite-personal-scores'),score=document.createElement('span');
 score.className='infinite-personal-score';score.style.color=window.leqraInfinityArt.colors[hero.colorIndex];
 const name=document.createElement('span');name.className='infinite-score-name';name.textContent=hero.name+' (P1)';
 const separator=document.createElement('span');separator.className='infinite-score-separator';separator.textContent=': ';
 const value=document.createElement('span');value.className='infinite-score-value';value.textContent='score: '+hero.score+', rank: #1';score.append(name,separator,value);scores.replaceChildren(score);
 if(mobile){const controls=visualClone(document.querySelector('#infiniteArena .infinite-touch-controls'));stage.append(controls);}
 else stage.append(buildLeaderboard(scene));
 const footer=document.createElement('footer');footer.className='infinite-underbar showcase-underbar';
 const loadouts=document.createElement('div');loadouts.className='local-loadouts infinite-loadouts';loadouts.append(visualClone(document.getElementById('pilotLoadout1')));footer.append(loadouts);
 if(!mobile){
  const readout=document.createElement('div');readout.className='infinite-readout';
  const hint=document.createElement('p');hint.className='bar-hint showcase-controls-hint';hint.innerHTML=window.leqraInfinityArt.showcaseControlHint();
  readout.append(hint);footer.append(readout);
 }
 dialog.prepend(header,bar);dialog.append(footer);window.leqraInfinityArt.renderShowcaseLoadout(hero,prefix);
}
function draw(){
 mobile=window.leqraInfinityArt.isTouchUI();
 const next=mobile?(innerHeight>innerWidth?'portrait':'wide'):window.leqraShowcaseScene.desktop?'desktop':'wide',key=(mobile?'mobile-':'desktop-')+next;
 dialog.classList.toggle('showcase-mobile',mobile);
 if(key!==variant){
  variant=key;const scene=next==='portrait'?window.leqraShowcaseScene.portrait:next==='desktop'?window.leqraShowcaseScene.desktop:window.leqraShowcaseScene;
  dialog.dataset.scene=next;buildChrome(scene);render=window.leqraInfinity.showcaseRenderer(canvas,scene,{portrait:next==='portrait'});
 }
 render?.();
}
function close(){if(!dialog.open)return;dialog.close();render=null;variant='';wasHidden=false;previousFocus?.focus?.({preventScroll:true});}
function open(){if(dialog.open)return;previousFocus=document.activeElement;wasHidden=false;variant='';dialog.showModal();draw();}
dialog.addEventListener('cancel',event=>event.preventDefault());
for(const type of ['click','pointerdown','pointerup','contextmenu'])dialog.addEventListener(type,event=>{event.preventDefault();event.stopPropagation();},true);
window.addEventListener('keydown',event=>{if(!dialog.open)return;event.preventDefault();event.stopImmediatePropagation();if(event.code==='Escape')close();},true);
window.addEventListener('keyup',event=>{if(dialog.open){event.preventDefault();event.stopImmediatePropagation();}},true);
window.addEventListener('resize',()=>{if(dialog.open)draw();});
if(typeof ResizeObserver!=='undefined')new ResizeObserver(()=>{if(dialog.open)render?.();}).observe(stage);
if(typeof MutationObserver!=='undefined')new MutationObserver(()=>{if(dialog.open)draw();}).observe(document.body,{attributes:true,attributeFilter:['class']});
document.addEventListener('visibilitychange',()=>{if(!dialog.open)return;if(document.hidden)wasHidden=true;else if(wasHidden)close();});
window.addEventListener('pagehide',()=>{if(dialog.open)wasHidden=true;});
window.addEventListener('pageshow',()=>{if(wasHidden)close();});
window.leqraShowcase=Object.freeze({open});
})();
