'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('infinite.js'),'utf8');
const start=source.indexOf('function alignControlHints('),end=source.indexOf('\n}',start)+2;
const scope={};vm.createContext(scope);vm.runInContext(source.slice(start,end),scope);
function group(width){return{style:{width:'',maxWidth:'100%'},getBoundingClientRect(){assert.equal(this.style.width,'max-content');assert.equal(this.style.maxWidth,'none');return{width};}};}

test('paired control actions share their natural widths so long aliases wrap on the same boundary',()=>{
 const rows=[[63.2,63.2,44.7,50.9,66.9],[63.2,63.2,44.7,50.9,112.8]].map(widths=>({children:widths.map(group)}));
 scope.alignControlHints({querySelectorAll:()=>rows});
 for(const row of rows){assert.deepEqual(row.children.map(group=>group.style.width),['64px','64px','45px','51px','113px']);assert.ok(row.children.every(group=>group.style.maxWidth==='100%'));}
 rows[0].children[2].getBoundingClientRect=()=>({width:161.4});
 scope.alignControlHints({querySelectorAll:()=>rows});
 assert.equal(rows[0].children[2].style.width,'162px');assert.equal(rows[1].children[2].style.width,'162px');
});

test('solo and touch hints keep their natural compact flow',()=>{
 const one={children:[group(10)]};scope.alignControlHints({querySelectorAll:()=>[one]});assert.equal(one.children[0].style.width,'');
 scope.alignControlHints({querySelectorAll:()=>[]});
});
