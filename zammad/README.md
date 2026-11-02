# Zammad – Docker Compose setup

Self-hosted [Zammad](https://zammad.org) helpdesk. It's a slimmed-down version of the
official `zammad-docker-compose` stack.

## Services

| Service                | Role                                              |
|------------------------|---------------------------------------------------|
| `zammad-nginx`         | Web entrypoint, published on `localhost:8080`     |
| `zammad-railsserver`   | Rails app (REST API + UI)                         |
| `zammad-websocket`     | Live updates in the browser                       |
| `zammad-scheduler`     | Background jobs (mail fetching, triggers, SLAs)   |
| `zammad-init`          | One-shot: DB migrations, seeds, search index      |
| `zammad-backup`        | Daily DB + file backup into `zammad-backup` volume |
| `zammad-postgresql`    | PostgreSQL 17 database                            |
| `zammad-elasticsearch` | Full-text search                                  |
| `zammad-redis`         | Websocket / job coordination                      |
| `zammad-memcached`     | Cache                                             |

## Requirements

- Docker + Docker Compose v2
- At least 4 GB of free RAM (Elasticsearch alone uses 1 GB heap)
- Linux host: `vm.max_map_count >= 262144` for Elasticsearch
  (`sudo sysctl -w vm.max_map_count=262144`)

## Quick start

```bash
cp .env.example .env        # then set a real POSTGRES_PASS
docker compose up -d
docker compose logs -f zammad-init   # wait until it exits with code 0
```

Open <http://localhost:8080>. The `zammad-seed` service has already skipped the setup
wizard, created the accounts below, and loaded the teamwork-attendance tickets from
`seed/tickets.json`.

## Seeded accounts and tickets

| Login                   | Role          | Default password  |
|-------------------------|---------------|-------------------|
| `admin@example.com`     | Admin + Agent | `Admin2026!Pass`  |
| `genanomer99@gmail.com` | Agent         | `Teamwork2026!`   |
| `guzhansofia@gmail.com` | Agent         | `Teamwork2026!`   |

Agents have full access to the `Users` group, so they can take, update and close the tickets.
Override the passwords with `SEED_ADMIN_PASSWORD` / `SEED_AGENT_PASSWORD` in `.env` before
the first start, and change them in the UI afterwards.

- **Add a person:** add them to `seed/users.json` and run `docker compose run --rm zammad-seed`.
- **Update the shipped tickets** after adding new ones in the UI:
  `docker compose run --rm --no-deps zammad-seed bundle exec rails r /opt/zammad-seed/export.rb`,
  then commit `seed/tickets.json`.

The seed can run more than once: it updates existing users without changing their
passwords and skips tickets whose title already exists.

## Everyday commands

```bash
docker compose ps                       # status
docker compose logs -f zammad-railsserver
docker compose stop / start             # pause without losing data
docker compose down                     # remove containers, keep volumes/data
docker compose down -v                  # ⚠ delete EVERYTHING incl. database

# Rails console (e.g. to reset a password)
docker compose exec zammad-railsserver rails c
#   u = User.find_by(email: 'admin@example.com'); u.password = 'NewPass123!'; u.save!

# Rebuild the search index
docker compose exec zammad-railsserver rake zammad:searchindex:rebuild
```

## Backups

`zammad-backup` writes a DB dump and a file archive every day at `BACKUP_TIME`, and
keeps them for `HOLD_DAYS` days. To list them:

```bash
docker compose exec zammad-backup ls -lh /var/tmp/zammad
```

## Configuration

All settings live in `.env` (see `.env.example`):

- `ZAMMAD_PORT` – host port for the UI
- `VERSION` – Zammad image tag. Upgrade with `docker compose pull && docker compose up -d`
- `POSTGRES_*` – DB credentials. Set these **before** the first start, because Postgres
  only reads them when it initializes an empty volume
- `ELASTICSEARCH_ENABLED=false` – run without Elasticsearch on low-RAM machines. Search
  is then limited, and you should also remove `zammad-elasticsearch` from
  `zammad-init`'s `depends_on`

For HTTPS behind a reverse proxy, set `ZAMMAD_FQDN`, `ZAMMAD_HTTP_TYPE=https`, and
`NGINX_SERVER_SCHEME=https`.
