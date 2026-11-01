# Windows App Runner

A small native macOS launcher for running Windows games and apps through Apple's **Game Porting Toolkit** (Wine + D3DMetal) on Apple Silicon.

Drop an `.exe` on the window (or the Dock icon), and it's remembered with its own settings, ready to launch with one click.

## Features

- **Library of Windows apps** — drag-and-drop `.exe` files; each keeps its own name, settings and last-run time. Opening an `.exe` with the app adds and launches it.
- **Engine detection** — recognises Unreal Engine and Unity games and passes the right launch options (resolution, window mode, upscaling cvars).
- **Auto-Optimize** — one click applies sensible defaults for the detected engine.
- **Per-app settings**
  - GPTK runtime / version picker (Homebrew toolkit or runtimes installed from Apple's DMGs)
  - Frame-rate cap, Metal 4 backend, DirectX ray tracing (DXR), AVX advertising to Rosetta
  - Thread sync: MSync / ESync / off
  - Render scale (TSR upscaling) and MetalFX for DLSS games
  - Window mode and resolution
  - Extra launch arguments and environment variables
  - Metal performance HUD and verbose logging, with per-app logs
- **Experimental runtimes** — newer Wine builds run in their own Windows environment so they never touch the stable one.

## Requirements

- Apple Silicon Mac, macOS 14 Sonoma or later
- Rosetta 2
- The Homebrew Game Porting Toolkit:
  ```sh
  brew install --cask gcenx/wine/game-porting-toolkit
  ```

The Windows environment lives in `~/Games/GPTK-Prefix`; app list and runtimes in `~/Library/Application Support/Windows App Runner`; logs in `~/Library/Logs/Windows App Runner`.

## Install

Download the latest zip from [Releases](../../releases), unzip it and move **Windows App Runner.app** to `/Applications` (or `~/Applications`).

The app is ad-hoc signed, not notarised, so macOS will block the first launch. Either right-click → **Open**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/Windows App Runner.app"
```

## Build from source

Needs the Xcode Command Line Tools.

```sh
./build.sh      # builds and installs to ~/Applications
./package.sh    # builds a release zip into dist/
```

## Extra runtimes (optional)

- `install-gptk-runtime.sh` — installs D3DMetal from one of Apple's Game Porting Toolkit DMGs as an additional runtime (e.g. GPTK 4.0 betas). See the header of the script for options (`--experimental`, `--base`).
- `build-crossover-wine.sh` — builds Wine from CodeWeavers' published CrossOver sources as a newer base for GPTK 4.0+.

## Releasing

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, then push a matching tag:

```sh
git tag v2.1 && git push origin v2.1
```

GitHub Actions builds the app on a macOS runner and attaches the zip to the release.
