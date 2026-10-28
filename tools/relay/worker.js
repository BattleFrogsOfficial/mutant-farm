// Mutant Farm weather relay: a Cloudflare Worker (free tier) that forwards the game's weather
// alerts to a Discord channel. Roblox servers can't call Discord directly; they POST here.
//
//   POST /weather   JSON { event, startsAt, key?, link? }   header X-Relay-Key (or body.key)
//
// Bindings (see README.md): secret RELAY_KEY (must match the Roblox secret WEATHER_RELAY_KEY),
// secret DISCORD_WEBHOOK (the channel's webhook URL), KV namespace POSTED (dedupe), optional var
// GAME_LINK (used when the request has no link).
//
// Every server of the game runs the same schedule, so several may report the same event; the game
// already lets only one post (a MemoryStore claim). This drops repeats too: the first POST for a
// startsAt is forwarded, any other for the same startsAt within an hour is answered "duplicate".

const EVENTS = {
  GlitchStorm: { emoji: "🟣", name: "Glitch Storm", mutation: "Glitched", multiplier: 25 },
  AcidRain: { emoji: "🟢", name: "Acid Rain", mutation: "Radioactive", multiplier: 10 },
  SolarFlare: { emoji: "🟡", name: "Solar Flare", mutation: "Golden", multiplier: 5 },
};

const DEDUPE_SECONDS = 3600;

function reply(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// Same-length strings compared without an early exit (the key is a shared secret).
function sameKey(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export function message(event, link) {
  const e = EVENTS[event];
  return `${e.emoji} ${e.name} hits every farm in 5 minutes! ${e.mutation} x${e.multiplier} odds — get your eggs planted. ${link || ""}`.trim();
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/weather") return reply(404, { error: "not found" });
    if (request.method !== "POST") return reply(405, { error: "POST only" });
    let body;
    try {
      body = await request.json();
    } catch {
      return reply(400, { error: "body must be JSON" });
    }
    const key = request.headers.get("X-Relay-Key") || body.key;
    if (!env.RELAY_KEY || !sameKey(key, env.RELAY_KEY)) return reply(401, { error: "bad key" });
    const startsAt = Number(body.startsAt);
    if (!EVENTS[body.event] || !Number.isInteger(startsAt)) return reply(400, { error: "need event and startsAt" });

    const dedupeKey = `weather:${startsAt}`;
    if (await env.POSTED.get(dedupeKey)) return reply(200, { posted: false, duplicate: true });
    await env.POSTED.put(dedupeKey, "1", { expirationTtl: DEDUPE_SECONDS });

    const res = await fetch(env.DISCORD_WEBHOOK, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content: message(body.event, body.link || env.GAME_LINK) }),
    });
    if (!res.ok) {
      await env.POSTED.delete(dedupeKey); // let a retry through
      return reply(502, { error: `discord answered ${res.status}` });
    }
    return reply(200, { posted: true });
  },
};
