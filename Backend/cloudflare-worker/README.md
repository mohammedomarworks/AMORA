# AMORA — GitHub OAuth Token Exchange Backend

This Cloudflare Worker handles secure token exchange between the native AMORA macOS application and GitHub using the standard OAuth 2.0 authorization code flow with PKCE S256.

By terminating the exchange in this lightweight Worker, your GitHub App's **Client Secret** remains completely secure in Cloudflare Secrets and is **never bundled or reverse-engineered from the macOS application binary**.

---

## 1. Prerequisites

1. [Node.js](https://nodejs.org) (v18+)
2. [Cloudflare Account](https://cloudflare.com)
3. Cloudflare Wrangler CLI:
   ```bash
   npm install -g wrangler
   ```

---

## 2. GitHub OAuth App / GitHub App Registration

1. Visit [GitHub Developer Settings](https://github.com/settings/developers).
2. Click **New OAuth App** (or **New GitHub App**).
3. Fill out the application details:
   * **Application name:** `AMORA Companion`
   * **Homepage URL:** `https://github.com` (or your landing page)
   * **Authorization callback URL:**
     ```text
     http://127.0.0.1/callback
     ```
     *(GitHub supports ephemeral ports on `127.0.0.1`, matching any port requested by the native loopback listener).*
4. Click **Register application**.
5. Note your **Client ID** (e.g. `Ov23li...`).
6. Click **Generate a new client secret** and copy your **Client Secret**.

---

## 3. Configuration & Deployment

1. Navigate to this directory:
   ```bash
   cd Backend/cloudflare-worker
   npm install
   ```

2. Set your GitHub Client Secret in Cloudflare:
   ```bash
   npx wrangler secret put GITHUB_CLIENT_SECRET
   ```
   *(When prompted, paste your secret).*

3. Optionally set your Client ID in `wrangler.toml` under `[vars]`:
   ```toml
   [vars]
   GITHUB_CLIENT_ID = "Ov23li..."
   ```

4. Deploy to Cloudflare Workers:
   ```bash
   npx wrangler deploy
   ```

5. Once deployed, Cloudflare will output your worker endpoint URL, e.g.:
   `https://amora-github-auth.<your-subdomain>.workers.dev`

---

## 4. Connecting to AMORA macOS App

Set your deployed endpoint in AMORA:
* Either via environment variable:
  ```bash
  export AMORA_GITHUB_BACKEND_URL="https://amora-github-auth.<your-subdomain>.workers.dev/api/github/token"
  export AMORA_GITHUB_CLIENT_ID="Ov23li..."
  ```
* Or by updating `GitHubConfig.defaultBackendURL` and `GitHubConfig.defaultClientId` in `GitHubAuth.swift`.

---

## 5. Endpoints

* `GET /health` — Health check & configuration status
* `POST /api/github/token` — Exchanges authorization code + PKCE verifier for GitHub access token
