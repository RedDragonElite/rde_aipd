# Changelog — rde_aipd

All notable changes to this project will be documented in this file.

## [1.0.1-alpha] — 2026-05-06

> 🚑 **Hotfix release.** 1.0.0-alpha had two pre-existing Lua syntax errors that prevented the resource from starting at all in some environments, plus several i18n and gameplay regressions. **Update is strongly recommended for everyone running 1.0.0-alpha.**

### 🩹 Fixed

#### FIX #30 — Critical: Resource failed to start (syntax errors in 1.0.0-alpha)
Six `Debug(...)` calls in `client/main.lua` and `server/main.lua` shipped with their opening line truncated, leaving orphan `))` tokens that broke Lua parsing:

- `client/main.lua` — `Prison.StartTimer()` (was line 815)
- `client/main.lua` — `Prison.EnsureRunning()` (was line 899)
- `client/main.lua` — systemReady jail-restore thread (was line 1377)
- `server/main.lua` — `playerDropped` save handler (was line 1018)
- `server/main.lua` — `playerLoaded` charid resolver (was line 1119)
- `server/main.lua` — DB-load result handler (was line 1160)
- `server/main.lua` — `police:systemReady` send (was line 1259)

All seven Debug calls have been reconstructed with descriptive messages.

#### FIX #28 — Witnesses never call the police for any non-fatal crime
`client/crime.lua` was hard-blocking **every** crime for any player in `Config.AdminGroups` (owner/admin/superadmin/god/mod), regardless of `Config.AdminSettings.exemptFromWanted`. The witness lookup (`GetNearbyWitnesses` / `FindBestCaller`) was never reached — players in admin groups simply never had crimes reported, so no NPC witnesses ever called 911 and no AI cops ever spawned. MURDER/MURDER_COP still worked because they're called with `force=true`.

The check now correctly respects the config flag:

```lua
if crimeState.isAdmin and not force
    and Config.AdminSettings
    and Config.AdminSettings.exemptFromWanted
then
    return false
end
```

#### FIX #29 — Triple notification spam per crime
Every successful crime fired three notifications back-to-back:

1. `crime.lua` — "⚠ Witness spotted you!" *(before 911 call — useful, kept)*
2. `crime_witness_handler.lua` — "🚨 Witness called 911! (~Xm away)" *(after call — redundant, removed)*
3. `main.lua` `SetWantedLevel` — "Wanted Level: X ⭐" *(after call — kept)*

Notification 2 has been removed. The witness distance is still persisted via `state.crimeHistory` for `/crimes` history and Nostr logs.

#### FIX #27 — i18n broken everywhere except Nostr logger
`locales/en.lua` and `locales/de.lua` were complete and correct, but `lib.load('locales.' .. GetConvar('ox:locale', 'en'))` was only called in `server/nostr.lua`. Every notification in `client/main.lua`, `client/crime.lua`, `server/main.lua` and `server/crime_witness_handler.lua` was hardcoded — and worse, **mixed German and English in the same code paths**. Setting `ox:locale "en"` in your `server.cfg` was silently ignored.

All four files now load the locale at file scope:

```lua
local Locale = lib.load('locales.' .. GetConvar('ox:locale', 'en')) or {}
local function L(key, ...)
    local s = Locale[key]
    if not s then return key end
    if select('#', ...) > 0 then return s:format(...) end
    return s
end
```

~30 hardcoded notification strings have been migrated to `L('key', ...)` calls.

### ✨ Added

New keys in `locales/en.lua` and `locales/de.lua`:

- `witness_spotted_you`
- `no_witnesses_nearby`
- `witness_killed_before_call`
- `witness_killed_during_call`
- `dragged_from_vehicle`
- `arrest_cancelled`
- `connection_issue`

### 📝 Notes for translators

If you have a custom locale (e.g. `locales/fr.lua`, `locales/es.lua`), please add the seven keys listed above. Missing keys will fall back to the key name itself (no crash), but the notification text will look broken.

### 🙏 Credits

Bug reports and reproduction case from the community. Special thanks to everyone who tested 1.0.0-alpha and pinged the Discord. 🐉

---

## [1.0.0-alpha] — 2026-05-06

Initial public release.
