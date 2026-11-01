import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: Store
    @StateObject private var dropTargeted = ViewState(false)
    @StateObject private var editing = ViewState<AppEntry?>(nil)

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 560)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                header
                if store.entries.isEmpty {
                    EmptyDropZone(onAdd: pickFiles)
                } else {
                    library
                }
                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 38)
            .padding(.bottom, 16)

            if dropTargeted.value {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                    .background(RoundedRectangle(cornerRadius: 20).fill(Theme.accent.opacity(0.06)))
                    .padding(10)
                    .allowsHitTesting(false)
            }

            toastOverlay
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted.value, perform: handleDrop)
        .sheet(item: $editing.value) { entry in
            SettingsSheet(entry: entry).environmentObject(store)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textHi)
                Text(store.entries.isEmpty
                     ? "Drop a Windows app here to get started."
                     : "Jump back into your recent apps.")
                    .foregroundStyle(Theme.textLo)
            }
            Spacer()
            Button(action: pickFiles) { Label("Add App", systemImage: "plus") }
                .buttonStyle(GhostButton())
            Button { store.stopAll() } label: { Label("Stop All", systemImage: "stop.fill") }
                .buttonStyle(GhostButton(tint: store.running.isEmpty ? Theme.textLo : Theme.amber))
                .help("Force-quit every Windows app running in the Game Porting Toolkit")
            SettingsLink { Image(systemName: "gearshape.fill") }
                .buttonStyle(IconButton())
                .help("Settings (⌘,)")
        }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let latest = store.recents.first {
                    HeroCard(entry: latest) { editing.value = latest }
                }
                Text("RECENT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textLo)
                    .padding(.top, 6)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach(store.recents.dropFirst()) { entry in
                        AppCard(entry: entry) { editing.value = entry }
                    }
                    AddTile(action: pickFiles)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.newestRuntime != nil ? Theme.amber : Color.red)
                .frame(width: 7, height: 7)
            Text(store.newestRuntime.map { "\($0.name) ready" } ?? "Game Porting Toolkit not installed")
            Text("·")
            Text("Windows environment in ~/Games/GPTK-Prefix")
            Spacer()
            Text("Drop .exe files anywhere")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.textLo)
    }

    private var toastOverlay: some View {
        VStack {
            Spacer()
            if let message = store.toast {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.panelHi))
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5)))
                    .foregroundStyle(Theme.textHi)
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "Late night session?"
        }
    }

    // MARK: Adding apps

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
        panel.allowsMultipleSelection = true
        panel.message = "Choose Windows programs (.exe) to add"
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.add(url) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in Store.shared.add(url) }
            }
        }
        return true
    }
}

// MARK: - Cards

struct HeroCard: View {
    let entry: AppEntry
    let onSettings: () -> Void
    @EnvironmentObject var store: Store
    @StateObject private var hover = ViewState(false)

    var body: some View {
        HStack(spacing: 22) {
            AppTile(name: entry.name, size: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.lastRun == nil ? "NEWLY ADDED" : "CONTINUE PLAYING")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
                Text(entry.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textHi)
                    .lineLimit(1)
                Subtitle(entry: entry, showCount: true)
                    .font(.system(size: 13))
                HStack(spacing: 10) {
                    PlayButton(entry: entry, large: true)
                    Button(action: onSettings) { Label("Settings", systemImage: "slider.horizontal.3") }
                        .buttonStyle(GhostButton())
                    CardMenu(entry: entry, onSettings: onSettings)
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Theme.panelHi, Theme.panel],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.accent.opacity(hover.value ?0.6 : 0.25), lineWidth: 1))
        .onHover { hover.value = $0 }
        .animation(.easeOut(duration: 0.15), value: hover.value)
        .contextMenu { CardMenuItems(entry: entry, onSettings: onSettings) }
    }
}

