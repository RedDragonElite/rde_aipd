-- ============================================================================
--
--   🐉 RED DRAGON ELITE | rde_aipd
--   LOCALE: Deutsch (de)
--   Author: RDE | SerpentsByte | https://rd-elite.com/
--   Version: 1.0.0
--
-- ============================================================================

return {

    -- =========================================================================
    --  SYSTEM
    -- =========================================================================

    system_initialized          = '✓ KI-Polizeisystem initialisiert',
    system_ready                = '✓ System bereit & aktiv',
    system_not_ready            = '⚠ System noch nicht bereit – bitte warten',

    -- =========================================================================
    --  VERBRECHENS-SYSTEM
    -- =========================================================================

    unknown_crime               = '⚠ Unbekannter Verbrechenstyp: %s',
    testing_crime               = '🔬 Teste Verbrechen: %s',
    crime_detected              = '🚨 Verbrechen erkannt: %s',
    crime_reported              = '📞 %s von Zeugen gemeldet',
    crime_witnessed             = '👁 %d Zeuge(n) haben den Vorfall gemeldet',
    police_notified             = '🚔 Die Polizei wurde benachrichtigt',
    admin_crime_suppressed      = '🛡 Admin-Verbrechen unterdrückt: %s (nicht gemeldet)',
    admin_mode_active           = '🛡 Admin-Modus – Verbrechen werden protokolliert, aber nicht eskaliert',
    crime_on_cooldown           = '⏳ Verbrechen im Cooldown: %s',

    -- =========================================================================
    --  FAHNDUNGSSYSTEM
    -- =========================================================================

    wanted_set                  = '⭐ Fahndungslevel: %d Stern(e)',
    wanted_cleared              = '✅ Du wirst nicht mehr gesucht',
    wanted_increase             = '🔺 Fahndungslevel erhöht auf %d',
    wanted_decrease             = '🔻 Fahndungslevel gesenkt auf %d',
    wanted_restored             = '🔄 Fahndungslevel wiederhergestellt: %d Stern(e)',
    wanted_decay_start          = '👁 Fahndungsverfall startet – bleib außer Sichtweite',
    wanted_decay_interrupted    = '🚨 Fahndungsverfall unterbrochen – du wurdest gesehen!',
    wanted_max                  = '☢ MAXIMALE FAHNDUNG – alle Einheiten im Einsatz',

    -- =========================================================================
    --  KAPITULATION
    -- =========================================================================

    surrendering                = '🙌 Kapitulation...',
    surrender_cancelled         = '❌ Kapitulation abgebrochen',
    surrender_complete          = '✅ Du hast dich ergeben',

    -- =========================================================================
    --  VERHAFTUNG & GEFÄNGNIS
    -- =========================================================================

    arrested                    = '🚔 Du wurdest verhaftet',
    jailed                      = '⛓ Inhaftiert für %d Sekunden',
    jail_released               = '✅ Du wurdest entlassen',
    jail_restored               = '🔄 Gefängniszustand wiederhergestellt',
    jail_time_remaining         = '⛓ Verbleibende Zeit: %d Sekunden',
    jail_activity_reward        = '💰 $%d für Gefängnisaktivität erhalten',

    -- =========================================================================
    --  POLIZEI-EINSATZ
    -- =========================================================================

    police_alert                = '🚨 Code %s: %s bei %s',
    units_dispatched            = '🚔 %d Einheit(en) alarmiert',
    units_cleared               = '✅ Alle Polizeieinheiten abgezogen',
    officer_down                = '💀 BEAMTER NIEDER – alle Einheiten reagieren!',

    -- =========================================================================
    --  SICHTLINIE / VERFALL
    -- =========================================================================

    cops_can_see_player         = '👁 Beamte haben Sichtkontakt zu dir',
    cops_lost_visual            = '🌫 Beamte haben den Sichtkontakt verloren',
    escape_successful           = '✅ Du bist entkommen!',

    -- =========================================================================
    --  BERECHTIGUNGEN
    -- =========================================================================

    no_permission               = '⛔ Keine Berechtigung',
    no_access                   = '⛔ Zugriff verweigert',
    admin_only                  = '⛔ Admin-Zugriff erforderlich',
    police_only                 = '⛔ Polizei-Zugriff erforderlich',

    -- =========================================================================
    --  ADMIN-AUSNAHMEN
    -- =========================================================================

    admin_exempt_jail           = '🛡 Dieser Spieler ist ein Admin und kann nicht inhaftiert werden',
    admin_exempt_arrest         = '🛡 Dieser Spieler ist ein Admin und kann nicht verhaftet werden',

    -- =========================================================================
    --  SERVER – GEFÄNGNIS & VERHAFTUNGSAKTIONEN
    -- =========================================================================

    -- Spieler-Benachrichtigungen
    released                    = '✅ Du wurdest aus dem Gefängnis entlassen',

    -- Admin / Polizei-Feedback (mit Platzhaltern)
    wanted_level_set            = '⭐ Fahndungslevel auf %d Stern(e) gesetzt',
    set_wanted_success          = '✅ Fahndungslevel von %s auf %d Stern(e) gesetzt',
    cleared_wanted_success      = '✅ Fahndungslevel von %s gelöscht',
    jailed_success              = '⛓ %s für %d Sekunden inhaftiert',
    released_success            = '✅ %s aus dem Gefängnis entlassen',
    arrested_success            = '🚔 %s verhaftet – %d Sekunden Gefängnis',
    target_not_found            = '❌ Spieler nicht gefunden oder hat keinen Charakter geladen',
    target_not_wanted           = '❌ Dieser Spieler wird nicht gesucht',

    -- =========================================================================
    --  SERVER – VERBRECHENSHISTORIE
    -- =========================================================================

    crimes_found                = '📋 %d Verbrechenseinträge in der Datenbank gefunden',
    crimes_none                 = '✅ Keine Verbrechenseinträge für diesen Spieler gefunden',

    -- =========================================================================
    --  SERVER – STATUS-ABFRAGEN
    -- =========================================================================

    -- %s = Name | %d = Level | %s = Inhaftiert (Ja/Nein) | %d = Gesamtverbrechen
    status_checkwanted          = '🔍 %s | ⭐ %d Sterne | ⛓ Inhaftiert: %s | 📋 Verbrechen: %d',
    -- %d = Level | %d = Gesamtverbrechen
    status_wanted               = '🔍 Dein Fahndungslevel: %d ⭐ | Gesamtverbrechen: %d',

    -- =========================================================================
    --  SERVER – POLIZEI-BEFEHLE
    -- =========================================================================

    backup_requested            = '🚨 VERSTÄRKUNG ANGEFORDERT – Beamter braucht Unterstützung!',
    backup_called               = '✅ Verstärkungsanfrage an alle aktiven Beamten gesendet',
    -- %s = Beamtenname
    panic_button                = '🚨 PANIC-KNOPF – %s ist in unmittelbarer Gefahr! Sofort reagieren!',

    -- =========================================================================
    --  DATENBANK / SYSTEM
    -- =========================================================================

    db_initialized              = '✓ Datenbank-Tabellen bereit',
    cleanup_done                = '♻ Stale-State-Bereinigung abgeschlossen',

    -- =========================================================================
    --  DEBUG
    -- =========================================================================

    debug_mode                  = '⚠ Debug-Modus AKTIV',

    -- =========================================================================
    --  SERVER – SPIELER-EVENTS
    -- =========================================================================

    player_connected            = '%s ist dem Server beigetreten',
    player_disconnected         = '%s hat den Server verlassen (%s)',
    player_loaded               = '%s ist jetzt im Spiel aktiv',

    -- =========================================================================
    --  NOSTR LOGGER – LOG-TEMPLATES
    -- =========================================================================

    nostr_crime_event           = '🚨 [VERBRECHEN] %s beging %s | Gebiet: %s | Zeugen: %s',
    nostr_wanted_event          = '⭐ [FAHNDUNG] %s | Level: %d Stern(e) | Grund: %s',
    nostr_wanted_cleared        = '✅ [GELÖSCHT] %s | Fahndung aufgehoben',
    nostr_arrest_event          = '🚔 [VERHAFTET] %s verhaftet | Fahndungslevel war: %d',
    nostr_jail_event            = '⛓ [GEFÄNGNIS] %s inhaftiert für %d Sekunden',
    nostr_release_event         = '✅ [ENTLASSEN] %s aus dem Gefängnis entlassen',
    nostr_connect_event         = '🟢 [VERBUNDEN] %s beigetreten | ID: %s',
    nostr_disconnect_event      = '🔴 [GETRENNT] %s getrennt | Grund: %s',
    nostr_cop_killed_event      = '💀 [BEAMTER NIEDER] %s hat einen Polizisten getötet!',
    nostr_surrender_event       = '🙌 [KAPITULATION] %s hat vor der Polizei kapituliert',
    nostr_escape_event          = '💨 [FLUCHT] %s ist entkommen | Vorheriger Level: %d',
    nostr_admin_action          = '🛡 [ADMIN] %s | Aktion: %s | Ziel: %s',

    -- =========================================================================
    --  CLIENT – WANTED UI & DECAY
    -- =========================================================================

    wanted_evading              = '👁 Bleib außer Sichtweite um deinen Fahndungslevel zu senken',

    -- =========================================================================
    --  CLIENT – TACKLE
    -- =========================================================================

    tackled                     = '💥 Du wurdest von einem Beamten zu Boden gebracht!',

    -- =========================================================================
    --  CLIENT – SURRENDER
    -- =========================================================================

    cannot_surrender_vehicle    = '🚗 Du kannst dich nicht ergeben während du in einem Fahrzeug sitzt',

    -- =========================================================================
    --  CLIENT – POLIZEI VERBRECHENS-ALARM (nur für Beamte)
    -- =========================================================================

    -- %s = Verbrechensbeschreibung
    crime_alert_title           = '🚔 Verbrechens-Alarm: %s',
    -- %s = Schweregrad
    crime_alert_desc            = '⚠ Schweregrad: %s – Sofort reagieren',

    -- =========================================================================
    --  UI
    -- =========================================================================

    confirm                     = 'Bestätigen',
    cancel                      = 'Abbrechen',
    close                       = 'Schließen',
    save                        = 'Speichern',
    delete                      = 'Löschen',
    yes                         = 'Ja',
    no                          = 'Nein',

}