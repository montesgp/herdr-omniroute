# Herdr Hub — the multi-widget dock

The hub is a thin pane anchored to the right of a Herdr workspace. It shows a strip
of one icon per widget, expands the widget you select, and closes itself when you
press `q` or `Escape`. The OmniRoute gateway is the first widget; `Tokens` and
`Config` are honest placeholders. Adding another is one file plus one line.

## Quick path

1. Open it: `herdr plugin action invoke herdr.omniroute.hub`
2. Press `1`, `2` or `3` to expand a widget. Press the same key again to collapse it.
3. Press `q`, `Q` or `Escape` to close the dock. The workspace layout goes back to
   what it was.

Opening it a second time does nothing except say so: the dock is a singleton per
workspace.

## The two states

| State | Shows | Repaints |
| --- | --- | --- |
| Collapsed | `[HUB] 1 ◉  2 Σ  3 ⚙` plus the key hint | Never. The strip does not change, and repainting an unchanging frame is what caused the visible lag in the status popup. |
| Expanded | `[1] OmniRoute`, the widget's lines, the strip again at the bottom | Every `-RefreshSec` (default 15 s), so the dock is a live view and not a photograph. |

Everything is drawn in place — cursor home, one `ESC[K` per line, `ESC[J` at the
end — following `scripts/status-dashboard.ps1`, so the dock never scrolls and never
opens a window.

## Keys

| Key | Effect |
| --- | --- |
| `1` `2` `3` (whatever the registry declares) | Expand that widget. Pressed again on the expanded widget, it collapses. |
| `q` `Q` `Escape` | Close the dock, which restores the layout. |
| Anything else | Ignored. A dock owns its keymap; a stray byte must not be able to steer it. |

Unlike the status popup, the dock is an ordinary split pane, not a session modal, so
it only receives input while it is focused. The opener passes `--no-focus`, which
keeps the cursor where the user left it.

## Widgets

| Key | Widget | Shows | State |
| --- | --- | --- | --- |
| `1` | `OmniRoute` | Gateway UP/DOWN, active combo, the configured combos | Implemented |
| `2` | `Tokens` | Total token output per project | Stub — the data source is an open decision, so it prints no numbers |
| `3` | `Config` | Nothing yet | Stub |

## The widget contract

A widget is a module that exports one function. That is the whole interface.

```powershell
# scripts/hub/widgets/<id>.ps1
function Get-Widget<Id> {
  [CmdletBinding()]
  param([int]$Width = 37)

  $lines = @()
  $lines += "First line"
  $lines += "Second line"
  return $lines
}
```

| Rule | Why |
| --- | --- |
| Name it `Get-Widget<Id>` and file it `widgets/<id>.ps1`, lower case | The hub derives both from the registry `Id`. No path in the registry to keep in sync. |
| Return `[string[]]` lines | The hub clips, the hub positions, the hub paints. A widget never draws. |
| Take `-Width` (optional) | The dock is ~37 columns. The hub also clips every line, so ignoring this is safe; honouring it avoids ugly truncation. |
| Keep it under 14 lines | A widget cannot take over the dock. The hub truncates. |
| Use `[char]0x25CF` for glyphs, not literals | Windows PowerShell 5.1 reads a `.ps1` without a BOM as ANSI, so a literal `●` in the source arrives mojibake. See `status-dashboard.ps1`. |
| Bound every external call | A widget that hangs freezes the dock. Use `lib/Invoke-Native.ps1` with an explicit timeout. |
| Never invent a value | A source that fails renders `sin datos`. A failed read is never rendered as an empty configuration. |
| Throw freely, if you must | The hub catches per widget and prints `(error del widget: …)`; the dock stays alive. |

So, adding a widget:

1. Create `scripts/hub/widgets/<id>.ps1` with `Get-Widget<Id>`.
2. Add one line to `scripts/hub/widgets.ps1`:

```powershell
@{ Id = "MyWidget"; Key = "4"; Icon = [string][char]0x25A0; Title = "My Widget" }
```

The strip and the key hint are generated from the registry, so nothing else changes.
`Tokens` is the worked example: a module plus one line, no other edits.

## Dock mechanics

