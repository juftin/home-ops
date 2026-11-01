// Exchange the mounted GitHub App credentials for a fresh installation token.
// Only stdout is captured by preCommand; never log credentials or API bodies.
const { readFileSync } = require("node:fs");
const { sign } = require("node:crypto");

async function main() {
  const directory = "/var/run/renovate/github-app";
  const appId = readFileSync(`${directory}/APP_ID`, "utf8").trim();
  const installationId = readFileSync(`${directory}/APP_INSTALLATION_ID`, "utf8").trim();
  const privateKey = readFileSync(`${directory}/APP_PRIVATE_KEY`, "utf8");
  if (!/^\d+$/.test(appId) || !/^\d+$/.test(installationId)) {
    throw new Error("APP_ID and APP_INSTALLATION_ID must be numeric");
  }

  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const payload = [
    encode({ alg: "RS256", typ: "JWT" }),
    encode({ iat: now - 60, exp: now + 540, iss: appId }),
  ].join(".");
  const signature = sign("RSA-SHA256", Buffer.from(payload), privateKey).toString("base64url");
  const response = await fetch(
    `https://api.github.com/app/installations/${installationId}/access_tokens`,
    {
      method: "POST",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${payload}.${signature}`,
        "User-Agent": "home-ops-renovate",
        "X-GitHub-Api-Version": "2022-11-28",
      },
      signal: AbortSignal.timeout(30000),
    },
  );
  if (!response.ok) {
    throw new Error(`GitHub installation token request failed: HTTP ${response.status}`);
  }
  const { token } = await response.json();
  if (typeof token !== "string" || !token.startsWith("ghs_")) {
    throw new Error("GitHub did not return an installation token");
  }
  process.stdout.write(token);
}

main().catch((error) => {
  console.error(`GitHub App authentication failed: ${error.message}`);
  process.exitCode = 1;
});
