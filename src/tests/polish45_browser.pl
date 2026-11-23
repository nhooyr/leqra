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

my ( $a, $ap, $assets, $b, $c, $checks, $code, $contexts, $errors, $gid, $guest, $hid,
    $host, $html, $i, $js, $labels, $out, $p, $p2, $pw, $r, $speed, $state, $teamcheck, $web, $x );

# v4.5 focused browser regression: dark-only theme, callsigns, paint ownership, teams and speed stacks.
$ap = {};
$a  = do {
    my %args = (
        'url'    => 'http://127.0.0.1:8455',
        'output' => 'test-output/polish45'
    );
    my $help;
    GetOptions(
        'url=s'    => \$args{'url'},
        'output=s' => \$args{'output'},
        'help|h'   => \$help
      )
      or die 'Usage: perl polish45_browser.pl --url --output
';
    if ($help) {
        print 'Usage: perl polish45_browser.pl --url --output
';
        exit 0;
    }
    \%args;
};
$r      = path($0)->absolute->parent(2);
$web    = $r->child('web');
$assets = asset_directory($web);
$out    = path( $a->{'output'} );
$out->mkpath;
$html = replace_text(
    replace_re( '<link[^>]*>|<script[^>]*src=[^>]*></script>', '', $web->child('index.html')->slurp_utf8 ),
    '</head>',
    (
        ( ( '<style>' . $assets->child('theme.css')->slurp_utf8 ) . $assets->child('style.css')->slurp_utf8 )
        . '</style></head>'
    )
);
$js = replace_text( $assets->child('game.js')->slurp_utf8, '(() => {', '((location,history) => {', 1 );
$i  = rindex( $js, '})()' );
$js =
  ( ( substr( $js, 0, $i - 0 ) . '})(window.__location,window.__history);' ) . substr( $js, ( $i + 4 ) ) );
$checks   = [];
$errors   = [];
$contexts = [];

sub check {
    my ( $ok, $label ) = @_;
    assert_ok( $ok, $label );
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}

sub wait {
    my ( $p, $s, $kwargs ) = @_;
    $kwargs //= {};
    return wait_js( $p, $s, undef, { polling => 30 } );
}

