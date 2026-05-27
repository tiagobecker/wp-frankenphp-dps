# WordPress FrankenPHP DPS

Stack de produção para WordPress em Docker Compose, usando FrankenPHP com PHP 8.5, MariaDB, Redis e volumes limitados pelo Docker Plugin Storage (DPS).

## Estrutura

- `docker-compose.yml`: serviços `wordpress`, `wp-cron`, `mariadb` e `redis`.
- `.env.example`: variáveis documentadas para copiar ou importar.
- `dokploy.env.example`: mesma base em formato direto `KEY=value` para importadores.
- `frankenphp/`: imagem customizada, Caddyfile, PHP ini e scripts de boot.

## Deploy No Dokploy

1. Instale o DPS no host Docker antes do deploy.
2. Crie uma aplicação Docker Compose no Dokploy apontando para este repositório.
3. Importe `dokploy.env.example` no provisionador e substitua todos os `CHANGE_ME`.
4. Use o método Docker Compose, não Docker Stack, porque a imagem FrankenPHP é construída pelo `build`.
5. Na aba Domains do Dokploy, aponte o domínio para o serviço `wordpress` na porta `80`.

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

## DPS

Os volumes usam `driver: dps` por padrão:

```yaml
volumes:
  wordpress_data:
    driver: dps
    driver_opts:
      size: 10G
      inodes: "500000"
```

Para validar o limite dentro de um container:

```sh
df -h /app/public
df -i /app/public
```

## Local

Para testar localmente com DPS instalado:

```sh
cp .env.example .env
docker compose up --build
```

Sem DPS instalado, crie um override local removendo `driver_opts` ou instale o plugin no host.
