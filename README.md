# Perch

macOS menu bar utility that detects running dev servers and lets you open, inspect, or kill them with one click.

![menu bar](https://img.shields.io/badge/macOS-menu%20bar-blue) ![swift](https://img.shields.io/badge/Swift-AppKit-orange)

## What it does

- Polls every 5 seconds for processes listening on TCP ports
- Classifies them as dev servers using two tiers:
  - **Tier 1**: Pattern matches against 30+ known frameworks (Next.js, Vite, Flask, Django, Rails, Hugo, etc.)
  - **Tier 2**: Known runtimes (node, python, ruby, go, bun, deno) on common dev ports (3000, 5173, 8000, 8080, etc.)
- Shows a `>_` icon with a count in the menu bar
- Distinguishes apps by project name (for example `vercel` vs `vercel-site`)
- Each server submenu includes:
  - **Open in Browser**
  - **Open in Finder**
  - **Open in Terminal** (supports Ghostty and configurable terminal choice)
  - **Open in Editor** (auto-detected or configurable)
  - Full project path
  - **Kill**
- "Kill All" option when multiple servers are running
- Launch at Login toggle (uses LaunchAgent)
- Preferences window for terminal/editor configuration

## Supported frameworks

Next.js, Vite, Webpack, React Scripts, Angular, Nuxt, SvelteKit, Remix, Astro, Parcel, Turbopack, esbuild, Flask, Django, Uvicorn, Gunicorn, FastAPI, Python http.server, Rails, Puma, Hugo, Jekyll, Gatsby, Eleventy, PHP built-in server, Air (Go), Cargo Watch, live-server, http-server, Bun, Deno, NestJS, Nodemon, ts-node/tsx

## Install

### From DMG

1. Download `Perch.dmg` from [Releases](../../releases)
2. Open it and drag `Perch.app` to Applications
3. Open Terminal and run:
   ```bash
   xattr -cr /Applications/Perch.app
   ```
4. Double-click Perch in Applications

Step 3 removes the macOS quarantine flag. This is needed because the app isn't notarized with Apple. You only need to do this once.

**If you skip step 3** and macOS blocks the app: go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway** next to the Perch message.

After the first launch, updates are delivered automatically through the app menu — no re-downloading needed.

### Build from source

```bash
git clone https://github.com/raidalt/Perch.git
cd Perch
SOURCES=$(find Sources -name '*.swift' | sort)
swiftc -target arm64-apple-macos12.0 -o /tmp/Perch-arm64 main.swift $SOURCES -framework Cocoa -framework Carbon
swiftc -target x86_64-apple-macos12.0 -o /tmp/Perch-x86_64 main.swift $SOURCES -framework Cocoa -framework Carbon
lipo -create /tmp/Perch-arm64 /tmp/Perch-x86_64 -output Perch.app/Contents/MacOS/Perch
codesign --force --deep --sign - Perch.app
open Perch.app
```

## How it works

Modular AppKit Swift app with `main.swift` entrypoint and componentized sources under `Sources/Perch`. No Xcode project, no SwiftUI, no dependencies.

1. Runs `lsof -iTCP -sTCP:LISTEN -nP -F pcn` to find listening processes
2. Runs `ps` to get full command lines
3. Classifies via pattern matching
4. Kills with `SIGTERM`, then `SIGKILL` after 3s if still alive (direct syscall, no shelling out)
