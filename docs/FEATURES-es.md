# BATHOS — Características y funcionamiento

> **βάθος** (griego) — *"profundidad; lo profundo."* Un método de AI Workflow Agent de profundidad abrumadora, posicionado deliberadamente en contraste con la asistencia de IA superficial.
>
> Piensa en este documento como el compañero de "por qué, y cómo" de la guía de uso. Explica **qué es BATHOS (características) y cómo funciona realmente por dentro (mecánica)**. Todo aquí está escrito contra el **build real v0.4.0** — cada mecanismo descrito está implementado y verificado, y donde hay límites, se declaran abiertamente en lugar de ocultarse.
>
> **Ver también:** Si prefieres ejecutarlo antes que entenderlo, ve a la [guía de uso](USAGE-es.md). Las reglas de operación viven en [`../CLAUDE.md`](../CLAUDE.md), y los principios detrás de ellas en [`../ETHOS.md`](../ETHOS.md). · 한국어: [`FEATURES-kr.md`](FEATURES-kr.md) · English: [`FEATURES-en.md`](FEATURES-en.md)

---

## 0. La única idea debajo de todo

Una conversación larga con un solo LLM **deriva (drift)**: el contexto se fuga entre "diseño" e "implementación", los controles de calidad se saltan, y *el mismo modelo* escribe el trabajo y además lo aprueba. La tesis de BATHOS cabe en una frase:

> **Generación ≠ verificación.** Un generador no puede ver los puntos ciegos de su propia salida.

Por eso BATHOS reemplaza una conversación que deriva por **estructura**: roles especialistas separados, un pipeline por etapas, verificadores *independientes*, y un pequeño **motor determinista** que hace cumplir las invariantes clave **en código**, no por la buena voluntad del modelo.

Esto no es una metáfora — es literalmente cómo se construyó BATHOS. BATHOS se implementó a sí mismo y luego ejecutó la verificación independiente de Wave 6 sobre su propio código. El QA funcional estaba en verde, y aun así la revisión de código independiente detectó un **defecto bloqueante de invariante que el autor había pasado por alto** (el motor Rust y los hooks bash escribían en la misma cadena de auditoría en formatos *incompatibles* → la tamper-evidence quedaba neutralizada en silencio). Se corrigió, se re-gateó y se agotó el backlog — una demostración de la tesis.

---

## 1. Características (lo que distingue a BATHOS)

Antes de entrar en la mecánica, el panorama general — doce características y lo que cada una te da realmente.

| # | Característica | Qué te da |
|---|----------------|-----------|
| 1 | **17 roles especialistas × pipeline de 7 waves** | Una única sesión de Claude Code se comporta como un equipo de producto disciplinado (discovery → diseño → historia → build → verificación) en lugar de una conversación que no deja de hincharse. |
| 2 | **Dos planos de ejecución: orquestación en markdown + motor Rust** | Los flujos de trabajo de cara al humano permanecen como markdown editable, mientras un único binario estático computa y *hace cumplir* de forma determinista las invariantes clave. |
| 3 | **Enrutamiento Scale-Adaptive (Lv0–4)** | Solo se activan las waves que el trabajo realmente necesita. Un arreglo de bug no se empuja por todo el discovery, y un build enterprise no se sub-dimensiona. |
| 4 | **Archivos de historia zero-context-loss (Wave 3)** | Archivos de historia dev autocontenidos con `[Source: …]` en cada detalle técnico cierran de frente la brecha de contexto diseño→implementación. |
| 5 | **Gates de calidad duros (PASS / CONCERNS / FAIL)** | Un `FAIL` en el gate de readiness no es una recomendación — un hook (exit code 2) *bloquea físicamente* la entrada a implementación. |
| 6 | **Verificación independiente + cadena de auditoría tamper-evident** | Los verificadores están separados de los autores, y cada cambio de estado se registra en una cadena de hashes sha256 append-only. |
| 7 | **User Sovereignty (soberanía del usuario)** | La IA propone; *el usuario* decide. Las recomendaciones que cambiarían la dirección declarada del usuario se presentan como "recomendación + fundamento + contexto omitido" y nunca se ejecutan unilateralmente. |
| 8 | **Hooks de seguridad (careful / freeze)** | Se bloquean los comandos destructivos y las ediciones quedan restringidas a las rutas propias. Diseño fail-safe (ante la duda, bloquear). |
| 9 | **Módulos plug (core esbelto, dominios opt-in)** | Los paquetes de IP/patentes e investigación son plugs; el core no sabe nada de los módulos (sin dependencia inversa). Los dominios nuevos se enchufan sin engordar el core. |
| 10 | **Overrides de rol en 3 capas** | La identidad del rol queda fijada en la capa base, mientras las capas de proyecto y usuario sobrescriben rutas propias / idioma / intensidad de facilitación sin hacer fork. |
| 11 | **Guardar/reanudar sesión con una palabra** | `/save` toma un snapshot de la sesión entera y `/resume` la restaura en la siguiente. Funciona también en lenguaje natural ("guardar"/"continuar") → el trabajo multi-sesión nunca pierde contexto. |
| 12 | **Memoria cross-project** | Un registro global (`~/.bathos/registry/`) permite que incluso un proyecto totalmente nuevo arranque en caliente (warm-start) desde las decisiones, patrones y lecciones de proyectos anteriores — reutiliza lo que funcionó, no vuelvas a aprender lo que dolió. |

