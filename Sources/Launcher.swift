import Foundation

/// Builds and starts Wine (Game Porting Toolkit) processes. Safe to call off the main thread.
enum Launcher {
    /// Variables the app manages; inherited values are cleared so settings always win.
    private static let managedKeys = ["WINEMSYNC", "WINEESYNC", "ROSETTA_ADVERTISE_AVX", "MTL_HUD_ENABLED", "WINEDEBUG",
                                      "D3DM_ENABLE_METALFX", "D3DM_MAX_FPS", "D3DM_MTL4", "D3DM_SUPPORT_DXR",
                                      "DYLD_FALLBACK_LIBRARY_PATH", "CX_ACTIVE_GRAPHICS_BACKEND"]

    static func environment(for e: AppEntry, runtime: Runtime?) -> [String: String] {
        let s = e.settings
        var env = runtime?.baseEnvironment ?? ["WINEPREFIX": Paths.prefix.path]
        env["WINEDEBUG"] = s.verboseLog ? "err+all,warn+seh" : "-all"
        switch s.sync {
        case .msync: env["WINEMSYNC"] = "1"
        case .esync: env["WINEESYNC"] = "1"
        case .off: break
        }
        if s.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }
        if s.hud { env["MTL_HUD_ENABLED"] = "1" }
        // D3DMetal translates the game's DLSS calls to MetalFX upscaling / frame interpolation.
        if s.metalFX { env["D3DM_ENABLE_METALFX"] = "1" }
        // GPTK 4.0+: frame cap, Metal 4 backend (on by default on macOS 27), DirectX ray tracing.
        if let fps = Int(s.maxFPS), fps > 0 { env["D3DM_MAX_FPS"] = "\(fps)" }
        if !s.metal4 { env["D3DM_MTL4"] = "0" }
        if s.raytracing { env["D3DM_SUPPORT_DXR"] = "1" }
        for line in s.extraEnv.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
            env[String(t[..<eq])] = String(t[t.index(after: eq)...])
        }
        return env
    }

    static func arguments(for e: AppEntry) -> [String] {
        let s = e.settings
        var args: [String] = []
        let res = Int(s.resWidth).flatMap { w in Int(s.resHeight).map { (w, $0) } }
        switch e.engine {
        case .unreal:
            if s.windowMode == .windowed { args.append("-windowed") }
            if s.windowMode == .fullscreen { args.append("-fullscreen") }
            if let (w, h) = res { args += ["-ResX=\(w)", "-ResY=\(h)"] }
        case .unity:
            if s.windowMode == .windowed { args += ["-screen-fullscreen", "0"] }
            if s.windowMode == .fullscreen { args += ["-screen-fullscreen", "1"] }
            if let (w, h) = res { args += ["-screen-width", "\(w)", "-screen-height", "\(h)"] }
        case .generic:
            break
        }
        return args + splitArgs(s.extraArgs)
    }

    static func commandPreview(for e: AppEntry) -> String {
        let runtime = Runtime.resolve(e.settings.runtime)
        let hidden: Set = ["WINEPREFIX", "DYLD_FALLBACK_LIBRARY_PATH", "CX_ACTIVE_GRAPHICS_BACKEND"]
        let env = environment(for: e, runtime: runtime)
            .filter { !hidden.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        let args = arguments(for: e).map { $0.contains(" ") ? "\"\($0)\"" : $0 }
        let loader = runtime.map { URL(fileURLWithPath: $0.wine).lastPathComponent } ?? "wine64"
        var preview = "# \(runtime?.name ?? "no Game Porting Toolkit installed")"
        if let runtime { preview += " · \(runtime.prefix.path.replacingOccurrences(of: Paths.home.path, with: "~"))" }
        preview += "\n" + (env + [loader, e.url.lastPathComponent] + args).joined(separator: " ")
        if e.engine == .unreal, !e.settings.upscaling.cvarLines.isEmpty {
            preview += "\n\nEngine.ini [SystemSettings]:\n" + e.settings.upscaling.cvarLines.joined(separator: "\n")
        }
        return preview
    }

    /// Splits on whitespace, keeping "quoted strings" together.
    static func splitArgs(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        var hasToken = false
        for ch in s {
            if ch == "\"" {
                inQuotes.toggle()
                hasToken = true
            } else if ch.isWhitespace && !inQuotes {
                if hasToken { out.append(cur) }
                cur = ""
                hasToken = false
            } else {
                cur.append(ch)
                hasToken = true
            }
        }
        if hasToken { out.append(cur) }
        return out
    }

    static func prefixExists(for runtime: Runtime) -> Bool {
        FileManager.default.fileExists(atPath: runtime.prefix.appendingPathComponent("system.reg").path)
    }

    /// Creates the runtime's Windows environment on first use. Blocks until done.
    static func ensurePrefix(using runtime: Runtime) throws {
        guard !prefixExists(for: runtime) else { return }
        try FileManager.default.createDirectory(at: runtime.prefix, withIntermediateDirectories: true)
        // Without these overrides, newer Wine stops setup on dialogs offering to download Wine Mono
        // and Gecko, waiting for a click. Games here don't need either.
        try runAndWait(runtime.wine, ["wineboot", "--init"], runtime: runtime, extraEnvironment: ["WINEDLLOVERRIDES": "mscoree,mshtml="])
        try runAndWait(runtime.wineserver, ["-w"], runtime: runtime)
        if runtime.prefix != Paths.prefix { copyGameData(into: runtime.prefix) }
    }

    /// Brings game saves and settings (C:\users\<user>\AppData\Local\<Game>) from the main Windows
    /// environment into a newly created one. Folders that already exist are left alone.
    static func copyGameData(into prefix: URL) {
        let fm = FileManager.default
        func localAppData(_ prefix: URL) -> URL? {
            let users = prefix.appendingPathComponent("drive_c/users")
            let names = ((try? fm.contentsOfDirectory(atPath: users.path)) ?? []).filter { $0 != "Public" && !$0.hasPrefix(".") }
            guard let user = names.contains("crossover") ? "crossover" : names.first else { return nil }
            return users.appendingPathComponent("\(user)/AppData/Local")
        }
        guard let from = localAppData(Paths.prefix), let to = localAppData(prefix) else { return }
        for game in (try? fm.contentsOfDirectory(atPath: from.path)) ?? [] where !game.hasPrefix(".") {
            let target = to.appendingPathComponent(game)
            guard !fm.fileExists(atPath: target.path) else { continue }
            try? fm.copyItem(at: from.appendingPathComponent(game), to: target)
        }
    }

    /// D3DMetal's Windows-side DLLs. Wine loads these from C:\windows\system32 (copied there when the
    /// prefix was created), not from the runtime, and Apple's Read Me has nvngx.dll / nvapi64.dll
    /// placed there for MetalFX. Before each launch they're matched to the runtime being used, so the
    /// Windows and Mac halves of the graphics layer always come from the same GPTK version.
    private static let graphicsDLLs = ["d3d10.dll", "d3d10_1.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll",
                                       "d3d12core.dll", "dxgi.dll", "nvapi64.dll", "nvngx.dll"]

    static func syncGraphicsDLLs(from runtime: Runtime) throws {
        let fm = FileManager.default
        let source = runtime.wineDir.appendingPathComponent("lib/wine/x86_64-windows")
        let system32 = runtime.prefix.appendingPathComponent("drive_c/windows/system32")
        for dll in graphicsDLLs {
            let from = source.appendingPathComponent(dll)
            let to = system32.appendingPathComponent(dll)
            if !fm.fileExists(atPath: from.path) {
                // Only newer runtimes ship this DLL; leaving a newer copy behind would mix versions.
                try? fm.removeItem(at: to)
                continue
            }
            guard !fm.contentsEqual(atPath: from.path, andPath: to.path) else { continue }
            try? fm.removeItem(at: to)
            try fm.copyItem(at: from, to: to)
        }
    }

    static func runAndWait(_ exe: String, _ args: [String], runtime: Runtime,
                           extraEnvironment: [String: String] = [:]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env.merge(runtime.baseEnvironment) { _, new in new }
        env.merge(extraEnvironment) { _, new in new }
        env["WINEDEBUG"] = "-all"
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
    }

    static func start(_ e: AppEntry, runtime: Runtime, log: URL) throws -> Process {
        try UnrealConfig.apply(e, prefix: runtime.prefix)
        try syncGraphicsDLLs(from: runtime)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: runtime.wine)
        p.arguments = [e.path] + arguments(for: e)
        // Games load their data relative to their own folder.
        p.currentDirectoryURL = e.url.deletingLastPathComponent()

        var env = ProcessInfo.processInfo.environment
        for key in managedKeys { env.removeValue(forKey: key) }
        env.merge(environment(for: e, runtime: runtime)) { _, new in new }
        p.environment = env

        try FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        p.standardOutput = handle
        p.standardError = handle

        try p.run()
        return p
    }
}

