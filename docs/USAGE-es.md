# Guía de uso de BATHOS (v0.4.0)

> **BATHOS** — βάθος, que en griego significa 'profundidad; lo profundo'. El nombre expresa la aspiración a ser un **paquete de método de AI Workflow Agent de profundidad abrumadora**, situado en el extremo opuesto del conocimiento que solo roza la superficie.
> Orquesta el proceso completo de desarrollo de producto sobre un único runtime — Claude Code — con la estructura **17 roles × 7 waves × Scale-Adaptive Lv0–4**.
> Este documento no está escrito sobre conceptos sino sobre los **artefactos realmente construidos (B1–B4)**. Lo que aún no está implementado o está en estado stub se declara tal cual, sin ocultarlo.
>
> **Ver también:** Si es tu primera vez, se recomienda tomar el pulso con el [caso de uso (construir un servicio nuevo)](USECASE-es.md) → entender los principios con [Características y funcionamiento](FEATURES-es.md) → y luego venir a esta guía de uso. · 한국어: [`USAGE-kr.md`](USAGE-kr.md) · English: [`USAGE-en.md`](USAGE-en.md)

---

## 0. Concepto central — distingue los dos planos de ejecución

Para usar bien BATHOS solo hay que fijar una cosa primero. BATHOS corre simultáneamente en **dos capas** de naturaleza completamente distinta. En cuanto distingues estas dos, el resto del uso se resuelve casi solo.

| Capa | Qué es | Qué hace | Quién la ejecuta |
|------|--------|----------|------------------|
| **Plano de orquestación** | Comandos slash de Claude Code (`.claude/commands/*.md`) + roles (`.claude/agents/`) + hooks (`.claude/hooks/`) | Avanza las waves; genera (spawn), inspecciona y apaga compañeros | **El líder (Paul) = la sesión principal de Claude Code** |
| **Plano del motor** | El binario Rust estático único `bathos` | Computa y hace cumplir **de forma determinista** estado (SSOT) · gates · transiciones de wave · enrutamiento · historias · plugs | Los hooks/comandos invocan internamente `bathos <subcommand>` |

> En resumen: lo que tú tecleas a mano son normalmente **comandos slash** (como `/wave1-discovery`). El binario `bathos` es el motor de base que **los hooks y comandos llaman por su cuenta** debajo. Por supuesto, si hace falta, puedes manejar ambos directamente.

---

## 1. Requisitos · Instalación · Integración con el proyecto objetivo

### 1.1 Prerrequisitos
- **Claude Code v2.1.32 o superior**
- **Funcionalidad experimental Agent Teams activada** — `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (ya viene configurada en el `bathos/.claude/settings.json` del paquete).
- **Toolchain de Rust** (para compilar el motor) — verificado con cargo 1.92.0.

### 1.2 Compilación del motor
```bash
cd bathos/core
cargo build --release        # → target/release/bathos (binario estático único, ~5.7MB)
cargo test                   # verificación completa (18 grupos de tests)
cargo clippy --all-targets -- -D warnings   # lint (0 warnings)
```
Pon el resultado `bathos/core/target/release/bathos` en el PATH, o indica su ruta con la variable de entorno `BATHOS_BIN` para que los hooks lo encuentren (si no la defines, la ruta de búsqueda por defecto es `core/target/debug/bathos`).

### 1.3 Integración con el proyecto objetivo (instalación · adopción)

> **Clave:** BATHOS no es una app monolítica que corre por sí sola, sino un **paquete de método que corre sobre Claude Code** (ver los dos planos de ejecución en §0). Por eso, aquí "integrar" significa dos cosas: **① compilar el binario del motor de antemano, y ② plantar los activos de orquestación (`.claude/` · `assets/` · `modules/`) en el proyecto objetivo.**

#### 1.3.1 `install.sh` — compilar el motor + inyectar `.claude/`
`install.sh` hace dos cosas. Y **no borra nada.** Si ya existe un `.claude/`, se niega a sobrescribirlo sin `--force`.

```bash
# A) Solo compilar el motor (+ imprime la guía de los pasos siguientes)
./install.sh

