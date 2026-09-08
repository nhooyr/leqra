#!/bin/sh
set -eu

if ! ssh leqra getent passwd leqra; then
	ssh leqra useradd --system --home /opt/leqra --shell /usr/sbin/nologin leqra
	ssh leqra mkdir -p /opt/leqra /etc/leqra /var/lib/leqra
	ssh leqra chown -R leqra:leqra /opt/leqra /var/lib/leqra
fi

GOOS=linux GOARCH=amd64 go build
rsync -avzP leqra leqra:/opt/leqra/leqra-server
rsync -avzP deploy/leqra.service leqra:/etc/systemd/system/leqra.service
rsync -avzP deploy/leqra.env leqra:/etc/leqra/leqra.env
ssh leqra chown -R leqra:leqra /opt/leqra /var/lib/leqra
ssh leqra systemctl enable leqra
ssh leqra systemctl restart leqra
ssh leqra systemctl status leqra
