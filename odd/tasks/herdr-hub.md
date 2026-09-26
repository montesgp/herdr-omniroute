# Feature: herdr-hub — hub multi-widget anclado a la derecha (evolución del plugin)

Status: **implementado, pendiente E2E del orquestador** — H2/H3/H5 hechos y verificados en estático (2026-09-25); H4 es un stub honesto a la espera de la decisión de fuente de datos. Lo único que falta es la prueba en vivo del dock (`herdr plugin action invoke herdr.omniroute.hub`), que la hace el orquestador.

## Objective
Evolucionar el plugin `herdr-omniroute` a un **hub general de Herdr**: un dock delgado anclado a la derecha del workspace (estilo gaming / rueda de poderes tipo MU Online), colapsado a una franja de iconos, que al seleccionar un widget se expande y muestra su info. Extensible por registro de widgets (cada widget = módulo PS1). Primeros widgets: **OmniRoute** (estado, logo, combo activo ●) y **Tokens** (output total de todos los proyectos). Futuro: Config.

## Problem
- El plugin actual solo muestra un popup de estado de OmniRoute puntual; el usuario quiere algo persistente, compacto y extensible, "más que omniroute".
- La UI de Herdr es texto/ConPTY: no hay imágenes ni dock nativo; hay que emular el look gaming con símbolos Unicode + colores ANSI y anclar con `pane split`.

## Why (decisiones confirmadas)
- Forma elegida por el usuario (2026-09-25): **A: dock derecho split** (no popup).
- Probe de anclaje (2026-09-25): `pane split --direction right --ratio 0.2` crea split en el mismo tab, geometría consultable vía `pane edges`, `pane run`/`pane read` alojan y leen un comando persistente en el dock, `pane close` restaura. El `--ratio` se aplica al pane ORIGINAL (0.2 → original 37px, nuevo 80%) → para hub delgado a la derecha usar **ratio 0.8** (original conserva 80%, hub 20%) y/o `pane resize`.
- Extensión pi: **aparacada** (el usuario no la relaciona con el plugin de Herdr; foco en Herdr).
- Alcance del dock por defecto: workspace actual (no tocar otras sesiones); posible switch futuro `-AllWorkspaces`.

## Scope
- Manifest: nueva acción `hub` (o reemplazo de `status`) que crea el dock idempotente en el workspace actual y lo cierra/limpia.
- `scripts/hub/index.ps1`: menú del hub — franja colapsada (iconos por widget), selección por tecla (1-9 / letras), expande el widget elegido, colapsa y sale (q/Esc → cierra el dock auto-limpio).
- `scripts/hub/widgets/*.ps1`: módulos de widget con contrato común (función que devuelve líneas a renderizar). Registro en `scripts/hub/widgets.ps1`.
- Widget `omniroute`: estado UP/DOWN (:20128), combo activo ● vía `/api/settings` con token de máquina (derivación documentada: HMAC-SHA256 key=MachineGuid msg="omniroute-cli-auth-v1"), lista de combos desde `storage.sqlite` (lectura SQLite directa — ya resuelta en T2.4/T4b-key).
- Widget `tokens`: output total en tokens de todos los proyectos. **Fuente de datos PENDIENTE de definir** — candidata: `usage logs` del gateway (pero clientes aún no enrutados → 0 real); alternativas: session-snapshots de Herdr, logs de pi. Hasta decidir: honesto "sin datos" + nota. STUB inicial.
- Widget `config` (futuro): entrada deshabilitada/stub.
- Docs: README, docs/architecture.md, docs/status-panes.md (o nuevo docs/hub.md).

## Fuera de scope (por decisión)
- Imágenes reales en la UI (no soportadas; emulación simbólica).
- Extensión pi (aparcada; puede retomarse aparte).
- Cambios en Herdr mismo.

## Constraintes
- Windows 11, PowerShell 5.1; herdr CLI: `C:\Users\patri\.herdr\packages\standalone\releases\0.9.1-preview.2026-09-21-0ff0f27e2226-x86_64-pc-windows-msvc\herdr.exe`.
- Panel hub: render in-place (`Home` + `ESC[K` por línea + `ESC[J`), sin ventanas (Invoke-Native), topes acotados, contrato de teclas propio del hub (no "cualquier tecla").
- Hot path: evitar Test-Path/Join-Path/Get-Command; token de máquina derivado en PS 5.1 (verificado) para /api/settings.
- No exponer credenciales; no repetir la key del gateway en texto.

## Checklist (IDs estables)