# B) Compilar el motor + copiar el paquete de método al proyecto objetivo
./install.sh --into /abs/path/to/your-project
#   → cp -R de .claude/  assets/  modules/  dentro de your-project/
```

Las tres cosas que se copian al proyecto objetivo son precisamente los **"activos de integración"** que se plantan en él:
- **`.claude/`** — 32 comandos slash + 16 definiciones base de roles + 6 hooks de seguridad + `settings.json` (incluido el flag de Agent Teams)
- **`assets/`** — plantillas/workflows/checklists que consultan el motor de historias de W3 y los plugs
- **`modules/`** — módulos plug (`ip-pack`, `research-pack`)

#### 1.3.2 Hacer que los hooks encuentren el motor (variable de entorno obligatoria)
Los hooks copiados invocan el binario `bathos`. Por tanto, hay que decirles dónde está:

```bash
export BATHOS_BIN="/abs/path/to/bathos/core/target/release/bathos"
#   (si no se define, hace fallback a core/target/debug/bathos — se recomienda release)
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1   # ya viene también en settings.json
```

#### 1.3.3 Las dos formas de adopción
| | Modo A — el repo de BATHOS como directorio de trabajo | Modo B — adoptar en mi propio proyecto |
|---|---|---|
| **Operación** | Abre Claude Code directamente en `bathos/` (el `.claude/` ya está cableado) | Copia `.claude/` · `assets/` · `modules/` con `install.sh --into` |
| **Adecuado para** | Retocar BATHOS en sí o probarlo rápido | Aplicarlo a tu proyecto de producto real |

### 1.4 Los dos directorios que aparecen en el proyecto objetivo (importante)

Terminada la integración, en el proyecto objetivo conviven **dos rutas de naturaleza distinta**. Estas dos no se mezclan:

```
your-project/
├── .claude/          ← (activos de integración) comandos·roles·hooks·settings   ※ inyectado por install
├── .agent-team/      ← (salida en runtime) trabajo del equipo · metadatos       ※ lo crea /team-kickoff
│   ├── 00-plan/ ... 12-report/
│   └── _state/manifest.json   ← SSOT (todo el estado en un solo JSON, validación de esquema + cadena de hashes de auditoría)
└── src/ ...          ← el código fuente real de tu producto (en su ruta habitual)
```

- **`.agent-team/`** son los artefactos de trabajo que BATHOS produce (planificación · diseño · historias · reviews · QA · reportes · estado).
- En cambio, **el código real del producto sigue acumulándose en su ruta habitual, como `src/`**. Piensa en BATHOS como el **"proceso (工程)"** que se superpone encima.

> **Resumen en una línea:** planta `.claude/` · `assets/` · `modules/` con `install.sh --into <objetivo>` → configura `BATHOS_BIN` y el flag de Agent Teams → abre Claude Code en el objetivo y ejecuta en orden `/team-kickoff` → `/route` → los comandos de wave con el argumento de ruta absoluta. **Los artefactos se acumulan en `.agent-team/`, el código real en `src/`, y las invariantes clave las hace cumplir el motor Rust `bathos`.**

### 1.5 Estructura del paquete
```
bathos/
├── core/                      # Workspace de Rust (motor)
│   ├── Cargo.toml             # workspace de 7 crates
│   └── crates/
│       ├── bathos-state/      # M1 SSOT de estado (manifest.json · cadena de auditoría)
│       ├── bathos-router/     # M2 Router Scale-Adaptive (Lv0–4)
│       ├── bathos-wave-engine/# M3 Transiciones de 7 waves (concurrencia ≤ 3)
│       ├── bathos-gate-engine/# M4 Veredictos de gate (PASS/CONCERNS/FAIL)
│       ├── bathos-story-engine/#M5 Compilación de historias · staleness
│       ├── bathos-plug/       # M12 Gestor de módulos plug
│       └── bathos-cli/        # bin: bathos
├── .claude/
│   ├── agents/_base/          # M8 definiciones base de 17 roles (00-paul ~ 17-matthew)
│   ├── commands/              # M7 32 comandos slash
│   ├── hooks/                 # M6 6 hooks de seguridad·eventos + harness de tests
│   └── settings.json          # binding de hooks + activación de Agent Teams
├── assets/                    # M9 plantillas·workflows·checklists·glosario
├── modules/                   # módulos plug (W4)
│   ├── ip-pack/               # M10 módulo de especificación de patente
│   └── research-pack/         # M11 módulo de Abstract/Introduction de paper
├── CLAUDE.md  ETHOS.md  README.md  VERSION
└── docs/USAGE-es.md           # (este documento)
```

---

## 2. Inicio rápido (Quick Start)

Abre una sesión de Claude Code (= el líder, Paul) en la raíz del proyecto objetivo y avanza las waves una a una con comandos slash.

```
# 1) Kickoff — esqueleto de .agent-team + charter + inicialización del manifest
/team-kickoff

# 2) Enrutamiento del tamaño del trabajo — recibe la recomendación Lv0–4 por stakes y el usuario confirma
/route /ruta/absoluta/del/proyecto

# 3) Avanza en orden las waves del nivel recomendado (p. ej. Lv2–3)
/wave1-discovery   /ruta/absoluta
/wave2-design      /ruta/absoluta
/wave3-story-gate  /ruta/absoluta     # ← el corazón: Readiness Gate (debe ser PASS para entrar a W5)
/wave5-implement   /ruta/absoluta
/wave6-verify-report /ruta/absoluta

# 4) (opcional · fuera de la línea principal) plug de IP/paper
/wave4-ip-research /ruta/absoluta

