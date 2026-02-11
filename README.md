# DevServers

macOS menu bar utility that detects running dev servers and lets you open or kill them with one click.

![menu bar](https://img.shields.io/badge/macOS-menu%20bar-blue) ![swift](https://img.shields.io/badge/Swift-single%20file-orange)

## What it does

- Polls every 5 seconds for processes listening on TCP ports
- Classifies them as dev servers using two tiers:
  - **Tier 1**: Pattern matches against 30+ known frameworks (Next.js, Vite, Flask, Django, Rails, Hugo, etc.)
  - **Tier 2**: Known runtimes (node, python, ruby, go, bun, deno) on common dev ports (3000, 5173, 8000, 8080, etc.)
- Shows a `>_` icon with a count in the menu bar
- Each server expands to **Open in Browser** or **Kill**
- "Kill All" option when multiple servers are running
- Launch at Login toggle (uses LaunchAgent)

## Supported frameworks

Next.js, Vite, Webpack, React Scripts, Angular, Nuxt, SvelteKit, Remix, Astro, Parcel, Turbopack, esbuild, Flask, Django, Uvicorn, Gunicorn, FastAPI, Python http.server, Rails, Puma, Hugo, Jekyll, Gatsby, Eleventy, PHP built-in server, Air (Go), Cargo Watch, live-server, http-server, Bun, Deno, NestJS, Nodemon, ts-node/tsx

## Install

### From DMG

Download `DevServers.dmg` from [Releases](../../releases), open it, and drag `DevServers.app` to Applications.

Since the app isn't signed, right-click > **Open** the first time.

### Build from source

```bash
git clone https://github.com/raidalt/DevServers.git
cd DevServers
swiftc -o DevServers.app/Contents/MacOS/DevServers main.swift -framework Cocoa
open DevServers.app
```

### Build DMG

```bash
mkdir -p /tmp/DevServers-dmg
cp -R DevServers.app /tmp/DevServers-dmg/
ln -s /Applications /tmp/DevServers-dmg/Applications
hdiutil create -volname "DevServers" -srcfolder /tmp/DevServers-dmg -ov -format UDZO DevServers.dmg
```

## How it works

Single-file Swift app (`main.swift`) using AppKit. No Xcode project, no SwiftUI, no dependencies.

1. Runs `lsof -iTCP -sTCP:LISTEN -nP -F pcn` to find listening processes
2. Runs `ps` to get full command lines
3. Classifies via pattern matching
4. Kills with `SIGTERM`, then `SIGKILL` after 3s if still alive (direct syscall, no shelling out)
