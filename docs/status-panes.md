# Status panes — el patrón para status plugins en Herdr

> "Quiero una sección o panel en Herdr para seguir implementando este tipo de status plugins."
> Este documento es la plantilla de referencia. `herdr-omniroute` es su primer caso real.

## Qué es un status pane

Herdr plugin v1 **no tiene UI nativa de plugins** (sin panel gráfico propio), PERO tiene
`[[panes]]`: el manifest puede declarar panes que son **procesos terminales reales** que Herdr
abre en su TUI como **pestaña (`tab`), división (`split`), popup, overlay o zoomed**. Un proceso
que imprime estado y se refresca en loop = un status pane. Eso es lo que "se ve en pantalla".

Un status plugin completo tiene 4 piezas:

| Pieza | Manifest | Qué hace |
| --- | --- | --- |
| Acciones | `[[actions]]` | Invocación puntual y verificable (status, start, dashboard) |
| Pane de status | `[[panes]]` | Proceso terminal visible que imprime estado y se refresca |
| Apertura idempotente | `scripts/open-status-pane.ps1` | Abre el pane sin duplicarlo (lo llama startup y acciones) |
| Auto-apertura | `[[startup]]` | Abre el pane automáticamente al restaurar la sesión de Herdr |

## Pieza 1 — Acciones (la API verificable)

Acciones = comandos puntuales que devuelven exit code y dejan log:

```toml
[[actions]]
id = "status"
title = "My Status: status"
contexts = ["workspace"]
command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/status.ps1"]
```

Se invocan con `herdr plugin action invoke <id>.<action>` o keybind. Su salida queda en
`herdr plugin log list --plugin <id>`. Son la forma **no-UI** de comprobar un estado.

## Pieza 2 — El pane (la parte visible)

```toml
[[panes]]
id = "status"
title = "My Status"
placement = "tab"           # tab | split | popup | overlay | zoomed
command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/status-dashboard.ps1"]
```

El script que corre dentro del pane es un **loop de render**:

```powershell
$refreshSec = 8
function Render { Clear-Host; ... salida con Write-Host y colores ... }
while ($true) { Render; Start-Sleep -Seconds $refreshSec }
```

Reglas útiles:
- **La salida debe ser legible como texto plano**: PowerShell 5.1 no interpreta ANSI, así que
  si consultas CLIs con color (p. ej. OmniRoute), limpia los escapes:
  `$s -replace "\x1b\[[0-9;]*m",""`.
- **Añade un switch `-Once`** para poder testear el render sin entrar en el loop infinito:
  `param([switch]$Once)` + `if ($Once) { Render; exit 0 }`. Así se valida el dashboard desde
  línea de comandos sin colgar el shell.
- Distingue estados con color (`Green` UP / `Red` DOWN) y muestra la acción de recuperación.
- Añade un timestamp de "Actualizado" — el pane vive mientras la pestaña está abierta.

## Pieza 3 — Apertura idempotente

`scripts/open-status-pane.ps1` — usado por startup Y por la acción "open status pane":

```powershell
$herdr = if ($env:HERDR_BIN_PATH) { $env:HERDR_BIN_PATH } else { "herdr" }
$existing = (& $herdr pane list 2>$null | Out-String)
if ($existing -match "<plugin-id>|<pane-title>") { Write-Output "pane already open"; exit 0 }
& $herdr plugin pane open --plugin <plugin-id> --entrypoint status 2>&1 | Out-String | Write-Output
exit $LASTEXITCODE
```

## Pieza 4 — Auto-apertura al arrancar

```toml
[[startup]]
command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/open-status-pane.ps1"]
```

El startup hook corre **una vez por plugin al restaurar la sesión** de Herdr (no en cada attach
ni reload de config). El script idempotente evita duplicar pestañas. Para desactivar la
auto-apertura de un plugin: borra su bloque `[[startup]]`.

> Nota: los cambios de manifest de *panes/acciones* se leen al invocarlos; el bloque `[[startup]]`
> requiere el próximo arranque/restauración de sesión. Si quieres el pane YA sin reiniciar, abre
> manualmente: `herdr plugin pane open --plugin <id> --entrypoint status`.

## Hacer tu propio status plugin (checklist)

1. Crea el repo (`herdr plugin init` no es necesario; el manifest es un TOML plano).
2. `scripts/status.ps1` (chequeo puntual + exit code) → acción.
3. `scripts/status-dashboard.ps1` (loop de render con `-Once`) → pane.
4. `scripts/open-status-pane.ps1` (idempotente) → startup + acción "open".
5. `herdr-plugin.toml` con acciones + pane + startup.
6. `herdr plugin link <ruta>`; testea con `-Once`; `herdr plugin action invoke ...`;
   abre el pane manualmente una vez; reinicia la sesión para validar la auto-apertura.
7. Publica con `gh repo create <owner>/<repo> --public --source . --push` y el topic `herdr-plugin`
   (el índice de herdr.dev/plugins lo indexa; refresco ~30 min).

## Hoja de ruta del usuario (montesgp)

- **Generales (Herdr, user-global)** — este repo es la plantilla:
  - ✅ `herdr-omniroute` — estado del gateway OmniRoute (primer caso real).
  - 🔜 **Output total** entre todos los proyectos: agregar CLI/socket de Herdr
    (`herdr status`, sesiones/workspaces) + datos de los agentes → dashboard que sume
    tokens/gasto por sesión y proyecto. El pane puede renderizar esa agregación igual que este.
  - 🔜 Plugins generales sobre el flujo (estado de scheduled tasks, recursos, git repos...).
- **Por proyecto (pi)** — cuando se aborde, serán extensiones pi (como `extensions/omniroute.ts`),
  con footer/notify por agente; se mantienen fuera de este repo o en repos separados.