# Feature: OmniRoute auto-fallback gateway — Herdr plugin + pi extension

Status: **in progress** — T1–T3 done, T2.1 (status pane) done, T4 needs user.

## Objective
Hacer que OmniRoute sea el gateway de fallback automático de tokens para todo el stack de agentes (pi/gentle-shell, codex, claude) con garantía de que siempre corre mientras el usuario trabaja en Herdr, y con visibilidad/control desde Herdr y desde pi (aviso post-call cuando se usa un respaldo).

## Problem
- Los agentes no hacen failover de proveedor por sí solos; al agotar tokens la sesión falla.
- OmniRoute estaba instalado (3.8.50) pero sin PATH, sin garantía de arranque, sin visibilidad.
- El usuario trabaja en Herdr (multiplexor) y quiere status global (no por proyecto) + poder lanzar el gateway si está caído, sin que las actualizaciones rompan la personalización.

## Why (decisiones confirmadas)
- Fallback automático transparente solo puede vivir en el gateway (OmniRoute): ningún agente/gateway HTTP puede pausar una request y preguntar.
- Modo elegido por el usuario: **Automático + aviso post-call** (no experimental de prompt interactivo).
- Personalización SIEMPRE en capa exterior: archivos de usuario (~/.pi/agent/, ~/.config/, %APPDATA%\herdr, %USERPROFILE%) y extensiones propias; NUNCA editar node_modules (gentle-pi/pi) ni binarios (gentle-ai).
- Plugins de Herdr son globales al usuario por diseño (link/install disponibles en todas las sesiones).
- Cuenta GitHub destino: `montesgp` (la logueada); repos locales en `C:\repositories\personal\`.

## Scope
- Repo nuevo `C:\repositories\personal\herdr-omniroute` (publicable como `montesgp/herdr-omniroute`, topic `herdr-plugin`).
- Plugin Herdr con manifest `herdr-plugin.toml`: acción `status`, acción `start`, acción `dashboard`, acción `open-status-pane`, pane `status` (tab auto-abierto) y keybind `prefix+o`.
- Extensión pi en `~/.pi/agent/extensions/omniroute.ts`: slash `/omniroute [status|start|dashboard]` + `setStatus` en footer + aviso `ui.notify` post-call ante respuestas anómalas del gateway.
- Scheduled task `OmniRouteGateway` + script `%USERPROFILE%\omniroute-start.cmd` (garantía de arranque al logon con restart-on-failure).
- Configuración de providers/combos en OmniRoute vía dashboard/TUI (T4, requiere al usuario).

## Fuera de scope (por decisión)
- Modo interactivo estricto ("¿redirijo a respaldo? Sí/No" en mitad de llamada) — descartado por el usuario.
- Editar gentle-pi / pi / gentle-ai internamente.
- Migración OmniRoute a npm global / otra ruta de instalación.

## Constraintes
- Windows 11, PowerShell 5.1, Node v22.22.3 (fnm persistente: C:\Users\patri\scoop\persist\fnm\node-versions\v22.22.3\installation\node.exe).
- OmniRoute entry: C:\Users\patri\node_modules\omniroute\bin\omniroute.mjs (no está en PATH; rutas absolutas en scripts/task).
- Pi 0.86.1: extensiones = archivos .ts en `~/.pi/agent/extensions/` con `export default function (pi: ExtensionAPI)`; API: `pi.registerCommand`, `pi.on`, `ctx.ui.notify`, `ctx.ui.setStatus`, `ctx.exec`.
- Herdr 0.9.1-preview (server corriendo, socket en %APPDATA%\herdr\herdr.sock): plugins = dir con `herdr-plugin.toml`; env HERDR_BIN_PATH/HERDR_SOCKET_PATH/...; `herdr plugin link` para local, `herdr plugin install owner/repo/subdir` para GitHub.
- No exponer credenciales; el `.env` de OmniRoute (STORAGE_ENCRYPTION_KEY) no se toca.

## Checklist (accelerable, IDs estables)

### T1 — Garantía de arranque (scheduled task) — DONE ✅
- [x] Script `%USERPROFILE%\omniroute-start.cmd`: si puerto 20128 libre → `node ...\omniroute.mjs serve --daemon --no-open`.
- [x] Scheduled task `OmniRouteGateway` (AtLogOn, `--daemon --no-open`, restart-on-failure 3x/1min, ExecutionTimeLimit 0).
- [x] Servicio actual corriendo: puerto 20128 LISTENING (iniciado manualmente con el mismo entry).
- [x] Verificación: `omniroute status --base-url http://localhost:20128` OK (DB 1.6MB, Claude Code 2.1.281 + Codex CLI 0.154.0 detectados).
- [ ] Verificación futura: reinicio/re-logon para confirmar daemon + no-browser.
- Evidencia: netstat :20128 LISTENING; status CLI OK.

