ARG FRANKENPHP_IMAGE=dunglas/frankenphp:1-php8.5-trixie
FROM ${FRANKENPHP_IMAGE}

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        default-mysql-client \
        less \
        tar \
        unzip; \
    install-php-extensions \
        bcmath \
        exif \
        gd \
        imagick \
        intl \
        mysqli \
        opcache \
        pdo_mysql \
        redis \
        soap \
        sockets \
        zip; \
    curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp; \
    chmod +x /usr/local/bin/wp; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY frankenphp/php.ini /usr/local/etc/php/conf.d/zz-wordpress.ini
COPY frankenphp/Caddyfile /etc/frankenphp/Caddyfile
COPY frankenphp/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY frankenphp/wp-cron-runner.sh /usr/local/bin/wp-cron-runner

RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/wp-cron-runner

WORKDIR /app/public

EXPOSE 80

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]
