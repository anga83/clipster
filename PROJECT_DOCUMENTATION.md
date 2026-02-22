# Clipster - Projektdokumentation

Stand: 22.02.2026

## 1. Projektüberblick
Clipster ist ein Clipboard-Manager für macOS (Swift/SwiftUI), der primär als Menüleisten-App läuft und optional ein Hauptfenster anbietet.

Ziele:
- Zwischenablage-Historie persistent speichern
- Text und Datei-Referenzen verwalten
- Inhalte schnell suchen, filtern, pinnen und erneut kopieren
- Historie inklusive Metadaten/Anhängen exportieren

## 2. Aktueller Versionsstand
- App-Version: `2.5.1`
- Build-Nummer: `35`
- Mindest-macOS: `15.0`
- Copyright: `2026`
- Quelle:
  - `Sources/Clipster/Resources/Info.plist`

## 3. Hauptfunktionen

### 3.1 Clipboard-Historie
- Polling-basierte Überwachung der systemweiten Zwischenablage
- Speicherung in SQLite (`clipster.db`)
- Unterstützte Inhalte:
  - Text
  - Datei-URLs
- Duplikat-Schutz für direkt aufeinanderfolgende identische Inhalte

### 3.2 Menüleisten-App und Hauptfenster
- Menüleisten-Popover mit Suche, Verlauf und Footer-Menü
- Optionales Hauptfenster mit erweitertem Workflow
- Aktivierungs-/Fokuslogik regressionssensitiv:
  - Beim Öffnen des Hauptfensters wird die App als `.regular` aktiviert.
  - Das Hauptfenster muss als aktive App im Vordergrund erscheinen.
  - Menüleisten-App-Modus (`.accessory`) nur im expliziten Menüleisten-Only-Fall.

### 3.3 Suche und Filter (aktuelle Architektur)
Zielkonflikt Performance vs. Vollständigkeit wurde explizit aufgelöst:

- Startverhalten:
  - Initial werden **nicht alle** Items geladen.
  - Geladen werden: alle gepinnten + eine konfigurierbare Anzahl aktueller ungepinnter Items.
- Suche/Filter-Verhalten:
  - Sobald Suche oder aktive Filter greifen, wird die **gesamte DB** abgefragt.
  - Damit werden auch ältere Einträge gefunden, die nicht im Initial-Subset liegen.

Aktuelle Filterkriterien:
- Mehrfachauswahl bei Apps (`App Filter`)
- `Pinned only`
- Datumsbereich (`Oldest date` bis `Newest date`)
- Textlänge:
  - Minimum
  - Maximum oder `Unlimited maximum` (nur Untergrenze aktiv)

### 3.4 Filter-UX (Apply-Workflow)
Der Filterdialog im Hauptfenster wurde auf einen performanten Apply-Workflow umgestellt:

1. Klick auf Filter-Button
2. Es werden nur Metadaten geladen:
   - eindeutige App-Liste
   - ältestes/neuestes Datum
3. Nutzer wählt Filter (Draft-Zustand, noch ohne Query)
4. Klick auf `Apply`
5. Erst dann DB-Query mit den exakten Kriterien

Weitere Details:
- Filterdialog zeigt Ladezustand für Metadaten
- Keine Vollabfrage beim bloßen Öffnen des Dialogs
- `Export Filtered JSON` exportiert die aktuell angewendete Query-Menge

### 3.5 Item-Aktionen
Pro Item (Kontextmenü):
- `Copy`
- `Pin/Unpin`
- `Delete`
- Datei-Items zusätzlich:
  - `Quick Look`
  - `Open`
- Text-Items zusätzlich:
  - `Show full text`

`Show full text` öffnet den vollständigen Text in einem großen, scrollbaren QuickLook-Fenster (technisch über temporäre UTF-8-`.txt`-Datei).