| Question | Answer |
| --- | --- |
| Where does the dock come from? | `pane split <largest pane> --direction right --ratio 0.8 --cwd <repo> --no-focus`, then `pane run` inside it. |
| Why 0.8 and not 0.2? | `--ratio` applies to the **original** pane. 0.8 keeps the workspace at 80% and leaves the new pane the remaining ~20% on the right. On a ~183 column workspace that is the ~37 column dock. |
| Why the largest pane? | A dock is a sidebar. Splitting a 30 px sliver in half produces a 15 px dock nobody can read. A tie in area goes to the focused pane. |
| How is the dock found when reopening? | `pane list` in the **current** workspace, matching `terminal_title_stripped` against the prefix `hub: `. The hub sets that title itself, so the running dock is the state — no state file, no marker process. |
| How does it close? | The hub receives its own pane id as `-PaneId` and calls `pane close <id>` on exit. The pane is the process, so the close is what ends it. Run by hand without `-PaneId`, it exits without closing anything. |
| Why `--no-focus`? | The dock is something to look at, not something to type into. |
| What if `pane run` fails? | The opener waits ~1.5 s, retries once, and then closes the pane it just created. A half-open dock on the right of the workspace is worse than no dock. |

Scope is the current workspace only. The opener resolves the workspace from
`pane current` and neither reads nor touches any other workspace.

## Where the OmniRoute data comes from

| Fact | Source | Notes |
| --- | --- | --- |
| Gateway UP/DOWN | `netstat -an`, filtered for a `LISTENING` socket on `:20128` | Same detection as the status popup, so the two can never disagree. |
| Active combo | `GET /api/settings` with the machine-derived CLI token | Token = `HMAC-SHA256(key = MachineGuid, message = "omniroute-cli-auth-v1")`, lowercase hex, header `x-omniroute-cli-token`. **No API key is read, printed or written** — the derivation only needs the registry. |
| Combo list | `scripts/lib/Get-OmniRouteCombos.ps1` | The same read-only `SELECT` the popup uses, not a second implementation. |

Measured on this install (2026-09-25): `/api/settings` answers `200` with the token,
but it exposes **no active-combo field** (`comboStrategy`, `comboConfigMode`,
`comboAutoPromoteEnabled`, `hideAutoCombos` only), and neither does `/api/combos`.
So the widget asks for the plausible field names, falls back to what SQLite can
prove (`key_value.settings.activeCombo`), and otherwise prints `Activo: sin datos`.
It does not guess, and it does not draw a `●`/`○` it cannot justify.

The port check and the database read are started together and collected afterwards,
so the frame costs the slower one instead of their sum.

## Command line

| Switch | Default | Why it exists |
| --- | --- | --- |
| `-PaneId` | `""` | The dock's own id, passed by the opener. Empty = run by hand, closes nothing on exit. |
| `-MaxSeconds` | `1800` | Hard cap, enforced in every path including a host that cannot report keypresses. |
| `-Width` | `37` | Columns the hub renders for. Lines are clipped one short of it: a full-width line leaves the terminal in the pending auto-wrap state and drags the frame down a row. |
| `-RefreshSec` | `15` | Repaint interval while a widget is expanded. `0` freezes the frame. |
| `-Once` | off | Render one frame and exit. Renders from a shell with no pane. |
| `-NoKeyWatch` | off | Render once, then wait out `-MaxSeconds` without reading keys. |
| `-Widget` | `""` | Start with that registry key expanded. Test hook: `-Once -Widget 1`. |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Herdr Hub: no hay un pane actual` | The action ran outside a workspace | Invoke it from a workspace, not from a bare shell. |
| `Herdr Hub: ya esta abierto (pane …)` | A dock is already open here | Nothing to do. This is the idempotent path. |
| `pane split fallo` | Herdr refused the split | Check `herdr pane list`; a workspace cannot be split while a modal is up. |
| `no se pudo lanzar el menu del dock` | `pane run` failed twice | The pane was closed again. Run `pane run` by hand on a fresh split to see the raw error. |
| Dock opens but keys do nothing | The dock lost focus | Click it. `--no-focus` deliberately leaves focus with you. |
| `Activo: sin datos` | The gateway exposes no active combo (see above) | Nothing to fix. It is the honest answer for this build. |
| `Combos: sin datos` | The SQLite read failed | The detail is printed in the line below; check `~/.omniroute/storage.sqlite`. |
| A widget shows `(error del widget: …)` | That module threw | The dock is fine. The message is the widget's exception. |
| Dock disappeared by itself | Host could not report keypresses, or `-MaxSeconds` elapsed | Both are bounded on purpose. A dock that cannot take input should not sit there forever. |

## Next step

Decide the `Tokens` data source (`odd/tasks/herdr-hub.md`, H4) and replace
`scripts/hub/widgets/tokens.ps1`. The contract above is all that is needed.
