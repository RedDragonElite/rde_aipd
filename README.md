# rde_aipd
🔥 ULTIMATE AI POLICE SYSTEM V1.0.0 - Built on ox_core &amp; Statebags! 🚨

<img width="1024" height="1024" alt="image" src="https://github.com/user-attachments/assets/7f044614-3c38-4b9e-87ce-40013a560b8a" />

PREVIEW:
https://www.youtube.com/watch?v=mCWg0jZlSbY

# 🐉 rde_aipd

[![Version](https://img.shields.io/badge/version-1.0.0--alpha-red?style=for-the-badge)](https://github.com/RedDragonElite/rde_aipd)
[![License](https://img.shields.io/badge/license-RDE%20Black%20Flag-black?style=for-the-badge)](LICENSE)
[![FiveM](https://img.shields.io/badge/FiveM-Compatible-blue?style=for-the-badge)](https://fivem.net)
[![ox_core](https://img.shields.io/badge/Framework-ox__core-blue?style=for-the-badge)](https://github.com/overextended/ox_core)
[![Nostr](https://img.shields.io/badge/Nostr-Decentralized-purple?style=for-the-badge)](https://github.com/RedDragonElite/rde_nostr_log)
[![Quality](https://img.shields.io/badge/Quality-Production-gold?style=for-the-badge)](https://github.com/RedDragonElite)

**🚨 RDE AIPD | Next-Gen AI Police & Crime System for FiveM ox_core | Ultra-Realistic | StateBag-Synced | Nostr-Logged | Production-Ready**

*Built by [Red Dragon Elite](https://rd-elite.com) | Free Forever | No Paywalls | No Legacy*

[📖 Installation](#-installation) • [⚙️ Configuration](#️-configuration) • [🌍 Locales](#-locales) • [🐉 Nostr Logging](#-nostr-logging) • [📡 Exports](#-exports) • [🐛 Troubleshooting](#-troubleshooting) • [🌐 Website](https://rd-elite.com) • [🔭 Terminal](https://rd-elite.com/Files/NOSTR/)

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
| Paid or locked down | 100% free forever — RDE Black Flag |

### 🎯 Key Features

- 🤖 **True Line-of-Sight AI** — cops only react to what they can actually see
- 🧠 **Threat Assessment** — dynamic threat calculation per unit (weapons, speed, cover, escape history)
- 😮‍💨 **Player Fatigue** — sprint enough and you slow down; cops exploit that
- ⭐ **6 Wanted Levels** — from minor warrant to maximum response with helicopters & roadblocks
- 📉 **Realistic Decay** — wanted level drops only when no officer has eyes on you
- 🥊 **Tackle System** — cops can physically tackle fleeing suspects
- 🚨 **Full Crime Detection** — 13+ crime types, witness system, area multipliers
- ⛓ **Prison System** — auto-jail, inventory save/restore, persistent state across reconnects
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

**Add a new language:**

1. Copy `locales/en.lua` → `locales/xx.lua`
2. Translate all values (keep the keys!)
3. Register it in `fxmanifest.lua` under `files {}`
4. Set `ox:locale "xx"` in your server.cfg

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
├── LICENSE
├── locales/
│   ├── en.lua              ← English (default)
│   └── de.lua              ← Deutsch
├── server/
│   ├── main.lua            ← Core server logic, callbacks, jail timer
│   └── nostr.lua           ← Nostr logging integration
├── client/
│   ├── main.lua            ← AI police, wanted system, prison
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
| `crimestatus` | Show current crime system state |
| `listcrimes` | List all registered crime types |
| `testjail [seconds]` | Jail yourself for testing |

---

## 🛡 Security

- All sensitive actions validated **server-side**
- StateBags used for realtime sync — no polling
- ox_core group checks on all privileged callbacks
- ACE permission support
- Nostr logs are cryptographically signed — tamper-proof by design
- Minimum jail time enforced server-side (anti 1s-jail exploit)

---

## 🐛 Troubleshooting

### `file 'locales.en' not found`

The `locales/en.lua` file is missing or not listed in `fxmanifest.lua`. Make sure both locale files are present and in the `files {}` block.

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

Fixed in v1.0.0-alpha. If you're still seeing this:

1. Confirm `oxmysql` is running and connected
2. Check that `police_records` table exists in your DB
3. Enable debug and check server console for `ox:playerLoaded` output on reconnect
4. Open an [issue](https://github.com/RedDragonElite/rde_aipd/issues) with your server console output

---

## 📚 Tech Stack

```
ox_core        → Player & group management
ox_lib         → UI, callbacks, progress bars, notifications
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
- ✅ Test on a live server before PR
- ❌ No telemetry, no paywalls, no ESX/QBCore
- ❌ Don't downgrade security — server-side validation stays

---

## 📜 License

**RDE Black Flag Source License v6.66**

```
###################################################################################
#                                                                                 #
#      .:: RED DRAGON ELITE (RDE)  -  BLACK FLAG SOURCE LICENSE v6.66 ::.         #
#                                                                                 #
#   PROJECT:    RDE_AIPD (NEXT-GEN AI POLICE & CRIME SYSTEM FOR FIVEM OX_CORE)   #
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
#      understanding, you WILL break something important.                          #
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
