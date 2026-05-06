-- ============================================================================
--
--   🐉 RED DRAGON ELITE | rde_aipd
--   LOCALE: English (default)
--   Author: RDE | SerpentsByte | https://rd-elite.com/
--   Version: 1.0.0
--
--   🌍 To add a new language:
--       1. Copy this file → locales/XX.lua
--       2. Translate all values (keep keys!)
--       3. Set ox:locale convar on your server
--
-- ============================================================================

return {

    -- =========================================================================
    --  SYSTEM
    -- =========================================================================

    system_initialized          = '✓ AI Police System initialized',
    system_ready                = '✓ System ready & active',
    system_not_ready            = '⚠ System not yet initialized – please wait',

    -- =========================================================================
    --  CRIME SYSTEM
    -- =========================================================================

    unknown_crime               = '⚠ Unknown crime type: %s',
    testing_crime               = '🔬 Testing crime: %s',
    crime_detected              = '🚨 Crime detected: %s',
    crime_reported              = '📞 %s reported by witness',
    crime_witnessed             = '👁 %d witness(es) reported the incident',
    police_notified             = '🚔 Police have been notified',
    admin_crime_suppressed      = '🛡 Admin crime suppressed: %s (not reported)',
    admin_mode_active           = '🛡 Admin mode – crimes logged but not dispatched',
    crime_on_cooldown           = '⏳ Crime on cooldown: %s',

    -- =========================================================================
    --  WANTED SYSTEM
    -- =========================================================================

    wanted_set                  = '⭐ Wanted level: %d star(s)',
    wanted_cleared              = '✅ You are no longer wanted',
    wanted_increase             = '🔺 Wanted level increased to %d',
    wanted_decrease             = '🔻 Wanted level decreased to %d',
    wanted_restored             = '🔄 Wanted level restored: %d star(s)',
    wanted_decay_start          = '👁 Wanted decay starting – stay out of sight',
    wanted_decay_interrupted    = '🚨 Wanted decay interrupted – cop spotted you!',
    wanted_max                  = '☢ MAXIMUM WARRANT – all units engaged',

    -- =========================================================================
    --  SURRENDER
    -- =========================================================================

    surrendering                = '🙌 Surrendering to police...',
    surrender_cancelled         = '❌ Surrender cancelled',
    surrender_complete          = '✅ You have surrendered',

    -- =========================================================================
    --  ARREST & JAIL
    -- =========================================================================

    arrested                    = '🚔 You have been arrested',
    jailed                      = '⛓ Jailed for %d seconds',
    jail_released               = '✅ You have been released',
    jail_restored               = '🔄 Jail status restored',
    jail_time_remaining         = '⛓ Time remaining: %d seconds',
    jail_activity_reward        = '💰 Earned $%d for jail activity',

    -- =========================================================================
    --  POLICE DISPATCH
    -- =========================================================================

    police_alert                = '🚨 Code %s: %s at %s',
    units_dispatched            = '🚔 %d unit(s) dispatched',
    units_cleared               = '✅ All police units cleared',
    officer_down                = '💀 OFFICER DOWN – all units respond!',

    -- =========================================================================
    --  LINE OF SIGHT / DECAY
    -- =========================================================================

    cops_can_see_player         = '👁 Officers have visual on you',
    cops_lost_visual            = '🌫 Officers lost visual',
    escape_successful           = '✅ You have escaped!',

    -- =========================================================================
    --  PERMISSIONS
    -- =========================================================================

    no_permission               = '⛔ You do not have permission',
    no_access                   = '⛔ Access denied',
    admin_only                  = '⛔ Admin access required',
    police_only                 = '⛔ Police access required',

    -- =========================================================================
    --  ADMIN EXEMPTIONS
    -- =========================================================================

    admin_exempt_jail           = '🛡 This player is an admin and is exempt from jail',
    admin_exempt_arrest         = '🛡 This player is an admin and cannot be arrested',

    -- =========================================================================
    --  SERVER – JAIL & ARREST ACTIONS
    -- =========================================================================

    -- Player notifications
    released                    = '✅ You have been released from jail',

    -- Admin / police feedback (with placeholders)
    wanted_level_set            = '⭐ Wanted level set to %d star(s)',
    set_wanted_success          = '✅ Set %s wanted level to %d star(s)',
    cleared_wanted_success      = '✅ Cleared wanted level for %s',
    jailed_success              = '⛓ Jailed %s for %d seconds',
    released_success            = '✅ Released %s from jail',
    arrested_success            = '🚔 Arrested %s – jailed for %d seconds',
    target_not_found            = '❌ Target player not found or has no character loaded',
    target_not_wanted           = '❌ This player is not wanted',

    -- =========================================================================
    --  SERVER – CRIME HISTORY
    -- =========================================================================

    crimes_found                = '📋 Found %d crime record(s) in the database',
    crimes_none                 = '✅ No crime records found for this player',

    -- =========================================================================
    --  SERVER – STATUS CHECKS
    -- =========================================================================

    -- %s = name | %d = level | %s = jailed (Yes/No) | %d = totalCrimes
    status_checkwanted          = '🔍 %s | ⭐ %d stars | ⛓ Jailed: %s | 📋 Crimes: %d',
    -- %d = level | %d = totalCrimes
    status_wanted               = '🔍 Your wanted level: %d ⭐ | Total crimes: %d',

    -- =========================================================================
    --  SERVER – POLICE COMMANDS
    -- =========================================================================

    backup_requested            = '🚨 BACKUP REQUESTED – officer needs assistance!',
    backup_called               = '✅ Backup request sent to all online officers',
    -- %s = officerName
    panic_button                = '🚨 PANIC BUTTON – %s is in immediate danger! Respond NOW!',

    -- =========================================================================
    --  DATABASE / SYSTEM
    -- =========================================================================

    db_initialized              = '✓ Database tables ready',
    cleanup_done                = '♻ Stale state cleanup completed',

    -- =========================================================================
    --  DEBUG
    -- =========================================================================

    debug_mode                  = '⚠ Debug mode ENABLED',

    -- =========================================================================
    --  SERVER – PLAYER EVENTS
    -- =========================================================================

    player_connected            = '%s connected to the server',
    player_disconnected         = '%s left the server (%s)',
    player_loaded               = '%s is now active in-game',

    -- =========================================================================
    --  NOSTR LOGGER – LOG TEMPLATES
    -- =========================================================================

    -- These are used server-side for structured Nostr event content.
    -- Use %s / %d placeholders matching the call-site args.

    nostr_crime_event           = '🚨 [CRIME] %s committed %s | Area: %s | Witnessed: %s',
    nostr_wanted_event          = '⭐ [WANTED] %s | Level: %d star(s) | Reason: %s',
    nostr_wanted_cleared        = '✅ [CLEARED] %s | Wanted level cleared',
    nostr_arrest_event          = '🚔 [ARREST] %s arrested | Wanted level was: %d',
    nostr_jail_event            = '⛓ [JAIL] %s jailed for %d seconds',
    nostr_release_event         = '✅ [RELEASE] %s released from jail',
    nostr_connect_event         = '🟢 [CONNECT] %s joined | ID: %s',
    nostr_disconnect_event      = '🔴 [DISCONNECT] %s left | Reason: %s',
    nostr_cop_killed_event      = '💀 [OFFICER DOWN] %s killed a police officer!',
    nostr_surrender_event       = '🙌 [SURRENDER] %s surrendered to police',
    nostr_escape_event          = '💨 [ESCAPE] %s escaped police | Prev level: %d',
    nostr_admin_action          = '🛡 [ADMIN] %s | Action: %s | Target: %s',

    -- =========================================================================
    --  CLIENT – WANTED UI & DECAY
    -- =========================================================================

    -- Shown when player breaks line-of-sight and decay starts
    wanted_evading              = '👁 Stay out of sight to clear your wanted level',

    -- =========================================================================
    --  CLIENT – TACKLE
    -- =========================================================================

    tackled                     = '💥 You have been tackled by an officer!',

    -- =========================================================================
    --  CLIENT – SURRENDER
    -- =========================================================================

    cannot_surrender_vehicle    = '🚗 You cannot surrender while in a vehicle',

    -- =========================================================================
    --  CLIENT – POLICE CRIME ALERT (shown to on-duty officers)
    -- =========================================================================

    -- %s = crime description (e.g. "Assault")
    crime_alert_title           = '🚔 Crime Alert: %s',
    -- %s = severity (e.g. "high")
    crime_alert_desc            = '⚠ Severity: %s – Respond immediately',

    -- =========================================================================
    --  UI
    -- =========================================================================

    confirm                     = 'Confirm',
    cancel                      = 'Cancel',
    close                       = 'Close',
    save                        = 'Save',
    delete                      = 'Delete',
    yes                         = 'Yes',
    no                          = 'No',

    -- =========================================================================
    --  CLIENT — WITNESS / 911-CALL FLOW (NEW IN 1.0.1-alpha)
    -- =========================================================================

    -- %s = crime description (e.g. "Assault")
    witness_spotted_you         = '⚠ A witness spotted you! %s',
    no_witnesses_nearby         = '✓ No witnesses nearby',
    witness_killed_before_call  = '✓ Witness eliminated – no 911 call',
    witness_killed_during_call  = '✓ Witness interrupted – call aborted',

    -- =========================================================================
    --  CLIENT — MISC (NEW IN 1.0.1-alpha)
    -- =========================================================================

    dragged_from_vehicle        = 'Dragged from vehicle!',
    arrest_cancelled            = 'Arrest cancelled',
    connection_issue            = 'Connection issue — please rejoin if stuck',

}