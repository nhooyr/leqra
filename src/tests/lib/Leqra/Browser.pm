package Leqra::Browser;
use v5.34;
use strict;
use warnings;
use utf8;
use Encode ();
use Exporter 'import';
use Carp         qw(confess);
use JSON::PP     qw(encode_json decode_json);
use Path::Tiny   qw(path);
use File::Temp   qw(tempfile);
use Scalar::Util qw(blessed looks_like_number);
use List::Util   qw(min max sum);
use Getopt::Long qw(GetOptions);
use URI;
use URI::file;
use URI::Escape qw(uri_escape_utf8);
use Time::HiRes qw(time sleep);

BEGIN {
    require File::Basename;
    require File::Spec;
    my $root = File::Spec->rel2abs( File::Spec->catdir( File::Basename::dirname(__FILE__), '../../../..' ) );
    $ENV{NODE_PATH} =
      File::Spec->catdir( $root, 'node_modules' ) . ( $ENV{NODE_PATH} ? ":$ENV{NODE_PATH}" : '' );
}
use Playwright;
use HTTP::Request;
use LWP::UserAgent;
our @EXPORT =
  qw(truth_value fixture_response array_index remove_item extract_archive_member inspect_elements contains_value transpose_columns browser_devices wait_event_log open_archive tally_values unique_values sorted_values most_common median query_pairs url_parts request_ok query_values path encode_json decode_json min max sum time sleep GetOptions uri_escape_utf8 asset_directory start_playwright evaluate_js wait_js assert_ok expect_locator capture_event capture_socket_event value_eq json_text format_value array_slice replace_text replace_re match_re regex trim_text remove_suffix mean stddev query_string random_bytes);
our $HANDLE;

sub asset_directory {
    my ($web)      = @_;
    my ($relative) = $web->child('index.html')->slurp_utf8 =~ /\bsrc="(assets\/v[^\/"]+)\/game\.js"/;
    return defined($relative) ? $web->child($relative) : $web;
}
our $HTTP = LWP::UserAgent->new( timeout => 10 );

sub request_ok {
    my ($request) = @_;
    my $response =
      ref($request) ? $HTTP->request($request) : $HTTP->get($request);
    die $response->status_line unless $response->is_success;
    return $response;
}

