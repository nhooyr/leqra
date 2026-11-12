'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {copyFileSync,existsSync,mkdirSync,mkdtempSync,readFileSync,rmSync,statSync,utimesSync,writeFileSync}=require('node:fs');
const path=require('node:path'),os=require('node:os'),{spawnSync}=require('node:child_process');

const scripts=path.resolve(__dirname,'../../scripts'),plistBuddy='/usr/libexec/PlistBuddy';
function fixture(t){
 const root=mkdtempSync(path.join(os.tmpdir(),'leqra ios version-'));
 t.after(()=>rmSync(root,{recursive:true,force:true}));
 for(const directory of ['scripts','src','generated outputs'])mkdirSync(path.join(root,directory));
 for(const name of ['version.sh','ios-version.sh'])copyFileSync(path.join(scripts,name),path.join(root,'scripts',name));
 const setVersion=version=>writeFileSync(path.join(root,'src/main.go'),'package main\n\nconst (\n\tversion = "'+version+'"\n)\n');
 setVersion('4.49.38');
 const run=(...args)=>spawnSync('/bin/sh',[path.join(root,'scripts/ios-version.sh'),...args],{cwd:root,encoding:'utf8'});
 const generate=(...args)=>{const result=run(...args);assert.equal(result.status,0,result.stderr||result.stdout);};
 return{root,setVersion,run,generate,output:name=>path.join(root,'generated outputs',name)};
}

test('iOS Swift version follows Go release changes and unchanged generation preserves mtime',t=>{
 const f=fixture(t),output=f.output('GeneratedVersion.swift');
 f.generate('--swift',output);
 assert.match(readFileSync(output,'utf8'),/enum\s+GeneratedVersion\b/);
 assert.match(readFileSync(output,'utf8'),/static\s+let\s+value\s*=\s*"4\.49\.38"/);
 const original=readFileSync(output,'utf8'),oldDate=new Date('2001-01-01T00:00:00Z');
 utimesSync(output,oldDate,oldDate);
 const unchangedTime=statSync(output,{bigint:true}).mtimeNs;
 f.generate('--swift',output);
 assert.equal(readFileSync(output,'utf8'),original);
 assert.equal(statSync(output,{bigint:true}).mtimeNs,unchangedTime,'identical output must not trigger a Swift rebuild');
 f.setVersion('4.50.1');f.generate('--swift',output);
 assert.match(readFileSync(output,'utf8'),/static\s+let\s+value\s*=\s*"4\.50\.1"/);
 assert.notEqual(readFileSync(output,'utf8'),original);
 assert.notEqual(statSync(output,{bigint:true}).mtimeNs,unchangedTime);
});

test('iOS generation uses scripts/version.sh as the version reader',t=>{
 const f=fixture(t),output=f.output('GeneratedVersion.swift');
 writeFileSync(path.join(f.root,'scripts/version.sh'),"#!/bin/sh\nprintf '%s\\n' '7.8.9'\n");
 f.generate('--swift',output);
 assert.match(readFileSync(output,'utf8'),/static\s+let\s+value\s*=\s*"7\.8\.9"/);
});

test('iOS generation rejects malformed release versions before modifying output',t=>{
 const f=fixture(t),output=f.output('GeneratedVersion.swift');
 f.generate('--swift',output);
 const original=readFileSync(output,'utf8');
 for(const version of ['','4','4.49','4.49.38.1','v4.49.38','4.49.beta','4..38']){
  f.setVersion(version);
  const result=f.run('--swift',output);
  assert.notEqual(result.status,0,'invalid release accepted: '+JSON.stringify(version));
  assert.equal(readFileSync(output,'utf8'),original,'invalid release changed generated source');
 }
});

test('iOS plist generation updates the release while preserving build and product placeholders',{
 skip:process.platform!=='darwin'||!existsSync(plistBuddy),
},t=>{
 const f=fixture(t),template=f.output('Template.plist'),output=f.output('Info.plist');
 const original='<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>\n'+
  '<key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>\n'+
  '<key>CFBundleVersion</key><string>$(CURRENT_PROJECT_VERSION)</string>\n'+
  '<key>CFBundleName</key><string>$(PRODUCT_NAME)</string>\n'+
  '<key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>\n'+
  '</dict></plist>\n';
 writeFileSync(template,original);
 const value=key=>{
  const result=spawnSync(plistBuddy,['-c','Print :'+key,output],{encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);return result.stdout.trim();
 };
 f.generate('--plist',template,output);
 assert.equal(value('CFBundleShortVersionString'),'4.49.38');
 assert.equal(value('CFBundleVersion'),'$(CURRENT_PROJECT_VERSION)');
 assert.equal(value('CFBundleName'),'$(PRODUCT_NAME)');
 assert.equal(value('CFBundleIdentifier'),'$(PRODUCT_BUNDLE_IDENTIFIER)');
 assert.equal(readFileSync(template,'utf8'),original,'source template must stay untouched');
 f.setVersion('4.50.1');f.generate('--plist',template,output);
 assert.equal(value('CFBundleShortVersionString'),'4.50.1');
 assert.equal(value('CFBundleVersion'),'$(CURRENT_PROJECT_VERSION)');
 assert.equal(value('CFBundleIdentifier'),'$(PRODUCT_BUNDLE_IDENTIFIER)');
});
