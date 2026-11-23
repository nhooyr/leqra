package main

const leaderboardAdminHTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>leqra administration</title><link rel="stylesheet" href="/admin.css"><script src="/admin.js" defer></script></head>
<body><main><header><a href="/">leqra</a><span>Public Infinity leaderboard</span></header>
<p class="muted">Local administration. Changes are saved immediately and sent to connected public players.</p>
<section class="controls"><label for="pattern">Match callsigns with a regular expression</label><div class="row"><input id="pattern" type="text" placeholder="e.g. (?i)^test" autocomplete="off" spellcheck="false" maxlength="1024"><button id="refresh" type="button">Refresh</button></div><p class="muted">Uses Go regular expressions. An empty pattern previews everyone.</p><div class="row"><button id="remove" class="danger" type="button" disabled>Clear matches</button><button id="reset" class="danger" type="button">Reset all</button></div><p class="muted">Clearing removes offline entries and sets affected connected players to 0. They stay in the game.</p><div class="row"><button id="randomizeColors" type="button" disabled>Randomize tank colors</button></div><p class="muted">Applies to every Public Infinity tank, including bots, regardless of the filter. The leader stays blue. Connected clients update immediately.</p></section>
<p id="status" role="status" aria-live="polite">Loading…</p><p id="counts" class="muted"></p><div class="table"><table><thead><tr><th>Callsign</th><th>Score</th><th>Kind</th><th>Status</th><th>Account key</th></tr></thead><tbody id="entries"></tbody></table></div>

