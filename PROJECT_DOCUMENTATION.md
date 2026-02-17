# Clipster - Projektdokumentation

## 1. Projektüberblick
Clipster ist ein in Swift/SwiftUI entwickelter Clipboard-Manager für macOS (ab macOS 13), der primär als Menüleisten-App genutzt wird und optional ein Hauptfenster anbietet.

Ziel der App:
- Zwischenablage-Historie dauerhaft speichern
- Text und Datei-Referenzen verwalten
- Elemente durchsuchen, filtern, pinnen und wiederverwenden
- Daten exportieren/sichern

## 2. Aktueller Versionsstand
- App-Version: `2.2.1`
- Build-Nummer: `23`
- Quelle: `Sources/Clipster/Resources/Info.plist`

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

### 3.3 Suche und Filter
- Volltextsuche über Historie
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
- Export als vollständiges ZIP-Backup mit:
  - `clipster.db` (SQLite Snapshot)
  - `settings.plist`
  - `attachments/`
  - `backup-manifest.json`
- Während der Vorbereitung wird ein kleines Fortschrittsfenster eingeblendet
- Danach öffnet sich ein Speichern-Dialog (`NSSavePanel`)

### 3.8 Import
- Import-Flow ist im `ClipboardHistoryStore` derzeit noch Placeholder
- Historischer `PersistenceManager` enthält Import-/Export-Logik (JSON/ZIP), ist aber nicht der aktive Primary-Flow des aktuellen Exports

### 3.9 Global Shortcut
- Optional aktivierbar
- Shortcut für manuelles Capture (`Option+Command+V` laut UI-Text)

### 3.10 UX-Verbesserungen
- Tooltips für die Top-Bar-Icons im Hauptfenster (Import, Export, Clear, Select)
- Dynamisches Build-Datum im About-Dialog (aus Binary-Timestamp)

## 4. Technischer Aufbau

### 4.1 Technologien
- Swift Package Manager (SPM)
- SwiftUI
- AppKit (Panels, Windowing, Pasteboard-nahe Funktionen)
- SQLite3 (direkt via C-Binding)

### 4.2 Projektstruktur
- `Sources/Clipster/ClipsterApp.swift`
  - App-Entry, Szenen, Window/MenuBarExtra
- `Sources/Clipster/ContentView.swift`
  - Haupt-UI und Popover-Inhalt
- `Sources/Clipster/Data/ClipboardHistoryStore.swift`
  - State-Management, History-Operationen, Export-Start
- `Sources/Clipster/Data/SettingsStore.swift`
  - Persistente Settings (`settings.plist`)
- `Sources/Clipster/Services/DatabaseManager.swift`
  - SQLite-Schema + CRUD + Archivlogik
- `Sources/Clipster/Services/ClipboardMonitor.swift`
  - Polling-basierte Clipboard-Überwachung
- `Sources/Clipster/Services/BackupExportService.swift`
  - ZIP-Backup-Erstellung (inkl. SQLite-Snapshot)
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

### 5.3 Icons
- Kanonisches App-Icon: `Sources/Clipster/Resources/AppIcon.icns`
- Asset-Katalog: `Sources/Clipster/Resources/AppIcon.xcassets`
- `Scripts/generate_app_icon.sh` kopiert das kanonische ICNS an den Zielort und validiert Lesbarkeit

### 5.4 Aktuelle Release-Artefakte
- `Release/Clipster-2.2.1/Clipster.app`
- ältere Release-Verzeichnisse können zusätzlich vorhanden sein

## 6. Bekannte Hinweise und technische Schulden

1. SPM-Warnung zu `AppIcon.icns`
- Da in `Package.swift` nur `AppIcon.xcassets` als Resource deklariert ist, meldet SPM `AppIcon.icns` derzeit als unhandled file.
- Das ist für den Build nicht kritisch, sollte aber langfristig sauber im Paketmodell berücksichtigt oder bewusst außerhalb des Target-Resource-Pfads gehalten werden.