# 5) Revisión de progreso / confirmación final
/team-status
/team-confirm
```

> **Dependencia de la línea principal:** W0 → W1 → W2 → **W3** → W5 → W6. **W4 (IP & investigación) es un plug opcional** y puede insertarse en cualquier momento después de W2.
> Cada wave, al terminar, apaga a sus compañeros y pasa a la siguiente (se recomienda mantener ≤ 3 compañeros activos simultáneos).

---

## 3. Workflow de 7 waves

| Comando | Wave | Compañeros (concurrentes) | Gate |
|---------|------|---------------------------|------|
| `/team-kickoff` | (previo) | líder solo | — |
| `/wave0-analysis` | **W0** Analysis (opcional) | Caleb (doble función de Analyst) | Brief Readiness |
| `/wave1-discovery` | **W1** Discovery · mercado | John ∥ Caleb | USP Readiness |
| `/wave2-design` | **W2** Planificación · arquitectura · diseño | Joshua → (James, Jonnathan) | Plan Readiness |
| `/wave3-story-gate` | **W3** Story engineering · gate ★ | Matthew (#17) + Thomas·Matthias (revisión independiente) + Timothy | **Implementation Readiness (doble)** |
| `/wave4-ip-research` | **W4** IP · investigación (plug) | Mark ∥ Nathanael | ninguno |
| `/wave5-implement` | **W5** Implementación | Phillip, Andrew, Stephen | cierre por historia |
| `/wave6-verify-report` | **W6** Verificación · docs · reporte | (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin | Release Readiness |
| `/team-confirm` | (posterior) | líder solo | — |

Cada comando slash recibe como argumento la **ruta absoluta del proyecto objetivo** (`$1`). El comando genera (spawn) compañeros desde la sesión del líder, inspecciona sus artefactos, emite el veredicto del gate y luego apaga a los compañeros. El traspaso entre compañeros ocurre exclusivamente por **archivos en disco** (`.agent-team/...`) — sin apoyarse en el historial de conversación.

### Por qué W3 es el corazón
Entre el diseño (W2) y la implementación (W5) siempre hay **una grieta por donde se fuga el contexto**. W3 tapa esa grieta de frente. #17 Matthew condensa la salida de W2 en **archivos de historia dev autocontenidos** (9 secciones; cada detalle técnico lleva su fundamento `[Source:...]`), y Thomas y Matthias los revisan de forma independiente. Si el veredicto sale **FAIL, el hook `gate-enforce` bloquea físicamente la entrada misma a W5** (§7).

---

## 4. Enrutamiento Scale-Adaptive (Lv0–4)

**Se ajustan explícitamente las waves y roles a activar** según el tamaño del trabajo. Es decir, no siempre se pone todo a plena marcha. Al pasar los stakes a `/route` sale un nivel recomendado, y **la decisión final es del usuario** (User Sovereignty). El nivel actual queda registrado en `current_level` de `_state/manifest.json`.

| Lv | Tipo de trabajo | Waves activadas | #17 Matthew | W4 |
|----|-----------------|-----------------|:----:|:--:|
| **Lv0** | Arreglo de bug · cambio trivial | Solo W5 (+ W6 ultraligera) | ✗ | ✗ |
| **Lv1** | Funcionalidad pequeña · refactor local | W2 ligera + W3 (abreviada) + W5 + W6 ligera | ✓ (abreviado) | ✗ |
| **Lv2** | Funcionalidad/módulo estándar | W1 + W2 + W3 + W5 + W6 | ✓ | opcional |
| **Lv3** | Producto nuevo · grande | W0–W6 (W4 opcional) | ✓ | opcional (recomendado) |
| **Lv4** | Enterprise · deep-tech · regulado | W0–W6 completas + W4 completa | ✓ | ✓ obligatorio |

La regla de recomendación que traduce stakes a nivel la calcula `bathos-router`. Los stakes se componen de cuatro ejes — `scope`, `novelty`, `regulation_ip`, `team_size`. (Tabla de mapeo: ver el comando `route.md`.)

---

## 5. Sistema de gates (PASS / CONCERNS / FAIL)

Todos los gates de wave comparten **un único vocabulario**.

| Veredicto | Significado | Acción |
|-----------|-------------|--------|
| **PASS** | Criterios cumplidos, sin bloqueantes | Entrada inmediata a la siguiente wave |
| **CONCERNS** | Paso condicional (riesgos no bloqueantes) | Se registra el riesgo en `_state/` y se avanza |
| **FAIL** | Defecto bloqueante | Entrada bloqueada; corregir y **re-gatear** |

El principio es claro. El gate es un **FACILITATOR que ayuda al veredicto, no un generator que lo fabrica** — no se permite un auto-PASS sin fundamento. El gate central de W3 se impone de forma dura con un hook, y el sujeto del veredicto de gate (`facilitator`) jamás puede estar vacío (invariante).

---

## 6. Referencia CLI (binario `bathos`)

Opciones globales (comunes a todos los subcomandos):
- `-s, --state-dir <PATH>` — directorio de estado (por defecto `./_state`)
- `--modules-dir <PATH>` — directorio de módulos plug (por defecto `./modules`)
- `-h, --help` · `-V, --version`

**Convención de códigos de salida:** `0`=éxito · `1`=error general · `2`=gate FAIL (los hooks lo usan para bloquear la entrada).

### 6.1 `bathos state` — SSOT de estado (B1)
```bash
bathos --state-dir .agent-team/_state state init \
       --codename MYPROJECT                            # crea un manifest.json seed válido según el esquema
