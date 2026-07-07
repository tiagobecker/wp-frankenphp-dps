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
- Cron WordPress: `WORDPRESS_CRON_INTERVAL`, `WP_CRON_CPUS`, `WP_CRON_MEMORY_LIMIT`, `WP_CRON_PHP_MEMORY_LIMIT`.

Mantenha `FRANKENPHP_NUM_THREADS * PHP_MEMORY_LIMIT` abaixo da memória disponível para o container `wordpress`.

O serviço `wp-cron` é um worker WP-CLI e não sobe Caddy/FrankenPHP. Por isso ele desabilita healthcheck explicitamente: um healthcheck HTTP como `/healthz` sempre falharia nesse container, mesmo com o cron funcionando.

## Primeiro Boot

No primeiro boot, o entrypoint baixa o WordPress no volume `wordpress_data`, cria `wp-config.php`, configura URLs, Redis, salts e ajustes para proxy HTTPS.

Se `WORDPRESS_AUTO_INSTALL=false`, finalize pelo instalador web do WordPress. Se `WORDPRESS_AUTO_INSTALL=true`, defina também `WORDPRESS_ADMIN_PASSWORD`.

O entrypoint aguarda MariaDB sem limite por padrão (`STARTUP_WAIT_TIMEOUT=0`). Isso é intencional: uma demora na rede, no volume DPS ou no banco após reiniciar o host mantém o processo vivo até a dependência voltar. Defina um valor em segundos somente se preferir falhar e deixar `restart: always` criar uma nova tentativa.

## Recuperação Após Reboot Do Host

O status `Exited (255)` em todos os quatro serviços não é causado pelo healthcheck. O Docker apenas registra o estado `healthy/unhealthy`; ele não encerra o container. Como todos os serviços desta stack montam um volume DPS, a causa mais provável é o Docker tentar montar os volumes antes de o driver estar pronto. A mesma falha pode acontecer se a rede do Docker ainda não estiver disponível.

Esta stack usa quatro proteções:

- `restart: always` em todos os serviços;
- healthchecks com `start_period` maior para hosts lentos;
- dependências iniciadas sem bloquear o comando do Dokploy até ficarem saudáveis;
- espera interna por MariaDB no `wordpress` e `wp-cron`, sem corrida para alterar `wp-config.php`.

Uma falha que acontece antes de o processo do container iniciar, como erro no `VolumeDriver.Mount`, não pode ser corrigida de dentro do Compose. Para esse caso, instale no host Ubuntu o recuperador systemd incluído neste repositório. Ele espera Docker, tenta iniciar MariaDB/Redis até os volumes montarem e só então inicia WordPress e cron:

```sh
sudo install -m 0755 ops/wp-frankenphp-recover /usr/local/sbin/wp-frankenphp-recover
sudo install -m 0644 ops/wp-frankenphp-recovery@.service /etc/systemd/system/wp-frankenphp-recovery@.service
sudo systemctl daemon-reload
sudo systemctl enable "wp-frankenphp-recovery@SEU_COMPOSE_PROJECT_NAME.service"
```

Use exatamente o valor efetivo de `COMPOSE_PROJECT_NAME`. Para testar sem reiniciar:

```sh
sudo systemctl start "wp-frankenphp-recovery@SEU_COMPOSE_PROJECT_NAME.service"
sudo journalctl -u "wp-frankenphp-recovery@SEU_COMPOSE_PROJECT_NAME.service" -n 100 --no-pager
```

Se continuar em `Exited (255)`, capture o erro do runtime, que é mais útil que o exit code:

```sh
docker inspect --format '{{json .State}}' NOME_DO_CONTAINER
docker plugin ls
docker volume inspect NOME_DO_VOLUME
sudo journalctl -u docker -b --no-pager | tail -n 300
```

Procure especialmente por `error while mounting volume`, `plugin ... not found`, `network not found`, corrupção no MariaDB ou OOM. O recuperador trata indisponibilidade transitória; ele não mascara corrupção de dados nem falta permanente do plugin DPS.

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