/// Writes the render-scale settings into an Unreal game's Engine.ini inside the Wine prefix.
/// Unreal reads [SystemSettings] there even in shipping builds, and it outranks the game's own
/// scalability settings.
enum UnrealConfig {
    private static let managedKeys = UpscaleMode.performance.cvarLines.map { String($0.prefix { $0 != "=" }) }

    struct UnreadableConfig: LocalizedError {
        let url: URL
        var errorDescription: String? { "\(url.lastPathComponent) isn't a readable text file, so it was left alone" }
    }

    static func apply(_ e: AppEntry, prefix: URL) throws {
        guard e.engine == .unreal else { return }
        let lines = e.settings.upscaling.cvarLines
        let fm = FileManager.default
        for ini in engineInis(for: e, prefix: prefix) {
            let exists = fm.fileExists(atPath: ini.path)
            if !exists && lines.isEmpty { continue }
            let current = exists ? try? String(contentsOf: ini, encoding: .utf8) : ""
            guard let current else { throw UnreadableConfig(url: ini) }
            let updated = rewrite(current, with: lines)
            guard updated != current else { continue }
            try fm.createDirectory(at: ini.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updated.write(to: ini, atomically: true, encoding: .utf8)
        }
    }

    /// Unreal stores per-user config at
    /// C:\users\<user>\AppData\Local\<Project>\Saved\Config\Windows (UE5) or WindowsNoEditor (UE4).
    static func engineInis(for e: AppEntry, prefix: URL) -> [URL] {
        let fm = FileManager.default
        let users = prefix.appendingPathComponent("drive_c/users")
        let names = ((try? fm.contentsOfDirectory(atPath: users.path)) ?? []).filter { $0 != "Public" && !$0.hasPrefix(".") }
        guard let user = names.contains("crossover") ? "crossover" : names.first else { return [] }
        let config = users.appendingPathComponent("\(user)/AppData/Local/\(projectName(for: e.url))/Saved/Config")

        var dirs = [config.appendingPathComponent("Windows")]
        let legacy = config.appendingPathComponent("WindowsNoEditor")
        if fm.fileExists(atPath: legacy.path) { dirs.append(legacy) }
        return dirs.map { $0.appendingPathComponent("Engine.ini") }
    }

    /// Game.exe -> "Game"; Game/Binaries/Win64/Game-Win64-Shipping.exe -> "Game".
    static func projectName(for exe: URL) -> String {
        let stem = exe.deletingPathExtension().lastPathComponent
        guard stem.hasSuffix("-Shipping") else { return stem }
        return exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
    }

    /// Replaces the managed keys in [SystemSettings] with `lines`, leaving everything else untouched.
    static func rewrite(_ text: String, with lines: [String]) -> String {
        var out: [String] = []
        var inSystemSettings = false
        var inserted = false
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") {
                inSystemSettings = line.caseInsensitiveCompare("[SystemSettings]") == .orderedSame
                out.append(raw)
                if inSystemSettings && !inserted {
                    out += lines
                    inserted = true
                }
                continue
            }
            if inSystemSettings {
                let key = line.prefix { $0 != "=" }.trimmingCharacters(in: .whitespaces)
                if managedKeys.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) { continue }
            }
            out.append(raw)
        }
        if !inserted && !lines.isEmpty {
            while out.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "" { out.removeLast() }
            if !out.isEmpty { out.append("") }
            out.append("[SystemSettings]")
            out += lines
        }
        var result = out.joined(separator: "\n")
        // Byte check: Swift treats "\r\n" as one Character, so hasSuffix("\n") misses CRLF files.
        if !result.isEmpty && result.utf8.last != UInt8(ascii: "\n") { result += "\n" }
        return result
    }
}
