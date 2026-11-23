#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;
open my $command, '-|', 'xcrun', 'simctl', 'list', '--json' or die "xcrun: $!\n";
my $inventory = do { local $/; decode_json(<$command>) };
close $command or die "simctl list failed\n";
my @runtimes = grep { $_->{identifier} =~ /\.iOS-/ && $_->{isAvailable} } @{$inventory->{runtimes}};
my @standard = grep { (my $version = $_->{version}) =~ s/\./-/g; $_->{identifier} =~ /\.iOS-\Q$version\E\z/ } @runtimes;
@runtimes = @standard if @standard;
@runtimes = sort {
    my @a = split /\./, $a->{version};
    my @b = split /\./, $b->{version};
    my $comparison = 0;
    for my $i (0 .. (@a > @b ? $#a : $#b)) {
        $comparison = ($b[$i] // 0) <=> ($a[$i] // 0);
        last if $comparison;
    }
    $comparison;
} @runtimes;
for my $runtime (@runtimes) {
    for my $device (@{$inventory->{devices}{$runtime->{identifier}} // []}) {
        next unless $device->{name} =~ /^iPhone/ && $device->{isAvailable};
        if ($device->{state} eq 'Shutdown') {
            system('xcrun', 'simctl', 'boot', $device->{udid}) == 0 or die "simctl boot failed\n";
        }
        print "$device->{udid}\n";
        exit;
    }
}
die "No available iPhone simulator\n";