bathos --state-dir .agent-team/_state state validate   # validación JSON Schema de manifest.json (VALID/lista de violaciones)
bathos --state-dir .agent-team/_state state show        # imprime el JSON del estado actual
```

`state init` crea el estado mínimo válido con `level=0`, `lang=ko` y un
`project_id=bathos-<uuid>` automático. No reemplaza un manifest existente
sin `--force`. `/team-kickoff` lo invoca durante el uso normal.

### 6.2 `bathos gate` — veredictos de gate (B3)
```bash
# Registrar un veredicto — GATE_TYPE: Brief|Usp|Plan|Implementation|Release / VERDICT: PASS|CONCERNS|FAIL
bathos -s _state gate verdict Implementation PASS Matthew
bathos -s _state gate verdict Implementation FAIL Matthew \
       --issues-json '[{"level":"critical","description":"...","source":"..."}]'
#   → registrar FAIL produce código de salida 2

# Consultar el último gate Implementation (el SSOT que llama gate-enforce.sh)
bathos -s _state gate show
#   → {"gate_type":"Implementation","verdict":"PASS","issues_total":0,"issues_critical":0,...}
#   sin gate → salida vacía (exit 0)
```
- Opciones: `--report <ruta>`, `--story-key <clave>`, `--issues-json <array JSON>`
- **Enum de level de issue:** `critical` | `enhancement` | `optimization` (un solo `critical` significa FAIL).

### 6.3 `bathos story` — verificación de historias (B3)
```bash
# Verificación de completitud D1 + trazabilidad D2 (stdin o --file)
bathos story compile 1-2-payment-auth --file story-1-2-es.md
#   → {"is_valid":true,"missing_sections":[],...}  / si falla: exit 1 (E-CTX-LOSS)

# Frescura D3 (staleness) — hash guardado vs archivos de aguas arriba actuales
bathos story check-stale 1-2-payment-auth \
       --stored-hash <sha256> --upstream archi.md --upstream design.md
#   → fresh: "FRESH" exit 0 / stale: E-STALE exit 1
```

### 6.4 `bathos wave` / `bathos route` (B2)
```bash
bathos -s _state wave activate W2     # transiciona la wave a active (impone activos concurrentes ≤ 3; exceso → E-CONCURRENCY)
bathos -s _state wave show            # JSON con el estado de todas las waves
bathos -s _state route show           # historial de decisiones de nivel

# Recomendación de nivel por stakes (JSON) — stdin o --stakes-json. Por defecto solo recomienda (sin commit).
echo '{"scope":"feature","novelty":true,"regulation_ip":false,"team_size":"medium"}' \
  | bathos -s _state route decide
#   → {"recommended_level":2,"wave_set":[...],"role_set":[...],"requires_confirmation":true}

# --confirm <0-4>: el usuario confirma explícitamente → se registra en manifest routing[] + se actualiza current_level
bathos -s _state route decide \
  --stakes-json '{"scope":"product","novelty":true,"regulation_ip":true,"team_size":"large"}' --confirm 4
```
- `route decide` **separa deliberadamente recomendación y confirmación** (User Sovereignty). Sin argumentos solo emite la recomendación; solo con `--confirm <nivel>` registra de verdad.
- Los 4 ejes de stakes: `scope` (bug|feature|module|product…) · `novelty` (bool) · `regulation_ip` (bool) · `team_size` (solo|medium|large).

### 6.5 `bathos plug` — módulos plug (B4)
```bash
bathos --modules-dir modules plug list              # lista de módulos + estado de activación (JSON)
bathos -s _state --modules-dir modules plug enable ip      # activar módulo (persistente)
bathos -s _state --modules-dir modules plug disable ip     # desactivar módulo
#   módulo inexistente → exit 1 (E-PLUG-NOTFOUND)
```

### 6.6 `bathos audit` — log de auditoría (B-1)
```bash
# append: vía el writer Rust único (formato unificado con los hooks bash). Siempre exit 0 (para no bloquear hooks).
bathos -s _state audit append --actor hook --action tool.write --target manifest.json

