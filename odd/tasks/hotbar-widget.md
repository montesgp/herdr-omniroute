# Feature: hotbar-widget — barra flotante de Windows siempre-encima (giro completo, 2026-09-26)

Status: **en implementación** — decisiones de producto cerradas; pendiente build del widget WPF.

> Este es el NUEVO rumbo del proyecto. El diseño previo (menú popup de Herdr, `herdr-hub.md`)
> queda **descartado por decisión del usuario** (2026-09-26): "no es para nada lo que esperaba".
> El repo se rebautizó en GitHub a `montesgp/hotbar`. Este documento es la fuente de verdad; el
> viejo queda como historia.

## Objective
Construir un **widget de escritorio para Windows** (PowerShell + WPF, sin dependencias) que flote
fijado por encima de toda ventana, anclado a la derecha de un monitor, centrado verticalmente,
con estética tipo dock de macOS: barra vertical, forma de **media luna / semicírculo alargado**,
tema oscuro moderno, **4-5 opciones visibles fijas** (claude, codex, opencode, omniroute, ajustes)
con posibilidad futura de submenús. Colapsable a una **flecha dentro de un semicírculo** que
permite descolapsar. Reutilizable: las opciones y acciones se configuran en `hotbar/config.json`.

## Problem
- Los panes/popups de Herdr no dan la experiencia pedida: o reservan layout o son modales del
  terminal. El usuario quiere una barra que **viva encima de todo** (incluso sobre Herdr), como
  la barra de Windows con espacio reservado, en cualquier monitor, a la derecha y centrada.
- La UI de Herdr es texto/ConPTY: imposible lograr el estilo visual moderno que se busca.

## Why (decisiones confirmadas 2026-09-26)
- **Enfoque**: eliminar todo lo que sea "herdr pane / herdr hub / herdr menu". El widget es un
  componente de Windows independiente, reutilizable, no un plugin de Herdr.
- **Plugin de Herdr**: se CONSERVA solo start/status/dashboard/open-status-pane (el usuario usa
  `prefix+b+o` a diario). Se borran hub/menu/open-menu del manifest y scripts.
- **Tecnología**: PowerShell 5.1 + WPF (opción elegida). Nota honesta: WPF es Windows-only; la
  lógica de datos se mantiene desacoplada (funciones puras) para facilitar un futuro port a
  Linux. No se re-abre la decisión de stack.
- **Nombre**: repo `hotbar` (GitHub ya renombrado a `montesgp/hotbar`; remote local actualizado).
  El nombre NO se limita a OmniRoute: OmniRoute es solo una de las opciones.
- **Forma/UX**: media luna (semicírculo alargado) vertical a la derecha, centrada en el monitor,
  siempre encima (Topmost), sin barra de tareas para la ventana. Colapso total → flecha en
  semicírculo; clic descolapsa.
- **Opciones**: 4-5 principales fijas visibles (claude ✳, codex ◎, opencode ◈, omniroute ▣,
  ajustes ⚙). A futuro: submenús por ítem.

## Scope (v1)
- `hotbar/` — app WPF autocontenida:
  - `hotbar/hotbar.ps1` — ventana WPF (XAML embebida), siempre-encima, transparente, sin marcos.
  - `hotbar/launch-hotbar.ps1` — lanzador sin ventana de consola (`-WindowStyle Hidden`).
  - `hotbar/config.json` — ítems, monitor, alineación, margen, colapsado. Schema con `action`:
    `none` | `omniroute-status` | `run:<comando>` | `edit-config`.
  - `hotbar/lib/` — copias de las rutinas de datos (netstat :20128, Get-OmniRouteCombos,
    Read-SqliteQuery) → el widget es standalone, no depende del plugin.
  - Colapso: estado visual flecha/barra; posición recalculada al colapsar.
  - Acciones v1: omniroute → panel inline UP/DOWN + combos (honesto `sin datos` si no hay campo);
    settings → abre config.json en el editor por defecto; agentes → `none` por defecto (tooltip
    explica cómo configurarlas en config.json); `run:<cmd>` soportado en config.
