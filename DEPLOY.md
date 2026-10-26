# Deployment Guide — Podman (Two Containers)

## Architecture

```
[Browser]
    │  port 80 (or 3000)
    ▼
┌──────────────────────────────┐
│  web  (nginx)  — frontend    │  ← dispute-frontend image
│  /api/* → proxy → api:8000   │
└──────────┬───────────────────┘
           │  dispute-net (internal)
           ▼
┌──────────────────────────────┐
│  api  (uvicorn:8000)         │  ← dispute-backend image
│  SQLite + FAISS + AI agent   │
└──────────────────────────────┘
```

- **Only port 80** (or 3000) is exposed to the host. The backend port 8000 stays internal.
- Frontend calls `/api/v1/...` → nginx proxies to `http://api:8000` → backend.
- `dispute-data` volume holds the SQLite database and FAISS indices (persists across restarts).
- `dispute-storage` volume holds uploaded dispute PDFs (persists across restarts).

---

## Step 0 — Copy project to server

```bash
# Option A: scp
scp -r ./dispute_system user@SERVER_IP:/opt/dispute_system

# Option B: git
git clone <repo-url> /opt/dispute_system

cd /opt/dispute_system
```

---

## Step 1 — Configure server.env

```bash
cp backend/server.env.example backend/server.env
```

Edit `backend/server.env` and fill in **only these values** (everything else comes from `.env`):

| Variable           | What to set                                      |
|--------------------|--------------------------------------------------|
| `LITELLM_BASE_URL` | Your server's LiteLLM proxy URL                  |
| `LITELLM_API_KEY`  | Your API key for that proxy                      |
| `LLM_MODEL`        | Chat model name (e.g. `azure/gpt-4o`)            |
| `EMBED_MODEL`      | Embedding model name                             |
| `GEMINI_MODEL`     | Vision model (default `gemini-2.5-flash` is fine)|
| `CORS_ORIGINS`     | `http://YOUR-SERVER-IP` or `https://your-domain` |
| `API_SECRET_KEY`   | Random 32+ char string (run `openssl rand -hex 32`)|
| `JWT_SECRET_KEY`   | Another random 32+ char string                   |

> `server.env` is loaded **after** `.env`, so its values win for any key that appears in both files.

---

## Step 2 — Create network and volumes

```bash
podman network create dispute-net

podman volume create dispute-data     # SQLite DB + FAISS indices
podman volume create dispute-storage  # Uploaded dispute documents
```

---

## Step 3 — Build images

```bash
# Build backend image
podman build -t dispute-backend:latest ./backend

# Build frontend image
podman build -t dispute-frontend:latest ./frontend
```

---

## Step 4 — Run containers

### Backend (named `api` — nginx.conf resolves it at http://api:8000)

```bash
podman run -d \
  --name api \
  --network dispute-net \
  --env-file ./backend/.env \
  --env-file ./backend/server.env \
  -v dispute-data:/app/data:Z \
  -v dispute-storage:/app/storage:Z \
  dispute-backend:latest
```

> `:Z` is required on RHEL/Fedora/CentOS for SELinux relabelling.
> On Ubuntu/Debian, remove the `:Z` if you get volume permission errors.

### Frontend (exposed on port 80)

```bash
podman run -d \
  --name web \
  --network dispute-net \
  -p 80:80 \
  dispute-frontend:latest
```

> To use a different host port (e.g., 3000): change `-p 80:80` to `-p 3000:80`.
> Then update `CORS_ORIGINS=http://YOUR-IP:3000` in `server.env` and restart the backend.

---

## Step 5 — First-time database setup

Run these once after the backend container starts:

```bash
podman exec api python scripts/seed_admin.py
podman exec api python scripts/seed_demo.py
podman exec api python scripts/seed_merchant.py
podman exec api python scripts/seed_evidence_requirements.py
```

Access the app at `http://YOUR-SERVER-IP` (or `:3000` if you used that port).

Default login credentials:
- Analyst:          `analyst` / `Analyst@123!`
- Merchant analyst: `merchant_analyst` / `MerchantAnalyst@123!`
- Admin:            `admin` / `Admin@12345!`

---

## Optional — Mock server (if real external APIs are not yet available)

If you need the mock server for Merchant/Issuer/Carrier/Auth/Network APIs:

```bash
podman run -d \
  --name mock \
  --network dispute-net \
  --env-file ./backend/.env \
  dispute-backend:latest \
  uvicorn mock_server.main:app --host 0.0.0.0 --port 8100
```

Add to `server.env` (or keep defaults in `.env`):
```
MERCHANT_API_URL=http://mock:8100/merchant
ISSUER_API_URL=http://mock:8100/issuer
CARRIER_API_URL=http://mock:8100/carrier
AUTH_API_URL=http://mock:8100/auth-system
NETWORK_API_URL=http://mock:8100/network
```

---

## Day-to-day operations

```bash
# View logs
podman logs -f api
podman logs -f web

# Restart a container
podman restart api
podman restart web

# Check running containers
podman ps

# Stop everything
podman stop api web
podman rm api web
```

---

## Rebuild and redeploy (after code changes)

```bash
# Backend only
podman stop api && podman rm api
podman build -t dispute-backend:latest ./backend
podman run -d --name api --network dispute-net \
  --env-file ./backend/.env \
  --env-file ./backend/server.env \
  -v dispute-data:/app/data:Z \
  -v dispute-storage:/app/storage:Z \
  dispute-backend:latest

# Frontend only
podman stop web && podman rm web
podman build -t dispute-frontend:latest ./frontend
podman run -d --name web --network dispute-net \
  -p 80:80 \
  dispute-frontend:latest
```

---

## Auto-start on server reboot (systemd — rootless Podman)

```bash
# Generate systemd units for each container
mkdir -p ~/.config/systemd/user

podman generate systemd --name api --files --new
podman generate systemd --name web --files --new

mv container-api.service ~/.config/systemd/user/
mv container-web.service ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable --now container-api.service
systemctl --user enable --now container-web.service

# Allow services to run without login session
loginctl enable-linger $USER
```

---

## Changing LLM settings later

Only edit `backend/server.env`, then restart the backend container:

```bash
# Edit
nano backend/server.env

# Restart
podman restart api

# Or full rebuild if code changed
podman stop api && podman rm api
podman build -t dispute-backend:latest ./backend
podman run -d --name api --network dispute-net \
  --env-file ./backend/.env \
  --env-file ./backend/server.env \
  -v dispute-data:/app/data:Z \
  -v dispute-storage:/app/storage:Z \
  dispute-backend:latest
```

You never touch `.env` or any code — only `server.env`.
