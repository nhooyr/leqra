#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

usage() {
	printf 'Usage: %s [--upload]\n' "${0##*/}"
	printf 'Build an Android App Bundle; --upload releases it to Google Play closed testing (alpha).\n'
	printf 'Uploading requires fastlane and Google Play credentials (SUPPLY_JSON_KEY or Application Default Credentials).\n'
}

if [ "$#" -gt 1 ]; then
	usage >&2
	exit 1
fi
case "${1-}" in
'') ;;
--upload)
	if ! command -v fastlane >/dev/null 2>&1; then
		printf 'Install fastlane before uploading: brew install fastlane\n' >&2
		exit 1
	fi
	;;
--help | -h)
	usage
	exit 0
	;;
*)
	usage >&2
	exit 1
	;;
esac

./android/gradlew -p android :app:bundleRelease
bundle=$(realpath android/app/build/outputs/bundle/release/app-release.aab)
printf '%s\n' "$bundle" | perl -pe 's/\Q$ENV{HOME}\E(?=\/|$)/~/g'

if [ "${1-}" = '--upload' ]; then
	version=$(./scripts/version.sh)
	metadata="$PWD/bin/android-play"
	release_notes=$(curl --fail --silent --show-error 'https://api.github.com/repos/nhooyr/leqra/releases?per_page=1' |
		perl -MJSON::PP -0777 -ne '
			my $release = decode_json($_)->[0] or die "No published GitHub release found\n";
			print $release->{html_url} // die "GitHub release has no URL\n";
		')
	mkdir -p "$metadata/en-US/changelogs"
	printf 'Release notes: %s\n' "$release_notes" >"$metadata/en-US/changelogs/default.txt"
	fastlane supply --aab "$bundle" --package_name com.leqra \
		--track alpha --release_status completed --version_name "$version" \
		--metadata_path "$metadata" --skip_upload_apk true --skip_upload_metadata true \
		--skip_upload_images true --skip_upload_screenshots true --skip_upload_changelogs false
	printf 'Uploaded %s to Google Play closed testing (alpha).\nRelease notes: %s\n' "$version" "$release_notes"
fi
