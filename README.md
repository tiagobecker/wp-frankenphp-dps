# WordPress FrankenPHP DPS

Stack de produção para WordPress em Docker Compose, usando FrankenPHP com PHP 8.5, MariaDB, Redis e volumes Docker nomeados.

## Estrutura

- `docker-compose.yml`: serviços `wordpress`, `wp-cron`, `mariadb` e `redis`.
- `.env.example`: template documentado para o campo `Environment variables template` do Dokploy Provisioner.
- `dokploy.env.example`: mesma base em formato direto `KEY=value` para copiar e colar.
- `frankenphp/`: imagem customizada, Caddyfile, PHP ini e scripts de boot.

## Deploy No Dokploy

1. Crie uma aplicação Docker Compose no Dokploy apontando para este repositório.
2. No plugin Dokploy Provisioner, cole `dokploy.env.example` no campo `Environment variables template`.
3. Use `docker-compose.yml` como Compose path.
4. Use o método Docker Compose, não Docker Stack, porque a imagem FrankenPHP é construída pelo `build`.
5. Na aba Domains do Dokploy, aponte o domínio para o serviço `wordpress` na porta `80`.

O Compose usa `expose: 80` em vez de publicar portas no host. O HTTPS deve ficar no Traefik/Dokploy, e o Caddy interno roda em HTTP com `SERVER_NAME=:80`.

## Recursos E Planos

Os limites de CPU e memória são controlados por variáveis:

- CPU/memória: `WORDPRESS_CPUS`, `WORDPRESS_MEMORY_LIMIT`, `MARIADB_CPUS`, `MARIADB_MEMORY_LIMIT`, `REDIS_CPUS`, `REDIS_MEMORY_LIMIT`.
- FrankenPHP/PHP: `FRANKENPHP_NUM_THREADS`, `FRANKENPHP_MAX_THREADS`, `PHP_MEMORY_LIMIT`, `GOMEMLIMIT`.

Mantenha `FRANKENPHP_NUM_THREADS * PHP_MEMORY_LIMIT` abaixo da memória disponível para o container `wordpress`.

## Primeiro Boot

No primeiro boot, o entrypoint baixa o WordPress no volume `wordpress_data`, cria `wp-config.php`, configura URLs, Redis, salts e ajustes para proxy HTTPS.

Se `WORDPRESS_AUTO_INSTALL=false`, finalize pelo instalador web do WordPress. Se `WORDPRESS_AUTO_INSTALL=true`, defina também `WORDPRESS_ADMIN_PASSWORD`.

## Volumes

Os volumes usam `driver: local` por padrão. O compose não define `driver_opts`, porque opções como `size` e `inodes` quebram o driver local em Docker/Dokploy.

```yaml
volumes:
  wordpress_data:
    driver: ${DPS_VOLUME_DRIVER:-local}
```

Se você usar um driver customizado, defina `DPS_VOLUME_DRIVER` no template somente depois de validar que o driver aceita volumes sem `driver_opts`.

Para validar o volume dentro de um container:

```sh
df -h /app/public
df -i /app/public
```

## Local

Para testar localmente, copie o exemplo e substitua os placeholders `{{...}}` por valores reais:

```sh
cp .env.example .env
docker compose up --build
```
