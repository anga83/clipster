# Clipster - Projektdokumentation

## 1. Projektüberblick
Clipster ist ein in Swift/SwiftUI entwickelter Clipboard-Manager für macOS (ab macOS 15), der primär als Menüleisten-App genutzt wird und optional ein Hauptfenster anbietet.

Ziel der App:
- Zwischenablage-Historie dauerhaft speichern
- Text und Datei-Referenzen verwalten
- Elemente durchsuchen, filtern, pinnen und wiederverwenden
- Daten exportieren/sichern

## 2. Aktueller Versionsstand
- App-Version: `2.4.1`
- Build-Nummer: `29`
- Mindest-macOS: `15.0`
- Quellen:
  - `Sources/Clipster/Resources/Info.plist`
  - `Package.swift`

## 3. Hauptfunktionen

### 3.1 Clipboard-Historie
- Automatisches Monitoring der systemweiten Zwischenablage
- Speicherung in SQLite (`clipster.db`)
- Unterstützung für:
  - Text-Content
  - Datei-URLs
- Duplikat-Schutz für direkt aufeinanderfolgende identische Items

### 3.2 Menüleisten-App + Hauptfenster
- Menüleisten-Popover mit Suchfeld und Verlaufsliste
- Optionales Hauptfenster
- Konfigurierbares Verhalten bei Klick auf das Menüleisten-Icon
- Wichtige Fokus-/Aktivierungslogik (regressionssensitiv):
  - Beim Öffnen des Hauptfensters wird die App auf `.regular` aktiviert.
  - Solange das Hauptfenster sichtbar ist, bleibt die App im `.regular`-Modus (Menüleiste inkl. App-Menü erreichbar).
  - Beim Schließen des Hauptfensters wird nur dann auf `.accessory` zurückgestellt, wenn `launchAtLogin && !startWithMainWindow`; sonst bleibt `.regular`.

### 3.3 Suche und Filter
- Volltextsuche über Historie (DB-gestützt)
- App-basierter Filter (Source App)
- Gruppierung nach Zeitabschnitten (Today, This Week, This Month, Monatsgruppen)

### 3.4 Item-Aktionen
- Anklicken eines Items kopiert es zurück in die Zwischenablage
- Kontextmenü-Aktionen:
  - Copy
  - Quick Look (für Dateien)
  - Open (Dateien)
  - Pin/Unpin
  - Delete
- Mehrfachauswahl im Hauptfenster inkl. Bulk-Delete

### 3.5 Archiv (Recently Deleted)
- Soft-Delete in separate SQLite-Tabelle (`recently_deleted`)
- Wiederherstellen gelöschter Items
- Permanentes Löschen
- Retention/Cleanup für Text- und Attachment-Archivdaten

### 3.6 Datei-Handling
- Größenlimits
- Optionales symlink-basiertes Handling großer Dateien
- Optionales physisches Speichern von Datei-Inhalten in `attachments/`
- Datei-Typ-Regeln (`always_symlink`, `save_never`)

### 3.7 Export/Backup
Export als vollständiges ZIP-Backup mit:
- `clipster.db` (SQLite-Snapshot)
- `history.json` (aktive Items aus `clipboard_history`)
- `archived.json` (Archiv-Items aus `recently_deleted`)
- `settings.plist` (falls vorhanden)
- `attachments/` (falls vorhanden)
- `backup-manifest.json`

Ablauf:
- Während der Vorbereitung wird ein Fortschrittsfenster eingeblendet.
- Danach öffnet sich ein Speichern-Dialog (`NSSavePanel`).

Wichtige Details:
- Startet der Export im Menüleisten-Popover, wird das Popover vor dem eigentlichen Export geschlossen, damit das Fortschrittsfenster sichtbar ist.
- JSON-Export wird primär aus dem SQLite-Snapshot erzeugt.
- Fallback: Wenn der Snapshot für JSON nicht gelesen werden kann, wird auf die Original-DB gewechselt.
- `history.json` bleibt semantisch unverändert (nur aktive Historie). Archivdaten stehen zusätzlich in `archived.json`.
- Fehlt `recently_deleted` in einer alten DB, wird `archived.json` als leere Liste exportiert (statt hartem Fehler).

### 3.8 Import
- Import-Flow ist im `ClipboardHistoryStore` derzeit weiterhin Placeholder.
- Historischer `PersistenceManager` enthält ältere Import-/Export-Logik (JSON/ZIP), ist aber nicht der aktive Primary-Flow des aktuellen Exports.

### 3.9 Global Shortcut
- Optional aktivierbar
- Shortcut für manuelles Capture (`Option+Command+V` laut UI-Text)