- Limpieza de Herdr: eliminar `scripts/hub/`, `scripts/menu/`, `scripts/open-menu.ps1`, acción
  `menu` y pane `menu` del manifest; conservar start/status/dashboard/open-status-pane; bump
  manifest a 0.6.0.
- Config global: quitar el keybind `prefix+m` (hecho) — el menú de Herdr deja de existir.
- Docs: README rebautizado (hotbar), `docs/architecture.md` reescrita (widget + sección plugin
  legado), `docs/hub.md` → reemplazada por `docs/hotbar.md`, `docs/status-panes.md` se conserva
  (sigue válida para start/status).
- Renombres: GitHub `montesgp/hotbar` ✓; remote `origin` ✓; **carpeta local**: NO mover durante
  la implementación (rompería el workdir de la sesión); se renombra al cierre, avisado al usuario.

## Fuera de scope (v1)
- Submenús por ítem (futuro).
- Multi-monitor avanzado (layouts por monitor / ítems distintos por pantalla). El drag entre
  monitores con snap ya está en v1.
- Autostart al login (futuro; se puede hacer con acceso directo en shell:startup).
- Port a Linux (futuro; la lógica de datos queda desacoplada para eso).

## Checklist (IDs estables)
- [x] HB1 — Esqueleto WPF: ventana invisible (Title del window), Topmost=true,
  AllowsTransparency, WindowStyle=None, ShowInTaskbar=false, fondo transparente, forma media
  luna (Border con CornerRadius asimétrico + gradiente oscuro + borde sutil + DropShadow).
- [x] HB2 — Posicionamiento: monitor activo (config `monitor`: "primary" o nombre de dispositivo
  p.ej. `\\.\DISPLAY2`), derecha-centro (WorkingArea), margen configurable; recálculo en colapso.
  **Drag multi-monitor**: arrastrar la barra con el ratón la mueve libre; al soltar, snap al
  borde derecho del monitor bajo su centro y persistencia de `monitor` en config.json (vale
  para la próxima ejecución).
- [x] HB3 — 5 ítems desde `config.json` (glyph por código Unicode, hover con glow, tooltip);
  contrato de `action` (none | omniroute-status | run:… | edit-config), ejecución sin ventanas
  (Invoke-Native para run; Start-Process sin ventana para edit-config).
- [x] HB4 — Panel inline de OmniRoute: UP/DOWN (netstat :20128 LISTENING) + combos (SQLite) en
  paralelo, honesto `sin datos`; toggle dentro de la ventana del widget.
- [x] HB5 — Colapso: flecha en semicírculo; clic descolapsa; tamaño/anchura menor; estado no
  persistido (session-only) en v1. **Chevrones por dirección de movimiento**: collapse muestra
  `›` (hacia el borde), expand muestra `‹` (hacia el escritorio).
- [x] HB6 — Limpieza Herdr: borrar hub/menu/open-menu + manifest (acción/pane menu), conservar
  start/status, bump 0.6.0.
- [x] HB7 — Docs/rebrand: README, docs/architecture.md, docs/hotbar.md, referencias al nombre.
- [x] HB8 — Self-test: `-SelfTest` (construye ventana 500 ms, valida XAML, geometría, config;
  cierra solo) para verificación sin E2E manual.

## Authorized scope (confirmado)
- Repo `hotbar` (antes herdr-omniroute): manifest de plugin, scripts/, docs/, hotbar/.
- Config global de Herdr: solo quitar `prefix+m` (hecho).
- NO tocar: configs de clientes (claude/codex/opencode), ~/.omniroute/.env, node_modules, gentle-pi.

## Acceptance criteria (v1)
1. `hotbar/launch-hotbar.ps1` abre la barra: derecha-centro del monitor primario, siempre encima,
   sin marco ni entrada en la barra de tareas, forma de media luna oscura moderna.
2. 5 opciones visibles con sus glifos; hover con glow; click: omniroute abre panel UP/DOWN+combos,
   settings abre config.json, agentes no hacen nada hasta configurar (tooltip lo dice).
