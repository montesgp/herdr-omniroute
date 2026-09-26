# Architecture — herdr-omniroute

## What this is

`herdr-omniroute` is the **thin control layer** for the [OmniRoute](https://github.com/montesgp/omniroute)
auto-fallback gateway. It does not implement routing, provide tokens, or run the
gateway process itself — it makes the gateway *visible and alive* from the two
places the user actually works: the Herdr session multiplexer and the pi agent.

## Where it mounts

```mermaid
flowchart LR
  subgraph HERDR["Herdr — multiplexor de sesiones"]
    direction TB
    S["Sesiones de agentes"]
    P["herdr-omniroute plugin<br/>(status · start · dashboard · popup status — prefix+o)"]
  end
  subgraph AGENTES["Agentes (clientes OpenAI-compatible)"]
    direction TB
    PI["pi / gentle-shell"]
    CC["Claude Code"]
    CX["Codex CLI"]
  end
  subgraph GW["OmniRoute gateway — localhost:20128"]
    direction TB
    C1["Combo Kimi Coding [priority]"]
    C2["Combo static-best-coding [weighted]"]
  end
  subgraph PROV["Providers"]
    direction TB
    G["gemini · g4f-gemini"]
    K["kimi · OpenCode Free"]
    U["uncloseai · otros free"]
  end
  subgraph INFRA["Windows — scheduled task OmniRouteGateway"]
    direction TB
    T["omniroute serve --daemon --no-open<br/>(headless, restart-on-failure)"]
  end

  PI -->|"POST /v1"| GW
  CC -->|"POST /v1"| GW
  CX -->|"POST /v1"| GW
  GW -->|"fallback en orden del combo"| G
  GW -->|"fallback"| K
  GW -->|"fallback"| U
  S --> P
  P -.->|"scripts status/start"| INFRA
  INFRA -.->|"mantiene vivo"| GW
  PI -.->|"omniroute.ts: /omniroute · footer · notify post-call"| P
```

## Layers

| Layer | Component | Responsibility |
| --- | --- | --- |
| 0 — Interfaz | Herdr + plugin + pi extension | Visibility and control: on-demand status popup (one snapshot of UP/DOWN + combos), status dot, actions, `/omniroute` |
| 1 — Agentes | pi, Claude Code, Codex CLI | Arbitrary OpenAI-compatible clients that POST to `:20128/v1` |
| 2 — Gateway | OmniRoute (`localhost:20128`) | Single entry point; owns combos and provider routing |
| 3 — Providers | gemini, kimi, OpenCode Free, uncloseai, ... | Real backends; exhausted/slow ones are bypassed by the combo |
| 4 — Infra | Scheduled task `OmniRouteGateway` + `omniroute-start.cmd` | Keeps the gateway running across logons and crashes |

## How a request flows

1. An agent calls `http://localhost:20128/v1` (any OpenAI-compatible shape).
2. OmniRoute resolves the **active combo**: `Kimi Coding [priority]` (explicit order)
   or `static-best-coding [weighted]` (automatic weighted scoring that mostly uses
   Gemini).
3. The combo starts with its first provider; on exhaustion or failure (429, 5xx,
   timeout) the **next provider in the combo serves the same request**.
4. The agent sees one seamless response. No agent-side fallback logic exists —
   that is deliberate: an HTTP request cannot be paused, so the gateway is the
   only layer where transparent failover is possible.
5. Control feedback outside the data path:
   - Herdr plugin reports UP/DOWN and can (re)start the daemon (`prefix+o`).
     The detail is an on-demand popup showing one snapshot taken at open time
     (no auto refresh, closes on `q` or Enter), never an auto-opened surface.
   - pi extension shows a footer status (`●`/`○`) and warns on non-2xx
     `after_provider_response`.

## How the status popup gets its data

The popup does **not** call the OmniRoute CLI. It reads the gateway's own
`storage.sqlite` with a `SELECT`-only, read-only connection. That is a
deliberate boundary, not an optimisation:

- **Latency.** `node omniroute.mjs combo list` cost 3–9 s per frame. The CLI
  boots `tsx` + Commander, and `isServerUp()` burns a health budget timing out
  before routing even starts. A direct read costs 33–57 ms.
- **No visible console.** `bin/cli/utils/cliToken.mjs` gets the machine id via
  `node-machine-id`, which runs `REG.exe QUERY` through `execSync(...,
  { shell: true, windowsHide: false })`. That allocates a console host, so every
  popup flashed a terminal window on the Windows Terminal broker. The direct read
  launches nothing that wants a window.

Because both the read and the port check are independent, they are started
through `Start-NativeProcess` and collected afterwards, so the frame pays for
the slower one instead of their sum. A failed read renders
`(datos de combos no disponibles: …)` — never an empty list, because a broken
read must not look like "no combos configured".

## Why personalization lives in the outer layer (anti-breakage contract)

- All runtime configuration stays in **user files**: `~/.pi/agent/extensions/`,
  `%APPDATA%\herdr\config.toml`, `%USERPROFILE%\omniroute-start.cmd`,
  Task Scheduler, and OmniRoute's own `~/.omniroute` data.
- This repo never writes into a tool's install directory: not into
  `node_modules` of pi/gentle-pi, not into the Herdr binary, not into the
  OmniRoute package. Updates to those tools can never silently overwrite these
  files.
- If pi or Herdr change their extension/plugin format, the fix is applied in
  this repo (or the user config), not inside a vendored dependency.

## Components in this repo

| Path | Purpose |
| --- | --- |
| `herdr-plugin.toml` | Herdr plugin manifest (4 workspace actions, 1 status popup, no startup hook) |
| `scripts/status.ps1` | Port 20128 check; exit 0 = up, 1 = down |
| `scripts/start.ps1` | No-op if up; else `serve --daemon --no-open` |
| `scripts/dashboard.ps1` | Opens `http://localhost:20128` |
| `scripts/lib/Invoke-Native.ps1` | Windowless external-command helper (`CreateNoWindow`) shared by the scripts. `Start-NativeProcess` / `Complete-NativeProcess` are split so two calls can be in flight at once |
| `scripts/lib/Read-SqliteQuery.ps1` | Read-only SQLite query: `sqlite3.exe` first, P/Invoke over `winsqlite3.dll` as fallback |
| `scripts/lib/Get-OmniRouteCombos.ps1` | Resolves OmniRoute's `storage.sqlite` and maps the combos table into the frame's fields |
| `scripts/status-dashboard.ps1` | Single-snapshot frame for the status popup: reads SQLite and checks the port in parallel, paints once, never repaints, then waits for `q`/Enter (`-MaxSeconds` cap, `-Once` test switch) |
| `scripts/open-status-pane.ps1` | Opens the single status popup (one `plugin pane open` call, no pane probing) |
| `docs/status-panes.md` | Reusable pattern for future status plugins |
| `extensions/omniroute.ts` | pi extension source (deployed to `~/.pi/agent/extensions/`) |
| `odd/tasks/omniroute-autofallback.md` | Feature tracker (ODD) — evidence of what was built and verified |

## Branching

Simple promotion flow, everything converges on `main`:

```
dev ──► staging ──► main
```

- `dev` — active development.
- `staging` — pre-release testing.
- `main` — stable release; all promoted work lives here.