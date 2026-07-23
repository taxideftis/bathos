<p align="center">
  <!-- BATHOS_LANDING_URL — replace href="#" with the landing-page URL once the landing page is live (same marker in all language READMEs) -->
  <a href="#"><img src=".github/assets/bathos-lockup-transparent.png" alt="BATHOS" width="480"></a>
</p>

# BATHOS

[English](README.md) · [한국어](README-kr.md) · **Español** · [Deutsch](README-de.md) · [日本語](README-ja.md)

> **βάθος** (griego) — *«profundidad, el abismo».* Un método de AI Workflow Agent con una profundidad abrumadora, en deliberado contraste con la asistencia de IA superficial.

![version](https://img.shields.io/badge/version-0.2.0-0e9aa1)
![license](https://img.shields.io/badge/license-MIT-blue)
![engine](https://img.shields.io/badge/engine-Rust-d2691e)
![runtime](https://img.shields.io/badge/runtime-Claude%20Code%20v2.1.32%2B-7b61ff)
![status](https://img.shields.io/badge/status-v0.2.0%20early%20%C2%B7%20dogfood--verified-c8841a)

BATHOS convierte una **única sesión de Claude Code en un equipo de producto disciplinado** — 17 roles especialistas, un pipeline de entrega de 7 olas, enrutamiento adaptable a la escala y estrictas puertas de calidad — respaldado por un pequeño **motor en Rust** que hace que los invariantes críticos sean deterministas en lugar de basados en la intuición.

> **한국어:** BATHOS는 Claude Code 위에서 **17역할 × 7웨이브 × Scale-Adaptive Lv0~4**로 제품 개발을 오케스트레이션하는 메서드 패키지입니다. 처음이라면 **[활용 사례(새 서비스 만들기)](docs/USECASE-kr.md)** → **[특징·구동원리](docs/FEATURES-kr.md)** → **[사용 가이드](docs/USAGE-kr.md)** 순서를 권장합니다. (운영 규칙: [`CLAUDE.md`](CLAUDE.md) · 원칙: [`ETHOS.md`](ETHOS.md))

---

## Tabla de contenidos

- [Documentación](#documentación)
- [Por qué BATHOS](#por-qué-bathos)
- [Cómo funciona: dos planos](#cómo-funciona-dos-planos)
- [Requisitos](#requisitos)
- [Inicio rápido](#inicio-rápido)
- [El pipeline de 7 olas](#el-pipeline-de-7-olas)
- [Enrutamiento adaptable a la escala (Lv0–4)](#enrutamiento-adaptable-a-la-escala-lv04)
- [Puertas de calidad](#puertas-de-calidad)
- [Referencia de la CLI (motor `bathos`)](#referencia-de-la-cli-motor-bathos)
- [Comandos de barra](#comandos-de-barra)
- [Los 17 roles](#los-17-roles)
- [Módulos de plugin](#módulos-de-plugin)
- [Hooks de seguridad](#hooks-de-seguridad)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Configuración](#configuración)
- [Estado del proyecto](#estado-del-proyecto)
- [Cómo se construyó BATHOS (dogfooding)](#cómo-se-construyó-bathos-dogfooding)
- [Contribuir](#contribuir)
- [Licencia y atribución](#licencia-y-atribución)

---

## Documentación

| Doc | English | 한국어 | Español | Para qué sirve |
|-----|:----------:|:---------:|:---------:|---------------|
| **Caso de uso** — construye un nuevo servicio paso a paso | [`docs/USECASE-en.md`](docs/USECASE-en.md) | [`docs/USECASE-kr.md`](docs/USECASE-kr.md) | [`docs/USECASE-es.md`](docs/USECASE-es.md) | Empieza aquí: un recorrido práctico (adóptalo en tu propio proyecto, construye «ReadShelf» de principio a fin) |
| **Características y principios operativos** | [`docs/FEATURES-en.md`](docs/FEATURES-en.md) | [`docs/FEATURES-kr.md`](docs/FEATURES-kr.md) | [`docs/FEATURES-es.md`](docs/FEATURES-es.md) | Qué hace distintivo a BATHOS y cómo funciona el motor por dentro |
| **Guía de uso** | [`docs/USAGE-en.md`](docs/USAGE-en.md) | [`docs/USAGE-kr.md`](docs/USAGE-kr.md) | [`docs/USAGE-es.md`](docs/USAGE-es.md) | Referencia: instalación, CLI, olas, puertas, hooks, resolución de problemas |
| **Gestión de tokens y cuota** | [`docs/QUOTA-en.md`](docs/QUOTA-en.md) | [`docs/QUOTA-kr.md`](docs/QUOTA-kr.md) | [`docs/QUOTA-es.md`](docs/QUOTA-es.md) | Controla el coste, secuencia las olas, recupérate de los límites de uso |
| **Autoría de módulos personalizados** | [`docs/MODULE-GUIDE-en.md`](docs/MODULE-GUIDE-en.md) | [`docs/MODULE-GUIDE-kr.md`](docs/MODULE-GUIDE-kr.md) | [`docs/MODULE-GUIDE-es.md`](docs/MODULE-GUIDE-es.md) | Escribe tu propio plugin (module.yaml, DSL de disparadores, W4) sin tocar el núcleo |
| **Personalización de roles** | [`docs/ROLE-GUIDE-en.md`](docs/ROLE-GUIDE-en.md) | [`docs/ROLE-GUIDE-kr.md`](docs/ROLE-GUIDE-kr.md) | [`docs/ROLE-GUIDE-es.md`](docs/ROLE-GUIDE-es.md) | Adapta los 17 roles mediante la sobrescritura de 3 capas (base → team → user) |
| **Arquitectura** (contribuyentes) | [`docs/ARCHITECTURE-en.md`](docs/ARCHITECTURE-en.md) | [`docs/ARCHITECTURE-kr.md`](docs/ARCHITECTURE-kr.md) | [`docs/ARCHITECTURE-es.md`](docs/ARCHITECTURE-es.md) | Mapa de crates, invariantes (A9, puerta, auditoría), códigos de salida/error, cómo contribuir |
| **FAQ** | [`docs/FAQ-en.md`](docs/FAQ-en.md) | [`docs/FAQ-kr.md`](docs/FAQ-kr.md) | [`docs/FAQ-es.md`](docs/FAQ-es.md) | Preguntas frecuentes y resolución de problemas |
| **Reglas operativas / principios** | [`CLAUDE.md`](CLAUDE.md) · [`ETHOS.md`](ETHOS.md) | | | Reglas operativas del equipo y el ETHOS derivado de gstack |

> **¿Nuevo por aquí?** Lee **Caso de uso** → **Características** → **Guía de uso**.

---

## Por qué BATHOS

Una única conversación larga con un LLM se desvía: el contexto se pierde entre el «diseño» y la «construcción», los controles de calidad se saltan, y el mismo modelo redacta y aprueba su propio trabajo. BATHOS reemplaza eso con estructura.

| Chat de LLM simple | BATHOS |
|---|---|
| Una conversación, deriva de contexto creciente | **17 roles especialistas** a lo largo de un pipeline de **7 olas** |
| Contexto perdido entre diseño ↔ implementación | Archivos de historia autocontenidos **Zero-Context-Loss** (Ola 3) |
| Esfuerzo implícito y de talla única | **Enrutador adaptable a la escala** — Lv0–4 explícito |
| La implementación empieza cuando sea | **Puerta de preparación estricta** que bloquea físicamente la construcción ante un `FAIL` |
| El autor también «verifica» | **Revisores independientes** + cadena de auditoría a prueba de manipulaciones |
| Consejos que te anulan en silencio | **User Sovereignty** — la IA propone, *tú* decides |

El resultado: una sola persona puede dirigir un equipo de IA a través de descubrimiento → diseño → implementación → verificación, con trazabilidad y puertas en cada paso.

---

## Cómo funciona: dos planos

Este es el concepto individual más importante. BATHOS se ejecuta sobre **dos capas**:

| Plano | Qué es | Qué hace | Quién lo dirige |
|---|---|---|---|
| **Orquestación** | **Comandos de barra** en Markdown, **roles** y **hooks** bajo `.claude/` | Ejecuta las olas; genera / revisa / cierra compañeros de equipo | El **líder (Paul)** — tu sesión principal de Claude Code |
| **Motor** | Un único binario estático de Rust, **`bathos`** | Calcula y *aplica* el estado, las puertas, las transiciones de olas, el enrutamiento, la frescura de las historias, los plugins | Invocado automáticamente por hooks y comandos (`bathos <subcommand>`) |

En su mayoría escribes **comandos de barra** (p. ej., `/wave1-discovery`). El binario `bathos` es el núcleo determinista que esos comandos y hooks invocan por debajo — y también puedes ejecutarlo directamente.

---

## Requisitos

- **[Claude Code](https://claude.com/claude-code) v2.1.32+** con la función experimental **Agent Teams** habilitada
  (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; el `.claude/settings.json` incluido ya la establece)
- **Cadena de herramientas de Rust** (verificada con cargo 1.92+) — para compilar el motor
- **`jq`** — usado por los hooks de seguridad para el análisis de JSON
- Un entorno de shell POSIX (macOS/Linux); los hooks son bash

---

## Inicio rápido

### 1. Obtén el código y compila el motor

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

### 2. Usa BATHOS en un proyecto

**Opción A — usa este repositorio como tu directorio de trabajo.** El directorio `.claude/` (comandos, agentes, hooks, ajustes) ya está conectado; solo abre Claude Code aquí.

**Opción B — adóptalo en tu propio proyecto.** Copia `.claude/` (comandos, agentes, hooks, `settings.json`), `assets/` y `modules/` a la raíz de tu proyecto, y luego establece `BATHOS_BIN` como se indica arriba.

### 3. Dirige el pipeline (comandos de barra, en Claude Code)

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

### Prueba el motor directamente

```bash
# Recommend a Scale-Adaptive level from "stakes" (recommend only; does not commit)
echo '{"scope":"feature","novelty":true,"regulation_ip":false,"team_size":"medium"}' \
  | bathos --state-dir .agent-team/_state route decide
#   → {"recommended_level":2,"wave_set":[...],"role_set":[...],"requires_confirmation":true}
```

---

## El pipeline de 7 olas

```
(pre) kickoff → W0 Analysis → W1 Discovery → W2 Design
        → W3 Story Gate ★ → W5 Implementation → W6 Verify → (post) Confirm
                                  ↑
                       W4 IP & Research  (optional plug-in, off the critical path)
```

Dependencia de la línea principal: **W0 → W1 → W2 → W3 → W5 → W6**. W4 (IP e investigación) es un plugin opcional ejecutable en cualquier momento después de W2.

| Comando | Ola | Equipo (paralelo) | Puerta |
|---|---|---|---|
| `/team-kickoff` | (pre) | solo el líder | — |
| `/wave0-analysis` | **W0** Analysis (opcional) | Caleb | Brief Readiness |
| `/wave1-discovery` | **W1** Discovery y mercado | John ∥ Caleb | USP Readiness |
| `/wave2-design` | **W2** Plan · arquitectura · diseño | Joshua → (James, Jonnathan) | Plan Readiness |
| `/wave3-story-gate` | **W3** Ingeniería de historias ★ | Matthew + Thomas · Matthias + Timothy | **Implementation Readiness** |
| `/wave4-ip-research` | **W4** IP e investigación (plugin) | Mark ∥ Nathanael | — |
| `/wave5-implement` | **W5** Implementación | Phillip, Andrew, Stephen | finalización por historia |
| `/wave6-verify-report` | **W6** Verificar · docs · reporte | (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin | Release Readiness |
| `/team-confirm` | (post) | solo el líder | — |

**Por qué W3 es el corazón.** La Ola 3 cierra la brecha de contexto entre diseño y construcción: el rol #17 **Matthew** condensa el trabajo previo en un **archivo de historia de dev autocontenido** (9 secciones, cada afirmación técnica etiquetada con `[Source: …]`), Thomas y Matthias lo revisan de forma independiente, y si el veredicto es `FAIL` el hook `gate-enforce` **bloquea físicamente** la entrada a W5.

---

## Enrutamiento adaptable a la escala (Lv0–4)

BATHOS activa solo las olas que una tarea realmente necesita. Tú confirmas el nivel (User Sovereignty); queda registrado en `manifest.json`.

| Lv | Tipo de trabajo | Olas activas | #17 Matthew | W4 |
|----|-----------|--------------|:---:|:--:|
| **0** | corrección de bug / trivial | W5 (+ W6 mínima) | ✗ | ✗ |
| **1** | función pequeña / refactor local | W2 ligera + W3(reducida) + W5 + W6 ligera | ✓ (reducida) | ✗ |
| **2** | función / módulo estándar | W1 + W2 + W3 + W5 + W6 | ✓ | opcional |
| **3** | nuevo producto / grande | W0–W6 (W4 opcional) | ✓ | recomendado |
| **4** | empresarial / deep-tech / regulado | W0–W6 completo + W4 | ✓ | obligatorio |

La recomendación la calcula el enrutador a partir de cuatro ejes de stakes: `scope`, `novelty`, `regulation_ip`, `team_size`.

---

## Puertas de calidad

Cada puerta de ola usa un único vocabulario:

| Veredicto | Significado | Efecto |
|---|---|---|
| **PASS** | criterios cumplidos, sin bloqueadores | avanzar a la siguiente ola |
| **CONCERNS** | aprobación condicional (riesgo no bloqueante) | registrar el riesgo en `_state/`, avanzar |
| **FAIL** | defecto bloqueante | entrada bloqueada; remediar y volver a la puerta |

Las puertas son **facilitadoras, no generadoras** — sin auto-PASS sin evidencia. La puerta W3 la aplica un hook (el código de salida `2` bloquea W5). La fuente de verdad del veredicto es el motor: `bathos gate show`.

---

## Referencia de la CLI (motor `bathos`)

Opciones globales: `-s, --state-dir <PATH>` (por defecto `./_state`), `--modules-dir <PATH>` (por defecto `./modules`), `-h/--help`, `-V/--version`.
Códigos de salida: `0` éxito · `1` error · `2` puerta FAIL (usado por los hooks para bloquear).

| Comando | Subcomandos | Propósito |
|---|---|---|
| `state` | `init`, `validate`, `show` | Crea, valida e inspecciona la fuente única de verdad `manifest.json` |
| `route` | `decide`, `show` | Recomendación de nivel adaptable a la escala (stdin/`--stakes-json`; `--confirm <0-4>` registra) |
| `wave` | `init`, `activate`, `show` | Transiciones de estado de las 7 olas (concurrencia ≤ 3 aplicada) |
| `gate` | `verdict`, `show` | Registrar / leer veredictos de puerta (PASS/CONCERNS/FAIL; FAIL → salida 2) |
| `story` | `compile`, `check-stale` | Integridad del archivo de historia (D1), rastreo de fuente (D2), frescura (D3) |
| `plug` | `list`, `enable`, `disable` | Alternar módulos de plugin (pack de IP, pack de investigación, …) |
| `audit` | `append`, `verify` | Añadir a / **verificar** la cadena de hash de auditoría a prueba de manipulaciones (`verify` → salida 1 ante `E-AUDIT-TAMPER`) |
| `doctor` | — | **Preverificación de instalación/conexión** — `BATHOS_BIN`, `jq`, flag de Agent Teams, bloque de hooks de `settings.json` (cuelgue por clave de comentario), bits de ejecución de hooks, esquema del manifest, cadena de auditoría |

```bash
bathos -s _state state init --codename MYPROJECT       # crea un manifest seed válido según el esquema
bathos -s _state state validate                       # validate manifest.json
bathos -s _state gate verdict Implementation PASS Matthew
bathos -s _state gate show                            # latest Implementation gate (JSON)
bathos --modules-dir modules plug list                # modules + enabled state
bathos -s _state audit append --actor hook --action tool.write --target manifest.json
```

Referencia completa con ejemplos: **[`docs/USAGE-kr.md`](docs/USAGE-kr.md)** (coreano).

---

## Comandos de barra

Se incluyen 34 comandos bajo `.claude/commands/`:

- **Olas:** `wave0-analysis`, `wave1-discovery`, `wave2-design`, `wave3-story-gate`, `wave4-ip-research`, `wave5-implement`, `wave6-verify-report`
- **Enrutamiento:** `route`
- **Equipo:** `team-kickoff`, `team-status`, `team-confirm`, `team-cleanup`
- **Revisiones de plan (refuerzo de W2):** `autoplan`, `plan-ceo-review`, `plan-design-review`, `plan-eng-review`, `plan-devex-review`
- **Guardado/restauración de sesión:** `save-session`, `cold-start` (canónico — guardado completo y restauración de arranque en frío completa); `save` / `resume` (alias cortos); `context-save` / `context-restore` (alias de gstack)
- **Memoria entre proyectos:** `project-handoff` (destila este proyecto en `~/.bathos/registry/`), `recall` (trae contexto relevante de un proyecto anterior a un nuevo proyecto)
- **Operaciones de ingeniería:** `review`, `investigate`, `cso` (OWASP + STRIDE), `retro`, `health`, `guard`, `unfreeze`, `context-save`, `context-restore`

---

## Los 17 roles

El líder (#0 Paul) es tu sesión principal y nunca se genera. Los roles #1–#17 se generan por ola; la concurrencia está limitada a 3.

| # | Nombre | Rol | Modelo | Ola |
|---|------|------|-------|------|
| 0 | Paul | Líder / confirmación final | Opus 4.8 | todas (sesión principal) |
| 1 | John | Especialista en ingeniería inversa | Opus 4.8 | W1 (+W0) |
| 2 | Caleb | Análisis de mercado / USP (+analista W0) | Opus 4.8 | W1 (+W0) |
| 3 | Joshua | Planificación de servicio | Opus 4.8 | W2 (puerta) |
| 4 | James | Arquitecto de SW / nube | Opus 4.8 | W2 |
| 5 | Mark | Especialista en IP (patentes) | Opus 4.8 | W4 |
| 6 | Nathanael | Redactor de investigación (abstract/intro) | Sonnet 5 | W4 |
| 7 | Jonnathan | Diseñador jefe (UX/UI) | Opus 4.8 | W2 |
| 8 | Phillip | Líder de backend y datos | Sonnet 5 | W5 |
| 9 | Andrew | Líder de frontend y móvil | Sonnet 5 | W5 |
| 10 | Stephen | Líder de IA/ML | Sonnet 5 | W5 |
| 11 | Timothy | Documentación de definición de dev | Sonnet 5 | W6 (+W3) |
| 12 | Thomas | Revisor de código | Sonnet 5 | W6 (+W3) |
| 13 | Michael | Especialista en seguridad (auditoría y endurecimiento defensivo web/ciber) | Sonnet 5 | W6 (después de Thomas) |
| 14 | Hananiah | Especialista en refactorización (preservando el comportamiento) | Sonnet 5 | W6 (después de Michael) |
| 15 | Matthias | QA / validación (E2E) | Sonnet 5 | W6 (+W3) |
| 16 | Martin | Monitoreo / reporte HTML | Sonnet 5 | W6 |
| **17** | **Matthew** | **Scrum master / ingeniero de historias** | Opus 4.8 | **solo W3 (inactivo en lo demás)** |

Las definiciones de roles residen en `.claude/agents/_base/` y admiten la sobrescritura de 3 capas (base → team → user).

---

## Módulos de plugin

El núcleo se mantiene esbelto; las capacidades de dominio son plugins opcionales bajo `modules/` (el núcleo nunca depende de un módulo — A9). Cada uno se declara en `module.yaml`:

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

Incluidos: **`ip-pack`** (redacción de borradores de especificaciones de patentes) y **`research-pack`** (abstract/introducción académicos). Alterna con `bathos plug enable <id>` / `disable <id>`.

---

## Hooks de seguridad

`.claude/settings.json` vincula 6 hooks deterministas y a prueba de fallos a los eventos de Claude Code (`PreToolUse`, `PostToolUse`, `TaskCompleted`, `SubagentStop`, `TeammateIdle`):

| Hook | Evento | Propósito |
|---|---|---|
| `careful-guard.sh` | PreToolUse(Bash) | Bloquear comandos destructivos (`rm -rf`, `DROP TABLE`, `git push --force`, `DELETE` sin `WHERE`, `TRUNCATE`) |
| `freeze-guard.sh` | PreToolUse(Write/Edit) | Bloquear las ediciones a las rutas propias |
| `audit-log.sh` | PostToolUse | Añadir cada uso de herramienta a la cadena de auditoría |
| `artifact-verify.sh` | TaskCompleted / SubagentStop | Verificar los artefactos requeridos / la integridad del archivo de historia |
| `gate-enforce.sh` | TaskCompleted | **Bloquear la entrada a W5 cuando el veredicto de W3 es FAIL** |
| `next-action.sh` | TeammateIdle | Sugerir la siguiente acción |

> Mantén **solo nombres de evento de hook válidos** dentro del bloque `hooks` de `settings.json` — una clave de comentario perdida allí cuelga el arranque del subagente.

---

## Estructura del repositorio

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

Los artefactos de equipo que produce una ejecución residen bajo `.agent-team/` (plan, descubrimiento, arquitectura, ingeniería de historias, revisiones, QA, reportes y `_state/`). El código fuente real de tu producto permanece en las rutas normales de tu proyecto (`src/`, …).

---

## Configuración

- **Directorio de estado del motor** — `--state-dir` (por defecto `./_state`); la SSOT es `<state-dir>/manifest.json` (validado por JSON-Schema, escrituras atómicas, cadena de hash de auditoría).
- **Directorio de módulos** — `--modules-dir` (por defecto `./modules`).
- **Ruta del motor para los hooks** — variable de entorno `BATHOS_BIN` (recurre a `core/target/debug/bathos`).
- **Sobrescrituras de roles** — fusión de 3 capas: `base` (identidad/modelo fijos) → `team` (rutas propias del proyecto) → `user` (idioma/facilitación). Los escalares sobrescriben; los arrays se añaden.

---

## Estado del proyecto

**v0.2.0 — temprano pero funcional.** BATHOS se compila y se ejecuta de principio a fin hoy. Advertencias honestas para quienes lo adopten:

- Es un **paquete de método que se ejecuta sobre Claude Code**, no una aplicación independiente, y depende de la función **experimental Agent Teams**.
- El motor está verificado: **510 pruebas de Rust + 86 comprobaciones de determinismo de hooks, todas en verde**; `cargo clippy -D warnings` limpio; compilaciones de release reproducibles.
- **Aún no está endurecido para producción**; las API, los esquemas y los nombres de comandos pueden cambiar antes de la 1.0.
- Algunos comandos de ola son **prompts de orquestación** que el líder ejecuta en Claude Code (generan/revisan compañeros de equipo), no flujos de motor completamente autónomos.

Consulta `_state/signoff.md` y `12-report/` para el rastro de verificación.

---

## Cómo se construyó BATHOS (dogfooding)

BATHOS se implementó a sí mismo y luego **ejecutó su propia verificación independiente de la Ola 6 sobre su propio código**. Ese pase separó intencionadamente al *autor* del *revisor*: el QA funcional parecía en verde, pero una revisión de código independiente sacó a la luz **defectos de invariantes bloqueantes que el autor había pasado por alto** (p. ej., el motor de Rust y los hooks de bash escribían formatos *incompatibles* en la misma cadena de auditoría, anulando silenciosamente la resistencia a manipulaciones). Esos bloqueadores se remediaron, se volvió a pasar por la puerta y se saldó la regresión/backlog — todos los defectos de revisión conocidos resueltos.

La lección es la tesis del producto: **generación ≠ verificación.** El rastro completo reside en `.agent-team/` (`10-review/`, `11-qa/`, `12-report/`, `_state/signoff.md`).

---

## Contribuir

Las contribuciones son bienvenidas. BATHOS *es* un método de desarrollo, así que por favor úsalo sobre sí mismo:

1. Abre un issue describiendo el cambio y su escala (Lv0–4).
2. Mantén el núcleo esbelto — las nuevas capacidades de dominio pertenecen a `modules/`, no al núcleo (sin dependencia inversa hacia los plugins).
3. Para cambios en el motor: `cd core && cargo test && cargo clippy --all-targets -- -D warnings` debe estar en verde; añade pruebas para los invariantes.
4. Para cambios en los hooks: ejecuta `bash .claude/hooks/_test-hooks.sh`; mantén los hooks deterministas y a prueba de fallos.
5. Respeta el vocabulario de puertas (PASS/CONCERNS/FAIL) y los hooks de seguridad (`careful`, `freeze`).

Tres principios operativos (de `ETHOS.md`): **User Sovereignty** (la IA propone, tú decides) · **Boil the Ocean** (termina por completo si son solo unos minutos más) · **Search Before Building**.

---

## Licencia y atribución

Publicado bajo la **Licencia MIT** — consulta el texto completo abajo.

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

**Linaje y reconocimiento.** BATHOS es una obra implementada de forma independiente. Su diseño de método fue reimplementado desde primeros principios tras un riguroso análisis de ingeniería inversa de **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)** (MIT © 2025 BMad Code, LLC), del cual hereda su vocabulario de diseño fundacional.

Nombramos este linaje por elección, no por obligación. Un sistema cuyo principio central es que *la generación debe seguir siendo responsable ante la verificación* se contradiría a sí mismo si ocultara el arte previo sobre el que se sostiene. Por eso BATHOS registra su deuda con BMAD-METHOD de forma clara y con genuino respeto — este trazó el terreno que BATHOS se propuso profundizar. De acuerdo con la Licencia MIT, el aviso de copyright y licencia de BMAD-METHOD se conservan en [`LICENSE`](LICENSE); el reconocimiento completo reside en [`CREDITS.md`](CREDITS.md).

BATHOS es un proyecto separado e implementado de forma independiente y **no** usa las marcas «BMAD», «BMad Method», «BMad Builder», «BMB», «TEA», «CIS», «GDS» ni «WDS» en su nombre de producto ni en su marketing.

---

<div align="center">

**BATHOS** · βάθος — profundidad sobre superficie
Documentos en coreano: [`docs/USECASE-kr.md`](docs/USECASE-kr.md) · [`docs/FEATURES-kr.md`](docs/FEATURES-kr.md) · [`docs/USAGE-kr.md`](docs/USAGE-kr.md) · [`docs/QUOTA-kr.md`](docs/QUOTA-kr.md) · [`docs/MODULE-GUIDE-kr.md`](docs/MODULE-GUIDE-kr.md) · [`CLAUDE.md`](CLAUDE.md) · [`ETHOS.md`](ETHOS.md)

</div>
