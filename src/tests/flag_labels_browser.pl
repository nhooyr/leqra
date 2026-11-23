#!/usr/bin/env perl
package main;
use v5.34;
use strict;
use warnings;
use utf8;
use Encode ();
binmode STDOUT, ":encoding(UTF-8)";
binmode STDERR, ":encoding(UTF-8)";
use FindBin;
use lib "$FindBin::Bin/lib";
use Leqra::Browser;

my ($args, $assets, $browser, $checks, $context, $errors, $expected, $height, $html, $i, $initial_size, $js, $mobile, $out, $overlap, $page, $parser, $pw, $report, $result, $root, $status, $t, $tag, $web, $width);
# Focused v3.7.1 rendering regression; run with Python Playwright + Chromium.
# Uses the shipped scripts with synthetic Location/storage for explicit test mode.
# No game logic is replaced and no network service is needed for this visual test.
$parser = {};
$args = do { my %args = ('browser' => '/usr/bin/chromium', 'output' => 'test-output/flag-labels'); my $help; GetOptions('browser=s' => \$args{'browser'}, 'output=s' => \$args{'output'}, 'help|h' => \$help) or die 'Usage: perl flag_labels_browser.pl --browser --output
'; if ($help) { print 'Usage: perl flag_labels_browser.pl --browser --output
'; exit 0; }  \%args; };
$root = path($0)->absolute->parent(2);
$web = $root->child('web');
$assets = asset_directory($web);
$out = path($args->{'output'});
$out->mkpath;
my $tuple_21_0 = [[], []];
$checks = $tuple_21_0->[0];
$errors = $tuple_21_0->[1];
sub check {
    my ($condition, $label) = @_;
    if (truth_value((!truth_value($condition)))) {
        die json_text($label);
    }
    push(@{$checks}, $label);
    print(join(" ", 'PASS', $label), "\n");
}
$pw = start_playwright();
my $playwright = $pw;
$browser = $pw->launch(type => 'chrome', headless => JSON::PP::true, executablePath => $args->{'browser'});
eval {
    for my $item (@{[[1365, 950], [390, 844], [320, 568], [844, 390]]}) {
        my $tuple_32_12 = $item;
        my $width = $tuple_32_12->[0];
        my $height = $tuple_32_12->[1];
        my $mobile = (do { my $boolean_value = (($width < 760)); truth_value($boolean_value) ? $boolean_value : (($height < 620)) });
        my $context = $browser->newContext({viewport => {'width' => $width, 'height' => $height}, isMobile => $mobile, hasTouch => $mobile, deviceScaleFactor => (truth_value($mobile) ? 2 : 1)});
        eval {
            my $page = $context->newPage();
            capture_event($page, 'pageerror', $errors, '(e) => String(e)');
            my $html = replace_re('<link[^>]*>', '', $web->child('index.html')->slurp_utf8);
            $html = replace_re('<script src="[^"]+" defer></script>', '', $html);
            $html = replace_text($html, '</head>', (('<style>' . $assets->child('style.css')->slurp_utf8) . '</style></head>'));
            $page->setContent($html);
            evaluate_js($page, '()=>{
                    window.__location=new URL(\'http://game.test/?test=1\');
                    const store=data=>({getItem:k=>Object.hasOwn(data,k)?data[k]:null,
                        setItem:(k,v)=>data[k]=String(v),removeItem:k=>delete data[k]});
                    Object.defineProperty(window,\'localStorage\',{value:store({\'leqra.name\':\'PILOT\',\'leqra.muted\':\'1\'})});
                    Object.defineProperty(window,\'sessionStorage\',{value:store({})});
                }');
            my $js = replace_text($assets->child('game.js')->slurp_utf8, '(() => {', '((location) => {', 1);
            my $i = rindex($js, '})()');
            assert_ok((($i >= 0)), 'i >= 0');
            $js = ((substr($js, 0, $i - 0) . '})(window.__location);') . substr($js, ($i + 4)));
            $page->addScriptTag({content => $assets->child('netcode.js')->slurp_utf8});
            $page->addScriptTag({content => $js});
            wait_js($page, 'window.__test && window.leqra');
            evaluate_js($page, '()=>{
                    const T=__test;
                    T.applyLocalPreset({rules:{...T.defaultRoomRules(),mode:\'ctf\',teamMode:\'teams\',
                        pickupRate:\'off\',timeLimit:600,scoreTarget:3,
                        teamNames:[\'Aurora\',\'Red Foxes\',\'Tidal Guard\',\'Violet Squad\']},
                        roster:[{kind:\'human\',name:\'PILOT\',team:1},
                            {kind:\'local\',name:\'PLAYER TWO\',team:1},
                            {kind:\'bot\',name:\'RUST\',difficulty:\'normal\',team:2},
                            {kind:\'bot\',name:\'VAPOR\',difficulty:\'normal\',team:2}]});
                }');
            $page->locator('#startRoomBtn')->click();
            evaluate_js($page, '()=>{
                    const T=__test;T.setPhase(\'paused\');T.clearBullets();
                    for(const t of T.tanks){t.invulnerable=0;t.shield=0;t.speedTime=0;}
                    T.updateHUD(true);
                }');
            for my $status (@{['home', 'dropped', 'carried']}) {
                my $result = evaluate_js($page, 'status=>{
                        const T=__test,o=T.localObjectives,w=leqra.getState().world;
                        for(let i=0;i<o.flags.length;i++){
                            const f=o.flags[i];f.home=status===\'home\';f.carrier=-1;
                            f.returnIn=status===\'dropped\'?7:0;
                            f.x=f.home?f.homeX:w.width*(i===0?.32:.68);
                            f.y=f.home?f.homeY:w.height*.52;
                            if(status===\'carried\'){
                                const t=T.tanks.find(t=>t.team!==f.team);
                                t.x=w.width*(i===0?.32:.68);t.y=w.height*.52;
                                f.carrier=t.id;f.x=t.x;f.y=t.y;
                            }
                        }
                        T.updateHUD(true);
                        const before=JSON.stringify(o),c=document.querySelector(\'#arena\').getContext(\'2d\');
                        const oldText=c.fillText,oldFill=c.fill;
                        let text=[],fills=0;
                        c.fillText=function(s,...args){text.push(String(s));return oldText.call(this,s,...args)};
                        c.fill=function(...args){fills++;return oldFill.apply(this,args)};
                        let flagText,flagFills,frameText;
                        try {
                            T.drawFlags();flagText=text.slice();flagFills=fills;text=[];
                            T.render();frameText=text.slice();
                        } finally {c.fillText=oldText;c.fill=oldFill;}
                        const r=document.querySelector(\'#arenaWrap\').getBoundingClientRect();
                        return {flagText,flagFills,frameText,count:o.flags.length,
                            unchanged:before===JSON.stringify(o),
                            objective:document.querySelector(\'#objectiveStatus\').textContent,
                            size:[r.width,r.height],overflow:document.documentElement.scrollWidth>innerWidth};
                    }', $status);
                my $tag = ($status . ' / ' . $width . 'x' . $height);
                main::check((value_eq($result->{'flagText'}, ['1', '2'])), ('Only numbered pennants, no flag captions: ' . $tag));
                main::check((value_eq($result->{'flagFills'}, (2 * $result->{'count'}))), ('No extra caption backing strips: ' . $tag));
                main::check((!truth_value(scalar(grep { my $t = $_; match_re('\\b(?:BASE|FLAG|CARRIED|DROPPED)\\b', $t) } @{$result->{'frameText'}}))), ('No base or status text drawn beneath flags in full frame: ' . $tag));
                main::check($result->{'unchanged'}, ('Rendering leaves objective state untouched: ' . $tag));
                my $expected = {'home' => 'HOME', 'dropped' => 'DROPPED', 'carried' => 'TAKEN'}->{$status};
                main::check((do { my $boolean_value = (contains_value($result->{'objective'}, $expected)); truth_value($boolean_value) ? (contains_value($result->{'objective'}, 'Aurora')) : $boolean_value }), ('Top objective status retained: ' . $tag));
                main::check((do { my $boolean_value = (!truth_value($result->{'overflow'})); truth_value($boolean_value) ? ((min(@{$result->{'size'}}) > 0)) : $boolean_value }), ('Layout fits viewport: ' . $tag));
                if (truth_value((value_eq($status, 'home')))) {
                    my $initial_size = $result->{'size'};
                } else {
                    main::check((value_eq($result->{'size'}, $initial_size)), ('Flag state does not resize arena: ' . $tag));
                }
                $page->screenshot({path => format_value($out->child(($status . '-' . $width . 'x' . $height . '.png')))});
            }
            my $overlap = evaluate_js($page, '()=>{
                    const T=__test,o=T.localObjectives,f=o.flags[0],t=T.tanks[0],v=T.view,w=leqra.getState().world;
                    const clamp=(x,a,b)=>Math.max(a,Math.min(b,x)),z=Math.max(1.35,1/v.scale);
                    f.home=true;f.carrier=-1;f.x=f.homeX;f.y=f.homeY;
                    t.x=clamp(f.x,40*z,w.width-40*z);t.y=clamp(f.y-12*z,26*z,w.height-36*z);
                    t.angle=0;t.recoil=0;t.shield=t.speedTime=t.invulnerable=0;
                    const cv=document.querySelector(\'#arena\'),c=cv.getContext(\'2d\'),d=cv.width/v.cssW;
                    const crop=()=>Array.from(c.getImageData(Math.round((v.offsetX+(t.x-10)*v.scale)*d),
                        Math.round((v.offsetY+(t.y-5)*v.scale)*d),Math.max(1,Math.floor(18*v.scale*d)),
                        Math.max(1,Math.floor(10*v.scale*d))).data);
                    T.render();const a=crop(),flags=o.flags;o.flags=[];T.render();const b=crop();o.flags=flags;T.render();
                    return a.every((n,i)=>n===b[i]);
                }');
            main::check($overlap, ('Flags still render behind tank hulls: ' . format_value([$width, $height])));
        1;
        };
        my $caught_error = $@;
        $context->close();
        die $caught_error if $caught_error;
    }
    main::check((!truth_value($errors)), 'No JavaScript page errors');
    $report = {'version' => '3.7.1', 'passed' => scalar(@{$checks}), 'checks' => $checks, 'errors' => $errors, 'limits' => 'Chromium desktop/mobile emulation with injected assets and synthetic Location/storage. No physical-device or public-host testing.'};
    $out->child('results.json')->spew_utf8(json_text($report, 1));
    print(join(" ", 'TOTAL', scalar(@{$checks})), "\n");
1;
};
my $caught_error = $@;
$browser->close();
die $caught_error if $caught_error;
