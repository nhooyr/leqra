#!/bin/sh
set -eu

go build -o ./bin/leqra ./src
./bin/leqra -check-assets

{
	for i in $(seq 1 20); do
		if curl -fsI "http://$(hostname):8080" >/dev/null; then
			open -a 'Google Chrome' "http://$(hostname):8080"
			break
		fi
		sleep 0.1
	done
} &
exec ./bin/leqra
