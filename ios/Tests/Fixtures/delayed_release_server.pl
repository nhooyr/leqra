#!/usr/bin/env perl
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use JSON::PP;
use Time::HiRes qw(time);

# Disposable accounts stay in memory; waiting releases never block gate requests.
@ARGV==1 && $ARGV[0] =~ /\A[0-9]+\z/ or die "Usage: delayed_release_server.pl PORT\n";
my $server=IO::Socket::INET->new(LocalAddr=>'127.0.0.1',LocalPort=>$ARGV[0],Listen=>16,ReuseAddr=>1) or die "listen: $!\n";
my $select=IO::Select->new($server);
my (%clients,%accounts,@pending);
my $released=0;
$SIG{PIPE}='IGNORE';
sub reply {
    my ($socket,$status,$value)=@_;
    my $data=encode_json($value);
    my %status=(200=>'OK',400=>'Bad Request',401=>'Unauthorized',503=>'Service Unavailable');
    print {$socket} "HTTP/1.0 $status $status{$status}\r\nContent-Type: application/json\r\nContent-Length: ".length($data)."\r\nConnection: close\r\n\r\n$data";
    $select->remove($socket); delete $clients{fileno($socket)}; close $socket;
}
sub release_reply {
    my ($socket,$key)=@_;
    if (($accounts{$key}//'') =~ /^FAIL/) {reply($socket,503,{code=>'server_busy'});}
    else {delete $accounts{$key};reply($socket,200,{released=>JSON::PP::true});}
}
while (1) {
    for my $socket ($select->can_read(.1)) {
        if ($socket==$server) {
            my $client=$server->accept(); next unless $client;
            $client->autoflush(1); $clients{fileno($client)}={socket=>$client,buffer=>''}; $select->add($client); next;
        }
        my $fd=fileno($socket); my $state=$clients{$fd};
        my $n=sysread($socket,my $chunk,65536);
        if (!$n) {$select->remove($socket);delete $clients{$fd};close $socket;next;}
        $state->{buffer}.=$chunk;
        next unless $state->{buffer}=~/\A(.*?)\r?\n\r?\n(.*)\z/s;
        my ($headers,$body)=($1,$2); my ($method,$path)=$headers=~/\A(\S+)\s+(\S+)/;
        my ($length)=$headers=~/^Content-Length:\s*(\d+)/mi; $length//=0;
        next if length($body)<$length;
        if ($method eq 'GET') {
            $released=1 if $path eq '/finish-release'; $released=0 if $path eq '/reset-release';
            reply($socket,200,{players=>0,tankCount=>0,capacity=>32,leaders=>[]});
        } elsif ($method eq 'POST') {
            my $value=eval{decode_json(substr($body,0,$length))};
            if ($@ || ref($value) ne 'HASH') {reply($socket,400,{code=>'invalid_json'});next;}
            my $key=$value->{publicToken}//'';
            if ($path eq '/api/callsigns') {
                my $i=0; reply($socket,200,{names=>[map {{seat=>$i++,name=>$_,available=>JSON::PP::true}} @{$value->{names}//[]}]});
            } elsif ($path eq '/api/account/create') {
                $accounts{$key}//=$value->{name}; reply($socket,200,{names=>[$accounts{$key}],totalNames=>1});
            } elsif ($path eq '/api/account' && exists $accounts{$key}) {
                reply($socket,200,{names=>[$accounts{$key}],totalNames=>1});
            } elsif ($path eq '/api/account/release' && exists $accounts{$key}) {
                if ($released) {release_reply($socket,$key);}
                else {$select->remove($socket);delete $clients{$fd};push @pending,[$socket,$key,time()+45];}
            } else {reply($socket,401,{code=>'account_key_invalid'});}
        } else {reply($socket,400,{code=>'invalid_method'});}
    }
    my @waiting;
    for my $request (@pending) {
        if ($released || time()>=$request->[2]) {release_reply(@$request[0,1]);}
        else {push @waiting,$request;}
    }
    @pending=@waiting;
}