# verify: verificación de integridad de la cadena de hashes de auditoría (comprueba directamente la promesa tamper-evident)
bathos -s _state audit verify
#   → íntegra: "OK — cadena de hashes de auditoría íntegra (N entries ...)" exit 0
#   → manipulación/ruptura: "[E-AUDIT-TAMPER] ... seq=N hash_prev no coincide ..." exit 1
```

### 6.7 `bathos doctor` — diagnóstico preflight de instalación/cableado
```bash
bathos -s .agent-team/_state doctor --root .
#   Revisa: BATHOS_BIN · jq · flag de Agent Teams · trampa de claves de comentario en el bloque hooks de settings.json ·
#           existencia/permisos de ejecución de hooks · assets·modules · esquema del manifest · cadena de auditoría
#   → imprime una checklist ✓//✗. Con 0 errores exit 0; con al menos uno, exit 1.
```
- Se recomienda ejecutarlo una vez justo después de `install.sh`. En particular, detecta de forma determinista **la trampa de las claves de comentario (`_note`, etc.) mezcladas en el bloque `hooks` de settings.json, que provocan una espera infinita** (§13 troubleshooting).
- `--root` es la ruta base donde buscar `.claude/` · `assets/` · `modules/` (por defecto el directorio actual), y `-s` apunta a la ubicación del manifest y la cadena de auditoría.

---

## 7. Hooks / capa de seguridad (M6)

`bathos/.claude/settings.json` enlaza los hooks a cada evento de Claude Code. Todos los hooks con capacidad de bloqueo están diseñados de forma **determinista y fail-safe** — ante la ambigüedad, se inclinan por bloquear.

| Hook | Evento | Función | Condición de bloqueo (exit 2) |
|------|--------|---------|-------------------------------|
| `careful-guard.sh` | PreToolUse(Bash) | Bloqueo de comandos destructivos | `rm -rf` · `DROP TABLE` · `git push --force`, etc. |
| `freeze-guard.sh` | PreToolUse(Write/Edit/MultiEdit) | Restricción del alcance de edición | Edición fuera de `BATHOS_OWNED_PATHS` |
| `audit-log.sh` | PostToolUse | Append al log de auditoría | (no bloqueante) `_state/audit-log.jsonl` |
| `artifact-verify.sh` | TaskCompleted | Verificación de existencia de artefactos | Artefacto faltante en tareas QA/W3 |
| `gate-enforce.sh` | TaskCompleted | **FAIL en W3 → bloqueo físico de la entrada a W5** | Tarea de entrada a W5 + verdict de W3 = FAIL |
| `next-action.sh` | TeammateIdle | Guía de la siguiente acción | (no bloqueante) |

**Orden en que corre `gate-enforce`:** al detectar la tarea de entrada a W5 → consulta el último verdict Implementation con `bathos gate show` → si el valor es `FAIL`, bloquea con exit 2; si es `PASS` o `CONCERNS`, deja pasar con exit 0. Si el binario o el gate no existen, siguiendo el principio fail-safe deja solo una advertencia y pasa.

> **Nota operativa:** en el bloque `hooks` de `settings.json` solo deben ir **nombres de eventos de hook válidos**. Si se mezcla una clave de comentario (`_note`, etc.), los subagentes caen en una espera infinita al arrancar.

Para verificar los hooks en sí: `bash .claude/hooks/_test-hooks.sh` (46 tests de determinismo, todos PASS).

---

## 8. Los 17 roles (M8)

Las definiciones base están en `bathos/.claude/agents/_base/`. Los overrides son en 3 capas (base→team→user): los valores escalares se sobrescriben y los arrays se hacen append.

| # | Nombre | Rol | Modelo | Wave |
|---|--------|-----|--------|------|
| 0 | Paul | Dirección general/líder/confirm final | Opus 4.8 | todas las waves (sesión principal) |
| 1 | John | Reverse Specialist | Opus 4.8 | W1 (+W0) |
| 2 | Caleb | Análisis de mercado/USP (+ Analyst en W0) | Opus 4.8 | W1 (+W0) |
| 3 | Joshua | Planificación de servicio | Opus 4.8 | W2 (gate) |
| 4 | James | Arquitecto SW · cloud | Opus 4.8 | W2 |
| 5 | Mark | IP Specialist (patentes) | Opus 4.8 | W4 (plug) |
| 6 | Nathanael | Abstract/Intro de paper | Sonnet 5 | W4 (plug) |
| 7 | Jonnathan | Diseñador principal (UX/UI) | Opus 4.8 | W2 |
| 8 | Phillip | Principal de backend · datos | Sonnet 5 | W5 |
| 9 | Andrew | Principal de frontend · móvil | Sonnet 5 | W5 |
| 10 | Stephen | Principal de AI/ML | Sonnet 5 | W5 |
| 11 | Timothy | Documentación de definiciones de desarrollo | Sonnet 5 | W6 (+W3) |
| 12 | Thomas | Revisor de código | Sonnet 5 | W6 (+ revisión independiente en W3) |
| 13 | Michael | Auditoría de seguridad/hardening (defensivo web/ciber) | Sonnet 5 | W6 (tras Thomas) |
| 14 | Hananiah | Refactorización (preserva comportamiento) | Sonnet 5 | W6 (tras Michael) |
| 15 | Matthias | QA/verificación (E2E) | Sonnet 5 | W6 (+ revisión independiente en W3) |
| 16 | Martin | Monitoreo/reporte HTML | Sonnet 5 | W6 (agregación) |
| **17** | **Matthew** | **Scrum Master/Story Engineer** | Opus 4.8 | **exclusivo de W3 (inactivo el resto del tiempo)** |

> Paul es la **sesión principal**, no se genera (spawn) como compañero. #17 Matthew se genera **solo cuando W3 está activa**, así que normalmente no consume ningún token. Su slug de agent type es `matthew-story-engineer`.

---

## 9. Módulos plug (extensión W4)

El core se mantiene esbelto, y las capacidades de dominio **se encienden y apagan como módulos plug.** El core no conoce la existencia de los módulos — porque la dependencia inversa está prohibida (A9). Cada módulo se declara a sí mismo con `modules/<id>/module.yaml`.

### 9.1 Contrato de module.yaml
```yaml
module_id: ip                      # ip | research | game | security ...
name: IP Pack
wave: W4
trigger: "Lv>=3 OR domain=ip"      # condición de auto-trigger (comparación de Lv + domain= , combinación con OR)
enabled_default: false
provides:
  workflows: [patent-spec-draft]
  templates: [patent-spec]
