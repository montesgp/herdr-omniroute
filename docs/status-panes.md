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
param([switch]$Once, [int]$RefreshSec = 8)
$ESC = [char]27   # PS 5.1 no tiene `e ; prepara la secuencia ANSI manualmente

function Home {
  # Volver arriba SIN borrar el buffer: sobrescribimos en el mismo sitio.
  try { [Console]::SetCursorPosition(0, 0) } catch { Write-Host "$ESC[H" -NoNewline }
}

function Render {
  Home
  # ... cada línea termina con "$ESC[K" (clear-to-end) para tapar restos de la pasada anterior ...
  Write-Host ("  Estado: UP" + $ESC + "[K") -ForegroundColor Green
  # usa SIEMPRE una línea reservada "en blanco" tras el estado y al final:
  # aspi a altura de salida constante para que DOWN↔UP no dejen restos.
}

while ($true) { Render; Start-Sleep -Seconds $RefreshSec }
```

Reglas útiles:
- **NUNCA uses `Clear-Host` en un pane**: borra el buffer entero en cada refresh y se ve como un pantallazo. El refresh suave es "cursor arriba + sobrescribir líneas": `Home` (set cursor position, fallback ANSI `ESC[H`) y cada línea termina con `ESC[K` (clear-to-end-of-line). PowerShell 5.1 no interpreta ANSI por sí mismo, pero la TUI de Herdr sí lo hace, así que las secuencias pasan.
- **Mantén la altura de salida constante** (reserva una línea en blanco donde el estado DOWN imprime la línea de acción) para que las transiciones UP↔DOWN no dejen texto residual.
- **La salida debe ser legible como texto plano**: si consultas CLIs con color (p. ej. OmniRoute), limpia los escapes:
  `$s -replace "\x1b\[[0-9;]*m",""`.
- **Añade un switch `-Once`** para poder testear el render sin entrar en el loop infinito:
  `param([switch]$Once)` + `if ($Once) { Render; exit 0 }`. Así se valida el dashboard desde
  línea de comandos sin colgar el shell.
- **Haz la frecuencia configurable** con `[int]$RefreshSec = 8` (refresca rápido de 8s sin parpadeo
  porque reescribe en el mismo sitio).
- Distingue estados con color (`Green` UP / `Red` DOWN) y muestra la acción de recuperación.
- Añade un timestamp de "Actualizado" — el pane vive mientras la pestaña está abierta.

## Pieza 3 — Apertura idempotente Y EN TODOS LOS WORKSPACES

Los panes viven **dentro de un workspace** (plugin v1: no hay pane "global de sesión").
Para ver el status en todos tus proyectos, el opener itera los workspaces existentes y abre
la pestaña en cada uno (`--workspace <id>` + `--no-focus` para no robar el foco), comprobando
por workspace si ya existe antes de abrir:

```powershell
$herdr = if ($env:HERDR_BIN_PATH) { $env:HERDR_BIN_PATH } else { "herdr" }
$label = "OmniRoute Gateway"

$ws = (& $herdr workspace list 2>$null | Out-String | ConvertFrom-Json)
$panes = (& $herdr pane list 2>$null | Out-String | ConvertFrom-Json)
$workspaces = @($ws.result.workspaces)

foreach ($w in $workspaces) {
  $already = @($panes.result.panes | Where-Object { $_.workspace_id -eq $w.workspace_id -and $_.label -eq $label }).Count -gt 0
  if ($already) { continue }
  & $herdr plugin pane open --plugin <plugin-id> --entrypoint status --workspace $w.workspace_id --no-focus
}
```

Si `workspace list` falla, el fallback es abrir sin target (workspace activo). El comando pane se
lanza con el cwd del plugin, no del workspace, así que las rutas relativas del manifest funcionan
en cualquier workspace.

## Pieza 4 — Auto-apertura al arrancar

```toml
[[startup]]
command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/open-status-pane.ps1"]
```

El startup hook corre **una vez por plugin al restaurar la sesión** de Herdr (no en cada attach
ni reload de config). Como el opener itera los workspaces, la auto-apertura cubre todos los
workspaces existentes en ese momento. Para desactivar la auto-apertura de un plugin: borra su
bloque `[[startup]]`.

> Nota 1: los cambios de manifest de *panes/acciones* se leen al invocarlos; el bloque `[[startup]]`
> requiere el próximo arranque/restauración de sesión. Si quieres los panes YA sin reiniciar, abre
> manualmente el opener (o la acción `open-status-pane`).
> Nota 2: los workspaces **creados después** del arranque no reciben el pane hasta el próximo
> reinicio de Herdr o una invocación manual del opener. Es una limitación de plugin v1 (los panes
> son por-workspace y no hay hook de "workspace creado").

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