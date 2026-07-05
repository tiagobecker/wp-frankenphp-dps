#!/usr/bin/env bash
set -Eeuo pipefail

wp_path=/app/public

bool_true() {
	case "${1:-}" in
		1|true|TRUE|yes|YES|on|ON) return 0 ;;
		*) return 1 ;;
	esac
}

require_env() {
	local name="$1"
	if [ -z "${!name:-}" ]; then
		echo "Missing required environment variable: ${name}" >&2
		exit 1
	fi
}

wait_for_database() {
	local host="${WORDPRESS_DB_HOST%%:*}"
	local port="${WORDPRESS_DB_HOST##*:}"
	local timeout="${STARTUP_WAIT_TIMEOUT:-0}"
	local interval="${STARTUP_WAIT_INTERVAL:-5}"
	local started_at="$SECONDS"
	local attempt=0

	if [ "$host" = "$port" ]; then
		port=3306
	fi

	if ! [[ "$timeout" =~ ^[0-9]+$ ]] || ! [[ "$interval" =~ ^[1-9][0-9]*$ ]]; then
		echo "STARTUP_WAIT_TIMEOUT must be zero or a positive integer and STARTUP_WAIT_INTERVAL must be a positive integer." >&2
		exit 1
	fi

	echo "Waiting for MariaDB at ${host}:${port}..."
	while true; do
		attempt=$((attempt + 1))
		if mysqladmin ping \
			--host="$host" \
			--port="$port" \
			--user="$WORDPRESS_DB_USER" \
			--password="$WORDPRESS_DB_PASSWORD" \
			--silent >/dev/null 2>&1; then
			echo "MariaDB is ready."
			return 0
		fi

		if [ "$timeout" -gt 0 ] && [ $((SECONDS - started_at)) -ge "$timeout" ]; then
			echo "MariaDB did not become ready within ${timeout}s." >&2
			exit 1
		fi

		if [ $((attempt % 12)) -eq 0 ]; then
			echo "MariaDB is still unavailable; continuing to wait..."
		fi
		sleep "$interval"
	done
}

wait_for_wordpress_files() {
	local timeout="${STARTUP_WAIT_TIMEOUT:-0}"
	local interval="${STARTUP_WAIT_INTERVAL:-5}"
	local started_at="$SECONDS"

	echo "Waiting for the WordPress runtime files..."
	while [ ! -f "$wp_path/wp-load.php" ] || [ ! -f "$wp_path/wp-config.php" ]; do
		if [ "$timeout" -gt 0 ] && [ $((SECONDS - started_at)) -ge "$timeout" ]; then
			echo "WordPress runtime files did not become ready within ${timeout}s." >&2
			exit 1
		fi
		sleep "$interval"
	done
}

wp_cmd() {
	wp --path="$wp_path" --allow-root "$@"
}

set_wp_config_constant() {
	local name="$1"
	local value="$2"
	shift 2
	wp_cmd config set "$name" "$value" --type=constant --quiet "$@"
}

upsert_wp_config_block() {
	local name="$1"
	local content="$2"

	php -r '
		$file = $argv[1];
		$name = $argv[2];
		$content = $argv[3];
		$start = "// BEGIN " . $name;
		$end = "// END " . $name;
		$block = $start . "\n" . $content . "\n" . $end . "\n";
		$config = file_get_contents($file);
		$pattern = "/" . preg_quote($start, "/") . ".*?" . preg_quote($end, "/") . "\n?/s";

		if (preg_match($pattern, $config)) {
			$config = preg_replace($pattern, $block, $config);
		} else {
			$marker = "/* That'\''s all, stop editing! Happy publishing. */";
			if (strpos($config, $marker) === false) {
				fwrite(STDERR, "Unable to find wp-config.php insertion marker.\n");
				exit(1);
			}
			$config = str_replace($marker, $block . "\n" . $marker, $config);
		}

		file_put_contents($file, $config);
	' "$wp_path/wp-config.php" "$name" "$content"
}

