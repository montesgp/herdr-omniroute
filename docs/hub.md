# Herdr Hub — the mini-menu

A popup, not a pane. `Herdr Hub` draws four rows on top of whatever you are doing,
takes one key, and is gone. It reserves no space in the tiled layout, never
displaces the pane you are working in, and leaves no trace once it closes.

This replaced a dock that split the workspace and kept ~20% of its width. That was
too expensive for a menu, and the cost was permanent while the value was occasional.

## Quick path

1. Open it: `herdr plugin action invoke herdr.omniroute.menu`
2. Press `1`, `2`, `3` or `4`.
3. Press `q`, `Q` or `Escape`.

## The four rows

| Key | Row | What it does | On failure |
| --- | --- | --- | --- |
| `1` | `✳ claude` | Focuses the `claude` pane in this workspace | Stays open, prints why |
| `2` | `◎ codex` | Focuses the `codex` pane in this workspace | Stays open, prints why |
| `3` | `◈ opencode` | Focuses the `opencode` pane in this workspace | Stays open, prints why |
| `4` | `▣ omniroute` | Expands the gateway state in place, same popup | Shows `sin datos` |

Each row carries that tool's own brand glyph, so you recognise the row before you
read it. The glyphs are `U+2733`, `U+25CE`, `U+25C8`, `U+25A3`.

Row 4 is the only one that does not close the menu. It expands inline, and `q`
collapses it back. Focus succeeded is the one case where the menu closes: the
popup sits on top of the pane you just selected, so staying up would hide the
thing you asked for.

## Keys

| Key | In the menu | In the expanded OmniRoute row |
| --- | --- | --- |
| `1`-`4` | Run that row | Ignored |
| `q` `Q` | Close the popup | Collapse back to the menu |
| `Escape` | Close the popup | Close the popup |
| Anything else | Ignored | Ignored |

A popup is a session modal: it takes the whole byte stream, not just the keys you
meant for it. An any-key rule would let ambient input close a menu you were still
reading, so unknown keys are dropped and the menu keeps its keymap.

`q` and `Escape` are deliberately different in the expanded row. `q` means "back"
when there is somewhere to go back to, and `Escape` always means "close".

## Both states are 9 lines

The frame does not change height when a row is picked. A menu that reflows under
your fingers is a menu you can mis-press.

| State | Lines |
| --- | --- |
| Menu | 6 boxed (title, 4 rows, bottom) + status + detail + hint |
| OmniRoute | 6 boxed (title, gateway, active combo, up to 3 combos, padding) + blank + hint |

Both draw at 34 columns inside a 35 column popup. The spare column is load-bearing:
a line that exactly fills the terminal leaves it in the pending auto-wrap state, and
the next `ESC[K` wraps the cursor and drags the frame down a row.

The frame is painted in place — cursor home, one `ESC[K` per line, `ESC[J` at the
end — following `scripts/status-dashboard.ps1`. No window, no scroll.

## Where the OmniRoute data comes from

| Fact | Source | Notes |
| --- | --- | --- |
| Gateway UP/DOWN | `netstat -an`, filtered for a `LISTENING` socket on `:20128` | Same detection as the status popup, so the two can never disagree. |
| Active combo | The gateway's SQLite `key_value.settings` | The HTTP settings API exposes no active-combo field on this build (measured 2026-09-25: only `comboStrategy`, `comboConfigMode`, `comboAutoPromoteEnabled`, `hideAutoCombos`). |
| Combo list | `scripts/lib/Get-OmniRouteCombos.ps1` | The same read-only `SELECT` the status popup uses, not a second implementation. |

**No API key is read, printed or written.** The port check and the database read are
started together and collected afterwards, so the frame costs the slower one instead
of their sum.

`combo activo: sin datos` is the honest answer on this build, not a bug to fix. The
menu does not guess and does not draw a value it cannot justify.

## Command line

| Switch | Default | Why it exists |
| --- | --- | --- |
| `-View` | `menu` | Start in `omni` instead. Test hook: `-Once -View omni`. |
| `-Once` | off | Render one frame and exit. Renders from a shell with no popup. |
| `-NoKeyWatch` | off | Render once, then wait out `-MaxSeconds` without reading keys. |
| `-MaxSeconds` | `300` | Hard cap, enforced in every path including a host that cannot report keypresses. |
| `-Width` | `34` | Columns the menu renders for. Lines are clipped one short of it, for the auto-wrap reason above. |

A host that cannot report keypresses (redirected input, no console) ends the loop
instead of spinning to the cap. A menu that cannot take input should not sit on top
of your work until a timer expires.

## Adding a row

One entry in `$script:MenuEntries`, near the top of `scripts/menu/menu.ps1`:

```powershell
@{ Key = "5"; Logo = [string][char]0x2699; Name = "mytool"; Agent = "mytool" }
```

`Agent` is what `pane list` reports for the pane, matched inside the current
workspace. Leave it `""` and the row expands inline instead of focusing a pane.
The key hint is generated from the registry, so nothing else needs editing.

Rules that keep a row honest:

| Rule | Why |
| --- | --- |
| Use `[char]0x…` for glyphs, never literals | Windows PowerShell 5.1 reads a `.ps1` without a BOM as ANSI, so a literal glyph arrives mojibake. |
| Bound every external call | A row that hangs freezes the menu. Use `lib/Invoke-Native.ps1` with an explicit timeout. |
| Never invent a value | A source that fails renders `sin datos`. A failed read is never rendered as an empty configuration. |
| Fail into a status line, not an exception | A dead source must not close a menu the user is looking at. |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Nothing happens when you invoke the action | Another modal already holds the UI | Herdr returns `ui_busy`. Close the other popup. |
| `ui_busy: cerra los popups abiertos` | Row focus was refused because the UI is modal | Press `q`, then retry. This is expected while another popup is up. |
| `no hay pane <agent> en este ws` | That agent is not running here | Open it in this workspace, then retry. |
| `no se pudo saber el workspace` | `herdr pane current` did not answer | Invoke the action from a workspace, not a bare shell. |
| `combo activo: sin datos` | The gateway exposes no active-combo field | Nothing to fix. See above. |
| The popup is wider than the menu | Herdr clamps popups to a minimum size | Cosmetic. The frame draws at 34 columns and stays centred in the pane. |
| The menu closed by itself | Host could not report keypresses, or `-MaxSeconds` elapsed | Both are bounded on purpose. |

## Open question

Whether `herdr agent focus` succeeds while the popup owns input, or returns
`ui_busy`. The menu handles both — it closes on success and prints the reason on
refusal — but the first real E2E settles which one you will actually see.
