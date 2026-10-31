#!/bin/sh
set -eu

attempt=0
while ! ip link show dev eth1 >/dev/null 2>&1; do
	attempt=$((attempt + 1))
	if [ "$attempt" -ge 30 ]; then
		printf '%s\n' 'Timed out waiting for eth1.' >&2
		exit 1
	fi
	sleep 1
done

ip link set dev eth1 up
ip address replace 10.0.3.2/30 dev eth1
ip address replace 198.51.100.10/32 dev lo
ip address replace 198.51.100.130/32 dev lo
ip route replace default via 10.0.3.1 dev eth1

printf '%s\n' 'incident lab service' > /usr/share/nginx/html/index.html
exec nginx -g 'daemon off;'