<section id="recovery" class="controls" hidden><h2 id="recoveryTitle">Recovery key</h2><label for="recoveryKey">Replacement account key</label><input id="recoveryKey" type="text" readonly autocomplete="off" spellcheck="false"><div class="row"><button id="copyKey" type="button" disabled>Copy key</button><button id="closeKey" type="button">Close</button></div><p id="recoveryStatus" role="status" aria-live="polite"></p></section>
</main></body></html>`

const leaderboardAdminCSS = `:root{color-scheme:dark;font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;background:#0c111c;color:#e6edf8}*{box-sizing:border-box}body{margin:0}main{max-width:1000px;margin:auto;padding:28px 20px}header{display:flex;gap:20px;align-items:center;flex-wrap:wrap;margin-bottom:18px}header a{font-size:30px;font-weight:bold;color:#f4cb6b;text-decoration:none}header span{font-size:18px}.muted{color:#a7b6cb}.controls{border:1px solid #33415a;background:#121c2c;padding:20px;border-radius:8px;margin-top:24px}label{display:block;margin-bottom:8px;font-weight:bold}.row{display:flex;gap:12px;flex-wrap:wrap}input,button{font:inherit;border:1px solid #4c6283;border-radius:5px;padding:10px 14px;background:#17253c;color:inherit}input{flex:1;min-width:160px}button{cursor:pointer}button:hover{background:#263d5e}button:disabled{opacity:.5;cursor:default}.danger{border-color:#ba686e}.danger:hover{background:#542c38}:focus-visible{outline:2px solid #f4cb6b;outline-offset:3px}#status{min-height:24px;color:#f4cb6b}.table{overflow:auto}table{width:100%;border-collapse:collapse;table-layout:fixed}th,td{text-align:left;padding:12px 8px;border-bottom:1px solid #27364e;overflow-wrap:anywhere}th:first-child{width:32%}th:nth-child(2){width:10%}th:nth-child(3){width:12%}th:nth-child(4){width:20%}th:nth-child(5){width:26%}th{color:#a7b6cb;font-size:12px}td:nth-child(2){font-variant-numeric:tabular-nums}#recoveryKey{width:100%;margin-bottom:12px}h2{font-size:18px}@media(max-width:500px){main{padding:18px 12px}.controls{padding:14px}th,td{padding:10px 5px;font-size:12px}th:first-child{width:28%}th:nth-child(2){width:14%}th:nth-child(3){width:15%}th:nth-child(4){width:19%}th:nth-child(5){width:24%}td:last-child button{max-width:100%;padding:8px 6px}}`

const leaderboardAdminJS = `"use strict";
const pattern=document.querySelector('#pattern'),remove=document.querySelector('#remove'),reset=document.querySelector('#reset'),randomizeColors=document.querySelector('#randomizeColors'),status=document.querySelector('#status'),counts=document.querySelector('#counts'),entries=document.querySelector('#entries');
const recovery=document.querySelector('#recovery'),recoveryKey=document.querySelector('#recoveryKey'),recoveryStatus=document.querySelector('#recoveryStatus'),copyKey=document.querySelector('#copyKey');
let csrf='',matched=0,busy=false,revision=0,timer,validatedPattern=null,recoveryButtons=[],recoveryConfirmed=false;
function canRemove(){return !busy&&!!csrf&&!!pattern.value&&validatedPattern===pattern.value&&matched>0}
function setBusy(value){busy=value;reset.disabled=busy;randomizeColors.disabled=busy||!csrf;document.querySelector('#refresh').disabled=busy;document.querySelector('#closeKey').disabled=busy;remove.disabled=!canRemove();for(const button of recoveryButtons)button.disabled=busy}
async function load(){
 const rev=++revision,query=pattern.value;validatedPattern=null;matched=0;remove.disabled=true;randomizeColors.disabled=busy||!csrf;
 try{
  const response=await fetch('/api/leaderboard?pattern='+encodeURIComponent(query),{cache:'no-store'});
  if(!response.ok)throw new Error(await response.text());
  const data=await response.json();if(rev!==revision)return;
  csrf=data.csrfToken;matched=data.matched;validatedPattern=query;
  const byID=new Map((data.accounts||[]).map(account=>[account.id,account])),seen=new Set(),rows=[];
  for(const entry of data.entries){const account=!entry.bot&&entry.accountId?(byID.get(entry.accountId)||{id:entry.accountId,names:[entry.name]}):null;if(account)seen.add(account.id);rows.push({...entry,account})}
  for(const account of data.accounts||[])if(!seen.has(account.id))rows.push({name:account.names.join(', '),score:null,bot:false,connected:null,account});
  counts.textContent=data.total+' leaderboard entries, '+data.connected+' connected, '+rows.length+' shown'+(matched>data.entries.length||data.accountMatched>(data.accounts||[]).length?' (refine the filter to see more)':'');
  entries.replaceChildren();recoveryButtons=[];
  for(const entry of rows){
   const row=document.createElement('tr');
   for(const value of [entry.name,entry.score===null?'—':String(entry.score),entry.bot?'Bot':'Player',entry.connected===null?'—':entry.connected?'Connected':'Offline']){const cell=document.createElement('td');cell.textContent=value;row.append(cell)}
   const action=document.createElement('td');
   if(entry.account){const button=document.createElement('button');button.type='button';button.textContent='Recover key';button.disabled=busy;button.addEventListener('click',()=>recover(entry.account));recoveryButtons.push(button);action.append(button)}else action.textContent='—';
   row.append(action);entries.append(row);
  }
  status.textContent='';remove.disabled=!canRemove();randomizeColors.disabled=busy||!csrf;
 }catch(error){if(rev!==revision)return;status.textContent=error.message;counts.textContent='';entries.replaceChildren();recoveryButtons=[]}
}
async function change(path,body,message){if(busy||!csrf||path==='/api/remove'&&!canRemove()||!confirm(message))return;setBusy(true);revision++;try{const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json','X-Leqra-Admin-CSRF':csrf},body:JSON.stringify(body)});if(!response.ok)throw new Error(await response.text());const data=await response.json();await load();status.textContent=path==='/api/randomize-colors'?'Tank colors randomized. '+data.affected+' tanks updated; the leader stays blue.':'Leaderboard updated. '+data.affected+' entries affected.'}catch(error){status.textContent=error.message}finally{setBusy(false)}}
function newRecoveryKey(){const bytes=crypto.getRandomValues(new Uint8Array(32));return 'p_'+btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')}
async function recover(account){
 if(busy||!csrf)return;
 const name=account.names.join(', ');
 if(!confirm('Replace the account key for '+name+'? The old key will stop working and connected clients will be signed out. Callsigns and scores are preserved.'))return;
 setBusy(true);revision++;recoveryConfirmed=false;recovery.hidden=false;recoveryKey.value='';copyKey.disabled=true;document.querySelector('#recoveryTitle').textContent='Recovery key for '+name;recoveryStatus.textContent='Creating recovery key…';recovery.scrollIntoView?.({block:'nearest'});
 let candidate='',uncertain=false;
 try{
  candidate=newRecoveryKey();uncertain=true;
  const response=await fetch('/api/recover-account',{method:'POST',headers:{'Content-Type':'application/json','X-Leqra-Admin-CSRF':csrf},body:JSON.stringify({accountId:account.id,newPublicToken:candidate})});
  if(!response.ok){uncertain=false;throw new Error(await response.text())}
  const result=await response.json();if(result.recovered!==true)throw new Error('Recovery response was not confirmed.');
  uncertain=false;recoveryConfirmed=true;recoveryKey.value=candidate;copyKey.disabled=false;recoveryStatus.textContent='The old key is revoked. Copy this key and import it in the client’s Account settings.';
  await load();status.textContent='Recovery key ready for '+name+'.';copyKey.focus();
 }catch(error){status.textContent=error.message;if(uncertain){recoveryKey.value=candidate;copyKey.disabled=false;recoveryStatus.textContent='Recovery was not confirmed. Keep this candidate key; refresh and recover again if needed.'}else recoveryStatus.textContent='No recovery key was issued. Refresh and try again.'}finally{setBusy(false)}
}
async function copyRecoveryKey(){if(!recoveryKey.value||copyKey.disabled)return;try{await navigator.clipboard.writeText(recoveryKey.value);recoveryStatus.textContent=recoveryConfirmed?'Account key copied.':'Candidate key copied; recovery is not confirmed.'}catch(_){recoveryKey.focus();recoveryKey.select();if(document.execCommand?.('copy'))recoveryStatus.textContent=recoveryConfirmed?'Account key copied.':'Candidate key copied; recovery is not confirmed.';else recoveryStatus.textContent='Select and copy the account key manually.'}}
copyKey.addEventListener('click',copyRecoveryKey);document.querySelector('#closeKey').addEventListener('click',()=>{recovery.hidden=true;recoveryConfirmed=false;recoveryKey.value='';copyKey.disabled=true;recoveryStatus.textContent=''});
pattern.addEventListener('input',()=>{clearTimeout(timer);revision++;validatedPattern=null;matched=0;remove.disabled=true;timer=setTimeout(load,250)});document.querySelector('#refresh').addEventListener('click',load);reset.addEventListener('click',()=>change('/api/reset',{},'Reset the entire Public Infinity leaderboard? All connected players will continue at score 0.'));remove.addEventListener('click',()=>change('/api/remove',{pattern:pattern.value},'Clear '+matched+' matching entries? Affected connected players will continue at score 0.'));randomizeColors.addEventListener('click',()=>change('/api/randomize-colors',{},'Randomize colors for every Public Infinity tank, including bots? The leader stays blue. This affects all tanks, regardless of the filter.'));load();setInterval(()=>{if(!busy&&!document.hidden)load()},5000);`
