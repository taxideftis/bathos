# Disciplina de Implementación W5 — La Escalera (Ladder)

> **Se inyecta en:** los roles implementadores de W5 — Phillip(#8) · Andrew(#9) · Stephen(#10).
> El líder (Paul) indica la ruta de este archivo y el valor actual de intensity en el prompt de spawn de W5.
> **Canónico = la edición en coreano** (`ponytail-inject-kr.md`). Este archivo `-es` es una
> traducción secundaria y se le permite quedar desactualizado en silencio (política de
> `scripts/drift-exclusions.json`, `docs/agent-portability-kr.md` §4).
>
> **Origen y licencia:** los principios están adaptados de ponytail (DietrichGebert/ponytail, MIT)
> y reescritos para el contexto W5 de BATHOS. Según la decisión vigente en
> `_recon/ponytail-analysis.md` §6, **no se adopta la persona, el tono ni el branding** (el
> personaje del "desarrollador senior perezoso", la mascota, los chistes) — **solo se absorben
> los principios de ingeniería**. BATHOS es un producto de orquestación, no un producto de
> persona única.

---

## 0. Precedencia — relación con ETHOS (leer primero)

Esta disciplina y el Principio 1 de ETHOS (Boil the Ocean) gobiernan **ejes distintos**. No entran en conflicto.

| Eje | Principio rector | Qué decide |
|-----|-------------------|------------|
| **Qué construir** | **La Escalera (este documento)** | alcance · abstracción · número de archivos · dependencias · parámetros de configuración |
| **Con qué grado de completitud construir el alcance ya fijado** | **ETHOS Boil the Ocean** | rutas de error · casos límite · pruebas · verificación · observabilidad |

- **Nunca uses la Escalera para recortar una ruta de error, una prueba o una validación de entrada.** Es un eje distinto.
- **Nunca uses Boil the Ocean para justificar una abstracción que nadie pidió.** También es un eje distinto.
- El punto donde ambos principios se solapan ya está escrito en §4 ("Cuándo NO ser perezoso") — ahí dicen lo mismo.
- El Principio 3 de ETHOS (User Sovereignty) **sigue estando por encima de todo**, incluida esta disciplina.

---

## 1. Antes de la escalera — entiende primero el problema

La escalera se aplica *después* de entender el problema, nunca *en lugar de* entenderlo.

- Lee la tarea y el código que toca, traza el flujo real de punta a punta y solo entonces sube la escalera.
- **Sé perezoso con la solución. Nunca perezoso con la lectura.** Un diff pequeño que no entiendes
  es una corrección confiada pero equivocada disfrazada de eficiencia.

### La corrección de un bug = causa raíz, no síntoma

Un reporte nombra un **síntoma**.

- **Haz grep de cada llamador** de la función que vas a tocar, antes de editarla.
- La corrección perezosa ES la corrección de causa raíz — un guard en la función compartida es un
  diff más pequeño que un guard en cada llamador.
- Parchear solo la ruta que nombra el ticket deja a todos los llamadores hermanos rotos. Corrígelo
  **una vez**, en el punto por donde pasan todos los llamadores.

---

## 2. La Escalera — antes de escribir código, detente en el primer peldaño que aguante

1. **¿Esto necesita existir siquiera?** Necesidad especulativa = sáltalo, dilo en una línea. (YAGNI)
2. **¿Ya existe en este código base?** Un helper, util, tipo o patrón que ya vive aquí → **reúsalo.**
   Busca antes de escribir — reimplementar lo que está a unos archivos de distancia es el descuido más común.
3. **¿Lo hace la biblioteca estándar?** Úsala.
4. **¿Lo cubre una función nativa de la plataforma?** `<input type="date">` antes que una librería
   de selector, CSS antes que JS, una restricción de la BD antes que código de aplicación.
5. **¿Lo resuelve una dependencia ya instalada?** Úsala. **Nunca agregues una dependencia nueva**
   para lo que resuelven unas pocas líneas.
6. **¿Se puede hacer en una línea?** Una línea.
7. **Solo entonces:** el mínimo código que funcione.

Si dos peldaños funcionan → toma el **más alto** y sigue adelante. La escalera es un reflejo, no un
proyecto de investigación. La primera solución perezosa que funcione es la correcta —
**una vez que realmente sabes qué debe tocar el cambio.**

---

## 3. Reglas

- **Sin abstracciones no solicitadas.** Ninguna interfaz con una sola implementación, ninguna
  fábrica para un solo producto, ninguna configuración para un valor que nunca cambia.
- **Sin boilerplate ni andamiaje "para después".** El después se hace su propio andamiaje.
- **Eliminar antes que añadir. Aburrido antes que ingenioso.** Lo ingenioso es lo que alguien
  tiene que descifrar a las 3 de la madrugada.
- **El menor número de archivos posible. Gana el diff funcional más corto** — pero solo una vez
  entendido el problema. El cambio más pequeño en el lugar equivocado no es pereza, es un segundo bug.
- **¿Solicitud compleja?** Entrega la versión perezosa y cuestiónala en la misma respuesta:
  "Hice X; Y lo cubre. ¿Necesitas la X completa? Dilo." Nunca te detengas ante una respuesta que
  puedes dar por defecto.
- **¿Dos opciones de biblioteca estándar del mismo tamaño?** Toma la que sea **correcta en los
  casos límite**. Ser perezoso significa escribir menos código, no elegir el algoritmo más frágil.
- **Marca las simplificaciones deliberadas.** → §5

---

## 4. Cuándo NO ser perezoso (donde esto se encuentra con Boil the Ocean)

**Nunca** simplifiques quitando:

- **La validación de entrada en los límites de confianza**
- **El manejo de errores que evita la pérdida de datos**
- **Las medidas de seguridad**
- **Lo básico de accesibilidad**
- **Cualquier cosa solicitada explícitamente** — si el usuario insiste en la versión completa,
  constrúyela, sin volver a discutirlo.
- **La comprensión del problema** — la escalera acorta la solución, nunca la lectura.
- **La calibración que exige el hardware real** — un reloj real se desvía, un sensor real lee de
  forma imprecisa. Deja el **parámetro de calibración**, no solo menos código. El mundo físico
  exige ajustes que un modelo mínimo no puede prever.

**El código perezoso sin su verificación está incompleto.**
La lógica no trivial (una rama, un bucle, un parser, una ruta de dinero/seguridad) deja
**UNA verificación ejecutable** — lo más pequeño que falle si esa lógica se rompe. Basta con una
autoverificación basada en `assert` o una prueba pequeña. Nada de frameworks, fixtures ni suites
por función salvo que se soliciten.
Las líneas triviales de una sola instrucción no necesitan prueba. **YAGNI también aplica a las pruebas.**

---

## 5. El marcador `ponytail:` — cómo aplicarlo

Cuando una simplificación deliberada **recorta una esquina real y tiene un límite conocido**, deja
ese límite y su ruta de actualización en un comentario del código fuente. Es lo único que impide
que "después" se convierta silenciosamente en "nunca".

### Formato

```
ponytail: <ceiling>, <upgrade path>
```

- **ceiling (techo)** — el punto en el que esta simplificación deja de funcionar. Sé específico
  sobre *cuál* es el límite.
- **upgrade path (ruta de actualización)** — con qué reemplazarlo cuando eso ocurra. **Incluye el
  disparador para revisitarlo.**
- Un marcador que no nombra ninguna ruta de actualización ni disparador es etiquetado como
  **`no-trigger`** por `/bathos-debt`.
  **Esos son justamente los que se pudren en silencio.**

### Idioma — se escribe en inglés

Según la regla vigente de W5 (el "estándar de anotación de código" en cada base de rol), **todos
los comentarios de código se escriben en inglés.** Incluso cuando los documentos y entregables
están en coreano, el cuerpo de un marcador `ponytail:` es en inglés. Aquí no hay excepción.

### Cuándo añadirlo / cuándo no

| Añádelo | No lo añadas |
|---------|---------------|
| Un único candado global (necesita dividirse bajo contención) | Algo que subiste por la escalera y **no construiste** — el código que no existe no tiene comentario |
| Escaneo O(n²) (aceptable mientras n sea pequeño) | Una línea trivial, una elección estándar sin controversia |
| Heurística ingenua, backoff fijo | Código de depuración temporal (elimínalo en su lugar) |
| Constante embebida (configuración postergada) | Un riesgo de gate ya registrado como `CONCERNS:` en un documento (sin duplicar) |
| Un solo reintento, contrato parcialmente implementado | |

### Ejemplos

```rust
// ponytail: single global lock, split into per-wave locks if profiling shows contention
```
```typescript
// ponytail: linear scan over waves (n <= 7), swap to a Map if the wave set ever grows
```
```python
# ponytail: fixed backoff, switch to exponential once the API starts rate-limiting
```
```bash
# ponytail: assumes jq is present, add a grep fallback if a jq-less host appears
```

### Recolección

- **Canónico:** `/bathos-debt` — recopila los `CONCERNS:` de los entregables en markdown y los
  `ponytail:` del código fuente en un único ledger.
- Manual:
  ```bash
  grep -rnE '(#|//|--) ?ponytail:' . \
    --include='*.rs' --include='*.ts' --include='*.tsx' --include='*.py' --include='*.sh' \
    --exclude-dir=target --exclude-dir=node_modules --exclude-dir=.git
  ```

### Principio de separación de anclas

- **Código fuente** = `ponytail:` (este documento)
- **Entregables en markdown y riesgos de gate** = `CONCERNS:` (`CLAUDE.md` §2.1, la convención
  existente de `/bathos-debt`)

Son medios distintos, así que nunca se solapan. Nunca registres el mismo elemento bajo ambas anclas.

---

## 6. Disciplina de salida

**El código primero.** Luego, como máximo tres líneas cortas: qué se omitió, cuándo agregarlo.

Nada de ensayos, recorridos de funcionalidades ni notas de diseño.
**Si la explicación es más larga que el código, elimina la explicación.** Cada párrafo que defiende
una simplificación es complejidad contrabandeada de vuelta como prosa.

```
[código] → omitido: [X], agregar cuando: [Y].
```

**Excepción:** la explicación que el usuario **pidió explícitamente** (un reporte, un recorrido
paso a paso, notas por fase) no es deuda — entrégala completa. Esta regla se dirige únicamente a
la **prosa no solicitada**.
`08-impl-notes/*.md` es un entregable requerido por el DoD de W5 y por tanto queda fuera del
alcance de esta regla.

---

## 7. Intensity — vinculado al interruptor existente

La fuerza de esta disciplina reutiliza **el interruptor de intensity que BATHOS ya tiene.** No se
construye uno nuevo.

- **Lectura:** `.intensity` en `_state/session-flags.json` (valor por defecto `full`)
- **Cambio:** `/bathos intensity <lite|full|ultra|off>` (el hook intensity-tracker)
- **Invariante (LD-4):** intensity ≠ Lv0–Lv4. **Lv** = escala del proyecto/tarea (router,
  `manifest.current_level`); **intensity** = agresividad de la sesión (alternable al instante). Son
  independientes entre sí.
- El líder (Paul) indica el valor actual de intensity en el prompt de spawn de W5.

| Nivel | Comportamiento del implementador de W5 |
|-------|------------------------------------------|
| **lite** | Construye lo que se pidió, pero nombra la alternativa más perezosa en una línea en `08-impl-notes/`. Decide el usuario. |
| **full** | Escalera forzada. Prioridad a stdlib y a lo nativo. Diff más corto, explicación más corta. **(por defecto)** |
| **ultra** | Extremismo YAGNI. Eliminar antes que añadir. Entrega la línea única y cuestiona el requisito en el mismo aliento. |
| **off** | Disciplina inactiva — solo aplica ETHOS. |

Ejemplo — "Agrega una caché para estas respuestas de API."

- **lite:** "Listo, caché agregada. Para tu información: `lru_cache` cubre esto en una línea si
  prefieres no mantener una clase de caché propia."
- **full:** "`@lru_cache(maxsize=1000)` en la función de fetch. Se omitió la clase de caché
  personalizada, agrégala cuando `lru_cache` se quede corta de forma medible."
- **ultra:** "Sin caché hasta que un profiler lo indique. Cuando lo indique: `@lru_cache`."

---

## 8. Límites (fuera de alcance)

- Esta disciplina gobierna **qué construyes**, no **cómo lo comunicas**. El formato de los
  reportes y el tono siguen ETHOS y las reglas de conducta compartidas del equipo.
- **Aplica solo a W5.** W2 (diseño) y W6 (verificación) siguen sus propias disciplinas.
  La revisión de sobre-ingeniería en W6 es responsabilidad ya existente de Thomas(#12) y Hananiah(#14).
- **Los bugs de corrección, las brechas de seguridad y las regresiones de rendimiento quedan fuera
  del alcance aquí** — se enrutan a W6 (Thomas #12, Michael #13).
- **Nunca toques nada fuera de tus rutas de propiedad** — los límites de propiedad ya existentes
  de W5 siguen prevaleciendo.
- Desactivación: cuando el usuario ejecuta `/bathos intensity off` o indica explícitamente detenerse.
