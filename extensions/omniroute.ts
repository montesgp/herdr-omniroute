/**
 * OmniRoute gateway extension for pi — layer-exterior personalization.
 * Slash /omniroute [status|start|dashboard], footer status, post-call warning.
 * Survives pi/gentle-pi updates: lives in the user extensions dir only.
 */
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent"
import net from "node:net"
import { spawn } from "node:child_process"

const PORT = 20128
const NODE = "C:\\Users\\patri\\scoop\\persist\\fnm\\node-versions\\v22.22.3\\installation\\node.exe"
const ENTRY = "C:\\Users\\patri\\node_modules\\omniroute\\bin\\omniroute.mjs"

function checkPort(port: number, timeoutMs = 1500): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = net.connect({ host: "127.0.0.1", port }, () => { socket.destroy(); resolve(true) })
    socket.on("error", () => resolve(false))
    socket.setTimeout(timeoutMs, () => { socket.destroy(); resolve(false) })
  })
}

async function startGateway(): Promise<boolean> {
  if (await checkPort(PORT)) return true
  return new Promise((resolve) => {
    const child = spawn(NODE, [ENTRY, "serve", "--daemon", "--no-open"], {
      detached: true,
      stdio: "ignore",
      windowsHide: true,
    })
    child.on("error", () => resolve(false))
    child.unref()
    resolve(true)
  })
}

export default function (api: ExtensionAPI) {
  api.registerCommand("omniroute", {
    description: "OmniRoute gateway: status, start, dashboard",
    handler: async (args: string | undefined, ctx: ExtensionCommandContext) => {
      const action = (args ?? "").trim().toLowerCase()
      const up = await checkPort(PORT)
      if (action === "start") {
        if (up) { await ctx.ui.notify(`OmniRoute already UP on :${PORT}`, "info") }
        else { await startGateway(); await ctx.ui.notify(`Starting OmniRoute on :${PORT} - recheck in ~15s`, "info") }
        return
      }
      if (action === "dashboard") {
        await api.exec("cmd", ["/c", "start", `http://localhost:${PORT}`])
        return
      }
      await ctx.ui.setStatus("omniroute", up ? `OmniRoute ● :${PORT}` : `OmniRoute ○ :${PORT}`)
      await ctx.ui.notify(up ? `OmniRoute UP on :${PORT}` : `OmniRoute DOWN on :${PORT}`, up ? "info" : "warning")
    },
  })

  api.on("session_start", async (ctx) => {
    const up = await checkPort(PORT)
    await ctx.ui.setStatus("omniroute", up ? `OmniRoute ● :${PORT}` : `OmniRoute ○ :${PORT}`)
  })

  api.on("after_provider_response", async (ctx, event: unknown) => {
    const status = (event as { status?: number } | null)?.status
    if (typeof status === "number" && status >= 400) {
      await ctx.ui.notify(`Provider responded ${status} - OmniRoute gateway may be down (check /omniroute)`, "warning")
    }
  })
}
