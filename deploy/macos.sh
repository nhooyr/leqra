#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

usage() {
	printf 'Usage: %s [--app-store|--upload [output-directory]]\n' "${0##*/}"
	printf 'Build and install locally using Apple development signing; export or upload with the optional flags.\n'
}

case "${1-}" in
-h | --help | --fish-completions)
	if [ "$#" -ne 1 ]; then
		usage >&2
		exit 1
	fi
	if [ "$1" = '--fish-completions' ]; then
		printf '%s\n' \
			"complete -c macos.sh -s h -l help -d 'Show usage'" \
			"complete -c macos.sh -l app-store -d 'Export a Mac App Store package'" \
			"complete -c macos.sh -l upload -d 'Upload to App Store Connect'" \
			"complete -c macos.sh -l fish-completions -d 'Print Fish completions'"
	else
		usage
	fi
	exit 0
	;;
esac

if [ "$#" -gt 0 ]; then
	output_arg=${2-}
	if { [ "$1" != '--app-store' ] && [ "$1" != '--upload' ]; } || [ "$#" -gt 2 ] || [ "${output_arg#--}" != "$output_arg" ]; then
		usage >&2
		exit 1
	fi
	mode=$1
	output=${output_arg:-bin/macos}
	mkdir -p "$output"
	output=$(CDPATH= cd "$output" && pwd)
	xcodebuild=$(command -v xcodebuild)
	"$xcodebuild" -project ios/leqra.xcodeproj -scheme leqra \
		-configuration Release -destination 'generic/platform=macOS,variant=Mac Catalyst' \
		-derivedDataPath "$output/DerivedData" -archivePath "$output/leqra.xcarchive" \
		ONLY_ACTIVE_ARCH=NO -allowProvisioningUpdates archive
	cp deploy/macos-export.plist "$output/ExportOptions.plist"
	set -- "$xcodebuild" -exportArchive -archivePath "$output/leqra.xcarchive" \
		-exportOptionsPlist "$output/ExportOptions.plist" -allowProvisioningUpdates
	if [ "$mode" = '--upload' ]; then
		/usr/bin/plutil -replace destination -string upload "$output/ExportOptions.plist"
	else
		set -- "$@" -exportPath "$output/export"
	fi
	# Apple's rsync must find its matching helper when Xcode packages the app.
	PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" "$@"
	if [ "$mode" = '--upload' ]; then
		printf 'Uploaded macOS build to App Store Connect.\n'
	else
		printf 'Mac App Store export: %s\n' "$output/export"
	fi
	exit 0
fi

output="$PWD/bin/macos"
install_dir=${LEQRA_MACOS_INSTALL_DIR:-"$HOME/Applications"}
codesign=$(command -v codesign)
xcodebuild -project ios/leqra.xcodeproj -scheme leqra \
	-configuration Release -destination 'platform=macOS,variant=Mac Catalyst' \
	-derivedDataPath "$output/DerivedData" \
	ONLY_ACTIVE_ARCH=NO -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
built="$output/DerivedData/Build/Products/Release-maccatalyst/leqra.app"
"$codesign" --verify --deep --strict "$built"

perl - "$built" "$codesign" "$output/leqra.app" "$install_dir/leqra.app" <<'PERL'
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);

my ($source, $codesign, @destinations) = @ARGV;
my (@entries, %seen);
sub exists_path { return -e $_[0] || -l $_[0] }
sub remove_path {
    my ($path) = @_;
    return unless exists_path($path);
    my $errors;
    remove_tree($path, {error => \$errors});
    die "Could not remove $path\n" if @$errors;
}
sub run {
    my ($command, @arguments) = @_;
    system {$command} $command, @arguments;
    die "$command failed\n" if $?;
}
$SIG{$_} = sub { die "Installation interrupted by SIG$_[0]\n" } for qw(HUP INT TERM);
my $ok = eval {
    for my $destination (@destinations) {
        my $parent = dirname($destination);
        make_path($parent);
        $destination = abs_path($parent) . '/' . basename($destination);
        next if $seen{$destination}++;
        my $directory = tempdir('.leqra-install-XXXXXX', DIR => abs_path($parent));
        my $entry = {destination => $destination, directory => $directory,
            staged => "$directory/leqra.app", previous => "$directory/previous.app"};
        push @entries, $entry;
        run('/usr/bin/ditto', $source, $entry->{staged});
        run($codesign, '--verify', '--deep', '--strict', $entry->{staged});
    }
    for my $entry (@entries) {
        $entry->{had_old} = exists_path($entry->{destination});
        $entry->{changing} = 1;
        if ($entry->{had_old}) {
            rename($entry->{destination}, $entry->{previous})
                or die "Could not preserve $entry->{destination}: $!\n";
        }
        rename($entry->{staged}, $entry->{destination})
            or die "Could not install $entry->{destination}: $!\n";
    }
    1;
};
my $error = $@;
$SIG{$_} = 'IGNORE' for qw(HUP INT TERM);
if (!$ok) {
    for my $entry (reverse @entries) {
        eval {
            if (exists_path($entry->{previous})) {
                remove_path($entry->{destination});
                rename($entry->{previous}, $entry->{destination})
                    or die "Could not restore $entry->{destination}: $!\n";
            } elsif ($entry->{changing} && !$entry->{had_old} && !exists_path($entry->{staged})) {
                remove_path($entry->{destination});
            }
            remove_path($entry->{directory});
        };
        $error .= $@ if $@;
    }
    die $error || "Installation failed\n";
}
remove_path($_->{directory}) for @entries;
PERL

printf 'Built app: %s\nInstalled app: %s\n' "$output/leqra.app" "$install_dir/leqra.app"
