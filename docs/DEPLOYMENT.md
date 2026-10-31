# ClubMates QA Deploy
<!-- Repository documentation; excluded from runtime deployment. -->

The QA backend runs on the DigitalOcean droplet at:

- IPv4: `139.59.25.255`
- App path: `/opt/clubmates/Backend`
- Runtime env: `NODE_ENV=qa`
- Runtime: Docker Compose, service `backend`
- Public health check: `https://139.59.25.255/health`

## GitHub Secrets

Add these in GitHub under the `QA` environment:

`Repository > Settings > Environments > QA`

Environment variables:

- `DROPLET_HOST`: `139.59.25.255`
- `DROPLET_USER`: `root`

Environment secret:

- `DROPLET_SSH_KEY`: the private key that can SSH into the droplet

Use this local command to copy the deploy key value:

```sh
pbcopy < ~/.ssh/clubmates_do
```

Paste that full private key into the `DROPLET_SSH_KEY` secret.

## Automatic QA Deploy Flow

When code is merged into `main`, GitHub Actions runs `.github/workflows/deploy-backend.yml`.

The workflow:

1. Checks out the merged `main` code.
2. Installs backend dependencies on the GitHub runner.
3. Runs `npm run build` and `npm test`.
4. Rsyncs `Backend/` to `/opt/clubmates/Backend` on the droplet.
5. Rsyncs `docker-compose.qa.yml` to `/opt/clubmates/docker-compose.qa.yml`.
6. Keeps server-only files on the droplet, including `.env` and `.deepface-home`.
7. Builds the Docker image on the droplet.
8. Starts/recreates the Docker Compose `backend` service.
9. Writes the deployed Git commit to `/opt/clubmates/DEPLOYED_COMMIT`.
10. Waits for `http://127.0.0.1:3001/health` locally on the droplet.

You can also deploy manually from GitHub:

`Actions > Deploy Backend > Run workflow`

## Server Commands

Useful commands:

```sh
ssh -i ~/.ssh/clubmates_do root@139.59.25.255
cd /opt/clubmates
docker compose -f docker-compose.qa.yml ps
docker compose -f docker-compose.qa.yml logs --tail=100 backend
curl http://127.0.0.1:3001/health
curl https://139.59.25.255/health
```

## Docker QA Runtime

The QA compose file is:

```sh
docker-compose.qa.yml
```

It builds `Backend/Dockerfile`, reads runtime env from `Backend/.env`, preserves the DeepFace model cache with `Backend/.deepface-home`, runs database migrations, and starts the backend on port `3001`.

The container uses host networking so it can reach the IPv6-only Supabase database hostname from the droplet.

Droplet smoke test:

```sh
docker compose -f docker-compose.qa.yml build backend
docker compose -f docker-compose.qa.yml up -d backend
curl http://127.0.0.1:3001/health
```

Stop it:

```sh
docker compose -f docker-compose.qa.yml down
```

If the DeepFace cache is empty, pre-warm the model once:

```sh
docker compose -f docker-compose.qa.yml run --rm backend \
  .venv-face/bin/python -c "from deepface import DeepFace; DeepFace.build_model('VGG-Face')"
```

Nginx points public HTTPS traffic to the Docker backend on `127.0.0.1:3001`.

## HTTPS

The current public API URL is HTTPS:

`https://139.59.25.255`

The iOS fallback currently points Debug and Release builds to that droplet URL. You can still override it with the `CLUBMATES_API_BASE_URL` environment or Info.plist value.

The Android debug and release API base URLs currently point to that droplet URL too.

Nginx redirects normal HTTP traffic to HTTPS. The server uses a Let's Encrypt IP-address certificate, which is short-lived, so Certbot renews it frequently and reloads nginx after renewal.

For a more standard production setup later, point a domain or subdomain to the droplet and issue a normal domain certificate.

## QA OTP Bypass

In QA, MSG91 can be disabled and the fixed test OTP can be used instead.

To use the fixed OTP, edit `/opt/clubmates/Backend/.env` on the droplet:

```env
NODE_ENV=qa
DEV_OTP_CODE=123456
# MSG91_AUTH_KEY=...
# MSG91_TEMPLATE_ID=...
# MSG91_SENDER_ID=...
```

Then restart:

```sh
cd /opt/clubmates
docker compose -f docker-compose.qa.yml up -d --force-recreate backend
```

If MSG91 values are present, the backend sends a real random OTP by SMS. If MSG91 values are absent/commented and `NODE_ENV=qa`, the backend uses `DEV_OTP_CODE`.
