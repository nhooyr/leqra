use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use LeqraTest;
use Test::More;
use IO::Socket::INET;
use IO::Select;
use JSON::PP;
use Time::HiRes qw(sleep time);
my $reservation=IO::Socket::INET->new(LocalAddr=>'127.0.0.1',LocalPort=>0,Listen=>1) or die $!;
my $port=$reservation->sockport; close $reservation;
my $pid=fork(); die $! unless defined $pid;
if (!$pid) { exec $^X,root().'/ios/Tests/Fixtures/delayed_release_server.pl',$port; die $!; }
END {local $?; if ($pid) {kill 'TERM',$pid;waitpid($pid,0);}}
my $deadline=time()+5;
while (1) {my $probe=IO::Socket::INET->new(PeerAddr=>'127.0.0.1',PeerPort=>$port);if ($probe) {close $probe;last;}die 'fixture did not start' if time()>$deadline;sleep .02;}
sub start_request {
    my ($method,$path,$body)=@_; my $socket=IO::Socket::INET->new(PeerAddr=>'127.0.0.1',PeerPort=>$port) or die $!;
    $socket->autoflush(1); my $data=defined($body) ? encode_json($body) : '';
    print {$socket} "$method $path HTTP/1.0\r\nContent-Type: application/json\r\nContent-Length: ".length($data)."\r\n\r\n$data";
    return $socket;
}
sub response {
    my ($socket)=@_; local $/; my $data=<$socket>; close $socket;
    my ($head,$body)=split /\r\n\r\n/,$data,2; my ($status)=$head=~/^HTTP\/1.0 (\d+)/;
    return ($status,decode_json($body));
}
sub request {response(start_request(@_));}
subtest 'disposable accounts and nonblocking release gates' => sub {
    my ($status,$body)=request('POST','/api/callsigns',{names=>['ONE','TWO']});
    is($status,200,'callsigns'); is_deeply($body->{names},[{seat=>0,name=>'ONE',available=>JSON::PP::true},{seat=>1,name=>'TWO',available=>JSON::PP::true}],'availability');
    ($status,$body)=request('POST','/api/account/create',{publicToken=>'test-key',name=>'ONE'});
    is($status,200,'created'); is_deeply($body,{names=>['ONE'],totalNames=>1},'account');
    my $pending=start_request('POST','/api/account/release',{publicToken=>'test-key'});
    ok(!IO::Select->new($pending)->can_read(.1),'release waits');
    ($status,$body)=request('GET','/finish-release'); is($status,200,'gate is responsive');
    ($status,$body)=response($pending); is($status,200,'released'); ok($body->{released},'release result');
    ($status,$body)=request('POST','/api/account',{publicToken=>'test-key'}); is($status,401,'account removed');
    request('GET','/reset-release'); request('POST','/api/account/create',{publicToken=>'fail-key',name=>'FAIL ONE'});
    $pending=start_request('POST','/api/account/release',{publicToken=>'fail-key'});
    ok(!IO::Select->new($pending)->can_read(.1),'reset gate waits'); request('GET','/finish-release');
    ($status,$body)=response($pending); is($status,503,'requested failure'); is($body->{code},'server_busy','failure code');
    ($status,$body)=request('POST','/api/account',{publicToken=>'fail-key'}); is($status,200,'failed release keeps account');
};
done_testing;
