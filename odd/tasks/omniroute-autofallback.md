# Feature: OmniRoute auto-fallback gateway — Herdr plugin + pi extension

Status: **in progress** — T1 done, T2/T3 pending, T4 needs user.

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
- Plugin Herdr con manifest `herdr-plugin.toml`: acción `status`, acción `start`, acción `dashboard`, keybind `prefix+o`.
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

### T2 — Plugin Herdr `herdr-omniroute` (repo nuevo) — PENDING
- [ ] Crear repo `C:\repositories\personal\herdr-omniroute` (branch feat/omniroute-autofallback) con README, .gitignore.
- [ ] `herdr-plugin.toml`: id `herdr.omniroute`, name "OmniRoute Gateway", min_herdr_version 0.7.0, platforms windows; [[actions]] status/start/dashboard; [[keys.command]] prefix+o → status.
- [ ] `scripts/status.ps1`: chequea puerto 20128 + `omniroute status` resumido, exit code indicativo.
- [ ] `scripts/start.ps1`: si puerto libre, lanza `node mjs serve --daemon --no-open`.
- [ ] `scripts/dashboard.ps1`: abre http://localhost:20128.
- [ ] `herdr plugin link` + `herdr plugin action invoke herdr.omniroute.status` de prueba.
- [ ] Push a GitHub `montesgp/herdr-omniroute` (topic `herdr-plugin`).

### T3 — Extensión pi `omniroute.ts` — PENDING
- [ ] `~/.pi/agent/extensions/omniroute.ts` (default factory ExtensionAPI).
- [ ] `pi.registerCommand("omniroute", ...)`: `status` (●/○, provider activo si disponible), `start`, `dashboard`.
- [ ] `setStatus("omniroute", "●"/"○")` en footer tras session_start (chequeo de puerto).
- [ ] `pi.on("after_provider_response")`: si status >= 400 → `ctx.ui.notify` warn (gateway caído o provider agotado sin respaldo).
- [ ] Verificar en probe (T4) si OmniRoute añade headers de fallback (x-omniroute-*) para aviso "se usó respaldo"; si no, el aviso queda limitado a estado del gateway (documentar).
- [ ] Carga con pi (jiti, sin compilación): `pi --extension` de prueba.

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

## Next step
T2+T3 en ejecución por writer delegado (ruta directa delegada: archivos mecánicos ya especificados por el orquestador); gatekeeper verifica al retorno; luego T4b (probe + provider custom pi) con el usuario.