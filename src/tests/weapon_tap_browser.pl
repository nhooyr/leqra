#!/usr/bin/env perl
# Real-browser power-up taps; artifacts stay outside the repository.
use v5.34;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Leqra::Browser;
use Leqra::HTTPFixture;
use HTTP::Response;
use LWP::MediaTypes qw(guess_media_type);
$| = 1;

my ($engine, $output, $help) = ('chromium', '/tmp/leqra-weapon-taps');
GetOptions('browser=s' => \$engine, 'output=s' => \$output, 'help|h' => \$help)
    or die "Usage: weapon_tap_browser.pl [--browser chromium|webkit|firefox] [--output DIR]\n";
if ($help) { say 'Usage: weapon_tap_browser.pl [--browser chromium|webkit|firefox] [--output DIR]'; exit; }
die "Unexpected arguments: @ARGV\n" if @ARGV;
die "Unknown browser $engine\n" unless $engine =~ /\A(?:chromium|webkit|firefox)\z/;
my $out = path($output);
$out->mkpath;
my $web = path($FindBin::Bin)->parent->child('web');
my $assets = asset_directory($web);

# Only served test copies expose fixture setup; shipped scripts stay unchanged.
my $fixed_hook = <<'JAVASCRIPT';

window.__ammoFixed={prepare(kind){
 window.leqraInfinity?.close();mode='room';localRoom.rules=validateRoomRules({...defaultRoomRules(),infinity:false,mode:'elimination',pickupRate:'off'});
 localRoom.players=[{id:0,member:1,kind:'human',name:'TAP PILOT',owner:0,team:0,colorIndex:0},{id:1,member:2,kind:'bot',name:'TARGET',owner:0,team:0,colorIndex:1,difficulty:'dumb'}];
 startMatch();phase='playing';spawnClock=1e9;pickups=[];clearInput();
 for(const t of tanks)Object.assign(t,{human:true,invulnerable:1000,spawnProtected:false,cooldown:0,fireHeld:false});
 const t=tanks[0];grantPower(t,kind);if(['rapid','scatter','homing','grenade','laser','cannon'].includes(kind))t.charges=t.machineRounds=1;
 updateHUD(true);return this.state();
},state(){const t=tanks[0];return{power:t.power||'',epoch:t.ammoEpoch,grenades:ownedGrenades(t).length,held:primaryFireHeld(),blocked:!!t.detonationHeld,phase,standard:bullets.filter(b=>!b.dead&&b.owner===t.id&&!b.kind).length,bullets:bullets.filter(b=>!b.dead&&b.owner===t.id).length};}};

JAVASCRIPT
my $infinity_hook = <<'JAVASCRIPT';

window.__ammoInfinity={prepare(kind){
 const w=session;if(!w)throw Error('Infinity fixture not open');resetControls();w.nextBot=w.nextPickup=Infinity;w.pickups=[];w.bullets=[];
 const t=makeTank(w.id,420,420,false);Object.assign(t,{name:'TAP PILOT',invulnerable:1000,spawnProtected:false});
 w.tanks=[t];art.grantPower(t,kind,15,8);if(['rapid','scatter','homing','grenade','laser','cannon'].includes(kind))t.charges=t.machineRounds=1;
 w.camera.x=t.x;w.camera.y=t.y;w.nextHUD=0;draw(w,performance.now(),0);return this.state();
},state(){const w=session,t=w.tanks[0];return{power:t.power||'',epoch:t.ammoEpoch,grenades:w.bullets.filter(b=>!b.dead&&b.owner===t.id&&b.kind==='grenade').length,standard:w.bullets.filter(b=>!b.dead&&b.owner===t.id&&!b.kind).length,bullets:w.bullets.filter(b=>!b.dead&&b.owner===t.id).length};}};

