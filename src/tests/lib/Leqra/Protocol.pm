package Leqra::Protocol;
use strict;
use warnings;
use utf8;
use Exporter 'import';
use File::Basename qw(dirname);
use File::Path qw(make_path);
use JSON::PP;
use List::Util qw(min);
use Mojo::IOLoop;
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::Util qw(steady_time);

our @EXPORT_OK = qw(peer connect_socket upgrade_status http_json http_status pause write_text token_hex json_text same close_peers);
my @peers;
my $json = JSON::PP->new->canonical->allow_nonref;

sub json_text { $json->encode($_[0]) }
sub same { json_text($_[0]) eq json_text($_[1]) }

sub _until {
    my ($predicate, $timeout, $label) = @_;
    my $deadline = steady_time() + $timeout;
    until ($predicate->()) {
        my $remaining = $deadline - steady_time();
        die "Timed out waiting for $label\n" if $remaining <= 0;
        my $timer = Mojo::IOLoop->timer(min(0.01, $remaining) => sub {});
        Mojo::IOLoop->one_tick;
        Mojo::IOLoop->remove($timer);
    }
}

sub pause {
    my ($seconds) = @_;
    return if $seconds <= 0;
    my $done = 0;
    my $timer = Mojo::IOLoop->timer($seconds => sub { $done = 1 });
    _until(sub { $done }, $seconds + 1, 'delay');
    Mojo::IOLoop->remove($timer);
}

sub _urls {
    my ($base) = @_;
    my $url = Mojo::URL->new($base);
    my $origin = $url->clone->path('')->query(undef)->fragment(undef)->to_string;
    my $ws = $url->clone->scheme($url->scheme eq 'https' ? 'wss' : 'ws')->path('/ws')->query(undef)->fragment(undef);
    return ($origin, $ws);
}

sub _connect {
    my ($base, %options) = @_;
    my ($origin, $url) = _urls($base);
    my $ua = Mojo::UserAgent->new->connect_timeout(7)->request_timeout(0)->inactivity_timeout(0);
    my $socket;
    $ua->websocket($url => {Origin => $options{origin} // $origin} => sub {
        my ($ua, $tx) = @_;
        $socket = Leqra::Protocol::Peer->new($ua, $tx, %options);
    });
    _until(sub { defined $socket }, 8, 'WebSocket upgrade');
    return $socket;
}

sub connect_socket {
    my $socket = _connect(@_);
    die 'WebSocket handshake failed: ' . ($socket->{status} // 0) . "\n" unless $socket->{tx}->is_websocket;
    push @peers, $socket;
    return $socket;
}

sub upgrade_status { _connect(@_)->{status} }

sub peer {
    my $socket = connect_socket(@_);
    my $hello = $socket->recv(7);
    die 'Missing server_hello: ' . json_text($hello) . "\n" unless ($hello->{type} // '') eq 'server_hello';
    $socket->send({type => 'client_hello', version => $hello->{version}, protocol => $hello->{protocol}});
    return $socket;
}

sub http_json {
    my ($url) = @_;
    return Mojo::UserAgent->new->request_timeout(7)->get($url)->result->json;
}

sub http_status {
    my ($url) = @_;
    return Mojo::UserAgent->new->request_timeout(7)->get($url)->result->code;
}

sub write_text {
    my ($path, $text) = @_;
    make_path(dirname($path));
    open my $file, '>:encoding(UTF-8)', $path or die "$path: $!\n";
    print {$file} $text;
    close $file or die "$path: $!\n";
}

sub token_hex {
    my ($count) = @_;
    open my $random, '<:raw', '/dev/urandom' or die "/dev/urandom: $!\n";
    read($random, my $bytes, $count) == $count or die "Unable to read random token\n";
    close $random;
    return unpack('H*', $bytes);
}

sub close_peers {
    for my $peer (@peers) { eval { $peer->close } }
    @peers = ();
}

package Leqra::Protocol::Peer;
use strict;
use warnings;
use Mojo::Util qw(steady_time);

sub new {
    my ($class, $ua, $tx, %options) = @_;
    my $self = bless {ua => $ua, tx => $tx, messages => [], status => $tx->res->code,
        closed => 0, last_action => 0, action_interval => $options{action_interval} // 0,
        timeout => $options{timeout} // 7}, $class;
    return $self unless $tx->is_websocket;
    $tx->max_websocket_size($options{max_size} // 1_000_000);
    $tx->on(json => sub { push @{$self->{messages}}, $_[1] });
    $tx->on(finish => sub {
        $self->{closed} = 1;
        $self->{close_code} = $_[1];
        $self->{close_reason} = $_[2];
    });
    return $self;
}

sub send {
    my ($self, $message) = @_;
    die "WebSocket is closed\n" if $self->{closed};
    if (($message->{type} // '') !~ /\A(?:input|ping)\z/ && $self->{action_interval}) {
        Leqra::Protocol::pause($self->{action_interval} - (steady_time() - $self->{last_action}));
        $self->{last_action} = steady_time();
    }
    $self->{tx}->send({json => $message});
}

sub wait {
    my ($self, $predicate, %options) = @_;
    my $after = $options{after} // 0;
    my $match;
    eval { Leqra::Protocol::_until(sub {
        for my $index ($after .. $#{$self->{messages}}) {
            my $message = $self->{messages}[$index];
            if ($predicate->($message)) { $match = $message; return 1 }
        }
        return 0;
    }, $options{timeout} // $self->{timeout}, $options{label} // 'matching packet') };
    if (my $error = $@) {
        my $messages = $self->{messages};
        my $first = @$messages > 3 ? @$messages - 3 : 0;
        die $error . 'Last packets: ' . Leqra::Protocol::json_text([@$messages[$first .. $#$messages]]) . "\n";
    }
    return $match;
}

sub op {
    my ($self, $kind, $predicate, %message) = @_;
    my $after = @{$self->{messages}};
    $self->send({type => $kind, %message});
    return $self->wait($predicate, after => $after, label => "reply to $kind");
}

sub recv {
    my ($self, $timeout) = @_;
    Leqra::Protocol::_until(sub { @{$self->{messages}} || $self->{closed} }, $timeout // 7, 'packet');
    die "WebSocket closed before packet\n" unless @{$self->{messages}};
    return shift @{$self->{messages}};
}

sub send_text { $_[0]->{tx}->send({text => $_[1]}) }
sub send_binary { $_[0]->{tx}->send({binary => $_[1]}) }
sub send_fragments {
    my ($self, @parts) = @_;
    for my $index (0 .. $#parts) {
        $self->{tx}->send([$index == $#parts ? 1 : 0, 0, 0, 0, $index == 0 ? 1 : 0, $parts[$index]]);
    }
}

sub ping {
    my ($self, $payload) = @_;
    my $received = 0;
    my $callback = sub {
        my ($tx, $frame) = @_;
        $received = 1 if $frame->[4] == 10 && $frame->[5] eq $payload;
    };
    $self->{tx}->on(frame => $callback);
    $self->{tx}->send([1, 0, 0, 0, 9, $payload]);
    Leqra::Protocol::_until(sub { $received }, 2, 'WebSocket pong');
    $self->{tx}->unsubscribe(frame => $callback);
}

sub wait_closed {
    my ($self, $timeout) = @_;
    Leqra::Protocol::_until(sub { $self->{closed} }, $timeout // 3, 'WebSocket close');
    return $self->{close_code};
}

sub close {
    my ($self) = @_;
    return if $self->{closed};
    $self->{tx}->finish;
    $self->wait_closed(3);
}

1;