configure_runtime_constants() {
	local force_ssl_admin=false
	local disable_wp_cron=false
	local wp_debug=false

	if bool_true "${WORDPRESS_FORCE_SSL_ADMIN:-true}"; then
		force_ssl_admin=true
	fi

	if bool_true "${WORDPRESS_DISABLE_WP_CRON:-true}"; then
		disable_wp_cron=true
	fi

	if bool_true "${WORDPRESS_DEBUG:-false}"; then
		wp_debug=true
	fi

	set_wp_config_constant WP_HOME "getenv('WORDPRESS_HOME')" --raw
	set_wp_config_constant WP_SITEURL "getenv('WORDPRESS_SITEURL')" --raw
	set_wp_config_constant WP_ENVIRONMENT_TYPE "getenv('WORDPRESS_ENVIRONMENT_TYPE') ?: 'production'" --raw
	set_wp_config_constant WP_DEBUG "$wp_debug" --raw
	set_wp_config_constant WP_DEBUG_DISPLAY false --raw
	set_wp_config_constant DISALLOW_FILE_EDIT true --raw
	set_wp_config_constant FORCE_SSL_ADMIN "$force_ssl_admin" --raw
	set_wp_config_constant DISABLE_WP_CRON "$disable_wp_cron" --raw
	set_wp_config_constant FS_METHOD direct
	set_wp_config_constant WP_MEMORY_LIMIT "getenv('PHP_MEMORY_LIMIT') ?: '256M'" --raw
	set_wp_config_constant WP_MAX_MEMORY_LIMIT "getenv('PHP_MEMORY_LIMIT') ?: '256M'" --raw
	set_wp_config_constant WP_REDIS_HOST "getenv('WORDPRESS_REDIS_HOST') ?: 'redis'" --raw
	set_wp_config_constant WP_REDIS_PORT "(int) (getenv('WORDPRESS_REDIS_PORT') ?: 6379)" --raw
	set_wp_config_constant WP_REDIS_DATABASE "(int) (getenv('WORDPRESS_REDIS_DATABASE') ?: 0)" --raw
	set_wp_config_constant WP_REDIS_PREFIX "getenv('WORDPRESS_REDIS_PREFIX') ?: 'wp:'" --raw

	upsert_wp_config_block "DOKPLOY_PROXY" "if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && strpos(\$_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {
    \$_SERVER['HTTPS'] = 'on';
}"

	if [ -n "${WORDPRESS_CONFIG_EXTRA:-}" ]; then
		upsert_wp_config_block "WORDPRESS_CONFIG_EXTRA" "$WORDPRESS_CONFIG_EXTRA"
	fi
}

configure_salts() {
	local names=(
		AUTH_KEY
		SECURE_AUTH_KEY
		LOGGED_IN_KEY
		NONCE_KEY
		AUTH_SALT
		SECURE_AUTH_SALT
		LOGGED_IN_SALT
		NONCE_SALT
	)

	local has_all_salts=true
	for name in "${names[@]}"; do
		local env_name="WORDPRESS_${name}"
		if [ -z "${!env_name:-}" ] || [[ "${!env_name}" == CHANGE_ME* ]]; then
			has_all_salts=false
			break
		fi
	done

	if [ "$has_all_salts" = true ]; then
		for name in "${names[@]}"; do
			local env_name="WORDPRESS_${name}"
			wp_cmd config set "$name" "${!env_name}" --type=constant --quiet
		done
	else
		wp_cmd config shuffle-salts --quiet
	fi
}

install_wordpress_core() {
	if [ ! -f "$wp_path/wp-load.php" ]; then
		echo "Downloading WordPress core..."
		wp core download \
			--path="$wp_path" \
			--locale="${WORDPRESS_LOCALE:-pt_BR}" \
			--force \
			--allow-root
	fi

	if [ ! -f "$wp_path/wp-config.php" ]; then
		echo "Creating wp-config.php..."
		wp_cmd config create \
			--dbname="$WORDPRESS_DB_NAME" \
			--dbuser="$WORDPRESS_DB_USER" \
			--dbpass="$WORDPRESS_DB_PASSWORD" \
			--dbhost="$WORDPRESS_DB_HOST" \
			--dbprefix="${WORDPRESS_TABLE_PREFIX:-wp_}" \
			--skip-check \
			--quiet

		configure_salts
	fi

	configure_runtime_constants
}

maybe_install_site() {
	if ! bool_true "${WORDPRESS_AUTO_INSTALL:-false}"; then
		return 0
	fi

	if wp_cmd core is-installed >/dev/null 2>&1; then
		return 0
	fi

	require_env WORDPRESS_ADMIN_PASSWORD

	echo "Installing WordPress site..."
	wp_cmd core install \
		--url="$WORDPRESS_HOME" \
		--title="${WORDPRESS_SITE_TITLE:-WordPress FrankenPHP}" \
		--admin_user="${WORDPRESS_ADMIN_USER:-admin}" \
		--admin_password="$WORDPRESS_ADMIN_PASSWORD" \
		--admin_email="${WORDPRESS_ADMIN_EMAIL:-admin@example.com}" \
		--skip-email
}

maybe_enable_redis_plugin() {
	if ! bool_true "${WORDPRESS_INSTALL_REDIS_PLUGIN:-false}"; then
		return 0
	fi

	if ! wp_cmd core is-installed >/dev/null 2>&1; then
		return 0
	fi

	if ! wp_cmd plugin is-installed redis-cache >/dev/null 2>&1; then
		wp_cmd plugin install redis-cache --activate
	else
		wp_cmd plugin activate redis-cache >/dev/null 2>&1 || true
	fi

	wp_cmd redis enable >/dev/null 2>&1 || true
}

main() {
	require_env WORDPRESS_DB_HOST
	require_env WORDPRESS_DB_NAME
	require_env WORDPRESS_DB_USER
	require_env WORDPRESS_DB_PASSWORD
	require_env WORDPRESS_HOME
	require_env WORDPRESS_SITEURL

	mkdir -p "$wp_path"
	wait_for_database

	# The cron container shares the WordPress volume. It must not rewrite
	# wp-config.php concurrently with the web container during daemon startup.
	if [ "${1:-}" = "wp-cron-runner" ]; then
		wait_for_wordpress_files
		exec "$@"
	fi

	install_wordpress_core
	maybe_install_site
	maybe_enable_redis_plugin

	exec "$@"
}

main "$@"