---

## 2. Funcionamiento (la mecánica real)

### 2.1 Los dos planos de ejecución

Es el primer mecanismo central que hay que entender.

| Plano | Qué es | Responsabilidad | Quién lo ejecuta |
|-------|--------|-----------------|------------------|
| **Orquestación** | **Comandos slash** en markdown · **definiciones de roles** · **hooks bash** bajo `.claude/` | Avanzar waves, generar (spawn)/inspeccionar/apagar compañeros, hablar con el humano | **El líder (Paul)** — la sesión principal de Claude Code |
| **Motor** | Un único binario Rust estático **`bathos`** (~5.6MB, 7 crates) | Computar y *hacer cumplir* estado · enrutamiento · transiciones de wave · gates · frescura de historias · plugs · la cadena de auditoría | Los hooks/comandos invocan `bathos <subcommand>` (también se puede usar directo) |

El humano teclea comandos slash. El binario `bathos` es el núcleo determinista de debajo que llaman los comandos y hooks. La separación es el punto: **todo lo que debe ser confiable y reproducible** (¿el gate realmente pasó? ¿los roles activos son ≤ 3? ¿la cadena de auditoría está intacta?) vive en el motor, garantizado por tests unitarios, para que un modelo persuasivo no pueda "sortearlo hablando".

### 2.2 Modelo de estado — fuente única de verdad (`bathos-state`)

Si el motor es la mitad confiable, aquí es donde esa confianza echa el ancla. Todo el estado del proyecto está inlined en un único archivo JSON, `<state-dir>/manifest.json` (por defecto `./_state`), validado con JSON Schema. Campos principales:

- `project_id` (`bathos-<uuid>`), `codename`, `current_level` (0–4), `status` (active|paused|done), `lang`, `created`
- Arrays 1:N: `routing[]` (decisiones de nivel), `waves[]`, `roles[]`, `tasks[]`, `gates[]`, `risks[]`, `modules[]`, `artifacts[]`

Dos invariantes hacen que el estado sea confiable:

1. **Escrituras atómicas** — el manifest nunca queda escrito a medias.
2. **Cadena de auditoría tamper-evident** (`audit-log.jsonl`) — cada cambio añade una entrada a una cadena de hashes **sha256 append-only**:
   - Cada entrada guarda `hash_prev` (el `hash_self` de la entrada anterior) y `hash_self` (sha256 de sí misma serializada con `hash_self` vacío — evita el hash circular).
   - Invariantes: `seq` monótonamente creciente; `hash_prev[n] == hash_self[n-1]`; la primera entrada tiene `hash_prev == "genesis"`.
   - Un único writer (`bathos audit append`) serializa todos los hooks con un file-lock bloqueante, de modo que los appends concurrentes no pueden corromper la cadena. *(Esta es precisamente la invariante que la revisión de dogfooding detectó — Rust y bash escribían en formatos incompatibles, y se unificó.)*