struct AppCard: View {
    let entry: AppEntry
    let onSettings: () -> Void
    @EnvironmentObject var store: Store
    @StateObject private var hover = ViewState(false)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AppTile(name: entry.name, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textHi)
                        .lineLimit(1)
                    Subtitle(entry: entry)
                        .font(.system(size: 11))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                PlayButton(entry: entry)
                Spacer()
                Button(action: onSettings) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(IconButton())
                    .help("Settings")
                CardMenu(entry: entry, onSettings: onSettings)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(hover.value ?Theme.panelHi : Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(hover.value ?Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
        .scaleEffect(hover.value ?1.015 : 1)
        .onHover { hover.value = $0 }
        .animation(.easeOut(duration: 0.15), value: hover.value)
        .onTapGesture(count: 2) { store.launch(entry.id) }
        .contextMenu { CardMenuItems(entry: entry, onSettings: onSettings) }
    }
}

struct AddTile: View {
    let action: () -> Void
    @StateObject private var hover = ViewState(false)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                Text("Add a Windows app")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .foregroundStyle(hover.value ?Theme.accent : Theme.textLo)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(hover.value ?Theme.accent : Theme.textLo.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
    }
}

struct EmptyDropZone: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 54))
                .foregroundStyle(Theme.accentGradient)
            Text("Drop a Windows .exe here")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textHi)
            Text("It'll be remembered here with its own settings, ready to launch.")
                .foregroundStyle(Theme.textLo)
            Button("Choose a File…", action: onAdd)
                .buttonStyle(AccentButton())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [10, 7])))
    }
}

// MARK: - Card pieces

struct PlayButton: View {
    let entry: AppEntry
    var large = false
    @EnvironmentObject var store: Store

    var body: some View {
        let isStarting = store.starting.contains(entry.id)
        let isRunning = store.running.contains(entry.id)
        Button { store.launch(entry.id) } label: {
            HStack(spacing: 7) {
                if isStarting {
                    ProgressView().controlSize(.small).tint(Theme.onAccent)
                    Text("Starting")
                } else if isRunning {
                    PulseDot(color: Theme.onAccent)
                    Text("Running")
                } else {
                    Image(systemName: "play.fill")
                    Text("Play")
                }
            }
        }
        .buttonStyle(AccentButton(large: large))
        .disabled(isStarting)
    }
}

struct Subtitle: View {
    let entry: AppEntry
    var showCount = false

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(text(now: context.date))
                .foregroundStyle(Theme.textLo)
                .lineLimit(1)
        }
    }

    private func text(now: Date) -> String {
        var parts = [entry.engine.label]
        if let last = entry.lastRun {
            parts.append(now.timeIntervalSince(last) < 60
                         ? "played just now"
                         : "played " + Self.relative.localizedString(for: last, relativeTo: now))
        } else {
            parts.append("not played yet")
        }
        if entry.engine == .unreal, let percent = entry.settings.upscaling.percent {
            parts.append("TSR \(percent)%")
        }
        if entry.settings.metalFX { parts.append("MetalFX") }
        if showCount && entry.runCount > 0 {
            parts.append(entry.runCount == 1 ? "1 launch" : "\(entry.runCount) launches")
        }
        return parts.joined(separator: " · ")
    }
}

struct CardMenu: View {
    let entry: AppEntry
    let onSettings: () -> Void

    var body: some View {
        Menu {
            CardMenuItems(entry: entry, onSettings: onSettings)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textHi)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.panelHi.opacity(0.7)))
                .overlay(Circle().strokeBorder(Theme.line))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct CardMenuItems: View {
    let entry: AppEntry
    let onSettings: () -> Void
    @EnvironmentObject var store: Store

    var body: some View {
        Button("Play") { store.launch(entry.id) }
        Button("Settings…", action: onSettings)
        Button("Auto-Optimize") { store.optimize(entry.id) }
        Divider()
        Button("Show in Finder") { store.reveal(entry) }
        Button("Open Log") { store.openLog(entry) }
        Divider()
        Button("Remove from List", role: .destructive) { store.remove(entry.id) }
    }
}