2. Historischer `PersistenceManager`
- Enthält teils ältere JSON/ZIP-Pfade.
- Der aktuelle produktive Backup-Export läuft über `BackupExportService` + `ClipboardHistoryStore.exportHistory`.

3. Konsolidierung von Altdateien
- Es gibt Dateien mit `_NEW`-Suffix (z. B. `ArchiveView_NEW.swift`, `ClipboardHistoryStore_NEW.swift`), die geprüft/aufgeräumt werden sollten.

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

3. Launchpad-/Bundle-Icon
- Entscheidend sind konsistente `Info.plist`-Keys und ein reales `AppIcon.icns` im Bundle.

## 8. Roadmap-Empfehlungen
- Import auf denselben modernen Backup-Standard heben wie Export
- Technische Konsolidierung (`PersistenceManager`, `_NEW`-Dateien)
- Unit-/Integrationstests einführen (aktuell keine echte automatisierte Test-Suite)
- Optional Signierung/Notarisierung und Distributionspipeline erweitern

---

## 9. LLM-Handover (für ein anderes Modell)
Dieser Abschnitt enthält projektrelevante Kontextinformationen aus dem bisherigen Verlauf, die nicht selbstverständlich aus dem Code alleine hervorgehen.

### 9.1 Produkt-/Verhaltensanforderungen aus dem Verlauf
1. Menüleisten-App-First
- Clipster läuft überwiegend als Menubar-App, Hauptfenster ist ergänzend.

2. Icon/Launchpad
- Es gab explizit ein Problem „Icon sichtbar in Dock/Applications, aber nicht in Launchpad".
- Erwartung: reproduzierbar korrektes App-Icon im Bundle, keine fehleranfällige Icon-Erzeugungskette.

3. Popover-Item-Zähler
- Realtime ist nicht zwingend erforderlich.
- Gewünscht: Aktualisierung in sinnvollen Batches (konkret: nach 10 neuen Items).

4. Export-Verhalten
- Export soll funktionieren aus Hauptfenster und Popover.
- Gewünscht ist ein vollständiges Backupformat als ZIP aus SQLite-DB, Settings, Attachments.
- Wenn Vorbereitung länger dauert: kleines Fortschrittsfenster anzeigen.
- Anschließend soll ein Speichern-Dialog erscheinen.

5. Copy-Regression vermeiden
- Klick auf ein Item im Menubar-Popover darf beim Re-Copy kein neues History-Item erzeugen.
- Interne Clipboard-Writes müssen im Monitor dedupliziert/ignoriert werden.

6. Hauptfenster-Toolbar
- Icons in der Top-Bar benötigen Tooltips (Bedeutung nicht selbsterklärend).

7. Build Date im About
- Muss das tatsächliche Build-Datum anzeigen, nicht hartcodiert.

### 9.2 Praktische Projektkonventionen aus dem Verlauf
1. Versions-/Build-Nummer
- Bei funktionalen Bugfix-Runden wurde die Version/Builnummer aktiv hochgezogen.
- Aktuell: `2.2.1 (23)`.

2. Release-Bundle
- Zielstruktur typischerweise `Release/Clipster-<version>/Clipster.app`.

3. Icon-Quelle
- Kanonische Quelle ist jetzt `Sources/Clipster/Resources/AppIcon.icns`.
- Vermeide alternative/duplizierte Iconquellen und defekte `iconset`-Pfadnutzung.

### 9.3 Offene Punkte, die ein LLM als Nächstes sauber weiterführen kann
1. Import modernisieren
- Den derzeitigen Import-Placeholder in `ClipboardHistoryStore` auf das neue Backupformat angleichen.

2. Resource-Warnung entschärfen
- Umgang mit `AppIcon.icns` in `Package.swift` sauber definieren (oder Ordnerlayout anpassen).

3. Doku-/Code-Konsolidierung
- Alte/duplizierte Artefakte und `_NEW`-Dateien prüfen und ggf. entfernen.

4. Testbarkeit
- Automatisierte Tests (mindestens für Export/Import und ClipboardMonitor-Deduplizierung) ergänzen.

