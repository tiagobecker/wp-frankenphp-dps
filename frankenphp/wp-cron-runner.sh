#!/usr/bin/env bash
set -Eeuo pipefail

wp_path=/app/public
interval="${WORDPRESS_CRON_INTERVAL:-60}"

if ! [[ "$interval" =~ ^[1-9][0-9]*$ ]]; then
	echo "WORDPRESS_CRON_INTERVAL must be a positive integer." >&2
	exit 1
fi

echo "Starting WordPress cron runner with interval ${interval}s."

while true; do
	if wp --path="$wp_path" --allow-root core is-installed >/dev/null 2>&1; then
		wp --path="$wp_path" --allow-root cron event run --due-now || true
	fi
	sleep "$interval"
done
