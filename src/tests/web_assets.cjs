'use strict';
const {readFileSync}=require('node:fs'),path=require('node:path');

const web=path.join(__dirname,'../web');
const shell=readFileSync(path.join(web,'index.html'),'utf8');
const assetVersion=shell.match(/src="assets\/(v\d+\.\d+\.\d+)\/game\.js"/)?.[1];
if(!assetVersion)throw new Error('index.html must reference a versioned game.js');

function assetPath(name){
 return path.join(web,'assets',assetVersion,name);
}

module.exports={assetPath,assetVersion};
