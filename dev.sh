#!/bin/sh
set -eu
cd "$(dirname "$0")"

go build -o ./bin/leqra ./src
./bin/leqra -check-assets

listen=${ADDR:-:${PORT:-8080}}
port=${listen##*:}
if [ "$(uname -s)" = Darwin ] && [ "$port" -gt 0 ] 2>/dev/null; then
	host=${listen%:*}
	case "$host" in ''|0.0.0.0|'[::]') host=$(hostname);; esac
	url="http://$host:$port"
	(
		for i in $(seq 1 20); do
			if curl -fsI --max-time 1 "$url" >/dev/null; then
				open -a 'Google Chrome' "$url"
				break
			fi
			sleep 0.1
		done
	) &
fi
exec ./bin/leqra