### H1 — Spike de input del dock — DONE ✅ (2026-09-25)
- [x] Dock stub creado (`pane split w1G:p1 --direction right --ratio 0.8` → dock `w1G:p5` de 37px a la derecha; ratio se aplica al ORIGINAL, así que 0.8 deja el hub delgado).
- [x] Tecla enviada vía `pane send-keys <id> <key>` (posicional, no `--pane`) → el stub recibió `KEY: 97` ('a'); `send-keys ... esc` → `KEY: 27` → EXIT/DONE.
- [x] `pane close` restaura el layout (pane list = originales).
- Conclusión: el ConPTY de input del split funciona con `[Console]::KeyAvailable`/`ReadKey` igual que el popup; el foco del usuario por UI usa el mismo stream. Canal de control del dock: `pane run`/`pane read`/`send-keys`.

### H2 — Widget registry + hub index — DONE ✅ (2026-09-25)
- [x] `widgets.ps1`: registro ordenado (id, key, icono, título, módulo): OmniRoute/1/`◉`, Tokens/2/`Σ`, Config/3/`⚙`; franja y hint derivados del registro.
- [x] `index.ps1`: franja colapsada `[HUB] 1 ◉  2 Σ  3 ⚙`; readkey loop con `KeyAvailable`+`ReadKey` (degrada a $null si el host no reporta teclas); expandir/colapsar con la misma tecla; q/Q/Esc → `pane close <PaneId>` (auto-close; sin pane id no cierra nada); tope duro de 1800 s en todos los caminos; pinto in-place (Home + `ESC[K` por línea + `ESC[J`).
- [x] Contrato de widget: `Get-Widget<Id> -Width` → `[string[]]`; tope de 14 líneas; clipping a `Width-1` (evita el auto-wrap que hacía parpadear el popup); error por widget aislado (`falta el modulo` / `el modulo no define …` / `error del widget: …`) sin tumbar el dock.
- [x] `-Once` / `-NoKeyWatch` / `-Widget <key>` como ganchos de prueba estática.
- [x] ASCII puro en los `.ps1` (0 bytes no-ASCII): los glyphs van como `[char]0x…` porque PS 5.1 lee un `.ps1` sin BOM como ANSI.

### H3 — Widget OmniRoute — DONE ✅ (2026-09-25)
- [x] Estado UP/DOWN (netstat :20128, mismo criterio que el popup: `LISTENING`), en paralelo con la lectura de la BD.
- [x] Combo activo vía `/api/settings` con el token de máquina (HMAC-SHA256 sobre el MachineGuid, nunca la key). **Medido en esta instalación**: la llamada responde `200` con el token, pero la build no expone ningún campo de combo activo (`/api/settings` solo trae `comboStrategy`, `comboConfigMode`, `comboAutoPromoteEnabled`, `hideAutoCombos`; `/api/combos` tampoco) → el widget cae a lo que SQLite sí puede probar (`key_value.settings.activeCombo`, ausente) y responde honesto `Activo: sin datos`, sin inventar `●`/`○`.
- [x] Lista de combos desde SQLite reusando `scripts/lib/Get-OmniRouteCombos.ps1` (misma lectura read-only del popup, no una segunda implementación).

### H4 — Widget Tokens — STUB HONESTO, decisión pendiente
- [x] Stub que no inventa cifras: `En construccion` + por qué falta la fuente.
- [ ] Decisión de fuente de datos con el usuario (OmniRoute usage logs vs session-snapshots vs pi) — UNO pregunta.
- [ ] Render de total + por proyecto con la fuente elegida.

### H5 — Manifest + action + limpieza — DONE ✅ (2026-09-25)
- [x] Acción `hub` en `herdr-plugin.toml` (versión 0.3.0 → 0.4.0, descripción con multi-widget).
- [x] Idempotencia por estado observable, sin archivos de estado: el hub titula su propio pane `hub: herdr-omniroute` y el opener busca ese prefijo en `pane list` **del workspace actual** (resuelto con `pane current`) antes de partir nada.
- [x] Split sobre el pane de mayor área (empate → pane enfocado) con `--direction right --ratio 0.8 --cwd <repo> --no-focus`; el `--ratio` es del pane ORIGINAL, así que 0.8 deja el dock en el ~20% derecho (~37 columnas aquí).
- [x] `pane run` + espera ~1.5 s + un reintento; si falla, cierra el pane creado (nada de docks a medias). Resolve el id del dock por la respuesta del split y, si no, por diff de `pane list`.
- [x] Auto-close al salir (q/Esc) vía `pane close`, que es lo que restaura el layout.
- [x] Docs: `docs/hub.md` nuevo (contrato de widgets, mecánica del dock, fuentes de datos, troubleshooting), README, `docs/architecture.md` y puntero en `docs/status-panes.md`.