### 3.10 UX-Verbesserungen
- Tooltips für die Top-Bar-Icons im Hauptfenster (Import, Export, Clear, Select)
- Dynamisches Build-Datum im About-Dialog (aus Binary-Timestamp)
- Settings-Fenster:
  - Toolbar-Hintergrund im Fensterkontext ausgeblendet (`toolbarBackgroundVisibility`)
  - Window-Controls (inkl. Schließen) bleiben erhalten
  - Benötigt macOS 15 API

## 4. Technischer Aufbau

### 4.1 Technologien
- Swift Package Manager (SPM)
- SwiftUI
- AppKit (Panels, Windowing, Pasteboard-nahe Funktionen)
- SQLite3 (direkt via C-Binding)

### 4.2 Projektstruktur
- `Sources/Clipster/ClipsterApp.swift`
  - App-Entry, Szenen, Window/MenuBarExtra, Aktivierungs-/Fokussteuerung
- `Sources/Clipster/ContentView.swift`
  - Haupt-UI und Popover-Inhalt (inkl. Export-Start aus Popover)
- `Sources/Clipster/Data/ClipboardHistoryStore.swift`
  - State-Management, History-Operationen, Export-Start
- `Sources/Clipster/Data/SettingsStore.swift`
  - Persistente Settings (`settings.plist`)
- `Sources/Clipster/Services/DatabaseManager.swift`
  - SQLite-Schema + CRUD + Archivlogik
- `Sources/Clipster/Services/ClipboardMonitor.swift`
  - Polling-basierte Clipboard-Überwachung
- `Sources/Clipster/Services/BackupExportService.swift`
  - ZIP-Backup-Erstellung (Snapshot, `history.json`, `archived.json`, Manifest)
- `Sources/Clipster/Services/ExportProgressWindowController.swift`
  - Fortschrittsfenster für Backup-Vorbereitung
- `Sources/Clipster/Views/*`
  - UI-Views inkl. Settings, Archive, About, Row-Views

### 4.3 Datenablage (lokal)
Unter `~/Library/Application Support/Clipster/`:
- `clipster.db`
- `settings.plist`
- `attachments/`

### 4.4 Datenmodell
- `ClipboardItem` (`Model/ClipboardItem.swift`)
  - `id`, `content`, `timestamp`, `isPinned`
  - Source App-Metadaten
  - Attachment-Metadaten (inline/physisch)

## 5. Build- und Release-Prozess

### 5.1 Entwicklung
- Build: `swift build`
- Dev-Script: `Scripts/dev.sh`

### 5.2 Release
- Release-Build: `swift build -c release`
- App-Bundle wird durch Scripts oder manuell erstellt

### 5.3 Plattform- und Bundle-Mindestversion
- SPM-Target: `Package.swift` mit `.macOS("15.0")`
- Bundle-Mindestversion: `LSMinimumSystemVersion = 15.0` in `Info.plist`

### 5.4 Icons
- Kanonisches App-Icon: `Sources/Clipster/Resources/AppIcon.icns`
- Asset-Katalog: `Sources/Clipster/Resources/AppIcon.xcassets`
- `Scripts/generate_app_icon.sh` kopiert das kanonische ICNS an den Zielort und validiert Lesbarkeit

### 5.5 Aktuelle Release-Artefakte
- `Release/Clipster-2.4/Clipster.app`
- `Release/Clipster-2.4.1/Clipster.app`
- ältere Release-Verzeichnisse können zusätzlich vorhanden sein

## 6. Bekannte Hinweise und technische Schulden

1. Import-Flow
- Der produktive Import ist weiterhin nicht auf dem neuen Backup-Standard umgesetzt.

2. Historischer `PersistenceManager`
- Enthält teils ältere JSON/ZIP-Pfade.
- Der produktive Export läuft über `BackupExportService` + `ClipboardHistoryStore.exportHistory`.

3. Deprecation-Warnings
- Mehrere `onChange(of:perform:)`-Verwendungen sind ab macOS 14 als deprecated markiert.
- Aktuell Warnungen, keine Build-Blocker.

4. Release-Skripte
- Einige Skripte enthalten historisch gewachsene Texte/Defaults.
- Relevante Release-Werte sind immer mit `Info.plist` und `Package.swift` gegenzuprüfen.

## 7. Wichtige Verhaltensdetails (Regression-sensitive)

1. Interner Copy aus Popover darf kein neues Item erzeugen
- Beim Kopieren aus der App wird eine interne Notification mit `pasteboard.changeCount` gesendet.
- `ClipboardMonitor` ignoriert diesen Change gezielt.
- Relevant:
  - `Sources/Clipster/App/Notifications.swift`
  - `Sources/Clipster/Views/ClipboardItemRowView.swift`
  - `Sources/Clipster/Services/ClipboardMonitor.swift`

