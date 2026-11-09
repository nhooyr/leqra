#!/bin/sh
set -eu
cd "$(dirname "$0")"

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/leqra-deploy.XXXXXX")
trap 'rm -rf "$build_dir"' 0
trap 'exit 1' HUP INT TERM
GOOS=linux GOARCH=amd64 go build -trimpath -o "$build_dir/leqra" ../src

ssh leqra sh -s <<'EOF'
set -eu
if ! command -v rsync 2>/dev/null; then
	sudo apt-get update
	sudo apt-get install -y rsync
fi
if ! getent passwd leqra >/dev/null; then
	sudo useradd --system --user-group --home /opt/leqra --shell /usr/sbin/nologin leqra
fi
sudo mkdir -p /opt/leqra /etc/leqra /var/lib/leqra
sudo chown leqra:leqra /opt/leqra /var/lib/leqra
EOF

rsync --rsync-path='sudo rsync' -avzP "$build_dir/leqra" leqra:/opt/leqra/leqra-server
rsync --rsync-path='sudo rsync' -avzP leqra.service leqra:/etc/systemd/system/leqra.service
rsync --rsync-path='sudo rsync' -avzP leqra.env leqra:/etc/leqra/leqra.env
ssh leqra sh -s <<'EOF'
set -eu
sudo chown leqra:leqra /opt/leqra/leqra-server
sudo systemctl daemon-reload
sudo systemctl enable leqra
sudo systemctl restart leqra
sudo systemctl status --no-pager leqra
EOF
