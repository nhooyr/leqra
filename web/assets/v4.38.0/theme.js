/* leqra dark-only appearance palette. No user theme state or media listeners. */
(() => {
 'use strict';
 const palette=Object.freeze({accent:'#00c8ff',page:'#111619',arena:'#10181e',floor:'#151f25',tileA:'#182229',tileB:'#172128',tileLine:'#d9e6e809',dots:'#a5b9b423',cross:'#c8d9cd0d',wallShadow:'#080e13',wall:'#35434b',wallEdge:'#667773',rim:'#829285',registration:'#62766d38',protection:'#d8e9c5',guideAlpha:.28,neutralHill:'#e7eadd',neutralHillFill:'#f1f3e922',outline:'#1c1830'});
 const colorNames=Object.freeze(['Electric blue','Coral','Jade','Amethyst','Amber','Orchid','Leaf','Iris']);
 const colors=Object.freeze(['#32c5ff','#ff758f','#3ee6c5','#ba91ff','#ffcb66','#ff7bd5','#79d878','#91a9ff']);
 const canonical=Object.freeze(['#d2f65a','#ff9679','#73cee4','#c5a2ff','#ffc46b','#ff83bd','#75f0cb','#b7c6ee']);
 const powerColors=Object.freeze({rapid:'#79d878',scatter:'#ba91ff',shield:'#32c5ff',homing:'#ff7bd5',grenade:'#ffcb66',speed:'#3ee6c5',laser:'#e879ff',scope:'#91a9ff',cannon:'#ff9e66',ghost:'#cedaff'});
 const legacyPower=Object.freeze({'#f57cff':'laser','#8fb8ff':'scope','#ffad70':'cannon','#cce4ff':'ghost'});
 const lookup=new Map();
 canonical.forEach((c,i)=>lookup.set(c,colors[i]));
 for(const [kind,c] of Object.entries(powerColors))lookup.set(c,c);
 for(const [c,kind] of Object.entries(legacyPower))lookup.set(c,powerColors[kind]);
 const cache=new Map();
 function assetColor(value){
  if(typeof value!=='string')return value;
  if(cache.has(value))return cache.get(value);
  const raw=value.toLowerCase();let out=raw;
  if(/^#[0-9a-f]{6}([0-9a-f]{2})?$/.test(raw)){
   const base=raw.slice(0,7),alpha=raw.slice(7),mapped=lookup.get(base)||base;
   out=mapped+alpha;
  }
  if(cache.size>=256)cache.clear();cache.set(value,out);return out;
 }
 function powerColor(kind,fallback){return powerColors[kind]||assetColor(fallback);}
 document.documentElement.dataset.theme='dark';document.documentElement.style.colorScheme='dark';
 const meta=document.querySelector('meta[name="theme-color"]');if(meta)meta.setAttribute('content',palette.page);
 window.leqraTheme=Object.freeze({assetColor,powerColor,colorNames,colors,palette,resolved:'dark'});
})();
