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

my ( $a, $ap, $assets, $b, $c, $checks, $errors, $f, $html, $i, $js, $migrated, $out, $p, $pw, $r, $web );

# v4.16 focused lowercase leqra rebrand and storage-migration checks.
$ap = {};
$a  = do {
    my %args = ( 'output' => 'tests/results/v4.16-branding' );
    my $help;
    GetOptions( 'output=s' => \$args{'output'}, 'help|h' => \$help )
      or die 'Usage: perl branding416_browser.pl --output
';
    if ($help) {
        print 'Usage: perl branding416_browser.pl --output
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
$checks = [];
$errors = [];

sub check {
    my ( $ok, $label ) = @_;
    assert_ok( $ok, $label );
    push( @{$checks}, $label );
    print( join( " ", 'PASS', $label ), "\n" );
}
$pw = start_playwright();
my $playwright = $pw;
$b = $pw->launch(
    type           => 'chrome',
    headless       => JSON::PP::true,
    executablePath => '/usr/bin/chromium'
);
$c = $b->newContext( { viewport => { 'width' => 1365, 'height' => 950 }, colorScheme => 'dark' } );
$p = $c->newPage();
capture_event( $p, 'pageerror', $errors, '(e) => String(e)' );
$p->setContent($html);
evaluate_js( $p,
'()=>{window.__location=new URL(\'http://127.0.0.1/?test=1\');window.__history={state:null,replaceState(){}};window.__store={\'ricochet.name\':\'LEGACY PILOT\',\'ricochet.muted\':\'1\',\'ricochet.difficulty\':\'hard\',\'ricochet.local2Name\':\'LEGACY P2\',\'leqra.wins\':\'7\'};window.__session={\'ricochet.session\':\'{"code":"OLD","token":"tok","name":"LEGACY PILOT","spectating":false,"at":1}\'};const store=d=>({getItem:k=>d[k]??null,setItem:(k,v)=>d[k]=String(v),removeItem:k=>delete d[k]});Object.defineProperty(window,\'localStorage\',{value:store(window.__store)});Object.defineProperty(window,\'sessionStorage\',{value:store(window.__session)});window.requestAnimationFrame=()=>0;}'
);

for $f ( @{ [ 'theme.js', 'netcode.js' ] } ) {
    $p->addScriptTag( { content => $assets->child($f)->slurp_utf8 } );
}
$p->addScriptTag( { content => $js } );
wait_js( $p, 'window.__test&&window.leqra&&leqra.version===\'4.16.0\'' );
main::check( ( value_eq( $p->title(), 'leqra' ) ), 'document title uses lowercase leqra' );
main::check( ( value_eq( $p->locator('.brand-name')->innerText(), 'leqra' ) ),
    'header wordmark is exactly lowercase leqra' );
main::check(
    (
        contains_value(
            $p->locator('meta[name="description"]')->getAttribute('content'),
            'leqra — a mobile-friendly tank maze game'
        )
    ),
    'meta description uses leqra'
);
main::check( ( contains_value( lc( $p->locator('#lobbyScreen h2')->innerText() ), 'leqra.' ) ),
    'landing hero uses leqra' );
main::check( evaluate_js( $p, 'typeof leqra===\'object\'&&leqra.version===\'4.16.0\'' ),
    'canonical public browser API is leqra v4.16.0' );
main::check( evaluate_js( $p, 'typeof leqraNet===\'object\'&&typeof leqraTheme===\'object\'' ),
    'browser helper globals use leqra names' );
main::check(
    evaluate_js(
        $p,
'typeof window.Ricochet===\'undefined\'&&typeof window.RicochetNet===\'undefined\'&&typeof window.RicochetTheme===\'undefined\''
    ),
    'old product-named browser globals are not exposed'
);
$migrated = evaluate_js( $p,
'()=>({name:__store[\'leqra.name\'],muted:__store[\'leqra.muted\'],difficulty:__store[\'leqra.difficulty\'],p2:__store[\'leqra.local2Name\'],wins:__store[\'leqra.wins\'],session:__session[\'leqra.session\']})'
);
main::check(
    (
        do {
            my $boolean_value =
              ( value_eq( $migrated->{'name'}, 'LEGACY PILOT' ) );
            truth_value($boolean_value)
              ? do {
                my $boolean_value = ( value_eq( $migrated->{'muted'}, '1' ) );
                truth_value($boolean_value)
                  ? do {
                    my $boolean_value =
                      ( value_eq( $migrated->{'difficulty'}, 'hard' ) );
                    truth_value($boolean_value)
                      ? ( value_eq( $migrated->{'p2'}, 'LEGACY P2' ) )
                      : $boolean_value;
                  }
                  : $boolean_value;
              }
              : $boolean_value;
        }
    ),
    'legacy local settings migrate into leqra namespace'
);
main::check( ( value_eq( $migrated->{'wins'}, '7' ) ), 'existing leqra setting wins over any legacy value' );
main::check(
    ( value_eq( decode_json( $migrated->{'session'} )->{'code'}, 'OLD' ) ),
    'legacy reconnect session migrates into leqra namespace'
);
main::check( ( value_eq( trim_text( $p->locator('.game-version')->innerText(), 'strip' ), 'leqra v4.16.0' ) ),
    'Controls version footer uses lowercase leqra' );
main::check( ( !truth_value($errors) ), ( 'no uncaught browser errors: ' . format_value($errors) ) );
$p->screenshot( { path => format_value( $out->child('leqra-v416-branding.png') ) } );
$c->close();
$b->close();
$out->child('results.json')->spew_utf8(
    json_text(
        {
            'version'  => '4.16.0',
            'passed'   => scalar( @{$checks} ),
            'checks'   => $checks,
            'errors'   => $errors,
            'migrated' => $migrated
        },
        1
    )
);
print( join( " ", 'TOTAL', scalar( @{$checks} ) ), "\n" );
