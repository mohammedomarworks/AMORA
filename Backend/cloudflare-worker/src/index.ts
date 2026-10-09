/**
 * AMORA GitHub OAuth Token Exchange Backend
 * Cloudflare Worker handling secure OAuth code & PKCE exchange with GitHub.
 *
 * Keeps GITHUB_CLIENT_SECRET secure in backend environment secrets without
 * embedding it into the macOS client binary.
 */

export interface Env {
  GITHUB_CLIENT_ID?: string;
  GITHUB_CLIENT_SECRET?: string;
}

interface TokenExchangeRequestBody {
  code?: string;
  code_verifier?: string;
  redirect_uri?: string;
  client_id?: string;
}

interface GitHubTokenSuccessResponse {
  access_token: string;
  token_type: string;
  scope: string;
  refresh_token?: string;
  expires_in?: number;
}

interface GitHubTokenErrorResponse {
  error: string;
  error_description?: string;
  error_uri?: string;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, X-Requested-With",
};

function jsonResponse(data: unknown, status: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...CORS_HEADERS,
    },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: CORS_HEADERS,
      });
    }

    // Health check endpoint
    if (request.method === "GET" && (url.pathname === "/health" || url.pathname === "/")) {
      return jsonResponse({
        status: "ok",
        service: "amora-github-oauth-worker",
        configured: Boolean(env.GITHUB_CLIENT_SECRET),
      });
    }

    // Token exchange endpoint: POST /api/github/token or POST /token
    if (request.method === "POST" && (url.pathname === "/api/github/token" || url.pathname === "/token")) {
      return handleTokenExchange(request, env);
    }

    return jsonResponse(
      { error: "not_found", error_description: "Endpoint not found." },
      404
    );
  },
};

async function handleTokenExchange(request: Request, env: Env): Promise<Response> {
  const clientSecret = env.GITHUB_CLIENT_SECRET;
  if (!clientSecret || clientSecret.trim().length === 0) {
    return jsonResponse(
      {
        error: "server_misconfigured",
        error_description: "GITHUB_CLIENT_SECRET secret is not configured in Worker environment.",
      },
      500
    );
  }

  let body: TokenExchangeRequestBody;
  try {
    body = (await request.json()) as TokenExchangeRequestBody;
  } catch {
    return jsonResponse(
      {
        error: "invalid_request",
        error_description: "Malformed JSON payload.",
      },
      400
    );
  }

  const code = body.code?.trim();
  const codeVerifier = body.code_verifier?.trim();
  const redirectUri = body.redirect_uri?.trim();
  const clientId = (body.client_id || env.GITHUB_CLIENT_ID)?.trim();

  if (!code) {
    return jsonResponse(
      { error: "invalid_request", error_description: "Missing 'code' parameter." },
      400
    );
  }

  if (!codeVerifier) {
    return jsonResponse(
      { error: "invalid_request", error_description: "Missing 'code_verifier' parameter." },
      400
    );
  }

  if (!redirectUri) {
    return jsonResponse(
      { error: "invalid_request", error_description: "Missing 'redirect_uri' parameter." },
      400
    );
  }

  if (!clientId) {
    return jsonResponse(
      { error: "invalid_request", error_description: "Missing 'client_id' parameter." },
      400
    );
  }

  try {
    const githubResponse = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "AMORA-OAuth-Worker",
      },
      body: JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        code: code,
        code_verifier: codeVerifier,
        redirect_uri: redirectUri,
      }),
    });

    const data = (await githubResponse.json()) as
      | GitHubTokenSuccessResponse
      | GitHubTokenErrorResponse;

    if ("error" in data) {
      return jsonResponse(data, 400);
    }

    return jsonResponse(data, 200);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse(
      {
        error: "upstream_error",
        error_description: `Failed to exchange token with GitHub: ${message}`,
      },
      502
    );
  }
}