### 3.6 Archiv (Recently Deleted)
- Soft-Delete nach `recently_deleted`
- Wiederherstellen einzelner Einträge
- Permanentes Löschen
- Retention/Cleanup für Text und Attachments

### 3.7 Export/Backup
Vollbackup als ZIP enthält:
- `clipster.db` (SQLite-Snapshot)
- `history.json` (aktive Historie aus `clipboard_history`)
- `archived.json` (Archiv aus `recently_deleted`)
- `settings.plist` (falls vorhanden)
- `attachments/` (falls vorhanden)
- `backup-manifest.json`

Wichtige Semantik:
- `history.json` bleibt aktive Historie.
- `archived.json` enthält Archivdaten separat.

Wichtige UX:
- Wird Export aus dem Popover gestartet, schließt sich das Popover zuerst, damit das Fortschrittsfenster sichtbar bleibt.

### 3.8 Menüs (aktueller Endstand)
Menüleisten-Popover (Footer-Gear-Menü):
- `Open Main Window`
- `Import History...`
- `Export History...`
- `Quit Clipster`

Bewusst entfernt:
- `Clear History...`
- `Open Settings`

Hinweis: `Clear History` existiert weiterhin als Aktion im Hauptfenster-Toolbar-Workflow.

### 3.9 Settings-UI
- Obere, inhaltlich unnötige graue Leiste entfernt
- Mehr Platz für eigentliche Einstellungen
- Fenster-Controls (inkl. Schließen) bleiben erhalten

## 4. Technischer Aufbau

### 4.1 Technologien
- Swift Package Manager
- SwiftUI + AppKit
- SQLite3 via C-Bindings

### 4.2 Relevante Dateien
- `Sources/Clipster/ClipsterApp.swift`
  - App-Entry, Szenen, Aktivierungslogik
- `Sources/Clipster/ContentView.swift`
  - Haupt-UI, Popover-UI, Filterdialog, Query-Trigger, Export Filtered JSON
- `Sources/Clipster/Views/ClipboardItemRowView.swift`
  - Item-Kontextmenü, inkl. `Show full text`
- `Sources/Clipster/Data/ClipboardHistoryStore.swift`
  - Store-Logik, Filter-Metadaten, Filter-Queries, Pin-Handling
- `Sources/Clipster/Services/DatabaseManager.swift`
  - SQLite-Schema/CRUD, Query-Bau, DB-Öffnung/Thread-Safety
- `Sources/Clipster/Services/BackupExportService.swift`
  - ZIP-Backup-Aufbereitung
- `Sources/Clipster/Services/ExportProgressWindowController.swift`
  - Fortschrittsfenster

### 4.3 Datenablage
Unter `~/Library/Application Support/Clipster/`:
- `clipster.db`
- `settings.plist`
- `attachments/`

## 5. Kritische Erkenntnisse und behobene Probleme aus diesem Chat

### 5.1 Pin-Persistenz
Problem:
- Gepinnte Einträge waren in der UI sichtbar, wurden aber teils nicht persistent in DB gespeichert.
- Folge: Nach App-Neustart erschienen alle als ungepinnt.

Fixes:
- Robustes Pin-Update in `DatabaseManager.updatePinnedStatus(...)`
- Sichere String-Bindings
- Logging, wenn ein Pin-Update 0 Zeilen betrifft (`sqlite3_changes == 0`)
- Pin/Unpin funktioniert auch für Items außerhalb des initial geladenen Subsets

Erkenntnis:
- Bereits verlorene Pins sind ohne altes Backup im Regelfall nicht zuverlässig rekonstruierbar.
- Teilweise historische Hinweise können über `recently_deleted.was_pinned` existieren, aber nicht vollständig für aktive Historie.

### 5.2 Filter-Crash beim Anwenden (EXC_BAD_ACCESS in sqlite3Prepare)
Beobachtung:
- Crash auf Background-Queue beim `sqlite3_prepare_v2` während Filter-Query.