Una ruptura de la cadena se detecta como `E-AUDIT-TAMPER`; una violación de esquema, como `E-STATE-CORRUPT`.

### 2.3 Router Scale-Adaptive (`bathos-router`)

El router convierte cuatro ejes de "stakes" en un nivel recomendado. La puntuación es completamente determinista:

| Eje | Entrada | Puntos |
|-----|---------|--------|
| `scope` | bug/fix/hotfix/trivial/small | 0 |
| | feature/medium *(o poco claro)* | 1 |
| | large/big/module/component | 2 |
| | enterprise/platform/product | 3 |
| `novelty` | true | +1 |
| `regulation_ip` | true | +2 *(señal fuerte de subida)* |
| `team_size` | solo/single/small | 0 |
| | medium/mid | 1 |
| | large/big/enterprise | 2 |

Mapeo total → nivel: **0 → Lv0 · 1 → Lv1 · 2–3 → Lv2 · 4–5 → Lv3 · 6+ → Lv4.**

| Lv | Tipo de trabajo | Waves activadas | #17 | W4 |
|----|-----------------|-----------------|:---:|:--:|
| 0 | Arreglo de bug · trivial | W5 (+ W6 ultraligera) | ✗ | ✗ |
| 1 | Funcionalidad pequeña · refactor local | W2 ligera + W3 (abreviada) + W5 + W6 ligera | ✓ | ✗ |
| 2 | Funcionalidad/módulo estándar | W1 + W2 + W3 + W5 + W6 | ✓ | opcional |
| 3 | Producto nuevo · grande | W0–W6 (W4 opcional) | ✓ | recomendado |
| 4 | Enterprise · deep-tech · regulado | W0–W6 completas + W4 | ✓ | obligatorio |

La clave es la **separación entre recomendación y confirmación** (User Sovereignty): `route decide` solo recomienda (`requires_confirmation: true`), y el nivel se registra únicamente cuando el usuario da `--confirm <0–4>`. Si el nivel confirmado difiere de la recomendación, el motor registra un veredicto `modify` y recalcula el conjunto de waves/roles. Si el nivel cambia después, se detecta como `E-LEVEL-DRIFT` y se vuelve a preguntar al usuario.

### 2.4 Motor de waves (`bathos-wave-engine`)

El pipeline es una máquina de estados de 7 waves: **W0 → W1 → W2 → W3 → W5 → W6**, con **W4 (IP · investigación)** como plug opcional ejecutable en cualquier momento después de W2.

```
(previo) kickoff → W0 análisis → W1 discovery → W2 diseño
        → W3 story gate ★ → W5 implementación → W6 verificación → (posterior) confirmación
                                  ↑
                       W4 IP & investigación  (plug opcional)
```

Cada wave atraviesa transiciones de estado (p. ej. `active → gated → …`). Dos reglas duras:

- **Concurrencia ≤ 3.** `MAX_CONCURRENT_ROLES = 3`; `spawn_role()` rechaza el 4.º rol activo en una wave con `E-CONCURRENCY`. (El costo en tokens escala linealmente con el número de compañeros activos, así que cada wave activa solo al personal necesario.)
- **Cierre de wave → shutdown de esos compañeros → siguiente wave.** El traspaso ocurre exclusivamente a través de los artefactos en disco de `.agent-team/`; los compañeros no heredan el historial de conversación del líder.

### 2.5 Motor de gates (`bathos-gate-engine`)

Todos los gates de wave usan un único vocabulario y una única regla determinista:

| Veredicto | Regla | Efecto |
|-----------|-------|--------|
| **PASS** | Sin issues | Entrada a la siguiente wave |
| **CONCERNS** | Solo issues no bloqueantes | Se registra el riesgo en `_state/` y se avanza |
| **FAIL** | `issues_critical > 0` | Entrada bloqueada; corregir y re-gatear |

