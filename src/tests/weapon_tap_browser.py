"""Real-browser power-up taps. Run with Playwright installed; artifacts stay in /tmp."""
import argparse
import functools
import http.server
import json
from pathlib import Path
import threading

from playwright.sync_api import sync_playwright

from web_assets import asset_directory


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--browser", choices=["chromium", "webkit", "firefox"], default="chromium")
parser.add_argument("--output", type=Path, default=Path("/tmp/leqra-weapon-taps"))
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
web = Path(__file__).resolve().parents[1] / "web"
assets = asset_directory(web)

# Only the served test copies expose fixture setup; the shipped scripts are unchanged.
fixed_hook = """
window.__ammoFixed={prepare(kind){
 window.leqraInfinity?.close();mode='room';localRoom.rules=validateRoomRules({...defaultRoomRules(),infinity:false,mode:'elimination',pickupRate:'off'});
 localRoom.players=[{id:0,member:1,kind:'human',name:'TAP PILOT',owner:0,team:0,colorIndex:0},{id:1,member:2,kind:'bot',name:'TARGET',owner:0,team:0,colorIndex:1,difficulty:'dumb'}];
 startMatch();phase='playing';spawnClock=1e9;pickups=[];clearInput();
 for(const t of tanks)Object.assign(t,{human:true,invulnerable:1000,spawnProtected:false,cooldown:0,fireHeld:false});
 const t=tanks[0];grantPower(t,kind);if(['rapid','scatter','homing','grenade','laser','cannon'].includes(kind))t.charges=t.machineRounds=1;
 updateHUD(true);return this.state();
},state(){const t=tanks[0];return{power:t.power||'',epoch:t.ammoEpoch,grenades:ownedGrenades(t).length,held:primaryFireHeld(),blocked:!!t.detonationHeld,phase,standard:bullets.filter(b=>!b.dead&&b.owner===t.id&&!b.kind).length,bullets:bullets.filter(b=>!b.dead&&b.owner===t.id).length};}};
"""
infinity_hook = """
window.__ammoInfinity={prepare(kind){
 const w=session;if(!w)throw Error('Infinity fixture not open');resetControls();w.nextBot=w.nextPickup=Infinity;w.pickups=[];w.bullets=[];
 const t=makeTank(w.id,420,420,false);Object.assign(t,{name:'TAP PILOT',invulnerable:1000,spawnProtected:false});
 w.tanks=[t];art.grantPower(t,kind,15,8);if(['rapid','scatter','homing','grenade','laser','cannon'].includes(kind))t.charges=t.machineRounds=1;
 w.camera.x=t.x;w.camera.y=t.y;w.nextHUD=0;draw(w,performance.now(),0);return this.state();
},state(){const w=session,t=w.tanks[0];return{power:t.power||'',epoch:t.ammoEpoch,grenades:w.bullets.filter(b=>!b.dead&&b.owner===t.id&&b.kind==='grenade').length,standard:w.bullets.filter(b=>!b.dead&&b.owner===t.id&&!b.kind).length,bullets:w.bullets.filter(b=>!b.dead&&b.owner===t.id).length};}};
"""


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path.startswith("/api/"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"players":0,"tankCount":0,"capacity":64,"leaders":[]}')
        else:
            super().do_GET()


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(web)))
threading.Thread(target=server.serve_forever, daemon=True).start()
origin = "http://127.0.0.1:" + str(server.server_port)
results = []
try:
    with sync_playwright() as pw:
        browser = getattr(pw, args.browser).launch()
        context = browser.new_context(viewport={"width": 430, "height": 932}, has_touch=True, service_workers="block")
        context.add_init_script("localStorage.setItem('leqra.introTour.v1','1');localStorage.setItem('leqra.muted','1');")
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        scripts = {
            "game.js": (assets / "game.js").read_text().replace("window.leqraInfinityArt=", fixed_hook + "\nwindow.leqraInfinityArt=", 1),
            "infinite.js": (assets / "infinite.js").read_text().replace("window.leqraInfinity =", infinity_hook + "\nwindow.leqraInfinity =", 1),
        }
        def serve_script(route):
            name = route.request.url.split("/")[-1].split("?")[0]
            route.fulfill(status=200, content_type="application/javascript", body=scripts[name])
        page.route("**/game.js", serve_script)
        page.route("**/infinite.js", serve_script)
        page.goto(origin + "/?test=1")
        page.wait_for_function("window.__ammoFixed && window.__ammoInfinity")
        weapons = ["rapid", "scatter", "homing", "grenade", "laser", "cannon"]
        for arena in ["fixed", "infinity"]:
            for kind in weapons + ["shield", "speed", "ghost", "starman"]:
                page.evaluate("""({arena,kind})=>{
                    if(arena==='fixed')return __ammoFixed.prepare(kind);
                    window.leqraInfinity.start('offline',{roomRules:{infinityRandomBots:false,pickupRate:'off'}});
                    return __ammoInfinity.prepare(kind);
                }""", {"arena": arena, "kind": kind})
                selector = "#fireBtn" if arena == "fixed" else "#infiniteFire"
                fire = page.locator(selector)
                fire.wait_for(state="visible")
                def down():
                    box = fire.bounding_box()
                    page.mouse.move(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
                    page.mouse.down()
                down()
                page.wait_for_timeout(100)
                page.mouse.up()
                page.wait_for_timeout(450)
                state = page.evaluate("arena=>(arena==='fixed'?__ammoFixed:__ammoInfinity).state()", arena)
                if kind in weapons:
                    assert state["power"] == "" and state["epoch"] == 2, (arena, kind, state)
                    assert state["standard"] == 0, (arena, kind, "tap also fired standard ammo", state)
                    if kind == "grenade":
                        down(); page.wait_for_timeout(100); page.mouse.up()
                        page.wait_for_function("arena=>(arena==='fixed'?__ammoFixed:__ammoInfinity).state().grenades===0", arg=arena)
                    page.wait_for_timeout(400)
                    down()
                    try:
                        page.wait_for_function("arena=>(arena==='fixed'?__ammoFixed:__ammoInfinity).state().standard>0", arg=arena, timeout=5000)
                    finally:
                        page.mouse.up()
                    held = page.evaluate("arena=>(arena==='fixed'?__ammoFixed:__ammoInfinity).state()", arena)
                    assert held["standard"] > 0, (arena, kind, "held fire did not resume", held)
                else:
                    assert state["bullets"] > 0, (arena, kind, state)
                assert not errors, errors
                results.append({"browser": args.browser, "arena": arena, "power": kind, "passed": True})
                print("PASS", args.browser, arena, kind, flush=True)
        page.screenshot(path=str(args.output / (args.browser + ".png")))
        browser.close()
finally:
    server.shutdown()
    (args.output / (args.browser + ".json")).write_text(json.dumps(results, indent=2) + "\n")
