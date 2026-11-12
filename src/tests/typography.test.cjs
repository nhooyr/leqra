'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {assetPath}=require('./web_assets.cjs');
const css=readFileSync(assetPath('style.css'),'utf8');

test('UI typography has a ten CSS pixel floor without reducing larger declarations',()=>{
 assert.match(css,/:root\{[^}]*--min-font-size:10px;/);
 const small=[];
 for(const match of css.matchAll(/(?:^|[;{])\s*(font(?:-size)?)\s*:\s*([^;}]+)/g)){
  for(const value of match[2].matchAll(/(?<![\w.-])(\d+(?:\.\d+)?)px/g))if(Number(value[1])<10)small.push(match[0]);
 }
 assert.deepEqual(small,[],'Text sizes and explicit font line heights cannot be smaller than the shared floor');
 assert.match(css,/\.brand-name\{[^}]*font-size:22px/);
 assert.match(css,/\.feature-header h2\{[^}]*font-size:25px/);
});