outputs: ".agent-team/05-ip/"
evidence_trace: true               # trazabilidad afirmación → fundamento [Source:]
```

### 9.2 Módulos incluidos por defecto
| Módulo | id | Salida | Workflow |
|--------|----|--------|----------|
| IP pack (Mark) | `ip` | `.agent-team/05-ip/` | `patent-spec-draft` (especificación de solicitud en formato de oficina de patentes) |
| Research pack (Nathanael) | `research` | `.agent-team/06-research/` | `abstract-introduction` (Abstract+Intro académicos) |

### 9.3 Sintaxis de triggers (`bathos-plug`)
- `Lv>=N` `Lv>N` `Lv<=N` `Lv<N` `Lv=N` (N=0–4) · `domain=X` / `domain:X`
- Encadenados con ` OR `, se dispara si al menos uno es verdadero. Los tokens no interpretables se tratan como `false` (conservadoramente).

---

## 10. Activos (M9, `assets/`)

Colección de activos, escritos de forma consistente en coreano, que consultan el motor de historias de W3 y los plugs.
- `templates/` — `story-template.md`, `project-context-template.md`, `readiness-report-template.md`, `session-snapshot-template.md`, `design-system-template.md` (design tokens · contrato de componentes)
- `workflows/` — `create-story.md` (procedimiento de compilación de historias), `check-implementation-readiness.md` (procedimiento de gate), `design-excellence.md` (UI/UX top-tier en 10 pasos)
- `checklists/` — `story-context-quality.md` (re-verificación adversarial de los 8 errores fatales), `design-quality.md` (rúbrica 0–10 de 11 dimensiones de calidad de diseño)
- `_index.md`, `_glossary-kr.md` (glosario)

---

## 11. Modelo de estado y convención de directorios

### 11.1 SSOT — `_state/manifest.json`
Todo el estado del proyecto está inlined en un único JSON (validado con JSON Schema). Los campos principales:
`project_id` (`bathos-<uuid>`), `codename`, `current_level` (0–4), `status` (active|paused|done), `lang`, `created`, y los arrays 1:N — `routing[]` (LevelDecision), `waves[]`, `roles[]`, `tasks[]`, `gates[]` (GateVerdict), `risks[]`, `modules[]` (PlugModule), `artifacts[]`.
Todas las escrituras se registran con **escritura atómica + cadena de hashes de auditoría** (`audit-log.jsonl`).

### 11.2 Directorio de artefactos `.agent-team/`
```
00-plan/  00-analysis/  01-reverse/  02-market-analysis/  03-service-planning/
03-story-engineering/   04-architecture/  05-ip/  06-research/  07-design/
08-impl-notes/  09-docs/  10-review/  11-qa/  12-report/  _state/
```
**El código fuente real del producto** se queda tal cual en la ruta habitual de la raíz del proyecto (`src/`, etc.); en `.agent-team/` solo se acumulan el trabajo del equipo y sus metadatos de salida.

---

## 12. Comandos de operación y refuerzos de gstack

- **Equipo:** `/team-kickoff` · `/team-status` · `/team-confirm` · `/team-cleanup` (limpieza de emergencia)
- **Guardar/restaurar sesión:** `/save-session` (guardado completo) · `/cold-start` (restauración completa en sesión nueva). Alias cortos `/save` · `/resume`, alias gstack `/context-save` · `/context-restore`. Ver §12.1.
- **Memoria cross-project:** `/project-handoff` (destila el proyecto actual en `~/.bathos/registry/`) · `/recall` (recuerda el contexto de proyectos anteriores relevantes en un proyecto nuevo). Ver §12.1.
- **Seguridad:** `/guard` (activa careful+freeze) · `/unfreeze`
- **Gates de revisión de plan (refuerzo de W2):** `/plan-ceo-review` · `/plan-design-review` · `/plan-eng-review` · `/plan-devex-review` · `/autoplan` (ejecuta los cuatro en secuencia)
- **Otros:** `/review` (revisión de PR) · `/investigate` (debugging de causa raíz) · `/cso` (auditoría de seguridad OWASP+STRIDE) · `/retro` · `/health` · `/context-save` · `/context-restore`

### 12.1 Guardado de sesión y cold-start (traspaso completo y sin pérdidas)

Un build real se extiende por varias sesiones de Claude Code. Y los compañeros **no heredan el historial de conversación del líder.** Por eso BATHOS persiste todo en disco, de modo que incluso una sesión nueva sin ningún contexto pueda restaurarlo por completo. Los comandos oficiales son estos dos (no necesitan argumentos — usan por defecto el `.agent-team/_state` del proyecto actual):

**`/save-session` — guarda *toda* la información de la sesión.** Ejecútalo antes de parar el trabajo. Deja dos artefactos (+ archivo con fecha):

| Artefacto | Qué contiene |
|-----------|--------------|
| `_state/session-state.json` | El SSOT de máquina completo — un dump del manifest entero (`routing` · `waves` · `roles` · `tasks` · `gates` · `risks` · `modules` · `artifacts`) vía `bathos state show`. |
| `_state/SESSION-SNAPSHOT.md` | La narrativa legible por humanos — su párrafo **"★ Estado actual"** es el punto de entrada del cold-start (resumen de un párrafo + el comando a ejecutar a continuación). |

Además incluye la verificación de la cadena de auditoría (`bathos audit verify`), el estado git del código de producto, el inventario de `.agent-team/`, y las decisiones de esta sesión · la wave en curso · los compañeros a re-generar (respawn) · el trabajo pendiente · el siguiente comando.

**`/cold-start` — restaura todo en una sesión nueva.** Ejecútalo en una sesión nueva con contexto cero. Lee en orden `SESSION-SNAPSHOT.md` → `session-state.json` → `manifest.json` → `wave-log.md`/`signoff.md`, contrasta las tres fuentes de estado para comprobar que no hay drift, verifica la integridad de la auditoría y entonces entrega un briefing completo: identidad del proyecto, nivel actual, estado de waves y veredictos de gate, lo ya terminado, lo que estaba en curso, **los compañeros que hay que volver a generar** (con el comando `/waveN-…` correspondiente — sin pérdidas porque los artefactos quedan en disco), los riesgos pendientes, y **▶ el comando a ejecutar a continuación**. Este proceso es de solo lectura y no avanza automáticamente el siguiente paso en lugar del usuario (User Sovereignty).

```text
# Al terminar la sesión:
/save-session            # (o /save — idéntico)