3. Colapsar → flecha en semicírculo mínima; descolapsar → barra completa.
4. Los ítems viven en config.json; agregar/editar un ítem no requiere tocar código.
5. El plugin de Herdr queda SOLO con start/status/dashboard/open-status-pane (acciones + libs);
   sin rastros de hub/menu en manifest, scripts ni docs.
6. `-SelfTest` pasa (XAML válido, config válido, geometría esperada, apertura/cierre automáticos).
7. 0 bytes no-ASCII en `.ps1` (glifos por `[char]0x…`); config.json y XAML con entidades `&#x…;`
   o `\u…` si hace falta (JSON) para mantener ASCII.

## Verification commands
- Parse de todos los .ps1 nuevos (Parser::ParseFile → 0 errores).
- `[xml]` del XAML embebido → carga sin error (validación estructural).
- `config.json` → `Get-Content -Raw | ConvertFrom-Json` OK; 5 ítems; actions válidas.
- `hotbar/hotbar.ps1 -SelfTest` → reporta PASS y cierra solo (≤ 2 s).
- Conteo bytes no-ASCII en hotbar/*.ps1, scripts/*.ps1 y manifest → 0.
- `herdr plugin action list` → ya NO aparece `menu`; aparecen start/status/dashboard/
  open-status-pane.
- E2E del orquestador: `launch-hotbar.ps1` en vivo (el usuario confirma visualmente).

## Verification results (2026-09-26)

Medido en esta máquina (monitor primario 1080x1872+0+0, `DpiX=96` → escala 1.0,
PowerShell 5.1.26100.9444, `sqlite3.exe` en PATH):

| Comprobación | Resultado |
| --- | --- |
| `Parser::ParseFile` en los 12 `.ps1` | 0 errores |
| `[xml]` del XAML embebido | OK (7423 chars) |
| `config.json` → `ConvertFrom-Json` | OK, 5 ítems, todas las `action` soportadas |
| `hotbar.ps1 -SelfTest` | `PASS`, exit 0, ~1.1–1.6 s (límite 2 s) |
| Camino de fallo del self test | exit 1; reporta ítem + glifo inválidos |
| Bytes no-ASCII (`hotbar/*.ps1`, `scripts/*.ps1`, manifest, config) | **0** en 17 ficheros |
| `herdr plugin action list` | 4 acciones: `dashboard`, `open-status-pane`, `start`, `status`. **Sin `menu`** |
| Segunda instancia | `hotbar: already running` (exit 0); directo `HOTBAR_ALREADY_RUNNING` (exit 3) |
| Mutex tras `Stop-Process -Force` | recoverido; el siguiente arranque funciona (sin wedge) |

### Geometría verificada contra píxeles reales

No se verificó "a ojo": se capturó la pantalla y se midió la silueta.

- **Barra (panel cerrado):** columnas oscuras `1000-1071` → 72 px clavados al borde
  derecho del monitor. La media luna es real: `minX` va `68 → 41 → 24 → 18 → 14 → 6 → 0`
  en `dy=200` y vuelve `6 → 15 → 18 → 24 → 41 → 64`. Simétrica, con el máximo
  abultamiento exactamente en el centro vertical.
- **Celdas:** 5 glifos + el chevron, clusters en `dy 76-79, 110-123, 158-171,
  206-219, 254-267, 301-315`. Pitch uniforme de 48 px, ninguno recortado por el
  bulbo (la columna de 44 px vive dentro de los 54 px que la curva deja en su banda).
- **Panel abierto:** columnas `680-1071` — panel + barra contiguos, con la barra
  **sigue** en `1000-1071`. El panel abre a la izquierda y la luna no se sale.

### Defectos encontrados y corregidos durante la verificación

1. `ShowDialog()` devuelto como sentencia suelta filtraba un `[bool]` a stdout, en el
   self test **y** en el arranque normal. `exit (Invoke-...)` además habría fallado al
   castear el informe (array de strings) a `int`: el código de salida viaja ahora en
   variable de script.
2. `Dispatcher.BeginInvoke([Action]{…})` desde un hilo no-UI depende de la resolución
   de un `params object[]`: sustituido por la sobrecarga explícita
   `(DispatcherPriority, Delegate)`.
3. **Las columnas del Grid estaban invertidas**: la barra iba en la columna 0
   (izquierda), pero la geometría ancla el borde **derecho** y desplaza la ventana a
   la izquierda al abrir el panel. Con el panel abierto la barra se iba a `x=680` y
   312 px fuera de pantalla. Ahora la barra es la última columna.
4. **`BarBorder` conservaba `Width="72"`** de cuando solo contenía la barra. Al meter
   el panel dentro, ese `Width` recortaba el panel a 0 y **centraba** la barra dentro de
   la ventana de 392 px (`(392-72)/2 = 160` → `x=840`, medido). Solo se veía con el
   panel abierto.
5. `CornerRadius="46,0,0,46"` no daba media luna: el borde recto ocupaba 308 de 400
   filas (era un rectángulo redondeado). Comprobado empíricamente que WPF **no** recorta
   el radio al ancho, así que `200,0,0,200` sí produce la media elipse; las celdas se
   dimensionaron contra la curva para que no la invadan.
6. `Sync-HotbarItems` se llamaba dos veces en el manejador de recarga.
7. `scripts/lib/Get-OmniRouteCombos.ps1` y `scripts/status-dashboard.ps1` tenían 15
   bytes no-ASCII en comentarios (●/○). Sustituidos por `U+25CF`/`U+25CB`; el código
   ya usaba `[char]0x25CF`.

### Nota sobre las 5 celdas

`claude`, `codex` y `opencode` quedan con `action: "none"` **declarado**: son
huecos honestos, y el tooltip lo dice. El contrato de `action` existe y funciona;
lo que falta es la decisión del usuario sobre qué debe lanzar cada agente. Agregar
un ítem o cambiar su acción no requiere tocar código.

## Work units (commits en `main`, sin push)

| # | Commit | Unidad |
| --- | --- | --- |
| 1 | `d1dea17` | `feat(hotbar): add standalone data readers and item config for the hotbar widget` |
| 2 | `8e82523` | `feat(hotbar): add the WPF half-moon widget, launcher and self-test` |
| 3 | `10dfe73` | `refactor(plugin): drop the hub/menu surface and bump the manifest to 0.6.0` |
| 4 | `4152b25` | `docs: rebrand the repo to hotbar` |
| 5 | este | `docs(odd): record hotbar verification and work-unit identities` |

`odd/tasks/omniroute-autofallback.md` tenía cambios previos sin relación con hotbar y
**no** se han incluido en ninguna de estas unidades.

## Progress notes
- 2026-09-26: giro completo del proyecto. Decisiones: widget WPF puro + conservar start/status;
  nombre `hotbar`; forma media luna; 4-5 opciones; colapso a flecha. GitHub renombrado a
  `montesgp/hotbar`, remote local actualizado, keybind `prefix+m` removido del config global.
  Repo local aún en ruta antigua (la carpeta se renombra al cierre, avisado al usuario).
- 2026-09-26 (build delegado): hotbar v0.6.0 implementado — hotbar/hotbar.ps1 + libs standalone,
  hub/menu borrados (manifest solo dashboard/open-status-pane/start/status), docs rebrand a
  hotbar, `-SelfTest` PASS. 5 commits en main sin push (d1dea17, 8e82523, 10dfe73, 4152b25,
  8f1fe17).
- 2026-09-26 (retro del usuario): chevrones de colapso/expansión invertidos y no había drag
  multi-monitor. Fix: chevrones por dirección de movimiento (collapse `›`, expand `‹`), drag
  libre con `DragMove()` en espacio vacío de la barra, snap al borde derecho del monitor bajo
  el centro al soltar, persistencia de `monitor` en config.json. Botón collapse ampliado al
  doble (56x36, fuente 24). Verificación: selftest PASS 1.4s, widget relanzado (pid 17244).
  Evidencia: commit `318aa61`.