Los niveles de issue son `critical | enhancement | optimization`, y **un solo issue `critical` significa FAIL.** El gate es **FACILITATOR, no generator** — el `facilitator` de un veredicto (quién decidió) no puede estar vacío, así que un auto-PASS sin fundamento es imposible. El motor además cuenta los FAIL *consecutivos* del historial de gates (`take_while(Fail)`) para rastrear los ciclos de re-gate. La fuente de verdad del veredicto más reciente es `bathos gate show`.

### 2.6 Motor de historias — Zero-Context-Loss (`bathos-story-engine`)

Wave 3 es el corazón: condensa el diseño de aguas arriba (W2) en **archivos de historia dev autocontenidos** para que el implementador arranque solo con la historia. El motor hace cumplir tres dimensiones:

- **D1 completitud** — deben existir 6 secciones obligatorias: `story_requirements`, `developer_context`, `architecture_compliance`, `library_framework_requirements`, `file_structure_requirements`, `testing_requirements`. Además, `developer_context` no puede estar vacío. Secciones faltantes o en blanco hacen fallar la compilación con `E-CTX-LOSS`. *(La plantilla markdown contiene más secciones — historia, criterios de aceptación, tareas, Dev Notes, Dev Agent Record, etc. — pero estas 6 son el mínimo que la máquina hace cumplir.)*
- **D2 trazabilidad** — las afirmaciones técnicas llevan el marcador `[Source:` que conecta cada detalle con su artefacto de aguas arriba.
- **D3 frescura (staleness)** — `story check-stale` compara el sha256 guardado con los archivos de aguas arriba actuales; si aguas arriba cambió, la historia queda en `E-STALE` y debe recompilarse. Impide la deriva silenciosa de diseño entre W2 y W5.

### 2.7 Gestor de plugs (`bathos-plug`)

Las capacidades de dominio son plugs opt-in bajo `modules/`, y **el core no sabe nada de los módulos** (invariante A9 — probada por el grafo de dependencias). Cada módulo se declara a sí mismo con `module.yaml`:

```yaml
module_id: ip                    # ip | research | game | security ...
name: IP Pack
wave: W4
trigger: "Lv>=3 OR domain=ip"    # condición de auto-trigger
enabled_default: false
provides:
  workflows: [patent-spec-draft]
  templates: [patent-spec]
outputs: ".agent-team/05-ip/"
evidence_trace: true
```

El DSL de triggers combina `Lv>=N`/`Lv>N`/`Lv<=N`/`Lv<N`/`Lv=N` (N=0–4) y `domain=X` con ` OR `; los tokens no interpretables se tratan conservadoramente como `false`. Los toggles (`plug enable`/`disable`) se persisten en `manifest.modules[]`. Un módulo inexistente produce `E-PLUG-NOTFOUND`. Incluidos por defecto: **ip-pack** (especificación de patente) · **research-pack** (Abstract/Introduction académicos).

### 2.8 Hooks de seguridad — donde la imposición se encuentra con Claude Code (`.claude/settings.json`)

Seis hooks deterministas y fail-safe se enlazan a eventos de Claude Code. Es el punto donde las garantías del motor cobran *efecto* en la sesión real:

| Hook | Evento | Función | Condición de bloqueo (exit 2) |
|------|--------|---------|-------------------------------|
| `careful-guard.sh` | PreToolUse(Bash) | Bloquear comandos destructivos | `rm -rf`, `DROP TABLE`, `git push --force`, `DELETE` sin WHERE, `TRUNCATE` |
| `freeze-guard.sh` | PreToolUse(Write/Edit) | Restringir ediciones a rutas propias | Edición fuera de `BATHOS_OWNED_PATHS` |
| `audit-log.sh` | PostToolUse | Append de cada uso de herramienta a la cadena de auditoría | (no bloqueante) |
| `artifact-verify.sh` | TaskCompleted / SubagentStop | Verificar completitud de artefactos · archivos de historia | Artefacto faltante en tareas QA/W3; archivo de historia incompleto al terminar #17 |
| `gate-enforce.sh` | TaskCompleted | **Bloquear entrada a W5 si el veredicto de W3 es FAIL** | Tarea de entrada a W5 + último veredicto Implementation = FAIL |
| `next-action.sh` | TeammateIdle | Guiar la siguiente acción | (no bloqueante) |