sub query_values {
    my ($query) = @_;
    my $uri     = URI->new( "?" . ( $query // "" ) );
    my $pairs   = $uri->query_form_hash;
    return {
        map { $_ => ref( $pairs->{$_} ) ? $pairs->{$_} : [ $pairs->{$_} ] }
          keys %$pairs
    };
}

sub open_archive {
    my ($filename) = @_;
    require Archive::Zip;
    my $zip = Archive::Zip->new;
    $zip->read("$filename") == Archive::Zip::AZ_OK()
      or die "Cannot read archive $filename\n";
    return $zip;
}

sub unique_values {
    my ($items) = @_;
    my %seen;
    return [ sort grep { !$seen{ format_value($_) }++ } @$items ];
}

sub tally_values {
    my ($items) = @_;
    my %counts;
    ++$counts{$_} for @$items;
    return \%counts;
}

sub sorted_values {
    my ($items) = @_;
    return [ sort { looks_like_number($a) && looks_like_number($b) ? $a <=> $b : $a cmp $b } @$items ];
}

sub most_common {
    my ( $counts, $limit ) = @_;
    my @pairs = map { [ $_, $counts->{$_} ] }
      sort { $counts->{$b} <=> $counts->{$a} || $a cmp $b } keys %$counts;
    splice( @pairs, $limit ) if defined($limit) && @pairs > $limit;
    return \@pairs;
}

sub median {
    my ($values) = @_;
    my $sorted   = sorted_values($values);
    my $n        = @$sorted;
    return $n % 2
      ? $sorted->[ int( $n / 2 ) ]
      : ( $sorted->[ $n / 2 - 1 ] + $sorted->[ $n / 2 ] ) / 2;
}

sub query_pairs {
    my ($query) = @_;
    my $uri     = URI->new( '?' . ( $query // '' ) );
    my @form    = $uri->query_form;
    my @pairs;
    push @pairs, [ splice( @form, 0, 2 ) ] while @form;
    return \@pairs;
}

sub url_parts {
    my ($parts) = @_;
    my ( $scheme, $authority, $path, $query, $fragment ) = @$parts;
    my $uri = URI->new("$scheme://$authority$path");
    $uri->query($query);
    $uri->fragment($fragment);
    return "$uri";
}

sub browser_devices {
    state $devices;
    unless ($devices) {
        open my $pipe, '-|', 'node', '-e',
          'process.stdout.write(JSON.stringify(require("playwright").devices))'
          or die $!;
        local $/;
        $devices = decode_json(<$pipe>);
        close $pipe or die 'Cannot load Playwright devices';
    }
    return $devices;
}

sub wait_event_log {
    my ( $events, $predicate, $timeout ) = @_;
    my $deadline = time() + ( $timeout // 30000 ) / 1000;
    my $index    = 0;
    while ( time() < $deadline ) {
        while ( $index < @$events ) {
            my $value = $events->[ $index++ ];
            return $value if $predicate->($value);
        }
        sleep(0.01);
    }
    die "Timed out waiting for browser event\n";
}

sub contains_value {
    my ( $items, $value ) = @_;
    return exists $items->{$value} if ref($items) eq 'HASH';
    return scalar( grep { value_eq( $_, $value ) } @$items )
      if ref($items) eq 'ARRAY';
    return defined($items) && index( $items, $value ) >= 0;
}

sub transpose_columns {
    my ($rows) = @_;
    return [] unless @$rows;
    my $n = min( map { scalar @$_ } @$rows );
    return [
        map {
            my $i = $_;
            [ map { $_->[$i] } @$rows ]
        } 0 .. $n - 1
    ];
}

sub array_index {
    my ( $items, $value ) = @_;
    for my $i ( 0 .. $#$items ) {
        return $i if value_eq( $items->[$i], $value );
    }
    die "Value absent from list\n";
}

sub remove_item {
    my ( $items, $value ) = @_;
    for my $i ( 0 .. $#$items ) {
        if ( $items->[$i] eq $value ) { splice( @$items, $i, 1 ); return; }
    }
    die "Value absent from list\n";
}

sub extract_archive_member {
    my ( $archive, $name, $target ) = @_;
    my $file = path($target)->child($name);
    $file->parent->mkpath;
    $archive->extractMember( $name, "$file" ) == Archive::Zip::AZ_OK()
      or die "Cannot extract $name\n";
}

sub fixture_response {
    my ( $context, $base, $relative, $body, $content_type ) = @_;
    my $url = URI->new_abs( $relative, $base )->as_string;
    my ( $fh, $filename ) = tempfile(
        'leqra-response-XXXXXX',
        SUFFIX => '.har',
        TMPDIR => 1,
        UNLINK => 1
    );
    state @files;
    push @files, $fh;
    my $content = ref($body) ? json_text($body) : $body;
    my $har     = {
        log => {
            version => '1.2',
            creator => { name => 'leqra tests', version => '1' },
            entries => [
                {
                    startedDateTime => '2024-01-01T00:00:00Z',
                    time            => 0,
                    request         => {
                        method      => 'GET',
                        url         => $url,
                        httpVersion => 'HTTP/1.1',
                        headers     => [],
                        queryString => [],
                        cookies     => [],
                        headersSize => -1,
                        bodySize    => 0
                    },
                    response => {
                        status      => 200,
                        statusText  => 'OK',
                        httpVersion => 'HTTP/1.1',
                        cookies     => [],
                        headers     => [ { name => 'Content-Type', value => $content_type } ],
                        content     => {
                            size     => length( Encode::encode_utf8($content) ),
                            mimeType => $content_type,
                            text     => $content
                        },
                        redirectURL => '',
                        headersSize => -1,
                        bodySize    => length( Encode::encode_utf8($content) )
                    },
                    cache   => {},
                    timings => { send => 0, wait => 0, receive => 0 }
                }
            ]
        }
    };
    print {$fh} Encode::encode_utf8( json_text($har) );
    $fh->flush;
    $context->routeFromHAR( $filename, { url => $url, notFound => 'fallback' } );
}

sub start_playwright {
    local $ENV{MAX_REQUEST_SIZE} = '50mb';
    return $HANDLE = Playwright->new( maxrequest => '50mb' );
}

sub evaluate_js {
    my ( $object, $script, @args ) = @_;
    my $value =
      $script =~ /;/ && $script !~ /=>|^\s*function/
      ? '(() => {' . $script . '})()'
      : '(' . $script . ')';
    my $result = $object->evaluate(
        'const value = '
          . $value
          . '; return Promise.resolve(typeof value === "function" ? value(...arguments) : value).then(value => ({value}));',
        @args
    );
    return $result->{value};
}

sub inspect_elements {
    my ( $parent, $selector, $script, $arg ) = @_;
    my $options = { selector => $selector };
    $options->{arg} = $arg if defined $arg;
    my $inspect =
q{const visible = selector.includes(":visible"); selector = selector.replaceAll(":visible", ""); const elements=[...root.querySelectorAll(selector)].filter(el=>!visible||(getComputedStyle(el).visibility !== "hidden" && (()=>{const r=el.getBoundingClientRect(); return r.width>0&&r.height>0;})())); return }
      . '('
      . $script
      . ')(elements,arg);';
    if (   $parent->isa('Playwright::Locator')
        || $parent->isa('Playwright::ElementHandle') )
    {
        return evaluate_js( $parent, '(root,{selector,arg})=>{' . $inspect . '}', $options );
    }
    return evaluate_js( $parent, '({selector,arg})=>{const root=document;' . $inspect . '}', $options );
}

sub wait_js {
    my ( $page, $script, $arg, $options ) = @_;
    $options //= {};
    my $timeout  = $options->{timeout} // 30000;
    my $deadline = time() + $timeout / 1000;
    my $interval = defined( $options->{polling} )
      && $options->{polling} =~ /^\d/ ? $options->{polling} / 1000 : 0.01;
    while (1) {
        my ( $value, $error );
        eval {
            $value =
              evaluate_js( $page, $script, ( defined($arg) ? ($arg) : () ) );
            1;
        } or $error = $@;
        die $error
          if $error
          && $error !~ /Execution context was destroyed|Cannot find context/;
        return $value if $value;
        die "Timed out waiting for JavaScript condition: $script\n"
          if $timeout && time() >= $deadline;
        sleep($interval);
    }
}

sub json_text {
    my ( $value, $pretty ) = @_;
    return JSON::PP->new->canonical->allow_nonref->pretty( $pretty // 0 )->encode($value);
}

sub format_value {
    my ($value) = @_;
    return
        defined($value)
      ? blessed($value) && !JSON::PP::is_bool($value)
          ? "$value"
          : ref($value) ? json_text($value)
          : "$value"
      : q{};
}

sub value_eq {
    my ( $left, $right ) = @_;
    return !defined($right) unless defined $left;
    return 0                unless defined $right;
    return json_text($left) eq json_text($right) if ref($left) || ref($right);
    return "$left" eq "$right";
}

sub truth_value {
    my ($value) = @_;
    return 0 unless defined $value;
    return scalar(@$value)        if ref($value) eq 'ARRAY';
    return scalar( keys %$value ) if ref($value) eq 'HASH';
    return !!$value;
}

sub assert_ok {
    my ( $ok, $label ) = @_;
    confess 'Assertion failed: ' . format_value($label) . "\n"
      unless truth_value($ok);
    return 1;
}

sub array_slice {
    my ( $items, $from, $to ) = @_;
    my $n = @$items;
    $from += $n if $from < 0;
    $to = $n unless defined $to;
    $to += $n if $to < 0;
    $from = max( 0, $from );
    $to   = min( $n, $to );
    return [] if $from >= $to;
    return [ @$items[ $from .. $to - 1 ] ];
}

sub replace_text {
    my ( $text, $old, $new, $count ) = @_;
    if ( defined($count) ) {
        while ( $count-- > 0 ) { last unless $text =~ s/\Q$old\E/$new/; }
    }
    else { $text =~ s/\Q$old\E/$new/g; }
    return $text;
}

sub replace_re {
    my ( $pattern, $replacement, $text, $count ) = @_;
    my $re = ref($pattern) eq 'Regexp' ? $pattern : qr/$pattern/;
    if ( defined($count) && $count ) {
        while ( $count-- > 0 ) { last unless $text =~ s/$re/$replacement/; }
    }
    else { $text =~ s/$re/$replacement/g; }
    return $text;
}

sub regex {
    my ( $pattern, $flags ) = @_;
    $flags //= q{};
    return
        $flags eq q{i} ? qr/(?i:$pattern)/
      : $flags eq q{s} ? qr/(?s:$pattern)/
      :                  qr/$pattern/;
}

sub match_re {
    my ( $pattern, $text, $full ) = @_;
    my @m = $full ? ( $text =~ /\A($pattern)\z/ ) : ( $text =~ /($pattern)/ );
    return @m ? \@m : undef;
}

sub trim_text {
    my ( $text, $chars, $mode ) = @_;
    ( $mode, $chars ) = ( $chars, undef ) unless defined $mode;
    my $pattern = defined($chars) ? '[' . quotemeta($chars) . ']' : '\s';
    $text =~ s/^$pattern+// unless $mode eq 'rstrip';
    $text =~ s/$pattern+$// unless $mode eq 'lstrip';
    return $text;
}

sub remove_suffix {
    my ( $text, $suffix ) = @_;
    $text =~ s/\Q$suffix\E$//;
    return $text;
}
sub mean { my ($values) = @_; return sum(@$values) / @$values; }

sub stddev {
    my ($values) = @_;
    my $average = mean($values);
    return sqrt( sum( map { ( $_ - $average )**2 } @$values ) / @$values );
}

sub query_string {
    my ($pairs) = @_;
    my $uri = URI->new('');
    $uri->query_form( ref($pairs) eq 'HASH' ? %$pairs : map { @$_ } @$pairs );
    return $uri->query;
}

sub random_bytes {
    my ($n) = @_;
    open my $fh, '<:raw', '/dev/urandom' or die $!;
    read( $fh, my $bytes, $n ) == $n or die 'short random read';
    close $fh;
    return $bytes;
}

sub capture_event {
    my ( $object, $event, $values, $expression ) = @_;
    my $filename = _event_log($values);
    $object->on( $event,
            'const value = ('
          . $expression
          . ')(...arguments); process.getBuiltinModule("fs").appendFileSync('
          . encode_json($filename)
          . ', JSON.stringify(value) + "\\n");' );
}

sub capture_socket_event {
    my ( $object, $event, $socket_event, $values, $expression ) = @_;
    my $filename = _event_log($values);
    $object->on( $event,
            'arguments[0].on('
          . encode_json($socket_event)
          . ', (...args) => { const value = ('
          . $expression
          . ')(...args); process.getBuiltinModule("fs").appendFileSync('
          . encode_json($filename)
          . ', JSON.stringify(value) + "\\n"); });' );
}

sub _event_log {
    my ($values) = @_;
    my $tied = tied(@$values);
    return $tied->{file} if $tied;
    my ( $fh, $filename ) = tempfile( 'leqra-events-XXXXXX', TMPDIR => 1, UNLINK => 1 );
    my @initial = @$values;
    tie @$values, 'Leqra::Browser::EventLog', $filename, $fh, \@initial;
    return $filename;
}

sub expect_locator {
    my ( $locator, $assertion, @args ) = @_;
    my $options  = ref( $args[-1] ) eq 'HASH' ? pop @args : {};
    my $deadline = time() + ( ( $options->{timeout} // 5000 ) / 1000 );
    my $negative = $assertion =~ s/^not_//;
    my ( $ok, $actual );
    while (1) {
        $ok = eval {
            if ( $assertion eq 'to_be_visible' ) {
                $actual = $locator->isVisible();
                $actual;
            }
            elsif ( $assertion eq 'to_be_hidden' ) {
                $actual = $locator->isHidden();
                $actual;
            }
            elsif ( $assertion eq 'to_be_enabled' ) {
                $actual = $locator->isEnabled();
                $actual;
            }
            elsif ( $assertion eq 'to_be_disabled' ) {
                $actual = $locator->isDisabled();
                $actual;
            }
            elsif ( $assertion eq 'to_be_checked' ) {
                $actual = $locator->isChecked();
                $actual;
            }
            elsif ( $assertion eq 'to_be_attached' ) {
                $actual = $locator->count();
                $actual > 0;
            }
            elsif ( $assertion eq 'to_be_focused' ) {
                evaluate_js( $locator, '(el) => el === document.activeElement' );
            }
            elsif ( $assertion eq 'to_be_in_viewport' ) {
                $actual = evaluate_js( $locator,
'(el) => new Promise(resolve => { const observer=new IntersectionObserver(entries => { observer.disconnect(); resolve(entries[0].intersectionRatio); }); observer.observe(el); })'
                );
                $actual > 0 && $actual >= ( $options->{ratio} // 0 );
            }
            elsif ( $assertion eq 'to_have_count' ) {
                $actual = $locator->count();
                $actual == $args[0];
            }
            elsif ( $assertion eq 'to_have_value' ) {
                $actual = $locator->inputValue();
                _matches( $actual, $args[0], 0 );
            }
            elsif ( $assertion eq 'to_have_attribute' ) {
                $actual = $locator->getAttribute( $args[0] );
                _matches( $actual, $args[1], 0 );
            }
            elsif ( $assertion eq 'to_have_class' ) {
                $actual = $locator->getAttribute('class');
                _matches( $actual, $args[0], 0 );
            }
            elsif ( $assertion eq 'to_have_css' ) {
                $actual = evaluate_js( $locator, '(el, prop) => getComputedStyle(el).getPropertyValue(prop)',
                    $args[0] );
                _matches( $actual, $args[1], 0 );
            }
            elsif ($assertion eq 'to_have_text'
                || $assertion eq 'to_contain_text' )
            {
                $actual =
                  ref( $args[0] ) eq 'ARRAY'
                  ? (
                      $options->{useInnerText}
                    ? $locator->allInnerTexts()
                    : $locator->allTextContents()
                  )
                  : (
                      $options->{useInnerText}
                    ? $locator->innerText()
                    : $locator->textContent()
                  );
                _matches( $actual, $args[0], $assertion eq 'to_contain_text', 1 );
            }
            else { die "Unsupported locator assertion $assertion\n"; }
        };
        my $exception = $@;
        $ok = !$ok if $negative && !$exception;
        $ok = 0    if $exception;
        return 1 if $ok;
        last     if time() >= $deadline;
        sleep(0.03);
    }
    confess "Locator assertion $assertion failed: "
      . format_value($actual)
      . " expected "
      . format_value( \@args ) . "\n";
}

sub _matches {
    my ( $actual, $expected, $contains, $normalize ) = @_;
    return 0 unless defined $actual;
    if ( ref($expected) eq 'Regexp' ) { return $actual =~ $expected; }
    if ( ref($expected) eq 'ARRAY' ) {
        return 0 unless ref($actual) eq 'ARRAY';
        if ($contains) {
            my $next = 0;
            for my $text (@$actual) {
                ++$next
                  if $next < @$expected
                  && _matches( $text, $expected->[$next], 1, $normalize );
            }
            return $next == @$expected;
        }
        return 0 unless @$actual == @$expected;
        for my $i ( 0 .. $#$expected ) {
            return 0
              unless _matches( $actual->[$i], $expected->[$i], 0, $normalize );
        }
        return 1;
    }
    if ($normalize) {
        $actual   =~ s/\s+/ /g;
        $actual   =~ s/^ | $//g;
        $expected =~ s/\s+/ /g;
        $expected =~ s/^ | $//g;
    }
    return $contains ? index( $actual, $expected ) >= 0 : $actual eq $expected;
}

package Leqra::Browser::EventLog;
use Tie::Array;
our @ISA = ('Tie::StdArray');

sub TIEARRAY {
    my ( $class, $file, $fh, $values ) = @_;
    return bless { file => $file, fh => $fh, values => $values, offset => 0 }, $class;
}

sub refresh {
    my ($self) = @_;
    seek( $self->{fh}, $self->{offset}, 0 ) or die $!;
    while ( my $line = readline( $self->{fh} ) ) {
        push @{ $self->{values} }, JSON::PP::decode_json($line);
    }
    $self->{offset} = tell( $self->{fh} );
}

sub FETCHSIZE {
    my ($self) = @_;
    $self->refresh;
    return scalar @{ $self->{values} };
}

sub FETCH {
    my ( $self, $index ) = @_;
    $self->refresh;
    return $self->{values}[$index];
}

sub STORE {
    my ( $self, $index, $value ) = @_;
    $self->refresh;
    $self->{values}[$index] = $value;
}

sub STORESIZE {
    my ( $self, $size ) = @_;
    $self->refresh;
    $#{ $self->{values} } = $size - 1;
}
sub CLEAR { $_[0]->{values} = []; }
sub PUSH  { my $self        = shift; $self->refresh; push @{ $self->{values} }, @_; }
sub POP   { my $self        = shift; $self->refresh; pop @{ $self->{values} }; }
sub SHIFT { my $self        = shift; $self->refresh; shift @{ $self->{values} }; }

sub SPLICE {
    my $self = shift;
    $self->refresh;
    splice @{ $self->{values} }, @_;
}
1;
