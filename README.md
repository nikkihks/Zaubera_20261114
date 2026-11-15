# Zaubera

Plattformübergreifendes **Wizard-Stichspiel** entwickelt mit **Godot 4.7.2** (GL Compatibility) für **Android** sowie einem direkt integrierten **HTTP/WebSocket-Browser-Client** für **iOS / Safari** und Desktop.

## Features

- **Vollständige Wizard-Regeln:** 60 Karten (4 Farben 1–13, 4 Zauberer, 4 Narren), 3–6 Spieler (KI-Bots optional), umschaltbare **Plus/Minus-Eins-Regel** (`Summe ≠ Rundenstiche`), Trumpfwahl beim Aufdecken eines Zauberers und Punktewertung.
- **Cross-Play ohne App-Store-Zwang für iOS:** Der Android-Host startet automatisch einen lokalen Server (HTTP `:8080`, WebSocket `:8081`, UDP-Discovery) und zeigt einen **QR-Code** in der Lobby. iPhone- und Browser-Mitspieler scannen den Code und spielen im selben WLAN/Hotspot direkt im Browser mit.
- **Einheitliches Design & Touch-Steuerung:** Fächerhand mit Daumen-Scrub, Hochwischen auf die zentrale leuchtende Rune zum Ausspielen, Soundeffekte, Runden-Timeline und Sternenhimmel-Punktegraph in App und Web.

## Projektstruktur

| Pfad | Beschreibung |
| :--- | :--- |
| `scenes/Main.tscn` | Haupteinstiegsszene (`project.godot` -> `run/main_scene`) |
| `scripts/main.gd` | UI-Aufbau, Spieltisch, Phasensteuerung & Animationslogik |
| `scripts/wizard_rules.gd` | Deck, Stichauswertung, Bedienpflicht & Punkteregeln |
| `scripts/wizard_server.gd` | Autoritativer Spielserver, Bot-KI, HTTP/Asset-Auslieferung & WebSocket-Host |
| `scripts/wizard_client.gd` | WebSocket-Client & Netzwerkkommunikation |
| `scripts/hand_fan.gd` | Interaktiver Kartenfächer, Scrubbing & Swipe-up-Ausspielgeste |
| `scripts/card_view.gd` | Darstellung und Hervorhebung einzelner Spielkarten |
| `scripts/progress_widgets.gd` | Sternenhimmel-Punktegraph & Runden-Timeline |
| `scripts/qr_generator.gd` | Lokale QR-Code-Generierung für den Lobby-Beitritt |
| `scripts/audio_fx.gd` | Prozedurale Soundeffekte |
| `web/index.html` | Browser-/iOS-Client mit identischem UI und WebSocket-Protokoll |
| `assets/` | Karten-/UI-Grafiken, Fonts (`Cinzel`), Sounds (`sfx/`) und Blender-Quellen (`blender/`) |
| `tests/run_tests.gd` | Automatisierte Regel-, UI- und End-to-End-Tests |
| `export_presets.cfg` | Export-Voreinstellungen für Android (`go.android.apk`) und iOS |

## Voraussetzungen & Setup

1. **Godot Engine 4.7.2** (Standard-Version mit Android Export Templates für APK-Builds) installieren.
2. Repository klonen und `project.godot` in Godot öffnen (der `.godot/`-Import-Cache wird automatisch neu erstellt).

## Tests & Export

### Automatisierte Tests (Headless)
```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd
```

### Android-APK bauen (Debug-signiert)
```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-debug "Android" "go.android.apk"
```
