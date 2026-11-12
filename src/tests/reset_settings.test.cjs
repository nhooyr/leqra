'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const {assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
function declaration(name){let start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);if(source.slice(start-6,start)==='async ')start-=6;const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot({pwa=true,capabilities=true}={}){
 const events=[],elements=new Map(),timers=new Map();let serial=0;
 class Element{
  constructor(id){this.id=id;this.children=[];this.dataset={};this.listeners={};this.attributes={};this.hidden=false;this.disabled=false;this.inert=false;this.open=false;this.textContent='';this.classes=new Set();this.classList={add:key=>this.classes.add(key),remove:key=>this.classes.delete(key),toggle:(key,on)=>on?this.classes.add(key):this.classes.delete(key)};elements.set(id,this);}
  append(...children){for(const child of children){child.parentElement=this;this.children.push(child);}}
  setAttribute(key,value){this.attributes[key]=String(value);}
  addEventListener(type,handler){this.listeners[type]=handler;}
  showModal(){this.open=true;this.shows=(this.shows||0)+1;}
  close(){this.open=false;this.listeners.close?.();}
  focus(){s.document.activeElement=this;}
 }
 const body=new Element('body'),app=new Element('app'),features=new Element('features'),controls=new Element('controlsDialog'),reset=new Element('settingsResetDialog');
 controls.open=true;features.append(controls);controls.append(new Element('resetAllSettingsBtn'));body.append(app,features,reset);
 for(const id of ['settingsResetTitle','settingsResetStatus','settingsResetRetryBtn','settingsResetReloadBtn'])reset.append(new Element(id));
 class Storage{
  constructor(entries,label){this.values=new Map(entries);this.label=label;}
  get length(){return this.values.size;}
  key(index){return [...this.values.keys()][index]??null;}
  getItem(key){return this.values.get(key)??null;}
  setItem(key,value){this.values.set(key,String(value));}
  removeItem(key){events.push('remove:'+this.label);if(this.fail)throw Error('Storage denied');this.values.delete(key);}
 }
 const local=new Storage([['leqra.name','OLD'],['leqra.roomSetup.v2','room'],['leqra.onlineWin.old','1'],['ricochet.bindings','old'],['unrelated.name','KEPT'],['leqra','KEPT TOO']],'local'),session=new Storage([['leqra.session','auth'],['ricochet.kicked','old'],['another.session','KEPT']],'session');
 const s={Promise,URL,STORAGE_PREFIX:'leqra.',LEGACY_STORAGE_PREFIX:'ricochet.',settingsResetActive:false,
  $:id=>elements.get(id),document:{body,activeElement:null,querySelectorAll:selector=>selector==='dialog[open]'?[controls,reset].filter(dialog=>dialog.open):[]},
  window:{},navigator:capabilities?{serviceWorker:{}}:{},location:{href:'https://leqra.test/?room=Friday&spectate=1&test=1#preview',replace(url){s.reloaded=url;}},
  freezeForSettingsReset(){events.push('freeze');s.settingsResetActive=true;if(s.freezeFail)throw Error('Freeze failed');},
  setTimeout(fn){timers.set(++serial,fn);return serial;},clearTimeout(id){timers.delete(id);},
 };
 Object.defineProperties(s,{localStorage:{get(){if(s.localDenied)throw Error('Denied');return local;}},sessionStorage:{get(){if(s.sessionDenied)throw Error('Denied');return session;}}});
 if(pwa)s.window.leqraPWA={async reset(){events.push('pwa');s.pwaCalls=(s.pwaCalls||0)+1;if(s.pwaFail)throw Error('Cached files could not be removed.');}};
 vm.createContext(s);for(const name of ['clearAppSettingsStorage','verifyAppSettingsStorage','resetPWASettings','resetAllSettings','reloadAfterSettingsReset','initSettingsReset'])vm.runInContext(declaration(name),s);s.initSettingsReset();
 return{s,$:s.$,local,session,events,timers,app,features,controls,reset};
}

test('Reset All freezes first, selectively clears both stores and locks the UI until explicit reload',async()=>{
 const h=boot(),{s,$,local,session,events,reset}=h;let complete;
 s.window.leqraPWA.reset=()=>{events.push('pwa');return new Promise(resolve=>{complete=resolve;});};
 const pending=$('resetAllSettingsBtn').onclick();await Promise.resolve();await Promise.resolve();
 assert.equal(events[0],'freeze');assert.ok(events.indexOf('pwa')>events.indexOf('remove:local'));assert.equal(h.controls.open,false);assert.equal(h.app.inert,true);assert.equal(h.features.inert,true);assert.equal(reset.inert,false);assert.equal(reset.open,true);assert.equal($('settingsResetReloadBtn').disabled,true);
 const cancel={preventDefault(){this.prevented=true;}};reset.listeners.cancel(cancel);assert.equal(cancel.prevented,true);reset.close();assert.equal(reset.open,true,'late dialog closes cannot dismiss the reload prompt');
 await $('resetAllSettingsBtn').onclick();assert.equal(events.filter(event=>event==='freeze').length,1,'repeated clicks share the pending attempt');complete();await pending;
 assert.deepEqual([...local.values],[['unrelated.name','KEPT'],['leqra','KEPT TOO']]);assert.deepEqual([...session.values],[['another.session','KEPT']]);
 assert.equal($('settingsResetTitle').textContent,'Reload to finish.');assert.match($('settingsResetStatus').textContent,/were cleared/);assert.equal($('settingsResetRetryBtn').hidden,true);assert.equal($('settingsResetReloadBtn').disabled,false);assert.equal(s.reloaded,undefined);
 $('settingsResetReloadBtn').onclick();const url=new URL(s.reloaded);assert.equal(url.searchParams.has('room'),false);assert.equal(url.searchParams.has('spectate'),false);assert.equal(url.searchParams.get('test'),'1');
});

