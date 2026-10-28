# Weather relay (Discord)

Roblox game servers can't post to Discord directly, so a tiny Cloudflare Worker (free tier) sits in
between. Five minutes before every **Glitch Storm**, exactly one game server (a MemoryStore claim in
`WeatherService`) posts to the Worker, which forwards one message to your Discord channel:

> 🟣 Glitch Storm hits every farm in 5 minutes! Glitched x25 odds — get your eggs planted. https://www.roblox.com/games/…

The weather schedule is the same on every server (`src/shared/Weather.lua`), so the alert is the same
for every player wherever they are.

## Request

`POST /weather` with JSON `{ "event": "GlitchStorm", "startsAt": 1793500300, "link": "https://…" }`
and the shared key in the `X-Relay-Key` header (or as `"key"` in the JSON). The game sends the key as
a header because Roblox secrets can only be placed in headers or URLs, not in a request body.

Answers: `200 {posted:true}`, `200 {posted:false, duplicate:true}` (same `startsAt` already posted in
the last hour, KV namespace `POSTED`), `401` bad key, `400` bad body, `502` Discord refused.

## Set it up (about 10 minutes)

1. **Discord:** in the channel, *Edit Channel → Integrations → Webhooks → New Webhook*, copy its URL.
2. **Worker:** with [Wrangler](https://developers.cloudflare.com/workers/wrangler/) (`npm i -g wrangler`, `wrangler login`):
   ```bash
   cd tools/relay
   wrangler kv namespace create POSTED          # prints an id
   ```
   Create `tools/relay/wrangler.toml` (not committed: it holds your ids):
   ```toml
   name = "mutant-farm-relay"
   main = "worker.js"
   compatibility_date = "2026-10-01"

   [[kv_namespaces]]
   binding = "POSTED"
   id = "<the id printed above>"

   [vars]
   GAME_LINK = "https://www.roblox.com/games/<place id>/Mutant-Farm"
   ```
   Then the two secrets and the deploy:
   ```bash
   wrangler secret put RELAY_KEY          # make up a long random string; you'll paste it into Roblox too
   wrangler secret put DISCORD_WEBHOOK    # the webhook URL from step 1
   wrangler deploy                        # prints https://mutant-farm-relay.<you>.workers.dev
   ```
   (The Cloudflare dashboard works too: *Workers → Create → paste worker.js*, add the KV binding
   `POSTED`, the secrets and the `GAME_LINK` variable under *Settings*.)
3. **Test it:**
   ```bash
   curl -X POST https://mutant-farm-relay.<you>.workers.dev/weather \
     -H "Content-Type: application/json" -H "X-Relay-Key: <RELAY_KEY>" \
     -d '{"event":"GlitchStorm","startsAt":1}'
   ```
   The message should appear in Discord; the same command again answers `duplicate`.
4. **Roblox:**
   - *Creator Hub → your experience → Secrets*: add `WEATHER_RELAY_KEY` = the same RELAY_KEY, with
     the domain restricted to `*.workers.dev`.
   - *Game Settings → Security*: turn on **Allow HTTP Requests**.
   - `src/shared/Config/Game.lua`: `relayUrl = "https://mutant-farm-relay.<you>.workers.dev/weather"`
     and `gameLink` = your game's page.

With `relayUrl = ""`, no secret, or HTTP off, the game skips the post and logs one warning per
server (`[Weather] Discord relay skipped: …`). Nothing else depends on it.

## Local check

`node tools/relay/test.mjs` runs the Worker against a fake KV and a fake Discord (keys, dedupe,
message text).
