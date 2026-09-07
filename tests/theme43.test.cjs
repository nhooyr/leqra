'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const source=readFileSync(path.join(__dirname,'../web/theme.js'),'utf8');
function boot(){
 const root={dataset:{},style:{}},meta={setAttribute(k,v){this[k]=v;}};
 const window={};
 vm.runInNewContext(source,{window,document:{documentElement:root,querySelector(sel){return sel==='meta[name="theme-color"]'?meta:null;}}});
 return{api:window.leqraTheme,root,meta};
}
test('appearance is dark-only with neon blue primary',()=>{const t=boot();assert.equal(t.api.resolved,'dark');assert.equal(t.api.palette.accent,'#00c8ff');assert.equal(t.root.dataset.theme,'dark');assert.equal(t.root.style.colorScheme,'dark');});
test('dark bootstrap contains no light-mode state or browser color-scheme listener',()=>{for(const bad of ['prefers-color-scheme','setPreference','theme.v1','themePreference','neon purple','#a100ff'])assert.equal(source.includes(bad),false,bad);});
test('eight stable dark palette colors remain distinct',()=>{const t=boot();assert.equal(t.api.colors.length,8);assert.equal(t.api.colorNames.length,8);assert.equal(new Set(t.api.colors).size,8);});
test('canonical team colors map deterministically and preserve alpha',()=>{const t=boot(),canon=['#d2f65a','#ff9679','#73cee4','#c5a2ff','#ffc46b','#ff83bd','#75f0cb','#b7c6ee'];for(let i=0;i<8;i++){assert.equal(t.api.assetColor(canon[i]),t.api.colors[i]);assert.equal(t.api.assetColor(canon[i]+'77'),t.api.colors[i]+'77');}});
test('theme-color metadata follows the dark page surface',()=>{const t=boot();assert.equal(t.meta.content,t.api.palette.page);assert(Object.isFrozen(t.api.palette));});
test('asset mapping is idempotent and ignores non-strings',()=>{const t=boot();for(const c of t.api.colors)assert.equal(t.api.assetColor(t.api.assetColor(c)),c);const v={};assert.equal(t.api.assetColor(v),v);});
