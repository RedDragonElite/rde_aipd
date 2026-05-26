# rde_aipd
🔥 ULTIMATE AI POLICE SYSTEM V1.0.5-ALPHA - Built on ox_core & Statebags! 🚨

<img width="1024" height="1024" alt="image" src="https://github.com/user-attachments/assets/7f044614-3c38-4b9e-87ce-40013a560b8a" />

PREVIEW:
https://www.youtube.com/watch?v=mCWg0jZlSbY

# 🐉 rde_aipd

[![Version](https://img.shields.io/badge/version-1.0.5--alpha-red?style=for-the-badge)](https://github.com/RedDragonElite/rde_aipd)
[![License](https://img.shields.io/badge/license-RDE%20Black%20Flag-black?style=for-the-badge)](LICENSE)
[![FiveM](https://img.shields.io/badge/FiveM-Compatible-blue?style=for-the-badge)](https://fivem.net)
[![ox_core](https://img.shields.io/badge/Framework-ox__core-blue?style=for-the-badge)](https://github.com/overextended/ox_core)
[![Nostr](https://img.shields.io/badge/Nostr-Decentralized-purple?style=for-the-badge)](https://github.com/RedDragonElite/rde_nostr_log)
[![Quality](https://img.shields.io/badge/Quality-Production-gold?style=for-the-badge)](https://github.com/RedDragonElite)

**🚨 RDE AIPD | Next-Gen AI Police & Crime System for FiveM ox_core | Ultra-Realistic | StateBag-Synced | Nostr-Logged | Race-Proof | Production-Ready**

*Built by [Red Dragon Elite](https://rd-elite.com) | Free Forever | No Paywalls | No Legacy*

[📖 Installation](#-installation) • [⚙️ Configuration](#️-configuration) • [🌍 Locales](#-locales) • [🐉 Nostr Logging](#-nostr-logging) • [📡 Exports](#-exports) • [🐛 Troubleshooting](#-troubleshooting) • [🌐 Website](https://rd-elite.com) • [🔭 Terminal](https://rd-elite.com/Files/NOSTR/)

---

## 🚑 Hotfix Notice — v1.0.5-alpha (Mandatory if on v1.0.4-alpha)

> **If you pushed v1.0.4-alpha and your jailed players reported a flickering jail-time HUD, this is the fix.** v1.0.4 changed the jail timer's `Wait(0)` to `Wait(100)` on the assumption it was a perf-only loop — but `UI.DrawJailTimer()` uses GTA immediate-mode natives (`DrawRect`, `DrawText`) which only render the exact frame they're called in. At 60 FPS + `Wait(100)`, that's ~6 of every 60 frames visible. Pure flicker. v1.0.5-alpha splits the render and counter logic into two threads — the renderer stays at `Wait(0)` (mandatory for immediate-mode), the counter sleeps 99.9% of the time at `Wait(1000)`. Net result: lower CPU than the original v1.0.0 code, zero flicker.

### What changed in 1.0.5-alpha

| # | Fix | Severity | Impact |
|---|-----|----------|--------|
| **#39** | Jail timer split into two threads — render at `Wait(0)` (immediate-mode required), counter at `Wait(1000)` | 🟠 High | Fixes hard flicker introduced in 1.0.4 by mis-applied perf "fix" #36; also more efficient than v1.0.0's original single-thread code |

> **Lesson logged in the contributing guidelines:** GTA immediate-mode natives (`DrawRect` / `DrawText` / `DrawSprite` / `DrawMarker` / `DisableControlAction`) **must** run on `Wait(0)`. The "always use Wait(N≥10)" rule from RDE OX Standards applies to polling/state/asset loops — not to per-frame rendering. See [Contributing](#-contributing).

---

## 🚑 Hotfix Notice — v1.0.4-alpha (still applies if on 1.0.1/1.0.2/1.0.3)

> The witness handler had a `Debug` cross-file `nil` crash that killed the entire crime path on every server restart since 1.0.2, a silent double-insert bug that doubled every unwitnessed crime in `crime_logs`, and no server-side protection against race-condition or external-resource double-fires. **1.0.5-alpha is a drop-in replacement** — same config, same database schema, same exports. All fixes below are still included.

### What changed in 1.0.4-alpha (still applies)

| # | Fix | Severity | Impact |
|---|-----|----------|--------|
| **#34** | `Debug(...)` was `local` in `server/main.lua`, called from `server/crime_witness_handler.lua` — instant `nil` value crash on first crime | 🔴 Critical | Crime witness path was effectively dead — no wanted level, no police alerts |
| **#35** | Double `table.insert` in `state.crimeHistory` for unwitnessed crimes (both the handler AND `LogCrime()` were inserting) | 🟠 High | Every silent crime counted twice in `/crimes` and `crime_logs` |
| **#36** | `Wait(0)` 60+ fps loop in `Prison.StartTimer` (only needed 1 Hz precision) ⚠️ **superseded by #39 in 1.0.5** | 🟡 Medium | Original intent was CPU savings; turned into flicker regression — fully corrected in 1.0.5 |
| **#37** | `server/nostr.lua` had no `or {}` locale fallback — every `:format()` crashed on missing locale file | 🟠 High | Nostr logging died silently on any locale convar mismatch |
| **#38** | Server-side `CrimeReportCache` (2s dedup window) added to `police:reportCrime` and `police:crimeDetectedNoWitness` | 🟠 High | Race-conditions, external-resource double-fires, and `/testwitness` spam can no longer create duplicate DB rows |
| polish | `Wait(0)` → `Wait(10)` in `LoadAnimDict()` / `LoadModel()` | 🟢 Low | RDE OX Standards compliance — these are asset-load loops, not render loops |

Full details and the legacy duplicate-cleanup SQL in [CHANGELOG.md](CHANGELOG.md).

### What changed in 1.0.1-alpha (still applies)

| # | Fix | Impact |
|---|-----|--------|
| **#30** | 7 truncated `Debug(...)` calls reconstructed in `client/main.lua` & `server/main.lua` | Resource actually loads on every server |
| **#28** | Admin-crime-block now respects `Config.AdminSettings.exemptFromWanted` | Witnesses call 911 again for admin players (default behavior) |
| **#29** | Removed redundant "Witness called 911" notification | 2 notifications per crime instead of 3 |
| **#27** | Locale loader added to all client/server files (was only in `nostr.lua`) | `set ox:locale "en"` / `"de"` now actually works everywhere |

---

## 🔥 Why This Destroys Every Other Police Script

Every other police script is either paid, ESX/QB-only, or a laggy mess with braindead AI.

We said no.

| ❌ Other Police Scripts | ✅ rde_aipd |
|---|---|
| Static wanted levels | Dynamic, decay-based wanted system |
| Dumb AI that just runs at you | True line-of-sight AI with threat assessment |
| Discord webhooks (deletable, bannable) | Decentralized Nostr logging — permanent & uncensorable |
| ESX / QBCore bloat | ox_core only — the future, not the past |
| 0.5ms+ idle resource usage | < 0.01ms idle — aggressive optimization |
| No locale support | Full EN / DE multilanguage |
| Trusts the client blindly | Server-side dedup window — race-proof by design |
| Single-thread render+logic spaghetti | Clean thread separation per concern |
| Paid or locked down | 100% free forever — RDE Black Flag |

### 🎯 Key Features

- 🤖 **True Line-of-Sight AI** — cops only react to what they can actually see
- 🧠 **Threat Assessment** — dynamic threat calculation per unit (weapons, speed, cover, escape history)
- 😮‍💨 **Player Fatigue** — sprint enough and you slow down; cops exploit that
- ⭐ **5 Wanted Levels** — from minor warrant to maximum response with helicopters & roadblocks
- 📉 **Realistic Decay** — wanted level drops only when no officer has eyes on you
- 🥊 **Tackle System** — cops can physically tackle fleeing suspects
- 🚨 **Full Crime Detection** — 13+ crime types, witness system, area multipliers
- 🛡️ **Server-Side Dedup** — race-proof crime reporting with 2s per-player+per-type window
- ⛓ **Prison System** — auto-jail, inventory save/restore, persistent state across reconnects, flicker-free HUD
- 🐉 **Nostr Logging** — decentralized, cryptographically signed, uncensorable server logs
- 🌍 **Multilanguage** — EN / DE out of the box, add any language in minutes
- 🛡 **Server-Side Authority** — all sensitive actions validated server-side, statebag-synced
- ⚙️ **Zero-Config Start** — sensible defaults, tables auto-create, no SQL import needed

---

## 📸 Screenshots

> Coming soon — drop a PR with your screenshots!

---

## 📦 Dependencies

```
oxmysql        → https://github.com/overextended/oxmysql
ox_lib         → https://github.com/overextended/ox_lib
ox_core        → https://github.com/overextended/ox_core
ox_inventory   → https://github.com/overextended/ox_inventory

optional:
rde_nostr_log  → https://github.com/RedDragonElite/rde_nostr_log
```

---

## 🚀 Installation

### Step 1: Clone or download

```bash
cd resources
git clone https://github.com/RedDragonElite/rde_aipd.git
```

> **Already on 1.0.0/1.0.1/1.0.2/1.0.3/1.0.4-alpha?** Just `git pull` — no schema migration, no config changes needed. Restart the resource and you're done. If you want to clean up legacy duplicate rows in `crime_logs`, run the dedup query in [CHANGELOG.md](CHANGELOG.md).

### Step 2: Add to server.cfg

```
# Dependencies first — order matters!
ensure oxmysql
ensure ox_lib
ensure ox_core
ensure ox_inventory

# Optional: Nostr logging (highly recommended)
ensure rde_nostr_log

# The AI police system
ensure rde_aipd
```

### Step 3: Configure

Edit `config.lua` — sensible defaults work out of the box. See [Configuration](#️-configuration).

### Step 4: Start your server

That's it. No SQL import needed — tables auto-create on first run.

---

## ⚙️ Configuration

`config.lua` is fully self-documented. Key sections:

```lua
-- Master debug toggle
Config.Debug = GetConvar('police_debug', 'false') == 'true'

-- Admin groups (exempt from wanted if configured)
Config.AdminGroups = { 'owner', 'admin', 'superadmin', 'god', 'mod' }

-- Police job names
Config.PoliceJobs = { 'police', 'sheriff', 'leo', 'trooper' }

-- Admin behavior
Config.AdminSettings = {
    exemptFromWanted = false,   -- Set true to make admins immune
    exemptFromArrest = false,
    exemptFromJail   = false,
    showAdminCrimes  = true,    -- Still log crimes to console
}

-- Language (override with set ox:locale "de" in server.cfg)
Config.Locale = GetConvar('ox:locale', 'en')
```

> **As of 1.0.1-alpha:** `exemptFromWanted = false` actually means *false* now. In 1.0.0-alpha the client-side crime detection was hard-blocking every non-fatal crime for any admin-group player regardless of this flag. Fixed in [#28](CHANGELOG.md).

### Nostr Config

```lua
Config.Nostr = {
    enabled  = true,
    resource = 'rde_nostr_log',

    logLevel = {
        player_connect    = true,
        player_disconnect = true,
        player_wanted     = true,
        player_arrested   = true,
        player_jailed     = true,
        player_released   = true,
        crime_detected    = true,
        cop_killed        = true,
        admin_action      = true,
    }
}
```

---

## 🌍 Locales

All user-facing text lives in `locales/`. Default is English. Switch language:

```
# server.cfg
set ox:locale "de"
```

> **As of 1.0.4-alpha:** `server/nostr.lua` finally has the `or {}` fallback the other files always had. If `lib.load` couldn't find your locale file in 1.0.0–1.0.3, every Nostr event call would throw — now it falls back to the key name and keeps running. [#37](CHANGELOG.md).

**Add a new language:**

1. Copy `locales/en.lua` → `locales/xx.lua`
2. Translate all values (keep the keys!)
3. Register it in `fxmanifest.lua` under `files {}`
4. Set `ox:locale "xx"` in your server.cfg

> **Translators porting from 1.0.0-alpha:** seven new keys were added in 1.0.1-alpha. See [CHANGELOG.md](CHANGELOG.md) → "Added" section. Missing keys won't crash — they fall back to the key name itself — but the text will look broken.

Currently supported:

| Code | Language |
|------|----------|
| `en` | 🇬🇧 English |
| `de` | 🇩🇪 Deutsch |

---

## 🐉 Nostr Logging

rde_aipd ships with **first-class [rde_nostr_log](https://github.com/RedDragonElite/rde_nostr_log) integration**.

Every critical event is logged to the decentralized Nostr network — permanent, cryptographically signed, uncensorable. No Discord. No rate limits. No single point of failure.

### Events logged automatically

| Event | Nostr Tag | Toggle Key |
|-------|-----------|------------|
| Player joins | `player_connect` | `logLevel.player_connect` |
| Player leaves | `player_disconnect` | `logLevel.player_disconnect` |
| Wanted level change | `wanted_set` | `logLevel.player_wanted` |
| Wanted cleared | `wanted_cleared` | `logLevel.player_wanted` |
| Player arrested | `player_arrested` | `logLevel.player_arrested` |
| Player jailed | `player_jailed` | `logLevel.player_jailed` |
| Player released | `player_released` | `logLevel.player_released` |
| Crime committed | `crime_detected` | `logLevel.crime_detected` |
| Officer killed | `officer_down` | `logLevel.cop_killed` |
| Player surrenders | `player_surrendered` | `logLevel.player_arrested` |
| Player escapes | `player_escaped` | `logLevel.player_wanted` |
| Admin action | `admin_action` | `logLevel.admin_action` |

### Fire events manually from your scripts

```lua
TriggerEvent('police:nostr:wantedSet',    source, level, 'crime')
TriggerEvent('police:nostr:wantedCleared', source)
TriggerEvent('police:nostr:arrested',     source, wantedLevel)
TriggerEvent('police:nostr:jailed',       source, jailTimeSeconds)
TriggerEvent('police:nostr:released',     source)
TriggerEvent('police:nostr:surrendered',  source)
TriggerEvent('police:nostr:crime',        source, 'MURDER', 'CITY_CENTER', true)
TriggerEvent('police:nostr:copKilled',    source)
TriggerEvent('police:nostr:escaped',      source, previousWantedLevel)
TriggerEvent('police:nostr:adminAction',  source, 'clear_wanted', targetPlayerName)
```

### Disable Nostr completely

```lua
Config.Nostr.enabled = false
```

Zero overhead. Zero side effects. The system runs normally.

---

## 📡 Exports

### Client

```lua
-- Read state
exports['rde_aipd']:getWantedLevel()        -- number
exports['rde_aipd']:isArrested()            -- boolean
exports['rde_aipd']:isSurrendered()         -- boolean
exports['rde_aipd']:isJailed()              -- boolean
exports['rde_aipd']:getJailTime()           -- number (seconds)
exports['rde_aipd']:getPursuingUnits()      -- number
exports['rde_aipd']:copsCanSeePlayer()      -- boolean
exports['rde_aipd']:isDecayActive()         -- boolean
exports['rde_aipd']:getPlayerThreatLevel()  -- number (0-100)
exports['rde_aipd']:getPlayerFatigue()      -- number (0-100)

-- Actions
exports['rde_aipd']:setWantedLevel(3)       -- set wanted level (0-5)
exports['rde_aipd']:surrender()             -- trigger surrender
exports['rde_aipd']:clearPolice()           -- despawn all AI units

-- Crime system
exports['rde_aipd']:LogCrime('ROBBERY', coords, true)
exports['rde_aipd']:IsCrimeOnCooldown('MURDER')    -- boolean
exports['rde_aipd']:GetCurrentArea()               -- string, number
```

> **As of 1.0.4-alpha:** External resources calling `exports['rde_aipd']:LogCrime(...)` are now protected by the server-side dedup window. Calling it twice within 2s for the same player + crime_type will silently skip the second call instead of creating duplicate DB rows. If your script needs back-to-back identical crimes, wait at least 2s between calls.

### Server

```lua
-- Fire a custom log into the Nostr channel
exports['rde_aipd']:nostrLog('Custom event message', {
    { 'event', 'my_custom_event' },
    { 'player', playerName }
}, 'crime_detected')
```

---

## 🗂 Folder Structure

```
rde_aipd/
├── fxmanifest.lua
├── config.lua
├── README.md
├── CHANGELOG.md            ← Updated for 1.0.5-alpha
├── LICENSE
├── locales/
│   ├── en.lua              ← English (default)
│   └── de.lua              ← Deutsch
├── server/
│   ├── main.lua            ← Core server logic, callbacks, jail timer
│   ├── crime_witness_handler.lua  ← Witness-based 911 reporting + dedup cache
│   └── nostr.lua           ← Nostr logging integration
├── client/
│   ├── main.lua            ← AI police, wanted system, prison (split-thread timer)
│   └── crime.lua           ← Crime detection & witness system
└── html/
    ├── wanted_stars.html
    ├── star.png
    ├── star2.png
    ├── star3.png
    └── star4.png
```

---

## 🔧 Debug Commands

Enable with `set police_debug "true"` in server.cfg, then in-game:

| Command | Description |
|---------|-------------|
| `debugpolice` | Dump full system state to console |
| `clearcops` | Despawn all pursuing units |
| `testwanted [1-5]` | Set wanted level instantly |
| `spawncop` | Spawn one test unit at current level |
| `testcrime [TYPE]` | Force-trigger a crime (bypasses cooldown) |
| `testwitness [TYPE]` | Force the full witness/911-call flow |
| `crimestatus` | Show current crime system state |
| `listcrimes` | List all registered crime types |
| `testjail [seconds]` | Jail yourself for testing |

**Verify the 1.0.4 dedup fix:**

```
/testwitness ASSAULT       # 1st → "🚨 Crime reported WITH witness"
/testwitness ASSAULT       # within 2s → "🚫 Dedup: ASSAULT ... skipped"
# wait 3s
/testwitness ASSAULT       # goes through again
```

**Verify the 1.0.5 timer fix:**

```
/testjail 60        # jail yourself for 60s
# Jail Time HUD should render smoothly — no flicker, no stutter
```

---

## 🛡 Security

- All sensitive actions validated **server-side**
- StateBags used for realtime sync — no polling
- ox_core group checks on all privileged callbacks
- ACE permission support
- Nostr logs are cryptographically signed — tamper-proof by design
- Minimum jail time enforced server-side (anti 1s-jail exploit)
- **NEW in 1.0.4:** Server-side dedup cache prevents race-condition / external-resource double-inserts in `crime_logs`

---

## 🐛 Troubleshooting

### Jail Time HUD flickers / blinks rapidly

You're on v1.0.4-alpha. The render loop was running at `Wait(100)`, but `DrawRect` and `DrawText` are immediate-mode natives that only render one frame at a time. Update to v1.0.5-alpha. Fixed in [#39](CHANGELOG.md).

### `attempt to call a nil value (global 'Debug')` in crime_witness_handler.lua

You're on 1.0.1/1.0.2/1.0.3-alpha. The `Debug(...)` function was declared `local` in `server/main.lua`, and Lua can't cross-file local references — so the witness handler hit `nil` the moment any crime fired. Update to 1.0.5-alpha. Fixed in [#34](CHANGELOG.md).

### Duplicate rows in `crime_logs` for the same crime + same second

You're on 1.0.1/1.0.2/1.0.3-alpha. Two separate bugs were causing this:

1. **Unwitnessed crimes** (`witnessed=false`): `police:crimeDetectedNoWitness` was double-inserting via both `table.insert(crimeHistory, ...)` AND `LogCrime()`. Fixed in [#35](CHANGELOG.md).
2. **Witnessed crimes** (`witnessed=true`): No server-side dedup protected against client races, external-resource double-fires, or `/testwitness` spam. Fixed in [#38](CHANGELOG.md).

Update to 1.0.5-alpha. To clean up legacy duplicates already in your DB:

```sql
-- Detect
SELECT charid, crime_type,
       JSON_EXTRACT(crime_data, '$.timestamp') AS ts,
       COUNT(*) AS dups,
       GROUP_CONCAT(id ORDER BY id) AS row_ids
FROM crime_logs
WHERE crime_data IS NOT NULL
GROUP BY charid, crime_type, ts
HAVING dups > 1;

-- Delete (keeps earliest ID per pair)
DELETE FROM crime_logs
WHERE id IN (
    SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY charid, crime_type,
                                JSON_EXTRACT(crime_data, '$.timestamp')
                   ORDER BY id ASC
               ) AS rn
        FROM crime_logs
        WHERE crime_data IS NOT NULL
    ) t
    WHERE rn > 1
);
```

### `attempt to index a nil value (local 'Locale')` in nostr.lua

You're on 1.0.1/1.0.2/1.0.3-alpha and `lib.load('locales.xx')` couldn't find your locale file — `Locale` was `nil` and `:format()` blew up. Fixed in [#37](CHANGELOG.md). Update to 1.0.5-alpha or temporarily set `Config.Nostr.enabled = false`.

### Jail timer feels laggy / high CPU on jailed players

You're on 1.0.1/1.0.2/1.0.3-alpha — `Prison.StartTimer` ran a `Wait(0)` 60fps loop including `GetGameTimer()` math on every frame. The fix in 1.0.4 over-corrected and introduced flicker; the proper fix landed in 1.0.5 with split rendering/counter threads. Update to 1.0.5-alpha. See [#36](CHANGELOG.md) (initial) and [#39](CHANGELOG.md) (final).

### `attempt to call a nil value` / resource refuses to start

You're on 1.0.0-alpha. Update to 1.0.5-alpha — see [#30 in CHANGELOG.md](CHANGELOG.md). Seven `Debug(...)` calls were truncated in the 1.0.0-alpha tarball, and on stricter Lua parsers the entire file fails to load.

### Witnesses never call 911 / cops never spawn for non-fatal crimes

You're on 1.0.0-alpha **and** your test character is in `Config.AdminGroups`. Either update or test from a non-admin character. Fixed in [#28](CHANGELOG.md).

### `file 'locales.en' not found`

The `locales/en.lua` file is missing or not listed in `fxmanifest.lua`. Make sure both locale files are present and in the `files {}` block.

### `set ox:locale "en"` ignored — still seeing German strings

You're on 1.0.0-alpha. The locale loader was missing in three of four files. Update. Fixed in [#27](CHANGELOG.md).

### Nostr logger not connecting

```
[RDE | AIPD | Nostr] ✗ Resource "rde_nostr_log" not found
```

Install [rde_nostr_log](https://github.com/RedDragonElite/rde_nostr_log) and ensure it starts **before** rde_aipd. The police system continues to function normally without it.

### Cops not spawning

1. Set `Config.Debug = true` and run `debugpolice` in-game
2. Verify wanted level: `testwanted 3`
3. Check resource console for script errors

### Jail timer not running after reconnect

Verified working in v1.0.5-alpha. If you're still seeing this:

1. Confirm `oxmysql` is running and connected
2. Check that `police_records` table exists in your DB
3. Enable debug and check server console for `ox:playerLoaded` output on reconnect
4. Open an [issue](https://github.com/RedDragonElite/rde_aipd/issues) with your server console output

---

## 📚 Tech Stack

```
ox_core        → Player & group management
ox_lib         → UI, callbacks, progress bars, notifications, locale loader
ox_inventory   → Inventory & weapon management
oxmysql        → Async database (auto-create tables)
StateBags      → Realtime player state sync
rde_nostr_log  → Decentralized logging (optional)
```

---

## 🤝 Contributing

PRs are always welcome.

1. **Fork** the repository
2. **Create** a branch: `git checkout -b feature/your-feature`
3. **Test** on a live server before submitting
4. **Commit**: `git commit -m 'feat: your feature description'`
5. **Push**: `git push origin feature/your-feature`
6. **Open** a Pull Request with a clear description

**Guidelines:**

- ✅ Keep the RDE header in all files
- ✅ Follow existing code style — ox_core, ox_lib, StateBags
- ✅ Run `luac -p` on every modified `.lua` file before pushing — 1.0.0 shipped because nobody did
- ✅ Test on a live server before PR — visually verify HUD elements (1.0.4 shipped a flicker because no one looked)
- ✅ Every file has its own `local function Debug(...)` — never reach for another file's local logger (this is the bug that took down 1.0.1–1.0.3)
- ✅ Server-side validation stays — `CrimeReportCache` pattern is non-negotiable for new crime events
- ✅ **Wait timing — read this carefully:**
  - `Wait(0)` is **required** for: GTA immediate-mode natives (`DrawRect`, `DrawText`, `DrawSprite`, `DrawMarker`, `Draw3DText`), per-frame control disabling (`DisableControlAction`), per-frame physics polling
  - `Wait(10–100)` is correct for: input polling, distance checks, statebag reads, animation/model asset loading
  - `Wait(1000+)` is correct for: tick-based counters, periodic cleanup, status sync
  - If unsure, ask in the issue tracker before changing a `Wait()` value. The 1.0.3 → 1.0.4 → 1.0.5 saga is a textbook example of why.
- ❌ No telemetry, no paywalls, no ESX/QBCore
- ❌ Don't downgrade security — server-side validation stays
- ❌ Don't hardcode user-facing strings — use `L('key')` and add the key to all locale files

---

## 📜 License

**RDE Black Flag Source License v6.66**

```
###################################################################################
#                                                                                 #
#      .:: RED DRAGON ELITE (RDE)  -  BLACK FLAG SOURCE LICENSE v6.66 ::.         #
#                                                                                 #
#   PROJECT:    RDE_AIPD (NEXT-GEN AI POLICE & CRIME SYSTEM FOR FIVEM OX_CORE)    #
#   ARCHITECT:  .:: RDE ⧌ Shin [△ ᛋᛅᚱᛒᛅᚾᛏᛋ ᛒᛁᛏᛅ ▽] ::. | https://rd-elite.com     #
#   ORIGIN:     https://github.com/RedDragonElite                                 #
#                                                                                 #
#   WARNING: THIS CODE IS PROTECTED BY DIGITAL VOODOO AND PURE HATRED FOR LEAKERS #
#                                                                                 #
#   [ THE RULES OF THE GAME ]                                                     #
#                                                                                 #
#   1. // THE "FUCK GREED" PROTOCOL (FREE USE)                                    #
#      You are free to use, edit, and abuse this code on your server.             #
#      Learn from it. Break it. Fix it. That is the hacker way.                   #
#      Cost: 0.00€. If you paid for this, you got scammed by a rat.               #
#                                                                                 #
#   2. // THE TEBEX KILL SWITCH (COMMERCIAL SUICIDE)                              #
#      Listen closely, you parasites:                                             #
#      If I find this script on any paid store, Patreon, or "Premium Pack":       #
#      > I will DMCA your store into oblivion.                                    #
#      > I will publicly shame your community on Nostr. Permanently.              #
#      > I hope every cop spawns directly inside your player model.               #
#      SELLING FREE WORK IS THEFT. AND I AM THE JUDGE.                            #
#                                                                                 #
#   3. // THE CREDIT OATH                                                         #
#      Keep this header. If you remove my name, you admit you have no skill.      #
#      You can add "Edited by [YourName]", but never erase the original creator.  #
#      Don't be a skid. Respect the architecture.                                 #
#                                                                                 #
#   4. // THE CURSE OF THE COPY-PASTE                                             #
#      This code implements real StateBag sync, server-side authority,            #
#      async MySQL, and AI pathfinding logic. If you copy-paste without           #
#      understanding, you WILL break something important.                         #
#      Don't come crying to my DMs. RTFM.                                         #
#                                                                                 #
#   --------------------------------------------------------------------------    #
#   "We build the future on the graves of paid resources."                        #
#   "REJECT MODERN MEDIOCRITY. EMBRACE RDE SUPERIORITY."                          #
#   --------------------------------------------------------------------------    #
###################################################################################
```

**TL;DR:**

- ✅ **Free forever** — use it, edit it, learn from it
- ✅ **Keep the header** — credit where it's due
- ❌ **Don't sell it** — commercial use = instant DMCA + public shaming on Nostr
- ❌ **Don't be a skid** — copy-paste without reading will break things

---

## ⚡ Related Projects

| Resource | Description |
|----------|-------------|
| [rde_nostr_log](https://github.com/RedDragonElite/rde_nostr_log) | Decentralized FiveM logging via Nostr — replace Discord forever |
| [awesome-ox-rde](https://github.com/RedDragonElite/awesome-ox-rde) | Curated list of the best ox_core resources |

---

## 🌐 Community & Support

| | |
|---|---|
| 🌍 **Website** | [rd-elite.com](https://rd-elite.com) |
| 🔭 **Nostr Terminal** | [rd-elite.com/Files/NOSTR/Terminal](https://rd-elite.com/Files/NOSTR/Terminal/) |
| 🐙 **GitHub** | [github.com/RedDragonElite](https://github.com/RedDragonElite) |
| 🟣 **Nostr** | `npub1wr4e24zn6zzjqx8kvnelfvktf0pu6l2gx4gvw06zead2eqyn23sq9tsd94` |

**Before opening an issue:**

- ✅ Read this README fully
- ✅ Check the [Troubleshooting](#-troubleshooting) section
- ✅ Read the [CHANGELOG.md](CHANGELOG.md) — your bug may already be fixed
- ✅ Include your server console output and F8 client logs
- ❌ Don't open issues without logs — we can't help without them

---

**Made with 🔥 and pure criminal AI paranoia by [Red Dragon Elite](https://rd-elite.com)**

*The future is ours. We are already inside.*

**REJECT MODERN MEDIOCRITY. EMBRACE RDE SUPERIORITY.**

**RDE FOREVER. SYSTEM FAILURE. ⚡777⚡**

[![Website](https://img.shields.io/badge/Website-Visit-red?style=for-the-badge&logo=google-chrome)](https://rd-elite.com)
[![Nostr](https://img.shields.io/badge/Nostr-Follow-purple?style=for-the-badge&logo=rss)](https://primal.net/p/npub1wr4e24zn6zzjqx8kvnelfvktf0pu6l2gx4gvw06zead2eqyn23sq9tsd94)
[![Terminal](https://img.shields.io/badge/Terminal-Live-green?style=for-the-badge&logo=gnome-terminal)](https://rd-elite.com/Files/NOSTR/)
