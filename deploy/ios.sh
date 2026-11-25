#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -eq 0 ]; then
	printf 'Usage: %s <iphone-name> | --app-store|--upload [output-directory]\n' "${0##*/}" >&2
	exit 1
fi

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

if [ "$1" = '--app-store' ] || [ "$1" = '--upload' ]; then
	output_arg=${2-}
	if [ "$#" -gt 2 ] || [ "${output_arg#--}" != "$output_arg" ]; then
		printf 'Usage: %s --app-store|--upload [output-directory]\n' "${0##*/}" >&2
		exit 1
	fi
	mode=$1
	output=${output_arg:-bin/ios}
	mkdir -p "$output"
	output=$(CDPATH= cd "$output" && pwd)
	xcodebuild=$(command -v xcodebuild)
	set -- "$xcodebuild" -project ios/leqra.xcodeproj -scheme leqra \
		-configuration Release -destination 'generic/platform=iOS' \
		-derivedDataPath "$output/DerivedData" CODE_SIGNING_ALLOWED=NO
	settings=$("$@" -showBuildSettings -json)
	team=$(printf '%s\n' "$settings" | perl -MJSON::PP -0777 -ne '
		for my $target (@{decode_json($_)}) {
			next unless $target->{target} eq "leqra";
			my $team = $target->{buildSettings}{DEVELOPMENT_TEAM};
			die "No development team configured for leqra\n" unless defined($team) && length($team);
			print $team;
			exit;
		}
		die "No leqra build settings found\n";
	')
	"$@" -archivePath "$output/leqra.xcarchive" archive
	cp deploy/ios-export.plist "$output/ExportOptions.plist"
	/usr/bin/plutil -insert teamID -string "$team" "$output/ExportOptions.plist"
	set -- "$xcodebuild" -exportArchive -archivePath "$output/leqra.xcarchive" \
		-exportOptionsPlist "$output/ExportOptions.plist" -allowProvisioningUpdates
	if [ "$mode" = '--upload' ]; then
		/usr/bin/plutil -replace destination -string upload "$output/ExportOptions.plist"
	else
		set -- "$@" -exportPath "$output/export"
	fi
	# Apple's rsync must find its matching helper when Xcode packages the IPA.
	PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" "$@"
	if [ "$mode" = '--upload' ]; then
		printf 'Uploaded iOS build to App Store Connect.\n'
	else
		printf 'App Store export: %s\n' "$output/export"
	fi
	exit 0
fi

if [ "$#" -ne 1 ] || [ "${1#--}" != "$1" ]; then
	printf 'Usage: %s <iphone-name> | --app-store|--upload [output-directory]\n' "${0##*/}" >&2
	exit 1
fi

xcodebuild \
	-project ios/leqra.xcodeproj \
	-scheme leqra \
	-configuration Release \
	-destination "platform=iOS,name=$1" \
	-derivedDataPath /tmp/leqra-ios-device \
	-allowProvisioningUpdates \
	build &&
	xcrun devicectl device install app \
		--device "$1" \
		/tmp/leqra-ios-device/Build/Products/Release-iphoneos/leqra.app &&
	xcrun devicectl device process launch \
		--device "$1" \
		--terminate-existing \
		com.leqra
