'use strict';
// Create a standalone showcase and a Chrome Local Overrides folder next to it.
// Run from the repository root. Install dependencies once with
//   npm install --no-save --package-lock=false playwright
//   npx playwright install chromium
// Then generate bin/showcase.html and bin/chrome-overrides with
//   node scripts/render-showcase.cjs
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');
const {assetPath} = require('../src/tests/web_assets.cjs');

const root = path.join(__dirname, '..');
const web = path.join(root, 'src/web');
const out = process.argv[2] ? path.resolve(process.argv[2]) : path.join(root, 'bin/showcase.html');
const overrides = path.join(path.dirname(out), 'chrome-overrides');
const overrideFile = path.join(overrides, 'leqra.com', 'index.html');
const origin = 'http://leqra-showcase.test';
const viewport = {width:1560, height:930};
const deviceScaleFactor = 2;
const infiniteAsset = assetPath('infinite.js');

// Expose staging controls only in the temporary page served by this script.
const source = fs.readFileSync(infiniteAsset, 'utf8');
const publicAPI = 'window.leqraInfinity =';
if (!source.includes(publicAPI)) throw Error('Could not find Infinity staging point');
const stagedSource = source.replace(publicAPI, `
window.captureShowcase = () => {
 cancelAnimationFrame(frame);
 return {world:session, geometry, art, makeTank, traceLaser, fireShot, advanceBullet, presentEffect, draw};
};
` + publicAPI);

function stageBattle() {
 window.leqraInfinity.start('offline',{name:'PILOT',roomRules:{teamMode:'ffa'}});
 const {world,geometry,art,makeTank,traceLaser,fireShot,advanceBullet,presentEffect,draw} = window.captureShowcase();
 const seed = 14383, now = 8420, cell = geometry.cellSize;
 world.maze = geometry.create(seed);
 const center = n => (n+.5)*cell;

 const lineup = [
  ['PILOT',    0, 0, -.34, ['laser','shield','shield']],
  ['RUST',    -5,-2,  .37, ['cannon']],
  ['VAPOR',   -2,-2,  .48, ['rapid','speed','speed','speed']],
  ['PHANTOM',  2,-2, 2.10, ['scatter','ghost']],
  ['EMBER',    5,-1, 2.90, ['homing']],
  ['NOVA',    -4, 2, -.58, ['grenade']],
  ['BLITZ',   -1, 2,-1.82, ['cannon','speed']],
  ['ORBIT',    4, 2,-2.72, ['rapid','starman']],
 ];
 world.tanks = lineup.map(([name,col,row,angle,powers],i) => {
  const tank = makeTank(i ? 'bot-'+i : world.id,center(col),center(row),i!==0);
  Object.assign(tank,{name,angle,colorIndex:i,track:i*7+3,score:[19,12,16,7,10,14,3,18][i],invulnerable:0,recoil:.75});
  for (const power of powers) art.grantPower(tank,power,12,6.4);
  return tank;
 });

 // Find a wide ricochet from the pilot through the actual streamed maze.
 const hero = world.tanks[0];
 let best;
 for (let i=0; i<180; i++) {
  const angle = i*Math.PI/90, beam = traceLaser(world,{...hero,angle},true);
  const xs = beam.points.map(p=>p.x), ys = beam.points.map(p=>p.y);
  const span = Math.max(...xs)-Math.min(...xs)+.8*(Math.max(...ys)-Math.min(...ys));
  const score = span-18*beam.points.length;
  if (!best || score > best.score) best = {angle,beam,score};
 }
 hero.angle = best.angle;
 presentEffect(world,{kind:'laser',x:hero.x,y:hero.y,owner:hero.id,points:best.beam.points},now-36);
 presentEffect(world,{kind:'shield',x:hero.x,y:hero.y,owner:hero.id},now-120);
 presentEffect(world,{kind:'blast',x:center(-5),y:center(1),owner:world.tanks[5].id},now-105);

 // Compose the still from actual launch paths, including real spread and wall
 // bounces. A separate staging world prevents those launches from moving tanks
 // or consuming the displayed equipment.
 const volleys = {
  rapid: Array.from({length:22},(_,i)=>.04+i*.023),
  scatter:[.08,.22,.36,.50], homing:[.32,.61,.96],
  grenade:[.27,.58,1.02], cannon:[.16,.31,.48],
 };
 for (const tank of world.tanks.slice(1)) {
  const ages = volleys[tank.power];
  for (const [i,age] of ages.entries()) {
   const shooter = {...tank,angle:tank.angle+(i%5-2)*(tank.power==='rapid'?.036:.09)};
   const shot = {maze:world.maze,tanks:[shooter],controllers:[],bullets:[],visualEffects:[],time:now/1000,lastBullet:world.lastBullet};
   fireShot(shot,shooter);
   world.lastBullet = shot.lastBullet;
   for (const bullet of shot.bullets) {
    let alive = true;
    for (let t=0; t<age && alive; t+=1/60) {
     const dt = Math.min(1/60,age-t);
     bullet.trail.push({x:bullet.x,y:bullet.y});
     if (bullet.trail.length>7) bullet.trail.shift();
     if (bullet.kind==='grenade') {
      const drag = art.grenadeDragFactor(bullet.life,bullet.life-dt);
      bullet.vx *= drag;
      bullet.vy *= drag;
     }
     bullet.life -= dt;
     alive = advanceBullet(shot,bullet,dt);
    }
    const onScreen = Math.abs(bullet.x-hero.x)<7.4*cell && Math.abs(bullet.y-hero.y)<3.75*cell;
    const clearOfTanks = world.tanks.every(t=>Math.hypot(bullet.x-t.x,bullet.y-t.y)>24+bullet.r);
    if (alive && onScreen && clearOfTanks) {
     bullet.trail.push({x:bullet.x,y:bullet.y});
     world.bullets.push(bullet);
    }
   }
  }
 }

 const pickupCells = [[-6,0],[-5,3],[-4,-1],[-3,1],[-1,-3],[0,3],[1,-1],[3,1],[4,-3],[6,2]];
 const activePowers = [...new Set(lineup.flatMap(entry=>entry[4]))].sort();
 world.pickups = Object.keys(art.powers).map((type,i) => {
  const [col,row] = pickupCells[i];
  return {id:i+1,type,x:center(col),y:center(row),life:22};
 });
 document.querySelector('#infiniteLeaderboardPanel').open = true;
 world.nextHUD = 0;
 draw(world,now,0);
 return {seed,tanks:world.tanks.length,activePowers,pickups:world.pickups.length,
  projectiles:world.bullets.length,laserSegments:best.beam.points.length-1};
}

