'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {lstatSync,readFileSync,realpathSync}=require('node:fs'),path=require('node:path');

test('versioned shared assets link to their browser sources',()=>{
 const web=path.join(__dirname,'../web');
 const shell=readFileSync(path.join(web,'index.html'),'utf8');
 const prefix=shell.match(/assets\/v[\d.]+\//)?.[0];
 assert.ok(prefix,'the shell references versioned assets');
 for(const name of ['favicon.svg','game.js','netcode.js','style.css','theme.css','theme.js']){
  const versioned=path.join(web,prefix,name);
  assert.ok(lstatSync(versioned).isSymbolicLink(),name);
  assert.equal(realpathSync(versioned),realpathSync(path.join(web,name)));
 }
});