### T2 — Plugin Herdr `herdr-omniroute` (repo nuevo) — DONE ✅
- [x] Repo creado (T1, branch feat/omniroute-autofallback) + README (T2). `.gitignore` pendiente (opcional).
- [x] `herdr-plugin.toml` (manifest validado contra plugins.mdx; 3 acciones).
- [x] `scripts/status.ps1`: netstat :20128 → UP/DOWN + exit code.
- [x] `scripts/start.ps1`: si puerto libre, lanza `node mjs serve --daemon --no-open`.
- [x] `scripts/dashboard.ps1`: abre http://localhost:20128.
- [x] `herdr plugin link` + `herdr plugin action invoke herdr.omniroute.status` OK (UP, exit 0) y `start` OK (already UP).
- [x] Push a GitHub `montesgp/herdr-omniroute` — público, topic `herdr-plugin`, default branch `main`, ramas `dev`/`staging`/`main` (todas en el mismo commit base). Docs públicas: README (diagrama Mermaid), `docs/architecture.md`, `LICENSE` (MIT). Commit docs: 2f0985c.
- Commit: `804c336 feat(plugin): add herdr-omniroute status/start/dashboard actions`

### T3 — Extensión pi `omniroute.ts` — DONE ✅
- [x] Fuente canónica en repo `extensions/omniroute.ts` + deploy `~/.pi/agent/extensions/omniroute.ts` (hash idéntico).
- [x] `pi.registerCommand("omniroute", ...)`: `status` (●/○), `start`, `dashboard`.
- [x] `setStatus("omniroute", "●"/"○")` en footer tras `session_start`.
- [x] `pi.on("after_provider_response")`: status >= 400 → `ctx.ui.notify` warn.
- [ ] Verificar en probe (T4b) si OmniRoute añade headers de fallback (x-omniroute-*) para aviso "se usó respaldo"; si no, el aviso queda limitado a estado del gateway (documentar).
- [x] Carga validada: `EXT OK true` (node strip-types ESM) + smoke test (sesión_start → ●, 500 → warn, 200 silencioso, `/omniroute status` → UP).
- Commit: `96aad49 feat(extension): add pi /omniroute gateway status extension`. Nota: pi real instalado es 0.87.1 (equivalente a 0.86.1 verificado en types).

### T2.1 — Status pane (sección visible en Herdr para status plugins) — DONE ✅
- [x] `scripts/status-dashboard.ps1`: dashboard live (UP/DOWN + combos + refresh cada 8s) con switch `-Once` para test sin loop; strip de ANSI del CLI de OmniRoute.
- [x] `[[panes]]` en manifest: `id = "status"`, `title = "OmniRoute Gateway"`, `placement = "tab"`.
- [x] `scripts/open-status-pane.ps1` idempotente (si `herdr pane list` ya muestra el pane, no duplica).
- [x] `[[startup]]` hook → auto-apertura al restaurar sesión de Herdr (aplica en próximos arranques).
- [x] Acción `herdr.omniroute.open-status-pane`; manifest v0.2.0.
- [x] `docs/status-panes.md`: patrón reutilizable de status plugins (roadmap: output total entre proyectos; plugins por proyecto irán a pi).
- [x] Test `-Once` OK: UP + combos `Kimi Coding`/`static-best-coding`. Pane abierto manualmente en la sesión activa.
- [x] Feedback usuario (15:44): quería el panel en TODOS los workspaces y refresco no brusco. Ajustado: opener itera `herdr workspace list` y abre con `--workspace <id>` `--no-focus` (idempotente por workspace); dashboard pasa de `Clear-Host` a render in-place (`Home` con `[Console]::SetCursorPosition`/fallback ANSI `ESC[H` + `ESC[K` por línea + línea reservada anti-restos + `-RefreshSec` configurable). Verificado: 3 pestañas (w19:t2, w1F:t3, w1G:t2) y segunda pasada → "0 opened, 3 already open".
- Evidencia: manifest v0.2.0 con panes/startup; test dashboard; pane abierto (pestaña visible en los 3 workspaces).

### T4 — Configuración de providers/combos en OmniRoute — REQUIERE USUARIO
- [x] Usuario: abrió dashboard y creó dos combos habilitados — `Kimi Coding` [priority] y `static-best-coding` [weighted] — con providers conectados (gemini/g4f-gemini/uncloseai activos; opencode/OpenCode Free, chipotle, cloudflare-playground, duckduckgo-web, felo-web, aihorde, theoldllm).
- [ ] Probe: llamada con modelo auto vía endpoint /v1 (curl) → confirmar corte automático y headers de respuesta.
- [ ] Registrar en pi un custom provider `omniroute` (models.json o registerProvider) apuntando a http://localhost:20128 (validar formato antes de tocar config real).
- [ ] Ajustar perfil/agente en gentle-pi si se decide fijar modelo crítico sin fallback (decisión pendiente del usuario).