test('storage and PWA failures remain visible and retryable without reactivating the game',async()=>{
 for(const failure of ['localDenied','sessionDenied','pwaFail','remove','freezeFail']){
  const h=boot(),{s,$,local}=h;if(failure==='remove')local.fail=true;else s[failure]=true;
  await $('resetAllSettingsBtn').onclick();assert.equal($('settingsResetTitle').textContent,'Reset needs attention.',failure);assert.equal($('settingsResetRetryBtn').hidden,false);assert.equal($('settingsResetReloadBtn').disabled,false);assert.equal(h.app.inert,true);assert.equal(h.reset.open,true);assert.doesNotMatch($('settingsResetStatus').textContent,/were cleared/);
  if(failure==='freezeFail'){assert.equal(local.values.get('leqra.name'),'OLD','cleanup waits until late writes can be stopped safely');assert.match($('settingsResetStatus').textContent,/Freeze failed/,'freeze failures retain their concrete cause');}
  if(failure==='remove')local.fail=false;else s[failure]=false;
  await $('settingsResetRetryBtn').onclick();assert.equal($('settingsResetTitle').textContent,'Reload to finish.',failure);assert.equal(local.values.has('leqra.name'),false);assert.equal(h.app.inert,true);
 }
});

test('reset supports non-PWA/offline pages and reports an unavailable or stalled PWA cleanup',async()=>{
 const plain=boot({pwa:false,capabilities:false});await plain.s.resetAllSettings();assert.equal(plain.$('settingsResetTitle').textContent,'Reload to finish.');
 const missing=boot({pwa:false});await missing.s.resetAllSettings();assert.equal(missing.$('settingsResetTitle').textContent,'Reset needs attention.');assert.match(missing.$('settingsResetStatus').textContent,/unavailable/);
 const stalled=boot();stalled.s.window.leqraPWA.reset=()=>new Promise(()=>{});const pending=stalled.s.resetAllSettings();await Promise.resolve();await Promise.resolve();for(const timeout of [...stalled.timers.values()])timeout();await pending;
 assert.match(stalled.$('settingsResetStatus').textContent,/timed out/);assert.equal(stalled.$('settingsResetRetryBtn').hidden,false);assert.equal(stalled.$('settingsResetReloadBtn').disabled,false);
});

test('Controls exposes reset after default keys and the reload prompt has no dismiss action',()=>{
 assert.match(source,/<button[^>]*id="resetBindingsBtn"[^>]*>RESET DEFAULT KEYS<\/button><button[^>]*id="resetAllSettingsBtn"[^>]*>RESET ALL SETTINGS<\/button>/);
 const html=readFileSync(path.join(__dirname,'../web/index.html'),'utf8'),dialog=html.match(/<dialog id="settingsResetDialog"[\s\S]*?<\/dialog>/)?.[0];assert.ok(dialog);assert.match(dialog,/aria-labelledby="settingsResetTitle"/);assert.doesNotMatch(dialog,/CANCEL|CLOSE|data-close-dialog|method="dialog"/);
 const css=readFileSync(assetPath('style.css'),'utf8');assert.match(css,/\.settings-reset-dialog \.feature-footer\{[^}]*gap:10px/);assert.match(css,/\.settings-reset-dialog \.feature-footer button\{margin:0\}/);
});


test('Reset All Settings preserves the account and any unacknowledged replacement key',async()=>{
 const {s,$,local}=boot({pwa:false,capabilities:false});local.setItem('leqra.publicToken','private-owner');local.setItem('leqra.localPublicToken','private-p2');local.setItem('leqra.localAccountRegistration','saved-p2-registration');local.setItem('leqra.pendingAccountKey.test','saved-replacement');
 await $('resetAllSettingsBtn').onclick();assert.equal(local.getItem('leqra.publicToken'),'private-owner');assert.equal(local.getItem('leqra.localPublicToken'),'private-p2');assert.equal(local.getItem('leqra.localAccountRegistration'),'saved-p2-registration');assert.equal(local.getItem('leqra.pendingAccountKey.test'),'saved-replacement');assert.equal(local.getItem('leqra.name'),null);assert.equal($('settingsResetTitle').textContent,'Reload to finish.');
});
