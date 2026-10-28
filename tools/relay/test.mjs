// Tests the relay Worker locally with a fake KV and a fake Discord: node tools/relay/test.mjs
import assert from "node:assert/strict";
import worker, { message } from "./worker.js";

const posts = [];
globalThis.fetch = async (url, init) => {
  posts.push({ url, body: JSON.parse(init.body) });
  return new Response(null, { status: 204 }); // what Discord answers a webhook post
};
const kv = new Map();
const env = {
  RELAY_KEY: "s3cret",
  DISCORD_WEBHOOK: "https://discord.test/api/webhooks/1/abc",
  GAME_LINK: "https://www.roblox.com/games/1/Mutant-Farm",
  POSTED: {
    get: async (k) => kv.get(k) ?? null,
    put: async (k, v, opts) => {
      assert.equal(opts.expirationTtl, 3600);
      kv.set(k, v);
    },
    delete: async (k) => kv.delete(k),
  },
};
const call = (body, headers = {}, method = "POST", path = "/weather") =>
  worker.fetch(new Request(`https://relay.test${path}`, { method, headers: { "Content-Type": "application/json", ...headers }, body: method === "POST" ? JSON.stringify(body) : undefined }), env);

let r = await call({ event: "GlitchStorm", startsAt: 1793500000 }, { "X-Relay-Key": "wrong" });
assert.equal(r.status, 401, "wrong key refused");
r = await call({ event: "GlitchStorm", startsAt: 1793500000 });
assert.equal(r.status, 401, "missing key refused");
r = await call({ event: "Nope", startsAt: 1793500000 }, { "X-Relay-Key": "s3cret" });
assert.equal(r.status, 400, "unknown event refused");
assert.equal((await call({}, {}, "GET")).status, 405);
assert.equal((await call({}, {}, "POST", "/other")).status, 404);
assert.equal(posts.length, 0);

r = await call({ event: "GlitchStorm", startsAt: 1793500000, link: "https://www.roblox.com/games/2/x" }, { "X-Relay-Key": "s3cret" });
assert.equal(r.status, 200);
assert.deepEqual(await r.json(), { posted: true });
assert.equal(posts.length, 1);
assert.equal(posts[0].url, env.DISCORD_WEBHOOK);
assert.equal(posts[0].body.content, "🟣 Glitch Storm hits every farm in 5 minutes! Glitched x25 odds — get your eggs planted. https://www.roblox.com/games/2/x");

// The same startsAt again (another server, or a retry): dropped. Key in the body works too.
r = await call({ event: "GlitchStorm", startsAt: 1793500000, key: "s3cret" });
assert.deepEqual(await r.json(), { posted: false, duplicate: true });
assert.equal(posts.length, 1);

// A different event time goes through; no link in the request = GAME_LINK.
r = await call({ event: "GlitchStorm", startsAt: 1793501500, key: "s3cret" });
assert.equal(posts.length, 2);
assert.ok(posts[1].body.content.endsWith(env.GAME_LINK));
assert.equal(message("GlitchStorm", ""), "🟣 Glitch Storm hits every farm in 5 minutes! Glitched x25 odds — get your eggs planted.");
console.log("relay worker: all checks passed");
