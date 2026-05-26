# Changelog 🚑 v1.0.4-alpha — Race-Proof & Crash-Free

> **Drop-in replacement for any 1.0.x-alpha release.** Same config, same DB schema,
> same exports. No migration needed for new installs. Existing installs may want
> to run the one-time dedup query at the bottom of this changelog.

## What's fixed

| # | Fix | Severity | Impact |
|---|-----|----------|--------|
| **#34** | `Debug(...)` was `local` in `server/main.lua`, called from `server/crime_witness_handler.lua` — instant `nil` value crash on first crime report | 🔴 Critical | Resource was effectively dead on the witness path |
| **#35** | Double `table.insert` in `state.crimeHistory` for unwitnessed crimes (both the handler AND `LogCrime()` were inserting) | 🟠 High | Every silent crime counted twice in `/crimes` and DB |
| **#36** | `Wait(0)` 60+ fps loop in `Prison.StartTimer` (only needed 1Hz precision) | 🟡 Medium | ~6× CPU saved per jailed player |
| **#37** | `server/nostr.lua` had no `or {}` locale fallback — `:format()` crashed on missing locale file | 🟠 High | Nostr logging died silently on any locale convar mismatch |
| **#38** | Server-side `CrimeReportCache` (2s dedup window) for `police:reportCrime` and `police:crimeDetectedNoWitness` | 🟠 High | Race-conditions, external-resource double-fires, and `/testwitness` spam can no longer create duplicate DB rows |
| polish | `Wait(0)` → `Wait(10)` in `LoadAnimDict()` / `LoadModel()` | 🟢 Low | RDE OX Standards compliance |

## What's new under the hood

```lua
-- server/crime_witness_handler.lua
local CrimeReportCache = {}
local CRIME_DEDUP_WINDOW = 2000  -- ms

local function IsCrimeRecentlyReported(source, crimeType)
    local cache = CrimeReportCache[source]
    if not cache or not cache[crimeType] then return false end
    return (GetGameTimer() - cache[crimeType]) < CRIME_DEDUP_WINDOW
end

AddEventHandler('playerDropped', function()
    local src = source
    if src and CrimeReportCache[src] then CrimeReportCache[src] = nil end
end)
```

The cache is **per-player + per-crime-type**, so two different crimes from the same player within 2s are still both logged correctly. Only literal duplicates get dropped.

## One-time DB cleanup (recommended)

If you're upgrading from 1.0.1/1.0.2/1.0.3 you might have legacy duplicate rows in `crime_logs`. Check first:

```sql
SELECT charid, crime_type,
       JSON_EXTRACT(crime_data, '$.timestamp') AS ts,
       JSON_EXTRACT(crime_data, '$.witnessed') AS witnessed,
       COUNT(*) AS dups,
       GROUP_CONCAT(id ORDER BY id) AS row_ids
FROM crime_logs
WHERE crime_data IS NOT NULL
GROUP BY charid, crime_type, ts
HAVING dups > 1;
```

If non-empty, dedupe (keeps the earliest ID of each pair):

```sql
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

## How to verify the fix in-game

With `set police_debug "true"`:
