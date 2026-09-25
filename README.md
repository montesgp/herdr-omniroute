# herdr-omniroute

Status, start and dashboard actions for the [OmniRoute](https://github.com/montesgp/omniroute)
auto-fallback gateway, which listens on `localhost:20128` and routes agent traffic
to a combo of providers so an exhausted token never kills a session.

## Install

Local development (link the working directory):

```bash
herdr plugin link C:\repositories\personal\herdr-omniroute
```

Once published on GitHub:

```bash
herdr plugin install montesgp/herdr-omniroute
```

Linking and installing both work without a running Herdr server.

## Actions

| Action | Command | Behavior |
| --- | --- | --- |
| `herdr.omniroute.status` | `scripts/status.ps1` | Reports whether port 20128 is listening. Exit 0 = up, exit 1 = down. |
| `herdr.omniroute.start` | `scripts/start.ps1` | No-op when the gateway is already up; otherwise launches `omniroute serve --daemon --no-open`. |
| `herdr.omniroute.dashboard` | `scripts/dashboard.ps1` | Opens `http://localhost:20128` in the default browser. |

Actions are declared for the `workspace` context, so they show up in a workspace's
action list.

## Keybinding

Suggested binding in `%APPDATA%\herdr\config.toml`:

```toml
[[keys.command]]
key = "prefix+o"
type = "plugin_action"
command = "herdr.omniroute.status"
```

## Scope and lifetime

- **User-global by design.** Herdr plugins are per-user, not per-project: once linked
  or installed, the actions are available in every Herdr session.
- **The gateway runs headless.** A Windows scheduled task named `OmniRouteGateway`
  starts it at logon with `serve --daemon --no-open`, retries 3 times at a
  1-minute interval on failure, and has no execution time limit. No browser opens.
- **Personalization lives only in user files.** This repo holds the plugin scripts
  and a pi extension; provider, combo and token configuration stays in
  OmniRoute's own storage and in the user's Herdr/pi config directories. Nothing
  here writes into a tool's install directory, so plugin or agent updates do not
  break it.

## Requirements

- Windows
- Herdr 0.7.0 or newer
- OmniRoute reachable at `http://localhost:20128` (see the scheduled task above)