2. Item-Counter im Popover
- `totalItemCount` wird nicht bei jedem Event voll neu geladen.
- Refresh erfolgt batchweise nach jeweils 10 neu gespeicherten Items.
- Relevant: `ClipboardHistoryStore`

3. Export aus Popover
- Popover wird geschlossen, bevor der Export startet.
- Ziel: Fortschrittsfenster darf nicht vom Popover verdeckt werden.

4. Main-Window-Aktivierung
- Hauptfenster muss App in `.regular` bringen, damit App-Menü in der macOS-Menüleiste verfügbar ist.
- Rückschalten auf `.accessory` nur in explizitem Menüleisten-Only-Fall (`launchAtLogin && !startWithMainWindow`) bei geschlossenem Hauptfenster.

5. Backup-Inhalt und JSON-Semantik
- `history.json`: aktive Historie (`clipboard_history`)
- `archived.json`: Archiv (`recently_deleted`)
- Diese Trennung bewusst beibehalten.

6. Launchpad-/Bundle-Icon
- Entscheidend sind konsistente `Info.plist`-Keys und ein reales `AppIcon.icns` im Bundle.

## 8. Roadmap-Empfehlungen
- Import auf denselben modernen Backup-Standard heben wie Export
- Technische Konsolidierung (`PersistenceManager`)
- Unit-/Integrationstests einführen (mindestens Export/Import und ClipboardMonitor-Deduplizierung)
- Deprecation-Warnings (`onChange`) auf neue API umstellen
- Optional Signierung/Notarisierung und Distributionspipeline erweitern

---

## 9. LLM-Handover (für ein anderes Modell)
Dieser Abschnitt enthält projektrelevante Kontextinformationen aus dem bisherigen Verlauf, die nicht selbstverständlich aus dem Code alleine hervorgehen.

### 9.1 Produkt-/Verhaltensanforderungen aus dem Verlauf
1. Menüleisten-App-First
- Clipster läuft überwiegend als Menubar-App, Hauptfenster ist ergänzend.

2. Popover-Item-Zähler
- Realtime ist nicht zwingend erforderlich.
- Gewünscht: Aktualisierung in sinnvollen Batches (konkret: nach 10 neuen Items).

3. Export-Verhalten
- Export soll funktionieren aus Hauptfenster und Popover.
- Exportformat: ZIP aus SQLite-DB + JSON-Dumps + Settings + Attachments.
- Enthalten: `clipster.db`, `history.json`, `archived.json`, `settings.plist`, `attachments/`, `backup-manifest.json`.
- Bei längerer Vorbereitung: Fortschrittsfenster anzeigen.
- Danach Speichern-Dialog anzeigen.

4. Copy-Regression vermeiden
- Klick auf ein Item im Menubar-Popover darf beim Re-Copy kein neues History-Item erzeugen.
- Interne Clipboard-Writes müssen im Monitor dedupliziert/ignoriert werden.

5. Hauptfenster-Fokus
- Beim Öffnen des Hauptfensters muss die App als aktive App in der Menüleiste erscheinen.
- Nicht dauerhaft im `.accessory`-Modus bleiben, wenn Hauptfenster sichtbar ist.

6. Settings-Fenster
- Optische Entschlackung im oberen Bereich ist gewünscht, aber ohne Verlust der Window-Controls.
- Lösung basiert auf macOS-15-Toolbar-API.

### 9.2 Praktische Projektkonventionen aus dem Verlauf
1. Versions-/Build-Nummer
- Bei funktionalen Bugfix-Runden wurden Version/Builnummer aktiv hochgezogen.
- Aktuell: `2.4.1 (29)`.

2. Release-Bundle
- Zielstruktur typischerweise `Release/Clipster-<version>/Clipster.app`.

3. Icon-Quelle
- Kanonische Quelle ist `Sources/Clipster/Resources/AppIcon.icns`.
- Alternative/duplizierte Iconquellen vermeiden.

4. Plattform-Target
- Mindest-macOS ist auf `15.0` angehoben.
- SPM-Konfiguration nutzt `.macOS("15.0")`, damit das Manifest mit aktuellem `swift-tools-version` kompatibel bleibt.

### 9.3 Offene Punkte, die ein LLM als Nächstes sauber weiterführen kann
1. Import modernisieren
- Den derzeitigen Import-Placeholder in `ClipboardHistoryStore` auf das aktuelle Backupformat angleichen.

2. Testbarkeit
- Automatisierte Tests für Export-Integrität (`history.json`, `archived.json`, Manifest) ergänzen.

3. API-Modernisierung
- `onChange`-Verwendungen auf die nicht-deprecated Signatur umstellen.
