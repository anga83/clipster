# Clipster: Projektdokumentation

Stand: 24. November 2026

## Projekt und aktueller Stand

Clipster ist ein nativer macOS-Zwischenablage-Manager mit SwiftUI und AppKit. Die App läuft mit Menüleisten-Popover und optionalem Hauptfenster. App-Version und Build-Nummer werden in `Sources/Clipster/Resources/Info.plist` gepflegt (derzeit `2.6.1`, Build `40`). Mindestversion ist macOS 15.

Das Repository verwendet Swift Package Manager. Es gibt ein ausführbares Target `Clipster`, aber derzeit kein separates Test-Target. SQLite wird über `sqlite3` eingebunden. AppKit- und SwiftUI-Funktionen werden im Paket direkt verwendet.

## Nutzerfunktionen und Verhalten

- `ClipboardMonitor` fragt das System-Pasteboard regelmäßig ab und speichert Text sowie Datei-URLs lokal. Clipster ignoriert standardmäßig eigene Pasteboard-Schreibvorgänge und kann Quell-Apps über eine Blacklist ausschließen.
- Die Historie liegt in `~/Library/Application Support/Clipster/clipster.db`. Einstellungen werden in `settings.plist`, physisch ausgelagerte Anhänge im Unterordner `attachments/` gespeichert.
- Normales Anklicken eines Eintrags kopiert weiterhin den unformatierten Text. Wenn RTF-Daten vorliegen, ergänzt das Kontextmenü `Copy formatted`; dabei werden Klartext und RTF aufs Pasteboard geschrieben.
- Text- und Datei-Einträge haben unterschiedliche Aktionen. Dateien können per Quick Look angesehen, geöffnet oder in andere Apps gezogen werden. Lange Texte können separat angezeigt werden.
- Einträge lassen sich suchen, nach Quell-App, Pin-Status, Datum und Textlänge filtern, pinnen und löschen. Die Initialansicht lädt ein begrenztes aktuelles Set plus Pins; Suche und angewendete Filter fragen die ganze Datenbank ab. Filter im Hauptfenster werden zunächst als Entwurf gewählt und erst mit `Apply` abgefragt.
- Gelöschte Einträge werden zunächst ins Archiv verschoben und können wiederhergestellt oder endgültig gelöscht werden. Archiv-Retention für Text und Anhänge ist getrennt konfigurierbar.
- Der optionale globale Shortcut `⌥⌘V` erfasst das aktuelle Pasteboard auch dann, wenn die Quell-App auf der Blacklist steht.
- Vollbackup als ZIP enthält einen SQLite-Snapshot, JSON-Exporte aktiver und archivierter Einträge, Einstellungen und vorhandene Anhänge. Beim Import kann ein vollständiges Restore oder ein Merge gewählt werden.
- Merge erhält vorhandene Clips bei ID-Konflikten und behält die aktuellen Einstellungen. Replace stellt Datenbank, Einstellungen und Anhänge aus dem Backup wieder her. Der Bestätigungsdialog bietet außerdem einen Abbruch, der keine Anwendungsdaten ändert.

## Persistenz und Datenbank-Kompatibilität

`DatabaseManager` erstellt Tabellen bei Bedarf und ergänzt Schema-Erweiterungen über `ensureColumn(...)`. So können neue optionale Spalten auch in bereits vorhandenen Datenbanken angelegt werden. Unter anderem ist `formatted_content BLOB` in `clipboard_history` und `recently_deleted` nullable: ältere Datenbanken behalten ihre Einträge und funktionieren ohne Rich-Text-Funktion, bis die Migration beim Start die Spalte ergänzt.

DB-Verbindungen verwenden `SQLITE_OPEN_FULLMUTEX`, WAL und einen Busy-Timeout von 3000 ms. Änderungen an Schema und Queries müssen mit bestehenden Benutzer-Datenbanken kompatibel bleiben; destructive Migrationen sind zu vermeiden.

## Development

### Voraussetzungen und Build

- macOS 15 oder neuer
- Vollständiges Xcode unter `/Applications/Xcode.app` für den App-Icon-Build (`actool`)
- SwiftPM aus der Xcode-Toolchain

Das aktive `xcode-select` darf auf die Command Line Tools zeigen. Für Builds, die Xcode-Werkzeuge benötigen, `DEVELOPER_DIR` setzen:

```bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
xcodebuild -version
swift build
```

Das ausführbare Debug-Binary liegt unter `.build/debug/Clipster`; den Release-Build erzeugt `swift build -c release` unter `.build/release/Clipster`. SwiftPM erstellt selbst kein vollständiges `.app`-Bundle.

### App-Bundle lokal erstellen

Die aktuelle, vollständige manuelle Anleitung steht in [`Scripts/BUILD_COMMANDS.txt`](Scripts/BUILD_COMMANDS.txt). Wesentliche Details:

1. Binary aus `.build/release/Clipster` nach `Clipster.app/Contents/MacOS/Clipster` kopieren und ausführbar machen.
2. `Sources/Clipster/Resources/Info.plist` nach `Contents/Info.plist` kopieren.
3. Den Asset-Katalog `Sources/Clipster/Resources/AppIcon.xcassets` mit `xcrun --sdk macosx actool` nach `Contents/Resources` kompilieren. Das erzeugt `Assets.car` und `AppIcon.icns`; die einzelnen PNGs gehören nicht roh ins Bundle.
4. Bundle-Info prüfen, zum Beispiel mit `plutil -lint`.

Version und Build-Nummer für den Bundle-Metadatenstand in `Info.plist` pflegen. `Release/` und `.build/` sind ignorierte Build-Artefakte.

