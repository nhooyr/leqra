#!/bin/sh
set -eu

{
	for i in $(seq 1 20); do
		if curl -fsI "http://$(hostname):8080" >/dev/null; then
			open "http://$(hostname):8080"
			break
		fi
		sleep 0.1
	done
} &
go build  -o ./bin/leqra ./src && ./bin/leqra
