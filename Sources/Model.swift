import Foundation

// MARK: - Paths

enum Paths {
    static let gptkApp = "/Applications/Game Porting Toolkit.app"

    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let prefix = home.appendingPathComponent("Games/GPTK-Prefix")
    static let experimentalPrefix = home.appendingPathComponent("Games/GPTK-Prefix-Experimental")
    static let support = home.appendingPathComponent("Library/Application Support/Windows App Runner")
    static let store = support.appendingPathComponent("apps.json")
    static let logs = home.appendingPathComponent("Library/Logs/Windows App Runner")
    static let runtimes = support.appendingPathComponent("Runtimes")
}

// MARK: - Runtimes

/// A Wine + D3DMetal build: the Homebrew Game Porting Toolkit.app, or one installed from an Apple
/// DMG by install-gptk-runtime.sh into ~/Library/Application Support/Windows App Runner/Runtimes.
struct Runtime: Identifiable, Hashable {
    static let homebrewID = "homebrew"
    static let experimentalDefaultsKey = "experimentalRuntimes"

    let id: String
    let version: String
    let wineDir: URL
    /// Built on a different (newer) Wine than the Homebrew toolkit; hidden unless enabled in Settings.
    var experimental = false

    var name: String {
        if id == Runtime.homebrewID { return "GPTK \(version) (Homebrew)" }
        return experimental ? "GPTK \(version) (Experimental)" : "GPTK \(version)"
    }
    /// Older Wine builds have a separate 64-bit loader; Wine 9+ has a single `wine`.
    var wine: String {
        let wine64 = wineDir.appendingPathComponent("bin/wine64").path
        return FileManager.default.isExecutableFile(atPath: wine64) ? wine64 : wineDir.appendingPathComponent("bin/wine").path
    }
    var wineserver: String { wineDir.appendingPathComponent("bin/wineserver").path }
    /// Description of the Wine this runtime is built on, recorded by install-gptk-runtime.sh.
    var baseWine: String? {
        let file = wineDir.deletingLastPathComponent().appendingPathComponent("BASE")
        return (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var majorVersion: Int { Int(version.prefix { $0.isNumber }) ?? 0 }

    /// Experimental runtimes run a newer Wine that would upgrade a Windows environment in place,
    /// so they get their own and never touch the stable one.
    var prefix: URL { experimental ? Paths.experimentalPrefix : Paths.prefix }

    /// Environment every launch with this runtime needs.
    var baseEnvironment: [String: String] {
        [
            "WINEPREFIX": prefix.path,
            // Libraries bundled with the runtime (FreeType, GnuTLS, SDL2) are dlopen'ed by name.
            "DYLD_FALLBACK_LIBRARY_PATH": wineDir.appendingPathComponent("lib").path + ":/usr/lib",
            // CrossOver's Wine reports the GPU scheduling caps D3DMetal expects (CW HACK 24905).
            "CX_ACTIVE_GRAPHICS_BACKEND": "d3dmetal",
        ]
    }

    static var experimentalEnabled: Bool { UserDefaults.standard.bool(forKey: experimentalDefaultsKey) }

    /// Newest first. Experimental runtimes are included only when enabled in Settings.
    static func installed(includeExperimental: Bool = experimentalEnabled) -> [Runtime] {
        let fm = FileManager.default
        var found: [Runtime] = []

        let homebrew = URL(fileURLWithPath: Paths.gptkApp + "/Contents/Resources/wine")
        if fm.isExecutableFile(atPath: homebrew.appendingPathComponent("bin/wine64").path) {
            found.append(Runtime(id: homebrewID, version: homebrewVersion(), wineDir: homebrew))
        }

        for folder in (try? fm.contentsOfDirectory(atPath: Paths.runtimes.path)) ?? [] where !folder.hasSuffix(".partial") {
            let base = Paths.runtimes.appendingPathComponent(folder)
            let wine = base.appendingPathComponent("wine")
            let bin = wine.appendingPathComponent("bin")
            guard fm.isExecutableFile(atPath: bin.appendingPathComponent("wine64").path)
                    || fm.isExecutableFile(atPath: bin.appendingPathComponent("wine").path) else { continue }
            let experimental = fm.fileExists(atPath: base.appendingPathComponent("EXPERIMENTAL").path)
            guard includeExperimental || !experimental else { continue }
            let version = (try? String(contentsOf: base.appendingPathComponent("VERSION"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? folder
            found.append(Runtime(id: folder, version: version, wineDir: wine, experimental: experimental))
        }
        return found.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    /// Every installed experimental runtime, regardless of the Settings switch.
    static var installedExperimental: [Runtime] { installed(includeExperimental: true).filter(\.experimental) }

    /// The cask version from /opt/homebrew/Caskroom/game-porting-toolkit/<version>, e.g. "3.0-3" -> "3.0".
    private static func homebrewVersion() -> String {
        let caskroom = "/opt/homebrew/Caskroom/game-porting-toolkit"
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: caskroom)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        return versions.last.map { String($0.prefix { $0 != "-" }) } ?? "3.0"
    }

    /// The chosen runtime, or the newest stable one when `id` is empty, no longer installed, or an
    /// experimental runtime while experimental runtimes are switched off.
    static func resolve(_ id: String) -> Runtime? {
        let all = installed()
        return all.first { $0.id == id } ?? all.first { !$0.experimental }
    }
}

// MARK: - Settings

enum SyncMode: String, Codable, CaseIterable, Identifiable {
    case msync, esync, off
    var id: Self { self }
    var label: String {
        switch self {
        case .msync: "MSync"
        case .esync: "ESync"
        case .off: "Off"
        }
    }
}

enum WindowMode: String, Codable, CaseIterable, Identifiable {
    case auto, windowed, fullscreen
    var id: Self { self }
    var label: String {
        switch self {
        case .auto: "Game default"
        case .windowed: "Windowed"
        case .fullscreen: "Fullscreen"
        }
    }
}

/// Fixed render scale for Unreal games, upscaled with Unreal's TSR (its built-in FSR 2 equivalent).
/// Percentages follow FSR's quality-mode names.
enum UpscaleMode: String, Codable, CaseIterable, Identifiable {
    case off, quality, balanced, performance, ultraPerformance
    var id: Self { self }

    var percent: Int? {
        switch self {
        case .off: nil
        case .quality: 77
        case .balanced: 67
        case .performance: 50
        case .ultraPerformance: 33
        }
    }

    var label: String {
        switch self {
        case .off: "Off (game default)"
        case .quality: "Quality · 77%"
        case .balanced: "Balanced · 67%"
        case .performance: "Performance · 50%"
        case .ultraPerformance: "Ultra Performance · 33%"
        }
    }

    /// Lines written to [SystemSettings] in the game's Engine.ini.
    var cvarLines: [String] {
        guard let percent else { return [] }
        return [
            "r.ScreenPercentage=\(percent)",
            "r.AntiAliasingMethod=4",          // TSR
            "r.Tonemapper.Sharpen=0.5",        // light sharpening, like FSR's RCAS pass
            "r.DynamicRes.OperationMode=0",    // dynamic resolution would override a fixed scale
        ]
    }
}

struct AppSettings: Codable, Equatable {
    var runtime = ""            // Runtime.id; empty = newest installed
    var upscaling: UpscaleMode = .off
    var metalFX = false
    var maxFPS = ""
    var metal4 = true
    var raytracing = false
    var hud = false
    var advertiseAVX = true
    var sync: SyncMode = .msync
    var verboseLog = false
    var windowMode: WindowMode = .auto
    var resWidth = ""
    var resHeight = ""
    var extraArgs = ""
    var extraEnv = ""

    init() {}

    // Tolerate missing keys so settings saved by older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        runtime = try c.decodeIfPresent(String.self, forKey: .runtime) ?? d.runtime
        upscaling = try c.decodeIfPresent(UpscaleMode.self, forKey: .upscaling) ?? d.upscaling
        metalFX = try c.decodeIfPresent(Bool.self, forKey: .metalFX) ?? d.metalFX
        maxFPS = try c.decodeIfPresent(String.self, forKey: .maxFPS) ?? d.maxFPS
        metal4 = try c.decodeIfPresent(Bool.self, forKey: .metal4) ?? d.metal4
        raytracing = try c.decodeIfPresent(Bool.self, forKey: .raytracing) ?? d.raytracing
        hud = try c.decodeIfPresent(Bool.self, forKey: .hud) ?? d.hud
        advertiseAVX = try c.decodeIfPresent(Bool.self, forKey: .advertiseAVX) ?? d.advertiseAVX
        sync = try c.decodeIfPresent(SyncMode.self, forKey: .sync) ?? d.sync
        verboseLog = try c.decodeIfPresent(Bool.self, forKey: .verboseLog) ?? d.verboseLog
        windowMode = try c.decodeIfPresent(WindowMode.self, forKey: .windowMode) ?? d.windowMode
        resWidth = try c.decodeIfPresent(String.self, forKey: .resWidth) ?? d.resWidth
        resHeight = try c.decodeIfPresent(String.self, forKey: .resHeight) ?? d.resHeight
        extraArgs = try c.decodeIfPresent(String.self, forKey: .extraArgs) ?? d.extraArgs
        extraEnv = try c.decodeIfPresent(String.self, forKey: .extraEnv) ?? d.extraEnv
    }
}

// MARK: - Engine detection

enum Engine: String, Codable {
    case unreal, unity, generic

    var label: String {
        switch self {
        case .unreal: "Unreal Engine"
        case .unity: "Unity"
        case .generic: "Windows app"
        }
    }

    static func detect(_ exe: URL) -> Engine {
        let fm = FileManager.default
        let dir = exe.deletingLastPathComponent()
        let stem = exe.deletingPathExtension().lastPathComponent
        if stem.hasSuffix("-Shipping")
            || fm.fileExists(atPath: dir.appendingPathComponent("Engine").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("../../../Engine").standardized.path) {
            return .unreal
        }
        if fm.fileExists(atPath: dir.appendingPathComponent("UnityPlayer.dll").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("\(stem)_Data").path) {
            return .unity
        }
        return .generic
    }

    /// For an Unreal bootstrap exe (Game.exe), the real game binary it starts:
    /// Game/Binaries/Win64/Game-Win64-Shipping.exe.
    static func unrealShippingExe(for exe: URL) -> URL? {
        let stem = exe.deletingPathExtension().lastPathComponent
        guard !stem.hasSuffix("-Shipping") else { return nil }
        let candidate = exe.deletingLastPathComponent()
            .appendingPathComponent("\(stem)/Binaries/Win64/\(stem)-Win64-Shipping.exe")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}

// MARK: - Library entry

struct AppEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String
    var name: String
    var engine: Engine
    var added = Date()
    var lastRun: Date?
    var runCount = 0
    var settings = AppSettings()

    init(url: URL) {
        path = url.standardizedFileURL.path
        name = AppEntry.prettyName(for: url)
        engine = Engine.detect(url)
    }

    var url: URL { URL(fileURLWithPath: path) }

    /// "MovieNight-Win64-Shipping.exe" -> "Movie Night"
    static func prettyName(for exe: URL) -> String {
        var stem = exe.deletingPathExtension().lastPathComponent
        for suffix in ["-Win64-Shipping", "-Win64-Test", "-Win64"] where stem.hasSuffix(suffix) {
            stem.removeLast(suffix.count)
            break
        }
        var out = ""
        var prev: Character?
        for ch in stem {
            if ch == "_" || ch == "-" {
                out.append(" ")
                prev = " "
                continue
            }
            if let p = prev, ch.isUppercase, p.isLowercase { out.append(" ") }
            out.append(ch)
            prev = ch
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Applies the recommended preset and returns what changed.
    mutating func optimize() -> [String] {
        var changes: [String] = []
        if !settings.advertiseAVX {
            settings.advertiseAVX = true
            changes.append("enabled AVX for Rosetta")
        }
        if settings.sync != .msync {
            settings.sync = .msync
            changes.append("switched to MSync, the fastest thread sync")
        }
        if settings.hud {
            settings.hud = false
            changes.append("hid the performance HUD")
        }
        if settings.verboseLog {
            settings.verboseLog = false
            changes.append("turned off verbose logging, which slows games down")
        }
        if engine == .unreal, let direct = Engine.unrealShippingExe(for: url) {
            path = direct.path
            changes.append("now starts the game directly, skipping Unreal's prerequisite check")
        }
        return changes
    }
}
