'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {lstatSync,readdirSync}=require('node:fs'),path=require('node:path');
const {assetPath}=require('./web_assets.cjs');

test('browser assets are regular files in the versioned directory',()=>{
 const web=path.join(__dirname,'../web');
 assert.deepEqual(readdirSync(web).sort(),['assets','index.html']);
 for(const name of ['favicon.svg','game.js','netcode.js','style.css','theme.css','theme.js']){
  assert.ok(lstatSync(assetPath(name)).isFile(),name);
 }
});
