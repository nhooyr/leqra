#!/bin/sh
set -eu
cd "$(dirname "$0")"

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/leqra-deploy.XXXXXX")
trap 'rm -rf "$build_dir"' 0
trap 'exit 1' HUP INT TERM
GOOS=linux GOARCH=amd64 go build -o "$build_dir/leqra" ../src

ssh leqra sh -s <<'REMOTE'
set -eu
if ! getent passwd leqra >/dev/null; then
	useradd --system --user-group --home /opt/leqra --shell /usr/sbin/nologin leqra
fi
mkdir -p /opt/leqra /etc/leqra /var/lib/leqra
chown leqra:leqra /opt/leqra /var/lib/leqra
REMOTE

rsync -avzP "$build_dir/leqra" leqra:/opt/leqra/leqra-server
rsync -avzP leqra.service leqra:/etc/systemd/system/leqra.service
rsync -avzP leqra.env leqra:/etc/leqra/leqra.env
ssh leqra sh -s <<'REMOTE'
set -eu
chown leqra:leqra /opt/leqra/leqra-server
systemctl daemon-reload
systemctl enable leqra
systemctl restart leqra
systemctl status leqra
REMOTE
