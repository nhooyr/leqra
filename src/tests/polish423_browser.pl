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

my (
    $after,   $args,     $assets, $before,  $browser, $checks, $context, $errors,
    $html,    $i,        $js,     $out,     $page,    $parser, $pw,      $report,
    $request, $response, $root,   $sockets, $state,   $teams,  $web
);

# v4.23 PWA/offline-networking, room UX and shutdown client regressions.
#
# Run the opt-in Go fixture in another terminal first, for example:
#   LEQRA_BROWSER_FIXTURE=1 LEQRA_BROWSER_ADDR=127.0.0.1:18790     go test -run '^TestBrowserFixture$' -timeout 30m
# Then run this script. The browser stays on about:blank and injects the exact shipped
# assets because this build environment may block navigation to loopback URLs; gameplay
# WebSockets still use the real loopback Go fixture.
$parser = {};
$args   = do {
    my %args = (
        'server' => 'http://127.0.0.1:18790',
        'output' => 'tests/results/v4.23-polish'
    );
    my $help;
    GetOptions(
        'server=s' => \$args{'server'},
        'output=s' => \$args{'output'},
        'help|h'   => \$help
      )
      or die 'Usage: perl polish423_browser.pl --server --output
';
    if ($help) {
        print 'Usage: perl polish423_browser.pl --server --output
';
        exit 0;
    }
    \%args;
};
$root   = path($0)->absolute->parent(2);
$web    = $root->child('web');
$assets = asset_directory($web);
$out    = (
    truth_value( ( !truth_value( path( $args->{'output'} )->is_absolute ) ) )
    ? $root->child( $args->{'output'} )
    : path( $args->{'output'} )
);
$out->mkpath;
$html = replace_re( '<link[^>]*>',                            '', $web->child('index.html')->slurp_utf8 );
$html = replace_re( '<script[^>]*src="[^"]+"[^>]*></script>', '', $html );
$html = replace_text(
    $html,
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
my $tuple_34_0 = [ [], [] ];
$checks = $tuple_34_0->[0];
$errors = $tuple_34_0->[1];

sub check {
    my ( $ok, $label ) = @_;
    assert_ok( $ok, $label );
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}
$pw = start_playwright();
my $playwright = $pw;
$browser = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
$context =
  $browser->newContext( { viewport => { 'width' => 1200, 'height' => 900 } } );
$page    = $context->newPage();
$sockets = [];
capture_event( $page, 'pageerror', $errors,  '(exc) => String(exc)' );
capture_event( $page, 'websocket', $sockets, '(ws) => ws.url' );
$page->on( 'dialog', 'arguments[0].accept();' );
$page->setContent($html);
evaluate_js(
    $page, 'server => {
      window.__location = new URL(server + \'/?test=1\');
      window.__history = {state:null, replaceState(state,title,url){this.state=state;window.__updatedURL=String(url)}};
      const data={\'leqra.muted\':\'1\'};
      const store=obj=>({getItem:k=>Object.hasOwn(obj,k)?obj[k]:null,setItem:(k,v)=>obj[k]=String(v),removeItem:k=>delete obj[k]});
      Object.defineProperty(window,\'localStorage\',{value:store(data)});
      Object.defineProperty(window,\'sessionStorage\',{value:store({})});
    }', $args->{'server'}
);
$page->addScriptTag( { content => $assets->child('theme.js')->slurp_utf8 } );
$page->addScriptTag( { content => $assets->child('netcode.js')->slurp_utf8 } );
$page->addScriptTag( { content => $js } );
wait_js( $page, 'window.__test && leqra.version === \'4.35.0\'' );
$Leqra::Browser::HANDLE->await( $page->waitForTimeout(100) );
main::check( ( value_eq( scalar( @{$sockets} ), 0 ) ),    'Local startup opens no WebSocket' );
main::check( $page->locator('#leaveRoomBtn')->isHidden(), 'Local room has no New local room action' );
evaluate_js(
    $page, '() => {
      window.__NativeWebSocket423 = window.WebSocket;
      class StaleSocket {
        static OPEN = 1;
        constructor(){
          this.readyState=0;this.bufferedAmount=0;
          setTimeout(()=>{this.readyState=1;this.onopen?.();this.onmessage?.({data:JSON.stringify({type:\'server_hello\',version:\'4.22.0\',protocol:1})});},0);
        }
        send(){}
        close(){this.readyState=3;setTimeout(()=>this.onclose?.(),0)}
      }
      window.WebSocket=StaleSocket;
      __test.shareLocalRoom();
    }'
);
wait_js( $page,
'leqra.getState().mode === \'room\' && document.querySelector(\'#roomStatus\').textContent.includes(\'Reload the page\')'
);
main::check( ( contains_value( $page->locator('#roomStatus')->innerText(), 'Reload the page' ) ),
    'Version mismatch asks the player to reload before online play' );
main::check( evaluate_js( $page, '!__test.online.connected && __test.online.code === \'\'' ),
    'Version mismatch aborts online room setup' );
evaluate_js( $page, 'window.WebSocket=window.__NativeWebSocket423;delete window.__NativeWebSocket423' );
$teams = evaluate_js(
    $page, '() => {
      __test.createLocalRoom();
      __test.setLocalRules({...__test.currentRules(),teamMode:\'ffa\'});
      __test.setLocalRules({...__test.currentRules(),teamMode:\'teams\'});
      return leqra.getState().room.players.map(p=>p.team);
    }'
);
main::check( ( value_eq( $teams, [ 1, 2, 3, 4 ] ) ),
    'Teams activation distributes four tanks across all four teams' );
evaluate_js( $page,
    '__test.setLocalRules({...__test.currentRules(),teamMode:\'ffa\'});__test.shareLocalRoom()' );
wait_js( $page, 'leqra.getState().online?.connected === true', undef, { timeout => 10000 } );
wait_js( $page, 'leqra.getState().phase === \'onlineLobby\'',  undef, { timeout => 10000 } );
main::check( ( value_eq( scalar( @{$sockets} ), 1 ) ),
    'Explicit Share Room Online opens exactly one WebSocket' );
main::check( ( value_eq( evaluate_js( $page, '__test.online.serverVersion' ), '4.35.0' ) ),
    'Online connection completes the v4.23 version handshake' );
$before = evaluate_js( $page, 'JSON.stringify(__test.walls)' );
evaluate_js( $page, '__test.unshareOnlineRoom()' );
wait_js( $page, 'leqra.getState().mode === \'room\'', undef, { timeout => 10000 } );
$after = evaluate_js( $page, 'JSON.stringify(__test.walls)' );
main::check( ( value_eq( $before, $after ) ), 'Unsharing preserves the displayed maze' );
evaluate_js( $page, '__test.shareLocalRoom()' );
wait_js( $page, 'leqra.getState().online?.connected === true', undef, { timeout => 10000 } );
wait_js( $page, 'leqra.getState().phase === \'onlineLobby\'',  undef, { timeout => 10000 } );
$page->locator('#startRoomBtn')->click();
wait_js( $page, 'leqra.getState().phase === \'playing\'', undef, { timeout => 10000 } );
evaluate_js( $page, '__test.openChat()' );
main::check( evaluate_js( $page, '__test.roomChat.open && __test.chatHasFocus()' ),
    'Focused chat suppresses gameplay controls' );
$page->locator('#arena')->focus();
$page->keyboard()->down('w');
$Leqra::Browser::HANDLE->await( $page->waitForTimeout(60) );
$state = evaluate_js( $page,
    '({open:__test.roomChat.open,focus:__test.chatHasFocus(),forward:__test.onlineControls().forward})' );
main::check(
    (
        do {
            my $boolean_value = $state->{'open'};
            truth_value($boolean_value)
              ? do {
                my $boolean_value = ( !truth_value( $state->{'focus'} ) );
                truth_value($boolean_value)
                  ? $state->{'forward'}
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'Visible but unfocused chat allows maze input'
);
$page->locator('#chatInput')->focus();
main::check( ( !truth_value( evaluate_js( $page, '__test.onlineControls().forward' ) ) ),
    'Refocusing chat suppresses maze input again' );
$page->keyboard()->up('w');
evaluate_js( $page, '__test.closeChat()' );
$page->locator('#roomBtn')->click();
wait_js( $page, '!document.querySelector(\'#onlineMenuScreen\').hidden' );
main::check(
    (
        do {
            my $boolean_value = $page->locator('#leaveMatchBtn')->isVisible();
            truth_value($boolean_value)
              ? (
                value_eq(
                    trim_text( $page->locator('#leaveMatchBtn')->innerText(), 'strip' ), 'Leave match'
                )
              )
              : $boolean_value;
        }
    ),
    'Online pause menu includes Leave match'
);
evaluate_js( $page, 'window.confirm=()=>true' );
$page->locator('#leaveMatchBtn')->click();
wait_js( $page, 'leqra.getState().mode === \'room\'', undef, { timeout => 10000 } );
main::check( $page->locator('#leaveMatchBtn')->isHidden(),
    'Leave match is reset hidden after switching from online to local play' );
evaluate_js( $page, '__test.showVictory(-1, [])' );
main::check(
    (
        value_eq(
            evaluate_js( $page->locator('#victoryAgainBtn'), 'e=>getComputedStyle(e).backgroundColor' ),
            'rgb(57, 255, 136)'
        )
    ),
    'Local PLAY AGAIN uses the same neon green treatment as REMATCH'
);
evaluate_js( $page, '__test.closeVictory()' );
evaluate_js( $page, '__test.shareLocalRoom()' );
wait_js( $page, 'leqra.getState().online?.connected === true', undef, { timeout => 10000 } );
$request  = HTTP::Request->new( 'POST', ( $args->{'server'} . '/_fixture/shutdown423' ), [], '' );
$response = request_ok($request);
main::check( ( value_eq( $response->code, 204 ) ), 'Shutdown fixture queued the server notice' );
wait_js( $page, 'leqra.getState().mode === \'room\'', undef, { timeout => 10000 } );
main::check(
    ( contains_value( lc( $page->locator('#roomStatus')->innerText() ), 'shutting down' ) ),
    'Server shutdown returns the online client Home with a visible notice'
);
main::check(
    (
        do {
            my $boolean_value = $page->locator('#shutdownDialog')->isVisible();
            truth_value($boolean_value)
              ? ( contains_value( $page->locator('#shutdownDialog')->innerText(), 'SERVER SHUTTING DOWN' ) )
              : $boolean_value;
        }
    ),
    'Server shutdown opens a pronounced blocking notice'
);
main::check( ( !truth_value($errors) ), ( 'No uncaught browser errors: ' . format_value($errors) ) );
$page->screenshot( { path => format_value( $out->child('v4.23-ui.png') ) } );
$context->close();
$browser->close();
$report = {
    'version' => '4.35.0',
    'passed'  => scalar( @{$checks} ),
    'checks'  => $checks,
    'errors'  => $errors
};
$out->child('results.json')->spew_utf8( json_text( $report, 1 ) );
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