function showcasePage(screenshot) {
 const favicon = fs.readFileSync(assetPath('favicon.svg')).toString('base64');
 return `<!doctype html>
<html lang="en">
<head>
 <meta charset="utf-8">
 <meta name="viewport" content="width=device-width, initial-scale=1">
 <title>leqra — Tank Arena</title>
 <link rel="icon" type="image/svg+xml" href="data:image/svg+xml;base64,${favicon}">
 <style>
  html, body { margin:0; background:#10171d; }
  img { display:block; width:100%; height:auto; }
 </style>
</head>
<body>
 <img alt="Eight tanks battling in the Infinity maze" src="data:image/png;base64,${screenshot.toString('base64')}">
</body>
</html>
`;
}

async function main() {
 if (!/\.html?$/i.test(out)) throw Error('Showcase output must end in .html or .htm');
 const browser = await chromium.launch({chromiumSandbox:true});
 try {
  const page = await browser.newPage({viewport,deviceScaleFactor,serviceWorkers:'block'});
  await page.addInitScript(() => {
   localStorage.setItem('leqra.introTour.v1','1');
   localStorage.setItem('leqra.muted','1');
  });
  await page.route('**/*', route => {
   const url = new URL(route.request().url());
   if (url.origin!==origin) return route.abort();
   const file = path.join(web,url.pathname==='/'?'index.html':url.pathname);
   if (file===infiniteAsset) return route.fulfill({contentType:'application/javascript',body:stagedSource});
   return route.fulfill({path:file});
  });
  await page.goto(origin);
  await page.evaluate(() => document.fonts.ready);
  const scene = await page.evaluate(stageBattle);
  if (scene.tanks!==8 || scene.activePowers.length!==10 || scene.projectiles<40) throw Error('Incomplete Infinity showcase');
  const screenshot = await page.screenshot({animations:'disabled'});
  const html = showcasePage(screenshot);
  fs.mkdirSync(path.dirname(overrideFile),{recursive:true});
  fs.writeFileSync(out,html);
  fs.writeFileSync(overrideFile,html);
  console.log(JSON.stringify({output:process.argv[2]?out:path.relative(root,out),chromeOverrides:overrides,width:viewport.width*deviceScaleFactor,
   height:viewport.height*deviceScaleFactor,mode:'Infinity',...scene,renderer:'production Infinity page and Canvas renderer'},null,2));
 } finally {
  await browser.close();
 }
}

main().catch(error=>{console.error(error);process.exitCode=1;});
