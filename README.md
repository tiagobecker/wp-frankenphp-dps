# WordPress FrankenPHP DPS

Stack de produção para WordPress em Docker Compose, usando FrankenPHP com PHP 8.5, MariaDB, Redis e volumes limitados pelo Docker Plugin Storage (DPS).

## Estrutura

- `docker-compose.yml`: serviços `wordpress`, `wp-cron`, `mariadb` e `redis`.
- `docker-compose.local.yml`: fallback local sem DPS para desenvolvimento e diagnóstico.
- `.env.example`: template documentado para o campo `Environment variables template` do Dokploy Provisioner.
- `dokploy.env.example`: mesma base em formato direto `KEY=value` para copiar e colar.
- `frankenphp/`: imagem customizada, Caddyfile, PHP ini e scripts de boot.

## Deploy No Dokploy

1. Instale e valide o plugin Docker DPS no host Dokploy.
2. Crie uma aplicação Docker Compose no Dokploy apontando para este repositório.
3. No plugin Dokploy Provisioner, cole `dokploy.env.example` no campo `Environment variables template`.
4. Use `docker-compose.yml` como Compose path.
5. Use o método Docker Compose, não Docker Stack, porque a imagem FrankenPHP é construída pelo `build`.
6. Na aba Domains do Dokploy, aponte o domínio para o serviço `wordpress` na porta `80`.

O Compose usa `expose: 80` em vez de publicar portas no host. O HTTPS deve ficar no Traefik/Dokploy, e o Caddy interno roda em HTTP com `SERVER_NAME=:80`.

## Recursos E Planos

Os limites de CPU, memória e armazenamento são controlados por variáveis:

- CPU/memória: `WORDPRESS_CPUS`, `WORDPRESS_MEMORY_LIMIT`, `MARIADB_CPUS`, `MARIADB_MEMORY_LIMIT`, `REDIS_CPUS`, `REDIS_MEMORY_LIMIT`.
- DPS/storage: `WORDPRESS_VOLUME_SIZE`, `MARIADB_VOLUME_SIZE`, `REDIS_VOLUME_SIZE` e os respectivos `*_INODES`.
- FrankenPHP/PHP: `FRANKENPHP_NUM_THREADS`, `FRANKENPHP_MAX_THREADS`, `PHP_MEMORY_LIMIT`, `GOMEMLIMIT`.

Mantenha `FRANKENPHP_NUM_THREADS * PHP_MEMORY_LIMIT` abaixo da memória disponível para o container `wordpress`.

## Primeiro Boot

No primeiro boot, o entrypoint baixa o WordPress no volume `wordpress_data`, cria `wp-config.php`, configura URLs, Redis, salts e ajustes para proxy HTTPS.

Se `WORDPRESS_AUTO_INSTALL=false`, finalize pelo instalador web do WordPress. Se `WORDPRESS_AUTO_INSTALL=true`, defina também `WORDPRESS_ADMIN_PASSWORD`.

## Volumes

Os volumes usam `driver: dps` por padrão, com quota e inodes declarados por ambiente:

```yaml
volumes:
  wordpress_data:
    driver: ${DPS_VOLUME_DRIVER:-dps}
    driver_opts:
      size: ${WORDPRESS_VOLUME_SIZE:-10G}
      inodes: "${WORDPRESS_VOLUME_INODES:-500000}"
```

O fallback local existe apenas para desenvolvimento e diagnóstico, usando `docker-compose.local.yml`. O driver local do Docker não aceita as opções `size` e `inodes`, por isso ele precisa de um arquivo separado que remove `driver_opts`.

Para validar o volume dentro de um container:

```sh
df -h /app/public
df -i /app/public
```

## Local

Para testar localmente sem DPS, copie o exemplo, substitua os placeholders `{{...}}` por valores reais e inclua o override local:

```sh
cp .env.example .env
docker compose -f docker-compose.yml -f docker-compose.local.yml up --build
```
