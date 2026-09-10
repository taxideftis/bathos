# BATHOS — Preguntas frecuentes (FAQ)

> Respuestas rápidas a las preguntas que surgen primero — qué es BATHOS, qué hace falta para ejecutarlo, cuánto cuesta y dónde profundizar. Cada respuesta apunta al documento completo cuando se necesita más detalle.
>
> **Ver también:** [Uso (USAGE-es)](USAGE-es.md) · [Características (FEATURES-es)](FEATURES-es.md) · [Costo y cuota (QUOTA-es)](QUOTA-es.md) · 한국어: [`FAQ-kr.md`](FAQ-kr.md) · English: [`FAQ-en.md`](FAQ-en.md)

### ¿Qué es exactamente BATHOS?
Un **paquete de método que corre sobre Claude Code** — un pipeline de 17 roles especializados × 7 waves + enrutamiento Scale-Adaptive + gates de calidad duros, más un pequeño motor en Rust. **No es una aplicación independiente**; orquesta una única sesión de Claude Code como un equipo de producto disciplinado.

### ¿Qué necesito para ejecutarlo?
Claude Code **v2.1.32+** + la funcionalidad experimental **Agent Teams** (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), un **toolchain de Rust** (compilación única del motor) y **`jq`** (hooks de seguridad). macOS/Linux.

### ¿Cómo lo añado a mi proyecto?
`./install.sh --into /abs/path/to/your-project` copia `.claude/` · `assets/` · `modules/`; después apunta `BATHOS_BIN` al motor compilado. Recorrido completo: [`USECASE-es.md`](USECASE-es.md). Luego verifica el cableado con **`bathos doctor`**.

### Un compañero se detuvo sin producir salida — ¿está roto?
Casi con seguridad **no** — la causa más común es el **límite de uso de la cuenta (session)**, no un bug del código. Re-genera (respawn) tras el reinicio del límite y se reanuda sin pérdidas gracias a los artefactos en disco de `.agent-team/`. Ver [`QUOTA-es.md`](QUOTA-es.md).

### Un subagente se cuelga al arrancar.
Revisa `.claude/settings.json` — una **clave de comentario** (p. ej. `_note`) dentro del bloque `hooks` envía el arranque del subagente a una espera infinita. Deja solo nombres de eventos válidos. **`bathos doctor`** lo detecta de forma determinista.

### ¿Cuánto cuesta ejecutarlo? ¿Cómo ahorro?
El costo en tokens escala con el número de compañeros activos y con el nivel. Elige el nivel más bajo que encaje, mantén los compañeros concurrentes ≤ 3, genera solo los roles necesarios y aplaza W4. Detalles: [`QUOTA-es.md`](QUOTA-es.md).

### ¿La "cadena de auditoría tamper-evident" es real o una afirmación?
Real y verificable: `bathos audit verify` valida la cadena sha256 de extremo a extremo (`hash_prev[n] == hash_self[n-1]`, ancla genesis, `seq` monótono). Una ruptura produce `E-AUDIT-TAMPER` + exit 1.

### ¿Puedo guardar el trabajo y continuar en una sesión nueva?
Sí. `/save-session` toma un snapshot de todo (SSOT de máquina + narrativa) en `_state/`, y `/cold-start` restaura por completo en una sesión nueva. Alias cortos: `/save` · `/resume`. [`USAGE-es.md`](USAGE-es.md) §12.1.

### ¿Por qué la revisión independiente encontró un bug que los tests no vieron?
Ese es el punto — **generación ≠ verificación**. Los tests solo prueban lo que comprueban; un revisor independiente (Thomas) ataca invariantes y puntos de integración que el autor no vio. BATHOS separa autor y verificador por diseño.

### ¿Cómo añado una capacidad nueva (p. ej. auditoría de seguridad)?
Para un **paquete de dominio**, usa un plug — [`MODULE-GUIDE-es.md`](MODULE-GUIDE-es.md). Para cambiar *cómo se comportan los roles en tu proyecto*, usa overrides de team/user — [`ROLE-GUIDE-es.md`](ROLE-GUIDE-es.md). Mantén el core esbelto (invariante A9).

### ¿Está listo para producción?
**Todavía no.** v0.4.0 es temprano pero funcional y validado por dogfooding (628 tests + 86 tests de hooks en verde, certificación totalmente independiente). APIs, esquemas y nombres de comandos pueden cambiar antes de 1.0. Hasta ahora solo se ha validado contra sí mismo — los pilotos externos reales son el siguiente hito.

### ¿Licencia? ¿Esto es BMAD?
MIT. BATHOS fue implementado de forma independiente desde primeros principios tras un análisis inverso cuidadoso de [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) (MIT © 2025 BMad Code, LLC), con sincero respeto por el trabajo previo en el que se apoya. No se usan las marcas de BMAD.

---

<div align="center">한국어: <a href="FAQ-kr.md">FAQ-kr</a> · English: <a href="FAQ-en.md">FAQ-en</a></div>