sub load {
    my ( $b, $size, $live, $code, $name ) = @_;
    my ( $c, $f, $h, $mobile, $p, $q, $w );
    $size //= [ 1365, 950 ];
    $live //= JSON::PP::false;
    $code //= undef;
    $name //= 'ALPHA';
    my $tuple_15_1 = $size;
    $w      = $tuple_15_1->[0];
    $h      = $tuple_15_1->[1];
    $mobile = (
        do {
            my $boolean_value = ( ( $w < 760 ) );
            truth_value($boolean_value) ? $boolean_value : ( ( $h < 620 ) );
        }
    );
    $c = $b->newContext(
        {
            viewport          => { 'width' => $w, 'height' => $h },
            hasTouch          => $mobile,
            isMobile          => $mobile,
            deviceScaleFactor => ( truth_value($mobile) ? 2 : 1 ),
            colorScheme       => 'dark'
        }
    );
    push( @{$contexts}, $c );
    $p = $c->newPage();
    $p->setDefaultTimeout(9000);
    capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
    $p->setContent($html);
    $q = { 'test' => '1' };

    if ( truth_value($code) ) {
        $q->{'room'} = $code;
    }
    evaluate_js(
        $p,
'a=>{window.__location=new URL(a.url);window.__history={state:null,replaceState(s,t,u){this.state=s;window.__updatedURL=String(u)}};const d={\'leqra.name\':a.name,\'leqra.muted\':\'1\'};Object.defineProperty(window,\'localStorage\',{value:{getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]}});Object.defineProperty(window,\'sessionStorage\',{value:{getItem:()=>null,setItem(){},removeItem(){}}});if(!a.live)window.requestAnimationFrame=()=>0;}',
        {
            'url'  => ( ( $a->{'url'} . '/?' ) . query_string($q) ),
            'live' => $live,
            'name' => $name
        }
    );
    for $f ( @{ [ 'theme.js', 'netcode.js' ] } ) {
        $p->addScriptTag( { content => $assets->child($f)->slurp_utf8 } );
    }
    $p->addScriptTag( { content => $js } );
    main::wait( $p, 'window.__test&&leqra.version==="4.5.0"' );
    evaluate_js( $p, '__test.render()' );
    return $p;
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
eval {
    $p = main::load($b);
    main::check(
        (
            do {
                my $boolean_value = ( value_eq( evaluate_js( $p, 'leqraTheme.resolved' ), 'dark' ) );
                truth_value($boolean_value)
                  ? ( value_eq( evaluate_js( $p, 'leqraTheme.palette.accent' ), '#00c8ff' ) )
                  : $boolean_value;
            }
        ),
        'dark-only neon-blue theme'
    );
    main::check( ( !( contains_value( $p->locator('#controlsDialog')->innerText(), 'APPEARANCE' ) ) ),
        'appearance/light-mode controls removed' );
    main::check( ( value_eq( $p->locator('[data-tank-color]')->count(), 4 ) ),
        'FFA host can paint own tank and local bots' );
    $p->locator('[data-kick-target="3"]')->first()->click();
    main::check( ( !truth_value( $p->locator('#kickDialog')->getAttribute('open') ) ),
        'bot removal has no confirmation dialog' );
    $p->locator('#addLocalBtn')->click();
    main::wait( $p, '__test.localRoom.players.some(p=>p.kind==="local")' );
    $p->locator('#roomP2Callsign')->fill('BRAVO');
    $p->locator('#roomP2CallsignForm button')->click();
    main::wait( $p, '__test.localRoom.players.find(p=>p.kind==="local").name==="BRAVO"' );
    $p2     = evaluate_js( $p, '__test.localRoom.players.find(p=>p.kind==="local").id' );
    $labels = evaluate_js(
        $p,
'ids=>{const c=document.getElementById(\'arena\').getContext(\'2d\'),old=c.fillText,seen=[];c.fillText=function(s,...a){seen.push(String(s));return old.call(this,s,...a)};try{for(const id of ids)__test.drawTank(__test.tanks.find(t=>t.id===id));}finally{c.fillText=old}return seen;}',
        [ 0, $p2 ]
    );
    main::check(
        (
            do {
                my $boolean_value = ( contains_value( $labels, 'ALPHA' ) );
                truth_value($boolean_value)
                  ? ( contains_value( $labels, 'BRAVO' ) )
                  : $boolean_value;
            }
        ),
        'both local tank labels use callsigns'
    );
    main::check(
        (
            !truth_value(
                scalar(
                    grep {
                        my $x = $_;
                        (
                            do {
                                my $boolean_value =
                                  ( contains_value( [ 'P1', 'P2' ], $x ) );
                                truth_value($boolean_value)
                                  ? $boolean_value
                                  : ( contains_value( $x, ', T' ) );
                            }
                        )
                    } @{$labels}
                )
            )
        ),
        'tank labels contain no P1/P2 or team suffix'
    );
    $speed = evaluate_js( $p,
'()=>{const t=__test.tanks[0];t.speedTime=0;t.speedStacks=0;for(let i=0;i<6;i++)__test.grantPower(t,\'speed\');__test.updateHUD(true);return{stacks:t.speedStacks,time:t.speedTime,buff:document.querySelector(\'#buffLabel\').textContent}}'
    );
    main::check(
        (
            do {
                my $boolean_value = ( value_eq( $speed->{'stacks'}, 5 ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value = ( value_eq( $speed->{'time'}, 6 ) );
                    truth_value($boolean_value)
                      ? ( contains_value( $speed->{'buff'}, 'SPD×5' ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
            }
        ),
        'Super Speed stacks to five and refreshes one timer'
    );
    $p->locator('[data-tank-color="0"]')->selectOption('7');
    main::check(
        ( value_eq( evaluate_js( $p, '__test.localRoom.players.find(p=>p.id===0).colorIndex' ), 7 ) ),
        'FFA tank paint can be customized' );
    $p->locator('#roomTeamMode')->selectOption('teams');
    wait_js( $p, '(value)=>leqra.getState().rules.teamMode===value', 'teams', {} );
    $p->locator('#roomRulesBtn')->click();
    $p->locator('#rule-teamColor1')->selectOption('4');
    $p->locator('#rule-teamColor2')->selectOption('6');
    $p->locator('#applyRulesBtn')->click();
    main::check(
        ( value_eq( $p->locator('[data-tank-color]')->count(), 0 ) ),
        'individual tank color controls disappear in Teams'
    );
    $state = evaluate_js( $p,
'()=>({rules:__test.currentRules(),players:__test.localRoom.players.map(p=>({id:p.id,team:p.team,colorIndex:p.colorIndex,color:__test.localRoom.players.find(x=>x.id===p.id)&&document.querySelector(`[data-seat="${p.id}"]`)?.style.getPropertyValue(\'--player\')}))})'
    );
    main::check(
        !scalar(
            grep {
                my $x = $_;
                !( ( !defined( ( $x->{'colorIndex'} // undef ) ) ) )
            } @{ $state->{'players'} }
        ),
        'switching to Teams clears hidden FFA paint overrides'
    );
    evaluate_js( $p, '__test.resetPreview()' );
    $teamcheck = evaluate_js( $p,
'()=>__test.tanks.every(t=>t.color===__test.localRoom.players.find(p=>p.id===t.id)?.color || t.color===([\'#d2f65a\',\'#ff9679\',\'#73cee4\',\'#c5a2ff\',\'#ffc46b\',\'#ff83bd\',\'#75f0cb\',\'#b7c6ee\'][__test.currentRules().teamColors[t.team-1]]))'
    );
    main::check( $teamcheck, 'team tank colors are authoritative' );
    $p->screenshot( { path => format_value( $out->child('teams-dark.png') ) } );
    $p->close();
    $code = ( 'v45-' . format_value( int( ( time() * 1000 ) ) ) );
    $host = main::load( $b, undef, JSON::PP::true, $code, 'HOST' );
    main::wait( $host, '__test.online.connected&&__test.online.roomData?.host===__test.online.id' );
    $guest = main::load( $b, [ 390, 844 ], JSON::PP::true, $code, 'GUEST' );
    main::wait( $guest, '__test.online.connected&&!__test.online.spectating' );
    $gid = evaluate_js( $guest, '__test.online.id' );
    $hid = evaluate_js( $host,  '__test.online.id' );
    main::wait( $host, ( '__test.online.roomData.players.some(p=>p.id===' . $gid . ')' ) );
    main::check( ( value_eq( $host->locator( ( '[data-tank-color="' . $gid . '"]' ) )->count(), 0 ) ),
        'host cannot repaint a remote online human in FFA' );
    main::check( ( value_eq( $guest->locator( ( '[data-tank-color="' . $gid . '"]' ) )->count(), 1 ) ),
        'online FFA player can edit own tank color' );
    $guest->locator( ( '[data-tank-color="' . $gid . '"]' ) )->selectOption('6');
    main::wait( $host, ( '__test.online.roomData.players.find(p=>p.id===' . $gid . ').colorIndex===6' ) );
    main::check(
        (
            value_eq(
                evaluate_js( $host, ( '__test.online.roomData.players.find(p=>p.id===' . $gid . ').color' ) ),
                '#75f0cb'
            )
        ),
        'self-selected FFA color replicates to room'
    );
    $host->locator('#roomTeamMode')->selectOption('teams');
    wait_js( $host, '(value)=>leqra.getState().rules.teamMode===value', 'teams', {} );
    $host->locator('#roomRulesBtn')->click();
    $host->locator('#rule-teamColor1')->selectOption('0');
    $host->locator('#rule-teamColor2')->selectOption('1');
    $host->locator('#applyRulesBtn')->click();
    main::wait( $guest, '__test.online.roomData.rules.teamMode==="teams"' );
    main::wait( $host,  'document.querySelectorAll(\'[data-tank-color]\').length===0' );
    main::wait( $guest, 'document.querySelectorAll(\'[data-tank-color]\').length===0' );
    main::check( JSON::PP::true, 'Teams lock individual paint for host and guest' );
    main::check(
        evaluate_js(
            $guest, ( '__test.online.roomData.players.find(p=>p.id===' . $gid . ').colorIndex==null' )
        ),
        'server clears former FFA paint when Teams begins'
    );
    main::check(
        (
            value_eq(
                evaluate_js(
                    $guest, ( '__test.online.roomData.players.find(p=>p.id===' . $gid . ').color' )
                ),
                '#ff9679'
            )
        ),
        'remote team tank matches host-selected Team 2 color'
    );
    $guest->screenshot( { path => format_value( $out->child('online-teams-390x844.png') ) } );
    main::check( ( !truth_value($errors) ), ( 'no uncaught browser errors: ' . format_value($errors) ) );
    1;
};
my $caught_error = $@;
for $c ( @{$contexts} ) {
    eval {
        $c->close();
        1;
    };
    if ($@) {
    }
}
$b->close();
die $caught_error if $caught_error;
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version' => '4.5.0',
            'passed'  => scalar( @{$checks} ),
            'checks'  => $checks,
            'errors'  => $errors
        },
        1
    )
);
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