JAVASCRIPT
my %scripts = (
    'game.js' => replace_text($assets->child('game.js')->slurp_utf8, 'window.leqraInfinityArt =', "$fixed_hook\nwindow.leqraInfinityArt =", 1),
    'infinite.js' => replace_text($assets->child('infinite.js')->slurp_utf8, 'window.leqraInfinity =', "$infinity_hook\nwindow.leqraInfinity =", 1),
);
my $server = Leqra::HTTPFixture->new(sub {
    my ($request) = @_;
    my $relative = $request->uri->path;
    return HTTP::Response->new(200, 'OK', ['Content-Type' => 'application/json'], '{"players":0,"tankCount":0,"capacity":64,"leaders":[]}') if $relative =~ m{^/api/};
    $relative =~ s{^/}{};
    $relative = 'index.html' unless length $relative;
    return HTTP::Response->new(404) if $relative =~ m{(?:^|/)\.\.(?:/|$)};
    my ($name) = $relative =~ m{([^/]+)$};
    my $file = $web->child($relative);
    return HTTP::Response->new(404) unless $file->is_file;
    my $body = exists($scripts{$name}) ? $scripts{$name} : $file->slurp_raw;
    utf8::encode($body) if utf8::is_utf8($body);
    return HTTP::Response->new(200, 'OK', ['Content-Type' => scalar guess_media_type($relative)], $body);
});
my (@results, $browser);
my $ok = eval {
    my $pw = start_playwright();
    $browser = $pw->launch(type => ($engine eq 'chromium' ? 'chrome' : $engine), headless => 1);
    my $context = $browser->newContext({viewport => {width => 430, height => 932}, hasTouch => JSON::PP::true, serviceWorkers => 'block'});
    $context->addInitScript("localStorage.setItem('leqra.introTour.v1','1');localStorage.setItem('leqra.muted','1');");
    my $page = $context->newPage;
    my $errors = [];
    capture_event($page, 'pageerror', $errors, '(error) => String(error)');
    $page->goto($server->url . '/?test=1');
    wait_js($page, 'window.__ammoFixed && window.__ammoInfinity');
    my @weapons = qw(rapid scatter homing grenade laser cannon);
    my %weapons = map { $_ => 1 } @weapons;
    for my $arena (qw(fixed infinity)) {
        for my $kind (@weapons, qw(shield speed ghost starman)) {
            evaluate_js($page, <<'JAVASCRIPT', {arena => $arena, kind => $kind});
({arena,kind})=>{
    if(arena==='fixed')return __ammoFixed.prepare(kind);
    window.leqraInfinity.start('offline',{roomRules:{infinityRandomBots:false,pickupRate:'off'}});
    return __ammoInfinity.prepare(kind);
}
JAVASCRIPT
            my $fire = $page->locator($arena eq 'fixed' ? '#fireBtn' : '#infiniteFire');
            expect_locator($fire, 'to_be_visible');
            my $down = sub {
                my $box = $fire->boundingBox;
                $page->mouse->move($box->{x} + $box->{width} / 2, $box->{y} + $box->{height} / 2);
                $page->mouse->down;
            };
            $down->();
            sleep 0.1;
            $page->mouse->up;
            sleep 0.45;
            my $state = evaluate_js($page, "arena=>(arena==='fixed'?__ammoFixed:__ammoInfinity).state()", $arena);
            if ($weapons{$kind}) {
                assert_ok($state->{power} eq '' && $state->{epoch} == 2, [$arena, $kind, $state]);
                assert_ok($state->{standard} == 0, [$arena, $kind, 'tap also fired standard ammo', $state]);
                if ($kind eq 'grenade') {
                    $down->(); sleep 0.1; $page->mouse->up;
                    wait_js($page, "arena=>(arena==='fixed'?__ammoFixed:__ammoInfinity).state().grenades===0", $arena);
                }
                sleep 0.4;
                evaluate_js($page, 'window.__ammoHeldState = null');
                $down->();
                my $held_ok = eval {
                    # Capture the observed shot before RPC latency lets it leave the arena.
                    wait_js($page, <<'JAVASCRIPT', $arena, {timeout => 5000});
arena=>{
    const state=(arena==='fixed'?__ammoFixed:__ammoInfinity).state();
    if(!state.standard)return false;
    window.__ammoHeldState=state;
    return true;
}
JAVASCRIPT
                    1;
                };
                my $held_error = $@;
                $page->mouse->up;
                die $held_error unless $held_ok;
                my $held = evaluate_js($page, 'window.__ammoHeldState');
                assert_ok($held->{standard} > 0, [$arena, $kind, 'held fire did not resume', $held]);
            } else {
                assert_ok($state->{bullets} > 0, [$arena, $kind, $state]);
            }
            assert_ok(!@$errors, $errors);
            push @results, {browser => $engine, arena => $arena, power => $kind, passed => JSON::PP::true};
            say "PASS $engine $arena $kind";
        }
    }
    $page->screenshot({path => '' . $out->child("$engine.png")});
    1;
};
my $error = $@;
eval { $browser->close } if $browser;
$server->stop;
$out->child("$engine.json")->spew_utf8(json_text(\@results, 1) . "\n");
die $error unless $ok;