## Authorized scope (confirmado)
- Repo herdr-omniroute (manifest, scripts/, docs).
- NO tocar: configs de clientes (claude/codex/opencode), ~/.omniroute/.env, node_modules, gentle-pi.

## Acceptance criteria
1. `herdr plugin action invoke herdr.omniroute.hub` → dock delgado a la derecha del workspace con franja de iconos; sin duplicado si ya está abierto. — lógica verificada en estático; E2E pendiente del orquestador.
2. Seleccionar el widget OmniRoute expande: estado, combo activo ●, combos. — render verificado; el combo activo sale `sin datos` en esta instalación (ver H3), que es el resultado honesto esperado.
3. q/Esc cierra el dock y el layout vuelve al estado previo. — auto-close implementado; E2E pendiente del orquestador.
4. Registro de widgets: agregar un widget nuevo = añadir un módulo + una línea de registro (demostrable con el stub Tokens). — cumplido, el stub Tokens es exactamente esa prueba.
5. Sin ventanas nuevas, sin procesos huérfanos (Invoke-Native), topes acotados. — cumplido por construcción (todas las llamadas externas vía `Invoke-Native`, todos los topes acotados).

## Verification commands
- `herdr plugin action invoke herdr.omniroute.hub` (en sesión Herdr) — **pendiente: lo hace el orquestador**, sin panes tocados por el agente.
- `herdr pane edges --pane <dock-id>` → layout con split right y rect delgado.
- `herdr pane read <dock-id>` → franja de iconos + expansión.
- `herdr pane list` antes/después de q/Esc → sin dock residual.
- Envato adicional del orquestador, con `pane list` invariable (2 panes antes y después):
  - Parse `[System.Management.Automation.Language.Parser]` sobre los 6 `.ps1` nuevos → 0 errores.
  - `hub-widget-check.ps1` → `Get-Command Get-WidgetOmniRoute/Tokens/Config` = 3 OK.
  - `hub-render-check.ps1` → franja, 3 widgets, clave desconocida, ancho estrecho; todos exit 0.
  - `open-hub-logic-check.ps1` → 7 funciones de `open-hub.ps1` aisladas del cuerpo (dot-source del AST) y probadas con datos sintéticos + lecturas reales: `pane current` (w1H:p1), `pane list` de 2 workspaces, dock inexistente → null, dock sintético → acierto, `layout` real (183x50, panes en `result.edges.layout.panes[]`), área > foco, foco desempata, sin layout → fallback, 3 formas de id del split, fallo de comando y salida no-JSON → null.
  - Idempotencia del título (9 casos): `hub: …` acierto, prefijo exacto, `prefix hub: herdr` no acierto, workspace ajeno, lista vacía/null, pane sin título.
  - `hub-loop-check.ps1` → `-NoKeyWatch -MaxSeconds 1` = 1 s exit 0; stdin redirigido (host sin teclas) degrada y sale en 1 s en vez de esperar 1800 s.
  - Rutas de error de widget: módulo inexistente, módulo sin la función, función que lanza excepción, tope de 14 líneas, widget sin parámetro `-Width`.
  - `Format-HubLine`/`Get-HubKeyRange`: 36 y 99 caracteres, tab, null, `-Width 12`; rangos `1-3`, `1-2`, hueco `1 4`, letras, registro vacío.

## Progress notes
- 2026-09-25: decisión A (dock derecho split) con datos del probe de anclaje; objetivo del hub definido; pendiente spike de input (H1) y luego implementación vía writer delegado.
- 2026-09-25: H1 cerrado (el ConPTY del split entrega teclas a `[Console]::KeyAvailable`/`ReadKey` igual que el popup, y `pane close` restaura). H2/H3/H5 implementados y verificados en estático, sin mutar panes reales. H4 queda como stub honesto.
- 2026-09-25: descubrimientos que cambiaron la implementación — (a) el layout real vive en `result.edges.layout.panes[]`, no en `result.layout` (el parser acepta ambos); (b) en esta instalación no hay campo de combo activo en la API, así que `sin datos` es la respuesta correcta, no un fallo del widget; (c) el docking se hace por título (`terminal_title_stripped` con prefijo `hub: `) porque no hay marker process ni archivo de estado que mantener.
- Pendiente para cerrar la feature: E2E del dock con el orquestador y la respuesta de H4 (fuente de datos de tokens).