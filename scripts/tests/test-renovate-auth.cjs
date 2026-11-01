const assert = require("node:assert/strict");
const { generateKeyPairSync, verify } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { runInNewContext } = require("node:vm");

const source = readFileSync(
  join(__dirname, "../../kubernetes/apps/default/renovate/app/github-app-token.cjs"),
  "utf8",
);
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const credentials = {
  APP_ID: "123\n",
  APP_INSTALLATION_ID: "456\n",
  APP_PRIVATE_KEY: privateKey.export({ type: "pkcs8", format: "pem" }),
};

async function run(fetch, overrides = {}) {
  const result = { stdout: "", stderr: "", exitCode: 0 };
  const process = {
    stdout: { write: (value) => { result.stdout += value; } },
    set exitCode(value) { result.exitCode = value; },
  };
  await runInNewContext(source, {
    require: (name) => name === "node:fs"
      ? { readFileSync: (path) => ({ ...credentials, ...overrides })[path.split("/").pop()] }
      : require(name),
    Buffer,
    AbortSignal,
    fetch,
    process,
    console: { error: (value) => { result.stderr += value; } },
  });
  return result;
}

test("signs a valid App JWT and exchanges it for an installation token", async () => {
  let requests = 0;
  const result = await run(async (url, options) => {
    requests += 1;
    assert.equal(url, "https://api.github.com/app/installations/456/access_tokens");
    assert.equal(options.method, "POST");
    assert.equal(options.headers["X-GitHub-Api-Version"], "2022-11-28");
    const [header, payload, signature] = options.headers.Authorization.slice(7).split(".");
    assert.equal(JSON.parse(Buffer.from(header, "base64url")).alg, "RS256");
    assert.ok(verify(
      "RSA-SHA256",
      Buffer.from(`${header}.${payload}`),
      publicKey,
      Buffer.from(signature, "base64url"),
    ));
    const claims = JSON.parse(Buffer.from(payload, "base64url"));
    const now = Math.floor(Date.now() / 1000);
    assert.equal(claims.iss, "123");
    assert.ok(claims.iat <= now && claims.iat >= now - 65);
    assert.ok(claims.exp > now && claims.exp <= now + 540);
    return { ok: true, json: async () => ({ token: "ghs_test-installation-token" }) };
  });
  assert.equal(requests, 1);
  assert.equal(result.stdout, "ghs_test-installation-token");
  assert.equal(result.stderr, "");
  assert.equal(result.exitCode, 0);
});

test("rejects invalid IDs before requesting a token", async () => {
  const result = await run(() => { throw new Error("must not call GitHub"); }, {
    APP_INSTALLATION_ID: "invalid/path",
  });
  assert.equal(result.stdout, "");
  assert.equal(result.exitCode, 1);
  assert.match(result.stderr, /must be numeric/);
});

test("fails without printing the API body or credentials", async () => {
  const result = await run(async () => ({
    ok: false,
    status: 401,
    json: async () => { throw new Error("response body must not be read"); },
  }));
  assert.equal(result.stdout, "");
  assert.equal(result.exitCode, 1);
  assert.match(result.stderr, /HTTP 401/);
  assert.ok(!result.stderr.includes("PRIVATE KEY"));
});

test("rejects missing tokens and reports network failures", async () => {
  for (const fetch of [
    async () => ({ ok: true, json: async () => ({}) }),
    async () => { throw new Error("connection timed out"); },
  ]) {
    const result = await run(fetch);
    assert.equal(result.stdout, "");
    assert.equal(result.exitCode, 1);
    assert.match(result.stderr, /GitHub App authentication failed/);
  }
});
