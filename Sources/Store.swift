import AppKit
import SwiftUI

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var entries: [AppEntry] = []
    @Published var running: Set<UUID> = []
    @Published var starting: Set<UUID> = []
    @Published var toast: String?
    @Published private(set) var runtimes: [Runtime] = Runtime.installed()
    @Published var experimentalEnabled = Runtime.experimentalEnabled {
        didSet {
            UserDefaults.standard.set(experimentalEnabled, forKey: Runtime.experimentalDefaultsKey)
            refreshRuntimes()
        }
    }

    private var toastTask: Task<Void, Never>?

    /// The default runtime: newest installed one that isn't experimental.
    var newestRuntime: Runtime? { runtimes.first { !$0.experimental } }

    func refreshRuntimes() { runtimes = Runtime.installed() }

    var recents: [AppEntry] {
        entries.sorted { ($0.lastRun ?? $0.added) > ($1.lastRun ?? $1.added) }
    }

    init() { load() }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Paths.store) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([AppEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: Paths.store, options: .atomic)
        } catch {
            flash("Couldn't save your app list: \(error.localizedDescription)")
        }
    }

    // MARK: Library

    @discardableResult
    func add(_ url: URL) -> UUID? {
        guard url.pathExtension.lowercased() == "exe" else {
            flash("\(url.lastPathComponent) isn't a Windows program (.exe)")
            return nil
        }
        let path = url.standardizedFileURL.path
        let direct = Engine.unrealShippingExe(for: url)?.path
        if let existing = entries.first(where: { $0.path == path || $0.path == direct }) {
            flash("\(existing.name) is already in your list")
            return existing.id
        }
        let entry = AppEntry(url: url)
        entries.append(entry)
        save()
        flash("Added \(entry.name)")
        return entry.id
    }

    func update(_ entry: AppEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i] = entry
        save()
    }

    func remove(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let name = entries[i].name
        entries.remove(at: i)
        save()
        flash("Removed \(name) from the list")
    }

    func optimize(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let changes = entries[i].optimize()
        save()
        let name = entries[i].name
        flash(changes.isEmpty ? "\(name) is already optimized" : "\(name): " + changes.joined(separator: ", "))
    }

    func reveal(_ entry: AppEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    func logURL(for entry: AppEntry) -> URL {
        Paths.logs.appendingPathComponent(entry.name.replacingOccurrences(of: "/", with: "-") + ".log")
    }

    func openLog(_ entry: AppEntry) {
        let url = logURL(for: entry)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            flash("No log yet. Play \(entry.name) first.")
        }
    }

    // MARK: Running

    func launch(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[i]
        refreshRuntimes()
        guard let runtime = Runtime.resolve(entry.settings.runtime) else {
            flash("Game Porting Toolkit isn't installed. Run: brew install --cask gcenx/wine/game-porting-toolkit")
            return
        }
        guard FileManager.default.fileExists(atPath: entry.path) else {
            flash("Can't find \(entry.name). Was it moved or deleted?")
            return
        }
        guard !running.contains(id), !starting.contains(id) else {
            flash("\(entry.name) is already running")
            return
        }

        entries[i].lastRun = Date()
        entries[i].runCount += 1
        save()
        starting.insert(id)
        flash(Launcher.prefixExists(for: runtime)
              ? "Starting \(entry.name) with \(runtime.name)…"
              : "Setting up the Windows environment for \(runtime.name). The first launch takes a minute.")

        let log = logURL(for: entry)
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try Launcher.ensurePrefix(using: runtime)
                let process = try Launcher.start(entry, runtime: runtime, log: log)
                await self?.didStart(id)
                process.waitUntilExit()
                await self?.didExit(id, name: entry.name, code: process.terminationStatus)
            } catch {
                await self?.didFail(id, name: entry.name, error: error)
            }
        }
    }

    private func didStart(_ id: UUID) {
        starting.remove(id)
        running.insert(id)
    }

    private func didExit(_ id: UUID, name: String, code: Int32) {
        running.remove(id)
        flash(code == 0 ? "\(name) closed" : "\(name) exited with code \(code). Check its log.")
    }

    private func didFail(_ id: UUID, name: String, error: Error) {
        starting.remove(id)
        running.remove(id)
        flash("Couldn't start \(name): \(error.localizedDescription)")
    }

    func stopAll() {
        // One wineserver per Windows environment, and it must come from the matching Wine build.
        var byPrefix: [URL: Runtime] = [:]
        for runtime in Runtime.installed(includeExperimental: true) where byPrefix[runtime.prefix] == nil {
            byPrefix[runtime.prefix] = runtime
        }
        guard !byPrefix.isEmpty else { return }
        flash("Stopping all Windows apps…")
        Task.detached {
            for runtime in byPrefix.values { try? Launcher.runAndWait(runtime.wineserver, ["-k"], runtime: runtime) }
        }
    }

    // MARK: Toast

    func flash(_ message: String) {
        withAnimation(.spring(duration: 0.35)) { toast = message }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }
}