Fix:
- DB-Öffnung auf `sqlite3_open_v2(..., SQLITE_OPEN_FULLMUTEX)` umgestellt
- `sqlite3_busy_timeout(..., 3000)` gesetzt
- Zusätzliches Fehlerlogging bei `prepare`-Fehlern

### 5.3 Filter-Performance
Problem:
- Vollhistorie im RAM für Filter führte zu Hängern beim Öffnen/Anpassen.

Fix:
- Metadatenladung getrennt von Ergebnissuche
- Draft-Filter + explizites `Apply`
- Query nur bei tatsächlicher Anwendung

### 5.4 Export-Zuverlässigkeit
- Export enthält jetzt konsistent DB + JSON-Dumps (`history.json`, `archived.json`)
- Export aus Popover schließt Popover vorher
- Snapshot-/JSON-Pfade wurden robuster gemacht

## 6. Build- und Release-Prozess (aktuell)

### 6.1 Aktive Vorgehensweise
Die Release-Erstellung erfolgt derzeit **ohne alte Skripte**, per direkten Shell-Befehlen.

Referenz:
- `Scripts/BUILD_COMMANDS.txt`

### 6.2 Skriptstruktur
- Alte Skripte wurden verschoben nach:
  - `Scripts/old/`
- Dort liegen u. a.:
  - `build_release.sh`
  - `release.sh`
  - `dev.sh`
  - `generate_app_icon.sh`

### 6.3 Aktuelle Release-Artefakte
- `Release/Clipster-2.5/Clipster.app`
- `Release/Clipster-2.5.1/Clipster.app`
- ältere Release-Ordner zusätzlich vorhanden

## 7. Regression-sensitive Verhaltensdetails

1. Interner Re-Copy darf kein neues History-Item erzeugen
- Interne Clipboard-Änderungen werden im Monitor erkannt und ignoriert.

2. Initiale Last gering halten
- Nicht volle DB laden beim Start.
- Trotzdem Suche/Filter über gesamte DB gewährleisten.

3. Pinned-Status ist persistenter Wahrheitswert
- UI darf nicht alleinige Quelle sein.
- DB-Update muss zuverlässig und prüfbar erfolgen.

4. Filterdialog darf nicht blockieren
- Nur Metadaten laden beim Öffnen.
- Ergebnisse erst bei `Apply`.

5. Menubar-Export
- Popover vorher schließen, damit Fortschrittsfenster sichtbar ist.

## 8. Bekannte technische Schulden

1. Import-Flow
- Import in `ClipboardHistoryStore` ist weiterhin Placeholder.

2. Deprecation-Warnings
- Mehrere `onChange(of:perform:)`-Verwendungen sind deprecated.

3. Concurrency-Warnings
- `Sendable`-Warnings rund um `DatabaseManager` in async-Kontexten bestehen weiterhin.

## 9. QA-Checkliste vor Release

- Pin/Unpin setzen, App neu starten, Persistenz prüfen
- `Pinned only`-Filter mit vorhandenen Pins prüfen
- Filterdialog öffnen: keine UI-Hänger
- Filter anwenden: kein Crash
- Textlängenfilter mit `Unlimited maximum` prüfen
- `Show full text` bei langen Texten prüfen
- Export aus Popover starten: Fortschrittsfenster sichtbar
- ZIP-Inhalt validieren (`clipster.db`, `history.json`, `archived.json`, Manifest)

## 10. Handover-Kurzfassung
Für Folgearbeit sind diese Punkte zentral:
- Architekturentscheidung: Initial-Subset + Full-DB bei Suche/Filter ist bewusst.
- Pinned-Persistenz und DB-Thread-Safety waren reale Produktionsprobleme und wurden explizit adressiert.
- Release-Prozess ist derzeit bewusst einfach (direkte Commands), alte Skripte sind archiviert unter `Scripts/old`.