Flujo de `gate-enforce`: detectar la tarea de entrada a W5 → consultar el último veredicto Implementation con `bathos gate show` → `FAIL` ⇒ exit 2 (bloqueo); `PASS`/`CONCERNS` ⇒ exit 0 (permitir). Fail-safe si falta el binario o el gate (advertir y dejar pasar). El hook `artifact-verify` detecta el rol #17 (Matthew) mediante múltiples nombres de campo del payload (`.role // .agent_type // .subagent_type // .agentType` + fallback con grep), de modo que si el nombre del campo cambia en runtime, la verificación de archivos de historia no se omite en silencio.

> Nota operativa: en el bloque `hooks` de `settings.json`, **solo nombres de eventos de hook válidos** — una clave de comentario envía el arranque de los subagentes a una espera infinita.

### 2.9 Superficie CLI y convención de códigos de salida

Rara vez llamarás el binario a mano — los hooks y comandos lo hacen por ti — pero para cuando haga falta, la superficie CLI completa queda registrada aquí.

Opciones globales: `-s, --state-dir <PATH>` (por defecto `./_state`), `--modules-dir <PATH>` (por defecto `./modules`), `-h/--help`, `-V/--version`.
**Códigos de salida:** `0` éxito · `1` error · **`2` gate FAIL** (los hooks lo usan para bloquear).

| Comando | Subcomandos | Propósito |
|---------|-------------|-----------|
| `state` | `validate`, `show` | Validar/consultar el esquema de manifest.json |
| `route` | `decide`, `show` | Recomendar/confirmar el nivel Scale-Adaptive |
| `wave` | `init`, `activate`, `show` | Transiciones de 7 waves (concurrencia ≤ 3) |
| `gate` | `verdict`, `show` | Registrar/consultar veredictos de gate (FAIL → exit 2) |
| `story` | `compile`, `check-stale` | Completitud (D1) · trazabilidad (D2) · frescura (D3) |
| `plug` | `list`, `enable`, `disable` | Toggle de módulos plug |
| `audit` | `append`, `verify` | Append a la cadena de auditoría tamper-evident / **verificación** (`verify` → `E-AUDIT-TAMPER` si hay manipulación, exit 1) |
| `doctor` | — | Diagnóstico preflight de instalación/cableado (ver §2.12) |

### 2.10 Taxonomía de errores (E-codes)

El motor pone nombre a los modos de fallo para que hooks y humanos reaccionen de forma determinista: `E-LEVEL-DRIFT` (cambio de nivel a mitad de camino), `E-CONCURRENCY` (roles activos > 3), `E-CTX-LOSS` (archivo de historia incompleto), `E-STALE` (historia desactualizada respecto a aguas arriba), `E-STATE-CORRUPT` (violación del esquema del manifest), `E-AUDIT-TAMPER` (ruptura de la cadena de auditoría), `E-PLUG-NOTFOUND` (módulo inexistente).

### 2.11 Guardar/reanudar sesión

Un build real abarca varias sesiones de Claude Code, y los compañeros **no heredan** el historial de conversación del líder — por eso BATHOS hace el traspaso explícito y sin pérdidas con dos comandos de una sola palabra:

- **`/save`** — captura la sesión *entera* en un único snapshot autoritativo `_state/SESSION-SNAPSHOT.md` (+ copia fechada). Agrega automáticamente el estado del motor (`bathos state/wave/gate/route show`) · el estado git del código de producto · las decisiones confirmadas (incluidas las elecciones de User Sovereignty) · la wave en curso y los roles activos · el trabajo pendiente, y **el comando exacto a ejecutar a continuación**. Funciona sin argumentos (el `_state` del proyecto actual es el valor por defecto) y no repregunta.
- **`/resume`** — lee ese snapshot (contrastándolo con `manifest.json` · `wave-log.md`) y restaura *hasta dónde llegaste y qué sigue* (solo lectura). Los compañeros in-process no pueden revivirse, así que indica re-generarlos (respawn) con el comando `/waveN-…` correspondiente — sin pérdidas gracias a los artefactos en disco.

Ambos son **amigables con el lenguaje natural**: el líder interpreta expresiones como "guardar/checkpoint" como `/save` y "continuar/reanudar" como `/resume` (regla de `CLAUDE.md`). Los dos son alias simples BATHOS-native de los más largos `/context-save` · `/context-restore` de gstack, y comparten el mismo `_state` y la misma fuente única de verdad.

### 2.12 Diagnóstico preflight y verificación de integridad

Dos comandos convierten las advertencias que antes solo vivían en la documentación y la promesa de tamper-evidence en *verificaciones realmente ejecutables*:

- **`bathos audit verify`** — verifica la cadena de hashes de auditoría de principio a fin (`hash_prev[n] == hash_self[n-1]`, ancla genesis, `seq` monótono). Íntegra → exit 0; ruptura/manipulación → imprime `E-AUDIT-TAMPER` con el `seq` problemático y exit 1. Hace que "tamper-evident" sea *demostrable*, no una afirmación.
- **`bathos doctor`** — un preflight de instalación/cableado que revisa de una vez exactamente los puntos donde tropiezan los adoptantes: `BATHOS_BIN` configurado, presencia de `jq`, flag de Agent Teams, **claves de comentario en el bloque `hooks` de `settings.json`** (un solo `_note` envía el arranque de subagentes a una espera infinita — ahora se detecta de forma determinista), existencia + permisos de ejecución de los archivos de hooks, existencia de `assets/` · `modules/`, validez del esquema de `manifest.json`, integridad de la cadena de auditoría. Imprime una checklist ✓//✗ y sale con exit 1 si hay errores duros. Recomendado justo después de `install.sh`.

### 2.13 Memoria cross-project y handoff

Guardar/restaurar sesión se limita al *interior* de un proyecto. Pero el conocimiento que vale la pena conservar — decisiones de arquitectura, sistemas de design tokens, lecciones operativas ganadas a alto precio — debe cruzar la frontera *entre* proyectos. BATHOS lo acumula en un **registro global** `~/.bathos/registry/`:

- `INDEX.md` — índice de una línea por proyecto trabajado.
- `<slug>.md` — la **tarjeta de proyecto** que destila cada proyecto: dominio, framing de USP, decisiones de arquitectura clave/ADRs, highlights del sistema de diseño, patrones reutilizables, lecciones e incidentes, estado actual, y un puntero al `.agent-team/` de ese proyecto.

**Cómo se aplica.** `/project-handoff` destila el proyecto actual en una tarjeta, y `/save-session` realiza este upsert **automáticamente** — el registro crece con cada guardado sin esfuerzo extra. En *otro* proyecto, en *otra* sesión, `/recall` (y `/cold-start`, que consulta el registro junto a lo demás) trae las tarjetas anteriores relevantes.

**Ventaja.** Un proyecto totalmente nuevo arranca *warm*, no cold: reutiliza decisiones y patrones que ya funcionaron, y las lecciones ya aprendidas (p. ej. la lección operativa "compañero colgado = quota", la trampa de la clave de comentario en `settings.json`) llegan como advertencia previa — no hace falta redescubrir la misma trampa. El recall es una propuesta (User Sovereignty): presenta contexto reutilizable, pero la dirección de este proyecto la decide el usuario.

---

## 3. Flujo de ejecución end-to-end

Juntándolo todo, una ejecución completa se lee de arriba abajo así — cada flecha es un comando que tú ejecutas directamente en la sesión del líder:

```
/team-kickoff        → esqueleto de .agent-team/ + charter + inicialización del manifest (creación del SSOT)
/route <abs-path>    → stakes → recomendación Lv0–4 → confirmación del usuario → registro de current_level
/wave1-discovery     → John ∥ Caleb            → gate USP Readiness
/wave2-design        → Joshua → (James, Jonnathan) → gate Plan Readiness
/wave3-story-gate ★  → Matthew condensa los archivos de historia; revisión independiente de Thomas · Matthias
                       → gate Implementation Readiness (PASS/CONCERNS/FAIL)
                       → un FAIL bloquea físicamente W5 vía el hook gate-enforce
/wave5-implement     → Phillip, Andrew, Stephen (concurrencia ≤ 3, aislamiento por rutas propias)
/wave6-verify-report → (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin → gate Release Readiness
/team-confirm        → sign-off final + cleanup
```

Durante todo el proceso, los roles solo leen sus rutas de entrada y solo editan sus rutas propias, el traspaso ocurre únicamente por disco, el motor registra cada transición y veredicto, y la cadena de auditoría captura cada uso de herramienta.

---

## 4. Principios de diseño (ETHOS)

BATHOS adopta y refuerza el ETHOS del **gstack** de Garry Tan. Tres principios gobiernan todos los roles:

1. **User Sovereignty (supremo)** — la IA propone, *el usuario* decide. Una recomendación que cambiaría la dirección declarada del usuario se presenta como "recomendación + fundamento + contexto omitido" y se *pregunta*; nunca se ejecuta primero.
2. **Boil the Ocean** — si la implementación completa solo cuesta unos minutos más, elige la completa; no aplaces tests ni casos límite.
3. **Search Before Building** — en terreno desconocido, busca primero para mapear el paisaje y luego desafía la sabiduría convencional desde primeros principios.

No son decoración: la regla de gate "facilitator, no generator" y la separación de verificadores independientes son User Sovereignty y "generación ≠ verificación" expresados como mecanismos impuestos.

---

## 5. Estado del proyecto y límites honestos (v0.4.0)

**Early but functional — hoy compila y funciona end-to-end.**

- BATHOS es un **paquete de método que corre sobre Claude Code v2.1.32+**, no una aplicación independiente, y depende de la **funcionalidad experimental Agent Teams**.
- **El motor está verificado:** **628 tests de Rust + 86 de determinismo de hooks, todos en verde**; `cargo clippy -D warnings` limpio; build de release reproducible.
- **Certificación totalmente independiente (dogfooding):** BATHOS aplicó Wave 6 a sí mismo. **ThomasCert (revisión de código independiente, PASS) + MatthiasCert (QA/E2E independiente, PASS)** ⇒ **Release Readiness = PASS**. Defectos Blocking/High/Medium conocidos: **0 abiertos**. Trail de verificación: `.agent-team/` (`10-review/` · `11-qa/` · `12-report/w6-final-certification.html` · `_state/signoff.md`).
- Algunos comandos de wave son **prompts de orquestación** que el líder ejecuta en Claude Code (spawn/inspección de compañeros), no flujos de motor totalmente automáticos.
- **Todavía no está production-hardened** — APIs, esquemas y nombres de comandos pueden cambiar antes de 1.0.

---

## 6. Licencia y aviso

Se distribuye bajo **MIT License**. BATHOS es una obra implementada de forma independiente, reconstruida desde primeros principios tras un análisis inverso cuidadoso de [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) (MIT © 2025 BMad Code, LLC) — con sincero respeto por el trabajo previo que dibujó antes el terreno que BATHOS quiso excavar más hondo. Las marcas "BMAD", "BMad Method", etc. **no se usan** en el nombre del producto ni en marketing. Texto completo: [`../README.md`](../README.md).

---

<div align="center">

**BATHOS** · βάθος — profundidad, no superficie
[`FEATURES-kr.md`](FEATURES-kr.md) · [`FEATURES-en.md`](FEATURES-en.md)

</div>