### GitHub Actions Release

`.github/workflows/release.yml` ist der maßgebliche automatisierte Distributionspfad:

- Läuft bei jedem Push auf `main` und manuell via `workflow_dispatch` auf einem GitHub-hosted `macos-15` Runner.
- Verwendet `actions/checkout@v5` (Node 24; v5 benötigt Runner 2.327.1 oder neuer) und lädt alle Tags sowie die vollständige Git-History.
- Liest `CFBundleShortVersionString` aus `Info.plist`, baut Binary und App-Bundle samt Icon, erstellt ein komprimiertes DMG und veröffentlicht es als GitHub Release `v<Version>`.
- Release Notes listen Commit-Betreffzeilen seit dem vorherigen `v*`-Tag. Falls noch kein Release-Tag existiert, wird beim Push dessen `before`-Commit als Startpunkt genutzt.
- Ein Versions-Tag wird nicht überschrieben: Gibt es `v<Version>` bereits, überspringt der Workflow Build und Veröffentlichung. Vor einem neuen Release deshalb Versionsnummer erhöhen und einen noch nicht verwendeten Tag sicherstellen.
- Workflow-Permissions sind auf `contents: write` begrenzt, damit `gh release create` Release und Tag veröffentlichen kann.
- Das DMG ist derzeit unsigniert und wird nicht notarisiert. Distribution ohne Apple Developer ID-Secrets ist dadurch möglich; Gatekeeper kann beim ersten Start eine manuelle Bestätigung erfordern.

### Release-Pipeline: Versionssprung bis GitHub Release

Für einen neuen Release ist kein lokaler App-Bundle-Build und kein manuell angelegter Git-Tag nötig. Der einheitliche Ablauf:

1. In `Sources/Clipster/Resources/Info.plist` `CFBundleShortVersionString` auf eine noch unveröffentlichte Version setzen und `CFBundleVersion` erhöhen.
2. Änderungen inklusive Versionssprung committen. Die Commit-Betreffzeilen werden als Changelog verwendet.
3. Den Commit auf `main` pushen (`git push origin main`). Jeder Push auf `main` startet die Action.
4. Die Action liest die Version, baut App und DMG, erstellt den Tag `v<Version>` und veröffentlicht das DMG als GitHub Release. Release Notes enthalten die Commit-Betreffzeilen seit dem vorherigen Versions-Tag.
5. Den Action-Lauf und das veröffentlichte Release auf GitHub prüfen.

Den Tag **nicht vorab lokal erstellen oder pushen**: `gh release create` legt ihn im Action-Lauf am gepushten Commit an. Existiert `v<Version>` bereits, überspringt die Action Build und Veröffentlichung; für jeden neuen Release ist daher ein Versionssprung erforderlich. Ein Push ohne Versionssprung startet zwar den Workflow, erzeugt aber keinen zweiten Release.

Xcode-Builds müssen auf einem Runner funktionieren, auf dem vollständige Xcode- und Command-Line-Tools verfügbar sind. Bei lokalen SwiftPM-/Asset-Katalog-Problemen sicherstellen, dass `DEVELOPER_DIR` auf Xcode zeigt. `actool` setzt die vollständige Xcode-Installation voraus.

## Architektur- und Änderungsleitlinien

- UI und Szenen: `ClipsterApp.swift`, `ContentView.swift` und `Views/`.
- App-Einstellungen: `Data/SettingsStore.swift`; DB und SQL: `Services/DatabaseManager.swift`.
- Pasteboard-Erfassung: `Services/ClipboardMonitor.swift`; fachliche Historienoperationen: `Data/ClipboardHistoryStore.swift`.
- Ein Clipboard-Eintrag und optionale Rich-Text-/Attachment-Daten: `Model/ClipboardItem.swift`.
- Backup-Erstellung: `Services/BackupExportService.swift`.
- Menüleisten-App-Icon und Dock-/App-Icon haben unterschiedliche Quellen: Menüleisten-Icon wird im SwiftUI-Label als SF Symbol `paperclip` gerendert; das Dock-/App-Icon kommt aus dem AppIcon-Asset-Katalog.
- Interne Pasteboard-Schreibvorgänge müssen vom Monitor ignoriert werden, damit das Kopieren eines Eintrags kein Duplikat in der Historie erzeugt.
- Initiales Laden soll begrenzt bleiben. Filterabfragen müssen auf der Datenbank laufen, damit ältere Einträge gefunden werden, ohne beim Öffnen des Filterdialogs die ganze Historie in den Speicher zu laden.
- Pins müssen in SQLite gespeichert werden und dürfen nicht allein aus dem UI-State abgeleitet werden.

## Relevante Dateien

- `Package.swift` – SwiftPM-Produkt, macOS-Zielplattform und SQLite-Link.
- `Sources/Clipster/Resources/Info.plist` – Bundle-Metadaten, App-Version, Build und Mindest-macOS.
- `Sources/Clipster/Resources/AppIcon.xcassets/` – App- und Dock-Icon-Quelldateien.
- `Scripts/BUILD_COMMANDS.txt` – lokale Bundle-Erstellung und Prüfung.
- `.github/workflows/release.yml` – CI-Build, DMG und Release-Erstellung.
- `README.md` – Endnutzer-Dokumentation für GitHub.

## Bekannte Einschränkungen

- Das Release-DMG wird nicht signiert oder notarisiert.
- Im Quellcode bestehen SwiftUI-Deprecation- und Concurrency-Warnungen; vor Änderungen an den betroffenen Pfaden auf mögliche Regressionen achten.