## Authorized scope (confirmado)
- Escribir en: repo herdr-omniroute, `~/.pi/agent/extensions/`, `%USERPROFILE%\omniroute-start.cmd`, Task Scheduler (OmniRouteGateway).
- Push/PR al repo montesgp/herdr-omniroute cuando T2 esté completa (usuario autorizó alojarlo en su cuenta).
- NO tocar: `~/.omniroute/.env`, node_modules de pi/gentle-pi, binario gentle-ai, config existente de Herdr (%APPDATA%\herdr\config.toml) salvo keybinding del plugin.

## Acceptance criteria
1. Reinicio de sesión Windows → gateway vuelve solo (`serve --daemon --no-open`), sin abrir navegador.
2. En cualquier sesión de Herdr, keybind/acción muestra ●/○ y permite lanzar el gateway.
3. En pi, `/omniroute status` muestra el estado y avisa post-call ante respuesta anómala; footer muestra el estado del gateway.
4. Con un modelo `auto`/combo, una prueba de llamada con proveedor principal agotado responde vía respaldo sin intervención.
5. Ninguna actualización futura de pi/gentle-pi/gentle-ai/OmniRoute rompe las piezas (todo en capa exterior).

## Verification commands
- `netstat -an | findstr :20128` → LISTENING
- `node C:\Users\patri\node_modules\omniroute\bin\omniroute.mjs status --base-url http://localhost:20128` → OK
- `herdr plugin action invoke herdr.omniroute.status` → salida de estado
- pi: `/omniroute status` (en sesión pi) → estado ●/○

## Progress notes
- 2026-09-25: T1 completada. Gateway corriendo en :20128 (arranque manual con entry node). Task `OmniRouteGateway` Ready con `serve --daemon --no-open`. Repo creado (git init, branch feat/omniroute-autofallback). Descubrimiento: OmniRoute escribe `~/.omniroute` (storage.sqlite 1.6MB, .env STORAGE_ENCRYPTION_KEY) — NO mostrar valores de .env; `server-ws.mjs` es el worker del serve. Config Dir NOT found → T4 pendiente de primera configuración.
- 2026-09-25 (14:50): combos creados por usuario: `Kimi Coding` [priority], `static-best-coding` [weighted]; `omniroute combo switch <name>` cambia el activo. T4a (providers+combos) lista; falta probe /v1 + provider custom en pi (T4b).
- Próximo (en curso): T2+T3 vía writer delegado.
- 2026-09-25 (15:18): T2 y T3 COMPLETADAS por writer delegado y verificadas por el orquestador (gatekeeper: archivos presentes, link enabled, action status UP, hash repo↔deploy idéntico, keybind añadido). Commits: 804c336 (plugin), 96aad49 (extensión). Riesgos anotados: pi instalado es 0.87.1 (API equivalente); campo `author` no documentado en manifest (Herdr lo ignora); `setStatus/notify` devuelven void (await inofensivo bajo jiti); `herdr plugin action invoke` devuelve `running` (stdout vía `herdr plugin log list`); carga real en sesión pi TTY + tecla `prefix+o` + dashboard end-to-end no verificables aquí.
- 2026-09-25 (15:38): T2.1 completada (ruta inline: piezas mecánicas derivadas de la doc oficial de panes, sin investigación nueva; verificación local `-Once` imprime UP + combos). Pane `status` (tab) declarado + startup idempotente + acción `open-status-pane`; manifest 0.2.0; `docs/status-panes.md` documenta el patrón reutilizable y la hoja de ruta (output total entre proyectos; plugins por proyecto → pi).
- 2026-09-25 (15:47): feedback T2.1b — panes por-workspace (plugin v1 no tiene pane global de sesión) → opener multi-workspace (workspace list + pane open --workspace --no-focus, idempotente por workspace) y refresh in-place sin Clear-Host (set cursor position + ESC[K por línea + línea reservada + -RefreshSec). Verificado: 3 pestañas (w19/w1F/w1G), 0 duplicados al repetir. Limitación documentada: workspaces nuevos en sesión activa no reciben el pane hasta reiniciar/acción manual.

## Next step
T4b (probe /v1 con combo + provider custom en pi hacia localhost:20128) y pruebas del usuario (ver la pestaña "OmniRoute Gateway", `prefix+o`, `/omniroute`, scheduler al reiniciar). Futuro: plugin general de output total entre proyectos siguiendo `docs/status-panes.md`.