# Al empezar la siguiente sesión, en el mismo directorio del proyecto:
/cold-start              # (o /resume — idéntico)
```

> **Alias y triggers.** `/save`=`/save-session`, `/resume`=`/cold-start`, y `/context-save` · `/context-restore` son los alias de gstack. Todos comparten el mismo `_state`/SSOT. Funciona también en lenguaje natural: "guardar sesión/guardar/checkpoint" → guardar, "cold-start/continuar/reanudar/cargar" → restaurar.
> **Nota sobre límites de uso.** Si un compañero se queda callado de repente, normalmente no es un crash sino que topó con el límite de quota — guarda con `/save-session`, espera el reinicio del límite, restaura con `/cold-start` y vuelve a ejecutar la wave. Ver [`QUOTA-es.md`](QUOTA-es.md).

**Memoria cross-project (cold-start caliente a través de proyectos).** Los dos comandos anteriores se limitan a un proyecto. El contexto que debe cruzar *entre* proyectos — decisiones a reutilizar, patrones recurrentes, lecciones aprendidas a alto precio — se acumula en el registro global `~/.bathos/registry/` (`INDEX.md` + tarjetas `<slug>.md` por proyecto):
- **`/project-handoff`** — destila el proyecto actual en una tarjeta del registro. `/save-session` realiza este upsert automáticamente, así que la memoria se acumula de forma natural con cada guardado.
- **`/recall`** — en un proyecto nuevo, trae las tarjetas de proyectos anteriores relevantes (decisiones · patrones a reutilizar + lecciones a evitar) para hacer **warm-start**. `/cold-start` también consulta el registro.

Es decir, **incluso en otro proyecto y otra sesión**, lo aprendido en proyectos anteriores se reutiliza en profundidad. Eso sí, el recall es siempre una propuesta (User Sovereignty) — la dirección de este proyecto la decide el usuario.

### Los 3 principios de gstack (ETHOS.md)
1. **User Sovereignty (supremo):** la IA propone, **la decisión la toma el usuario.** Una recomendación que cambia la dirección se pregunta en la forma "recomendación + fundamento + contexto omitido".
2. **Boil the Ocean:** si la implementación completa solo cuesta unos minutos más, elige la completa. No aplaces tests ni casos límite.
3. **Search Before Building:** en terreno desconocido, primero busca para mapear el paisaje.

---

## 13. Troubleshooting (lecciones de campo)

| Síntoma | Causa | Solución |
|---------|-------|----------|
| Espera infinita al arrancar un subagente | Clave de comentario mezclada en el bloque `hooks` de `settings.json` | Deja solo nombres de eventos válidos · **detéctalo con `bathos doctor`** (§6.7) |
| Un compañero parece detenido sin salida alguna | **Límite de uso (session) de la cuenta** de Claude — no es un bug del código | Espera el reinicio y re-genera (los artefactos quedan en disco, sin pérdidas). Detalle: [`QUOTA-es.md`](QUOTA-es.md) |
| No estás seguro de si la instalación/cableado está bien | — | Ejecuta **`bathos doctor`** (§6.7) |
| `state validate` rechaza un manifest correcto | Confusión entre el esquema antiguo (operativo) y el esquema bathos-product | Usa el esquema del manifest de bathos (§11.1) |
| Fallo de parseo en `gate verdict ... noncritical` | Error en el enum de level de issue | Usa `critical`/`enhancement`/`optimization` |
| Colisión de nombres de rol al operar varios proyectos a la vez | El mismo agent type/name colisiona en el registro del swarm | Añade un sufijo único por proyecto u opera en solitario |
| Un compañero no responde al shutdown | El hook TeammateIdle lo relanza | `tmux -L claude-swarm-<pid> kill-pane -t <id>` (el trabajo queda preservado en disco) |
| `gate-enforce` no bloquea | Desajuste en los campos de entrada del hook (`.title`/`.description`) o gate sin registrar | Revisa la forma de la entrada y la salida de `bathos gate show` |

---

## 14. Estado actual de implementación y límites (aviso de honestidad)

**v0.4.0 — etapa temprana, pero funciona de verdad.** BATHOS hoy compila y corre end-to-end. Para quienes consideran adoptarlo, lo declaramos con honestidad:

- Esto **no es una app independiente sino un paquete de método que corre sobre Claude Code v2.1.32+**, y depende de la **funcionalidad experimental Agent Teams**.
- **El motor está verificado:** **628 tests de Rust + 86 de determinismo de hooks, todos en verde**, `clippy -D warnings` limpio, `cargo build --release` reproducible; la imposición dura de gates y la integración de plugs se confirmaron end-to-end, y la no-dependencia del core respecto a módulos (A9) también quedó probada.
- **Certificación totalmente independiente completada (dogfooding):** BATHOS aplicó la verificación independiente de W6 a su propio código tal cual. Las dos certificaciones — **ThomasCert (revisión de código independiente, PASS) y MatthiasCert (QA/E2E independiente, PASS)** — pasaron, alcanzando **Release Readiness = PASS (certificación totalmente independiente)**. Lo interesante: aunque el QA funcional estaba en verde, la revisión de código independiente detectó un **defecto bloqueante de invariante que el propio autor había pasado por alto** — el motor Rust y los hooks bash escribían en la misma cadena de auditoría en formatos incompatibles, neutralizando la tamper-evidence. Se resolvió por completo tras corrección · re-gate · agotamiento del backlog. Trail de verificación: `.agent-team/` (`10-review/` · `11-qa/` · `12-report/w6-final-certification.html` · `_state/signoff.md`).
- Algunos comandos de wave no son flujos de motor totalmente automatizados, sino **prompts de orquestación que el líder ejecuta directamente** (spawn/inspección de compañeros).
- **Todavía no está en etapa production-hardened** — hasta 1.0, APIs, esquemas y nombres de comandos pueden cambiar.

> **La tesis que enuncia la metodología:** lo que el dogfooding anterior demostró es, en esencia, que **"generación ≠ verificación"**. Si el mismo modelo escribe y se aprueba a sí mismo, inevitablemente quedan puntos ciegos. Por eso BATHOS separa autor y verificador, erige el gate como FACILITATOR, y clava las invariantes clave con el motor Rust.

---

## 15. Licencia

BATHOS es un paquete implementado de forma independiente desde primeros principios tras un análisis inverso cuidadoso de BMAD-METHOD (MIT © 2025 BMad Code, LLC); con respeto por el trabajo previo que le sirvió de base, se distribuye bajo **MIT License**. Las marcas del autor original como "BMAD"/"BMad Method" no se usan en el nombre del producto ni en marketing. (Texto completo: ver `README.md`.)

---

*Versión del documento: v0.4.0 · Autor: el líder Paul · Base: artefactos de build reales (B1–B4).*
[USAGE-kr](USAGE-kr.md) · [USAGE-en](USAGE-en.md)
