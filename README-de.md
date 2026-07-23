<p align="center">
  <!-- BATHOS_LANDING_URL — replace href="#" with the landing-page URL once the landing page is live (same marker in all language READMEs) -->
  <a href="#"><img src=".github/assets/bathos-lockup-transparent.png" alt="BATHOS" width="480"></a>
</p>

# BATHOS

[English](README.md) · [한국어](README-kr.md) · [Español](README-es.md) · **Deutsch** · [日本語](README-ja.md)

> **βάθος** (Griechisch) — *„Tiefe, der Abgrund.“* Eine AI-Workflow-Agent-Methode mit überwältigender Tiefe, im bewussten Gegensatz zu oberflächlicher KI-Unterstützung.

![version](https://img.shields.io/badge/version-0.2.0-0e9aa1)
![license](https://img.shields.io/badge/license-MIT-blue)
![engine](https://img.shields.io/badge/engine-Rust-d2691e)
![runtime](https://img.shields.io/badge/runtime-Claude%20Code%20v2.1.32%2B-7b61ff)
![status](https://img.shields.io/badge/status-v0.2.0%20early%20%C2%B7%20dogfood--verified-c8841a)

BATHOS verwandelt eine **einzelne Claude-Code-Sitzung in ein diszipliniertes Produktteam** — 17 Spezialistenrollen, eine 7-Wellen-Lieferpipeline, skalenadaptives Routing und harte Qualitäts-Gates — gestützt durch eine kleine **Rust-Engine**, die die kritischen Invarianten deterministisch macht statt nach Bauchgefühl.

> **한국어:** BATHOS는 Claude Code 위에서 **17역할 × 7웨이브 × Scale-Adaptive Lv0~4**로 제품 개발을 오케스트레이션하는 메서드 패키지입니다. 처음이라면 **[활용 사례(새 서비스 만들기)](docs/USECASE-kr.md)** → **[특징·구동원리](docs/FEATURES-kr.md)** → **[사용 가이드](docs/USAGE-kr.md)** 순서를 권장합니다. (운영 규칙: [`CLAUDE.md`](CLAUDE.md) · 원칙: [`ETHOS.md`](ETHOS.md))

---

## Inhaltsverzeichnis

- [Dokumentation](#documentation)
- [Warum BATHOS](#why-bathos)
- [Wie es funktioniert: zwei Ebenen](#how-it-works-two-planes)
- [Voraussetzungen](#requirements)
- [Schnellstart](#quick-start)
- [Die 7-Wellen-Pipeline](#the-7-wave-pipeline)
- [Skalenadaptives Routing (Lv0–4)](#scale-adaptive-routing-lv04)
- [Qualitäts-Gates](#quality-gates)
- [CLI-Referenz (`bathos`-Engine)](#cli-reference-bathos-engine)
- [Slash-Befehle](#slash-commands)
- [Die 17 Rollen](#the-17-roles)
- [Plugin-Module](#plugin-modules)
- [Sicherheits-Hooks](#safety-hooks)
- [Repository-Aufbau](#repository-layout)
- [Konfiguration](#configuration)
- [Projektstatus](#project-status)
- [Wie BATHOS gebaut wurde (Dogfooding)](#how-bathos-was-built-dogfooding)
- [Mitwirken](#contributing)
- [Lizenz & Zuschreibung](#license--attribution)

---

## Dokumentation

| Dokument | English | 한국어 | Español | Wofür es gedacht ist |
|-----|:----------:|:---------:|:---------:|---------------|
| **Anwendungsfall** — ein neues Dienstangebot Schritt für Schritt aufbauen | [`docs/USECASE-en.md`](docs/USECASE-en.md) | [`docs/USECASE-kr.md`](docs/USECASE-kr.md) | [`docs/USECASE-es.md`](docs/USECASE-es.md) | Hier anfangen: eine praxisnahe Anleitung (in Ihr eigenes Projekt übernehmen, „ReadShelf“ von Anfang bis Ende aufbauen) |
| **Funktionen & Betriebsprinzipien** | [`docs/FEATURES-en.md`](docs/FEATURES-en.md) | [`docs/FEATURES-kr.md`](docs/FEATURES-kr.md) | [`docs/FEATURES-es.md`](docs/FEATURES-es.md) | Was BATHOS besonders macht und wie die Engine unter der Haube arbeitet |
| **Nutzungshandbuch** | [`docs/USAGE-en.md`](docs/USAGE-en.md) | [`docs/USAGE-kr.md`](docs/USAGE-kr.md) | [`docs/USAGE-es.md`](docs/USAGE-es.md) | Referenz: Installation, CLI, Wellen, Gates, Hooks, Fehlerbehebung |
| **Token- & Kontingentverwaltung** | [`docs/QUOTA-en.md`](docs/QUOTA-en.md) | [`docs/QUOTA-kr.md`](docs/QUOTA-kr.md) | [`docs/QUOTA-es.md`](docs/QUOTA-es.md) | Kosten steuern, Wellen sequenzieren, sich von Nutzungslimits erholen |
| **Erstellung eigener Module** | [`docs/MODULE-GUIDE-en.md`](docs/MODULE-GUIDE-en.md) | [`docs/MODULE-GUIDE-kr.md`](docs/MODULE-GUIDE-kr.md) | [`docs/MODULE-GUIDE-es.md`](docs/MODULE-GUIDE-es.md) | Schreiben Sie Ihr eigenes Plugin (module.yaml, Trigger-DSL, W4), ohne den Kern anzufassen |
| **Rollenanpassung** | [`docs/ROLE-GUIDE-en.md`](docs/ROLE-GUIDE-en.md) | [`docs/ROLE-GUIDE-kr.md`](docs/ROLE-GUIDE-kr.md) | [`docs/ROLE-GUIDE-es.md`](docs/ROLE-GUIDE-es.md) | Passen Sie die 17 Rollen über das 3-Schichten-Override an (base → team → user) |
| **Architektur** (für Mitwirkende) | [`docs/ARCHITECTURE-en.md`](docs/ARCHITECTURE-en.md) | [`docs/ARCHITECTURE-kr.md`](docs/ARCHITECTURE-kr.md) | [`docs/ARCHITECTURE-es.md`](docs/ARCHITECTURE-es.md) | Crate-Karte, Invarianten (A9, Gate, Audit), Exit-/Fehlercodes, Mitwirken |
| **FAQ** | [`docs/FAQ-en.md`](docs/FAQ-en.md) | [`docs/FAQ-kr.md`](docs/FAQ-kr.md) | [`docs/FAQ-es.md`](docs/FAQ-es.md) | Häufige Fragen & Fehlerbehebung |
| **Betriebsregeln / Prinzipien** | [`CLAUDE.md`](CLAUDE.md) · [`ETHOS.md`](ETHOS.md) | | | Betriebsregeln des Teams und das von gstack abgeleitete ETHOS |

> **Neu hier?** Lesen Sie **Anwendungsfall** → **Funktionen** → **Nutzungshandbuch**.

---

## Warum BATHOS

Eine einzelne lange LLM-Konversation driftet: Kontext geht zwischen „Design“ und „Bau“ verloren, Qualitätsprüfungen werden übersprungen, und dasselbe Modell schreibt und genehmigt seine eigene Arbeit. BATHOS ersetzt das durch Struktur.

| Einfacher LLM-Chat | BATHOS |
|---|---|
| Eine Konversation, wachsende Kontextdrift | **17 Spezialistenrollen** über eine **7-Wellen**-Pipeline |
| Kontext geht zwischen Design ↔ Implementierung verloren | **Zero-Context-Loss** eigenständige Story-Dateien (Welle 3) |
| Implizite, pauschale Anstrengung | **Skalenadaptiver Router** — explizit Lv0–4 |
| Implementierung beginnt irgendwann | **Hartes Readiness-Gate** blockiert den Bau physisch bei `FAIL` |
| Der Autor „verifiziert“ auch | **Unabhängige Prüfer** + manipulationssichere Audit-Kette |
| Ratschläge, die Sie stillschweigend übergehen | **User Sovereignty** — die KI schlägt vor, *Sie* entscheiden |

Das Ergebnis: Eine einzelne Person kann ein KI-Team durch Discovery → Design → Implementierung → Verifikation führen, mit Nachvollziehbarkeit und Gates bei jedem Schritt.

---

## Wie es funktioniert: zwei Ebenen

Dies ist das wichtigste Einzelkonzept. BATHOS läuft auf **zwei Schichten**:

| Ebene | Was es ist | Was es tut | Wer es steuert |
|---|---|---|---|
| **Orchestrierung** | Markdown-**Slash-Befehle**, **Rollen** und **Hooks** unter `.claude/` | Führt Wellen aus; spawnt / prüft / fährt Teammitglieder herunter | Der **Lead (Paul)** — Ihre Haupt-Claude-Code-Sitzung |
| **Engine** | Eine einzelne statische Rust-Binärdatei, **`bathos`** | Berechnet & *erzwingt* Zustand, Gates, Wellenübergänge, Routing, Story-Aktualität, Plugins | Automatisch aufgerufen durch Hooks & Befehle (`bathos <subcommand>`) |

Sie tippen meistens **Slash-Befehle** (z. B. `/wave1-discovery`). Die `bathos`-Binärdatei ist der deterministische Kern, den diese Befehle und Hooks darunter aufrufen — und Sie können sie auch direkt ausführen.

---

## Voraussetzungen

- **[Claude Code](https://claude.com/claude-code) v2.1.32+** mit aktivierter experimenteller **Agent Teams**-Funktion
  (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; die mitgelieferte `.claude/settings.json` setzt sie bereits)
- **Rust-Toolchain** (cargo 1.92+ verifiziert) — zum Bauen der Engine
- **`jq`** — von den Sicherheits-Hooks zum Parsen von JSON verwendet
- Eine POSIX-Shell-Umgebung (macOS/Linux); Hooks sind bash

---

## Schnellstart

### 1. Code holen & Engine bauen

```bash
git clone <your-fork-url> bathos && cd bathos

# Build the single static engine binary (~5.9 MB)
cd core
cargo build --release          # → core/target/release/bathos
cargo test                     # 510 tests, all green (optional sanity check)
cd ..

# Make the engine discoverable by hooks/commands:
export BATHOS_BIN="$(pwd)/core/target/release/bathos"
#   …or add core/target/release to your PATH
```

### 2. BATHOS in einem Projekt verwenden

**Option A — dieses Repo als Arbeitsverzeichnis nutzen.** Das Verzeichnis `.claude/` (Befehle, Agenten, Hooks, Einstellungen) ist bereits verdrahtet; öffnen Sie Claude Code einfach hier.

**Option B — in Ihr eigenes Projekt übernehmen.** Kopieren Sie `.claude/` (Befehle, Agenten, Hooks, `settings.json`), `assets/` und `modules/` in Ihr Projekt-Stammverzeichnis und setzen Sie dann `BATHOS_BIN` wie oben.

### 3. Die Pipeline steuern (Slash-Befehle, in Claude Code)

```text
/team-kickoff                       # scaffold .agent-team/ + charter + manifest
/route        /abs/path/to/project  # analyze "stakes" → recommend Lv0–4 (you confirm)
/wave1-discovery   /abs/path        # discovery + market research
/wave2-design      /abs/path        # planning · architecture · design
/wave3-story-gate  /abs/path        # ★ condense to story files + readiness gate
/wave5-implement   /abs/path        # implementation
/wave6-verify-report /abs/path      # verification · docs · report
/team-confirm                       # final sign-off + cleanup
```

### Die Engine direkt ausprobieren

```bash
# Recommend a Scale-Adaptive level from "stakes" (recommend only; does not commit)
echo '{"scope":"feature","novelty":true,"regulation_ip":false,"team_size":"medium"}' \
  | bathos --state-dir .agent-team/_state route decide
#   → {"recommended_level":2,"wave_set":[...],"role_set":[...],"requires_confirmation":true}
```

---

## Die 7-Wellen-Pipeline

```
(pre) kickoff → W0 Analysis → W1 Discovery → W2 Design
        → W3 Story Gate ★ → W5 Implementation → W6 Verify → (post) Confirm
                                  ↑
                       W4 IP & Research  (optional plug-in, off the critical path)
```

Hauptlinien-Abhängigkeit: **W0 → W1 → W2 → W3 → W5 → W6**. W4 (IP & Forschung) ist ein optionales Plug-in, das jederzeit nach W2 ausführbar ist.

| Befehl | Welle | Team (parallel) | Gate |
|---|---|---|---|
| `/team-kickoff` | (vor) | nur Lead | — |
| `/wave0-analysis` | **W0** Analyse (optional) | Caleb | Brief Readiness |
| `/wave1-discovery` | **W1** Discovery & Markt | John ∥ Caleb | USP Readiness |
| `/wave2-design` | **W2** Planung · Architektur · Design | Joshua → (James, Jonnathan) | Plan Readiness |
| `/wave3-story-gate` | **W3** Story-Engineering ★ | Matthew + Thomas · Matthias + Timothy | **Implementation Readiness** |
| `/wave4-ip-research` | **W4** IP & Forschung (Plug-in) | Mark ∥ Nathanael | — |
| `/wave5-implement` | **W5** Implementierung | Phillip, Andrew, Stephen | Abschluss pro Story |
| `/wave6-verify-report` | **W6** Verifikation · Doku · Report | (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin | Release Readiness |
| `/team-confirm` | (nach) | nur Lead | — |

**Warum W3 das Herz ist.** Welle 3 schließt die Kontextlücke zwischen Design und Bau: Rolle #17 **Matthew** verdichtet die vorgelagerte Arbeit in eine **eigenständige Dev-Story-Datei** (9 Abschnitte, jede technische Aussage mit `[Source: …]` getaggt), Thomas & Matthias prüfen sie unabhängig, und wenn das Urteil `FAIL` lautet, **blockiert** der Hook `gate-enforce` den Eintritt in W5 **physisch**.

---

## Skalenadaptives Routing (Lv0–4)

BATHOS aktiviert nur die Wellen, die eine Aufgabe tatsächlich braucht. Sie bestätigen das Level (User Sovereignty); es wird in `manifest.json` festgehalten.

| Lv | Arbeitstyp | Aktive Wellen | #17 Matthew | W4 |
|----|-----------|--------------|:---:|:--:|
| **0** | Bugfix / trivial | W5 (+ minimales W6) | ✗ | ✗ |
| **1** | kleines Feature / lokales Refactoring | leichtes W2 + W3(schlank) + W5 + leichtes W6 | ✓ (schlank) | ✗ |
| **2** | Standard-Feature / Modul | W1 + W2 + W3 + W5 + W6 | ✓ | optional |
| **3** | neues Produkt / groß | W0–W6 (W4 optional) | ✓ | empfohlen |
| **4** | Enterprise / Deep-Tech / reguliert | volles W0–W6 + W4 | ✓ | erforderlich |

Die Empfehlung wird vom Router aus vier Stakes-Achsen berechnet: `scope`, `novelty`, `regulation_ip`, `team_size`.

---

## Qualitäts-Gates

Jedes Wellen-Gate verwendet ein einheitliches Vokabular:

| Urteil | Bedeutung | Wirkung |
|---|---|---|
| **PASS** | Kriterien erfüllt, keine Blocker | weiter zur nächsten Welle |
| **CONCERNS** | bedingter Durchgang (nicht blockierendes Risiko) | Risiko in `_state/` protokollieren, fortfahren |
| **FAIL** | blockierender Defekt | Eintritt blockiert; beheben und erneut prüfen |

Gates sind **Facilitatoren, keine Generatoren** — kein evidenzfreies Auto-PASS. Das W3-Gate wird durch einen Hook erzwungen (Exit-Code `2` blockiert W5). Die Wahrheitsquelle für das Urteil ist die Engine: `bathos gate show`.

---

## CLI-Referenz (`bathos`-Engine)

Globale Optionen: `-s, --state-dir <PATH>` (Standard `./_state`), `--modules-dir <PATH>` (Standard `./modules`), `-h/--help`, `-V/--version`.
Exit-Codes: `0` Erfolg · `1` Fehler · `2` Gate FAIL (von Hooks zum Blockieren verwendet).

| Befehl | Unterbefehle | Zweck |
|---|---|---|
| `state` | `init`, `validate`, `show` | Erstellen, validieren und prüfen der zentralen `manifest.json` |
| `route` | `decide`, `show` | Skalenadaptive Level-Empfehlung (stdin/`--stakes-json`; `--confirm <0-4>` hält fest) |
| `wave` | `init`, `activate`, `show` | 7-Wellen-Zustandsübergänge (Parallelität ≤ 3 erzwungen) |
| `gate` | `verdict`, `show` | Gate-Urteile aufzeichnen / lesen (PASS/CONCERNS/FAIL; FAIL → Exit 2) |
| `story` | `compile`, `check-stale` | Vollständigkeit der Story-Datei (D1), Quellennachverfolgung (D2), Aktualität (D3) |
| `plug` | `list`, `enable`, `disable` | Plugin-Module umschalten (IP-Paket, Forschungspaket, …) |
| `audit` | `append`, `verify` | An die manipulationssichere Audit-Hash-Kette anhängen / sie **verifizieren** (`verify` → Exit 1 bei `E-AUDIT-TAMPER`) |
| `doctor` | — | **Installations-/Verdrahtungs-Preflight** — `BATHOS_BIN`, `jq`, Agent-Teams-Flag, `settings.json`-Hooks-Block (Kommentar-Key-Hänger), Hook-Ausführungsbits, Manifest-Schema, Audit-Kette |

```bash
bathos -s _state state init --codename MYPROJECT       # schema-validen Manifest-Seed erstellen
bathos -s _state state validate                       # validate manifest.json
bathos -s _state gate verdict Implementation PASS Matthew
bathos -s _state gate show                            # latest Implementation gate (JSON)
bathos --modules-dir modules plug list                # modules + enabled state
bathos -s _state audit append --actor hook --action tool.write --target manifest.json
```

Vollständige Referenz mit Beispielen: **[`docs/USAGE-kr.md`](docs/USAGE-kr.md)** (Koreanisch).

---

## Slash-Befehle

34 Befehle werden unter `.claude/commands/` ausgeliefert:

- **Wellen:** `wave0-analysis`, `wave1-discovery`, `wave2-design`, `wave3-story-gate`, `wave4-ip-research`, `wave5-implement`, `wave6-verify-report`
- **Routing:** `route`
- **Team:** `team-kickoff`, `team-status`, `team-confirm`, `team-cleanup`
- **Plan-Reviews (W2-Verstärkung):** `autoplan`, `plan-ceo-review`, `plan-design-review`, `plan-eng-review`, `plan-devex-review`
- **Sitzung speichern/wiederherstellen:** `save-session`, `cold-start` (kanonisch — vollständiges Speichern & vollständige Cold-Start-Wiederherstellung); `save` / `resume` (Kurzaliase); `context-save` / `context-restore` (gstack-Aliase)
- **Projektübergreifender Speicher:** `project-handoff` (dieses Projekt in `~/.bathos/registry/` destillieren), `recall` (relevanten Kontext eines früheren Projekts in ein neues Projekt ziehen)
- **Engineering-Ops:** `review`, `investigate`, `cso` (OWASP + STRIDE), `retro`, `health`, `guard`, `unfreeze`, `context-save`, `context-restore`

---

## Die 17 Rollen

Der Lead (#0 Paul) ist Ihre Hauptsitzung und wird niemals gespawnt. Die Rollen #1–#17 werden pro Welle gespawnt; die Parallelität ist auf 3 begrenzt.

| # | Name | Rolle | Modell | Welle |
|---|------|------|-------|------|
| 0 | Paul | Lead / finale Bestätigung | Opus 4.8 | alle (Hauptsitzung) |
| 1 | John | Reverse-Spezialist | Opus 4.8 | W1 (+W0) |
| 2 | Caleb | Marktanalyse / USP (+W0-Analyst) | Opus 4.8 | W1 (+W0) |
| 3 | Joshua | Serviceplanung | Opus 4.8 | W2 (Gate) |
| 4 | James | SW- / Cloud-Architekt | Opus 4.8 | W2 |
| 5 | Mark | IP-Spezialist (Patente) | Opus 4.8 | W4 |
| 6 | Nathanael | Research-Autor (Abstract/Einleitung) | Sonnet 5 | W4 |
| 7 | Jonnathan | Chefdesigner (UX/UI) | Opus 4.8 | W2 |
| 8 | Phillip | Backend- & Daten-Lead | Sonnet 5 | W5 |
| 9 | Andrew | Frontend- & Mobile-Lead | Sonnet 5 | W5 |
| 10 | Stephen | AI/ML-Lead | Sonnet 5 | W5 |
| 11 | Timothy | Dev-Definitions-Doku | Sonnet 5 | W6 (+W3) |
| 12 | Thomas | Code-Reviewer | Sonnet 5 | W6 (+W3) |
| 13 | Michael | Sicherheitsspezialist (defensives Web-/Cyber-Audit & Härtung) | Sonnet 5 | W6 (nach Thomas) |
| 14 | Hananiah | Refactoring-Spezialist (verhaltenserhaltend) | Sonnet 5 | W6 (nach Michael) |
| 15 | Matthias | QA / Validierung (E2E) | Sonnet 5 | W6 (+W3) |
| 16 | Martin | Monitoring / HTML-Report | Sonnet 5 | W6 |
| **17** | **Matthew** | **Scrum-Master / Story-Engineer** | Opus 4.8 | **nur W3 (ansonsten inaktiv)** |

Die Rollendefinitionen liegen in `.claude/agents/_base/` und unterstützen das 3-Schichten-Override (base → team → user).

---

## Plugin-Module

Der Kern bleibt schlank; Domänenfähigkeiten sind optionale Plugins unter `modules/` (der Kern hängt nie von einem Modul ab — A9). Jedes deklariert sich selbst in `module.yaml`:

```yaml
module_id: ip                    # ip | research | game | security ...
name: IP Pack
wave: W4
trigger: "Lv>=3 OR domain=ip"    # auto-enable condition
enabled_default: false
provides:
  workflows: [patent-spec-draft]
  templates: [patent-spec]
outputs: ".agent-team/05-ip/"
evidence_trace: true
```

Mitgeliefert: **`ip-pack`** (Erstellung von Patentspezifikationen) und **`research-pack`** (akademisches Abstract/Einleitung). Umschalten mit `bathos plug enable <id>` / `disable <id>`.

---

## Sicherheits-Hooks

`.claude/settings.json` bindet 6 deterministische, ausfallsichere Hooks an Claude-Code-Ereignisse (`PreToolUse`, `PostToolUse`, `TaskCompleted`, `SubagentStop`, `TeammateIdle`):

| Hook | Ereignis | Zweck |
|---|---|---|
| `careful-guard.sh` | PreToolUse(Bash) | Blockiert destruktive Befehle (`rm -rf`, `DROP TABLE`, `git push --force`, `DELETE` ohne `WHERE`, `TRUNCATE`) |
| `freeze-guard.sh` | PreToolUse(Write/Edit) | Sperrt Bearbeitungen auf eigene Pfade |
| `audit-log.sh` | PostToolUse | Hängt jede Werkzeugnutzung an die Audit-Kette an |
| `artifact-verify.sh` | TaskCompleted / SubagentStop | Verifiziert erforderliche Artefakte / Vollständigkeit der Story-Datei |
| `gate-enforce.sh` | TaskCompleted | **Blockiert W5-Eintritt, wenn das W3-Urteil FAIL ist** |
| `next-action.sh` | TeammateIdle | Schlägt die nächste Aktion vor |

> Belassen Sie **nur gültige Hook-Ereignisnamen** im `hooks`-Block von `settings.json` — ein versehentlicher Kommentar-Key dort hängt den Subagenten-Start auf.

---

## Repository-Aufbau

```
bathos/
├── core/                       # Rust workspace (the engine, 7 crates, ~9,200 LOC)
│   ├── Cargo.toml
│   └── crates/
│       ├── bathos-state/       # state SSOT: manifest.json + tamper-evident audit chain
│       ├── bathos-router/      # scale-adaptive Lv0–4 router
│       ├── bathos-wave-engine/ # 7-wave transitions, concurrency ≤ 3
│       ├── bathos-gate-engine/ # PASS/CONCERNS/FAIL verdicts
│       ├── bathos-story-engine/# story compilation, staleness (zero-context-loss)
│       ├── bathos-plug/        # plugin module manager
│       └── bathos-cli/         # the `bathos` binary
├── .claude/
│   ├── agents/_base/           # 17 role definitions (00-paul … 17-matthew-story-engineer)
│   ├── commands/               # 34 slash commands
│   ├── hooks/                  # 6 safety/event hooks + test harness
│   └── settings.json           # hook bindings + Agent Teams flag
├── assets/                     # templates, workflows, checklists, glossary
├── modules/                    # plugin modules: ip-pack, research-pack
├── docs/USAGE-kr.md            # detailed usage guide (Korean)
├── CLAUDE.md  ETHOS.md  VERSION  README.md
```

Die Team-Artefakte, die ein Lauf erzeugt, liegen unter `.agent-team/` (Plan, Discovery, Architektur, Story-Engineering, Reviews, QA, Reports und `_state/`). Ihr eigentlicher Produkt-Quellcode bleibt in den normalen Pfaden Ihres Projekts (`src/`, …).

---

## Konfiguration

- **Engine-Zustandsverzeichnis** — `--state-dir` (Standard `./_state`); die SSOT ist `<state-dir>/manifest.json` (JSON-Schema-validiert, atomare Schreibvorgänge, Audit-Hash-Kette).
- **Modulverzeichnis** — `--modules-dir` (Standard `./modules`).
- **Engine-Pfad für Hooks** — Umgebungsvariable `BATHOS_BIN` (fällt zurück auf `core/target/debug/bathos`).
- **Rollen-Overrides** — 3-Schichten-Merge: `base` (feste Identität/Modell) → `team` (projekteigene Pfade) → `user` (Sprache/Facilitation). Skalare überschreiben; Arrays hängen an.

---

## Projektstatus

**v0.2.0 — früh, aber funktionsfähig.** BATHOS baut und läuft heute von Anfang bis Ende. Ehrliche Einschränkungen für Anwender:

- Es ist ein **Methodenpaket, das auf Claude Code läuft**, keine eigenständige App, und hängt von der **experimentellen Agent-Teams**-Funktion ab.
- Die Engine ist verifiziert: **510 Rust-Tests + 86 Hook-Determinismus-Prüfungen, alle grün**; `cargo clippy -D warnings` sauber; Release-Builds reproduzierbar.
- Sie ist **noch nicht produktionsgehärtet**; APIs, Schemata und Befehlsnamen können sich vor 1.0 ändern.
- Einige Wellen-Befehle sind **Orchestrierungs-Prompts**, die der Lead in Claude Code ausführt (sie spawnen/prüfen Teammitglieder), keine vollautonomen Engine-Abläufe.

Siehe `_state/signoff.md` und `12-report/` für die Verifikationsspur.

---

## Wie BATHOS gebaut wurde (Dogfooding)

BATHOS hat sich selbst implementiert und dann **seine eigene Welle-6-Unabhängigverifikation an seinem eigenen Code durchgeführt**. Dieser Durchgang trennte bewusst *Autor* von *Prüfer*: Die funktionale QA sah grün aus, doch ein unabhängiges Code-Review brachte **blockierende Invariantendefekte zutage, die der Autor übersehen hatte** (z. B. schrieben die Rust-Engine und die bash-Hooks *inkompatible* Formate in dieselbe Audit-Kette und hebelten so stillschweigend die Manipulationssicherheit aus). Diese Blocker wurden behoben, erneut geprüft, und die Regression/das Backlog wurde bereinigt — jeder bekannte Review-Defekt gelöst.

Die Lehre ist die These des Produkts: **Generierung ≠ Verifikation.** Die vollständige Spur liegt in `.agent-team/` (`10-review/`, `11-qa/`, `12-report/`, `_state/signoff.md`).

---

## Mitwirken

Beiträge sind willkommen. BATHOS *ist* eine Entwicklungsmethode, also verwenden Sie sie bitte auf sich selbst:

1. Eröffnen Sie ein Issue, das die Änderung und ihre Skala (Lv0–4) beschreibt.
2. Halten Sie den Kern schlank — neue Domänenfähigkeiten gehören in `modules/`, nicht in den Kern (keine Rückwärtsabhängigkeit von Plugins).
3. Für Engine-Änderungen: `cd core && cargo test && cargo clippy --all-targets -- -D warnings` muss grün sein; fügen Sie Tests für Invarianten hinzu.
4. Für Hook-Änderungen: Führen Sie `bash .claude/hooks/_test-hooks.sh` aus; halten Sie Hooks deterministisch und ausfallsicher.
5. Respektieren Sie das Gate-Vokabular (PASS/CONCERNS/FAIL) und die Sicherheits-Hooks (`careful`, `freeze`).

Drei Betriebsprinzipien (aus `ETHOS.md`): **User Sovereignty** (die KI schlägt vor, Sie entscheiden) · **Boil the Ocean** (vollständig fertigstellen, wenn es nur Minuten mehr sind) · **Search Before Building**.

---

## Lizenz & Zuschreibung

Veröffentlicht unter der **MIT License** — siehe den vollständigen Text unten.

```
MIT License

Copyright (c) 2026 BATHOS

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

**Herkunft und Anerkennung.** BATHOS ist ein unabhängig implementiertes Werk. Sein Methodendesign wurde nach einer gründlichen Reverse-Analyse von **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)** (MIT © 2025 BMad Code, LLC) von Grund auf aus ersten Prinzipien neu implementiert, von dem es sein grundlegendes Design-Vokabular erbt.

Wir benennen diese Herkunft aus freier Entscheidung, nicht aus Verpflichtung. Ein System, dessen zentraler Grundsatz lautet, dass *Generierung gegenüber Verifikation rechenschaftspflichtig bleiben muss*, würde sich selbst widersprechen, wenn es den Stand der Technik, auf dem es steht, verschleierte. BATHOS hält seine Schuld gegenüber BMAD-METHOD daher klar und mit aufrichtigem Respekt fest — es hat das Terrain kartiert, das BATHOS zu vertiefen antrat. Gemäß der MIT License sind der Copyright- und Lizenzhinweis von BMAD-METHOD in [`LICENSE`](LICENSE) erhalten; die vollständige Anerkennung liegt in [`CREDITS.md`](CREDITS.md).

BATHOS ist ein separates, unabhängig implementiertes Projekt und verwendet die Marken „BMAD“, „BMad Method“, „BMad Builder“, „BMB“, „TEA“, „CIS“, „GDS“ oder „WDS“ **nicht** in seinem Produktnamen oder Marketing.

---

<div align="center">

**BATHOS** · βάθος — Tiefe statt Oberfläche
한국어 문서: [`docs/USECASE-kr.md`](docs/USECASE-kr.md) · [`docs/FEATURES-kr.md`](docs/FEATURES-kr.md) · [`docs/USAGE-kr.md`](docs/USAGE-kr.md) · [`docs/QUOTA-kr.md`](docs/QUOTA-kr.md) · [`docs/MODULE-GUIDE-kr.md`](docs/MODULE-GUIDE-kr.md) · [`CLAUDE.md`](CLAUDE.md) · [`ETHOS.md`](ETHOS.md)

</div>
