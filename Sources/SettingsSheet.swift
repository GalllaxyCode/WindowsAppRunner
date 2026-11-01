import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draft: ViewState<AppEntry>
    @StateObject private var noteState = ViewState<String?>(nil)
    @StateObject private var confirmRemove = ViewState(false)

    init(entry: AppEntry) {
        _draft = StateObject(wrappedValue: ViewState(entry))
    }

    private var entry: AppEntry {
        get { draft.value }
        nonmutating set { draft.value = newValue }
    }

    private var note: String? {
        get { noteState.value }
        nonmutating set { noteState.value = newValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let note { NoteBanner(text: note) }
                    toolkit
                    performance
                    upscaling
                    if entry.engine != .generic { display }
                    advanced
                    command
                }
                .padding(22)
            }
            .scrollIndicators(.never)
            Divider().overlay(Theme.line)
            footer
        }
        .frame(width: 580, height: 660)
        .background(Theme.bg)
        .tint(Theme.accent)
        .confirmationDialog("Remove \(entry.name) from the list?", isPresented: $confirmRemove.value) {
            Button("Remove", role: .destructive) {
                store.remove(entry.id)
                dismiss()
            }
        } message: {
            Text("The game's files and saves are not touched.")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 16) {
            AppTile(name: entry.name, size: 58)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: $draft.value.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textHi)
                Text(entry.path)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textLo)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.path)
            }
            Spacer()
            EngineBadge(engine: entry.engine)
        }
        .padding(22)
        .background(LinearGradient(colors: [Theme.accent.opacity(0.14), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// Whether the runtime this app will launch with understands the GPTK 4.0 settings.
    private var hasGPTK4: Bool { (Runtime.resolve(entry.settings.runtime)?.majorVersion ?? 0) >= 4 }

    private var toolkit: some View {
        SettingsSection(title: "Game Porting Toolkit", icon: "cpu.fill") {
            SettingRow(title: "Version",
                       detail: "The D3DMetal graphics layer this app runs on. Switch back to an older one if a game misbehaves on a beta.") {
                Picker("", selection: $draft.value.settings.runtime) {
                    Text("Newest (\(store.newestRuntime?.name ?? "none"))").tag("")
                    ForEach(store.runtimes) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 250)
            }
            if let chosen = Runtime.resolve(entry.settings.runtime), chosen.experimental {
                NoteBanner(text: "Experimental: runs on \(chosen.baseWine ?? "a custom Wine") in its own Windows environment (~/Games/GPTK-Prefix-Experimental). Saves and settings are copied over on its first launch; after that the two are separate.")
            } else if !store.experimentalEnabled, let beta = Runtime.installedExperimental.first {
                RowLabel(title: "\(beta.name) is available",
                         detail: "Turn on experimental runtimes in Settings (⌘,) to choose it here.")
            }
        }
    }

    private var performance: some View {
        SettingsSection(title: "Performance", icon: "bolt.fill") {
            SettingRow(title: "Frame rate cap",
                       detail: hasGPTK4 ? "Caps FPS in DirectX games. Saves battery and heat. Leave empty for no cap."
                                        : "Needs GPTK 4.0 or newer.") {
                TextField("Off", text: $draft.value.settings.maxFPS)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .disabled(!hasGPTK4)
            }
            ToggleRow(title: "Metal 4 backend",
                      detail: hasGPTK4 ? "Newer, faster DirectX 12 path on macOS 27. Turn off if a game glitches or crashes."
                                       : "Needs GPTK 4.0 or newer.",
                      isOn: $draft.value.settings.metal4)
                .disabled(!hasGPTK4)
            ToggleRow(title: "Ray tracing (DXR)",
                      detail: "Lets DirectX 12 games use ray-traced effects. Off by default on M1 and M2 Macs, where it's slow.",
                      isOn: $draft.value.settings.raytracing)
            ToggleRow(title: "Advertise AVX to Rosetta",
                      detail: "Unreal Engine 5 and many modern games won't start without it.",
                      isOn: $draft.value.settings.advertiseAVX)
            SettingRow(title: "Thread sync",
                       detail: "MSync is the fastest on macOS. Try ESync or Off if a game hangs.") {
                Picker("", selection: $draft.value.settings.sync) {
                    ForEach(SyncMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            ToggleRow(title: "Performance HUD",
                      detail: "Shows FPS, GPU time and memory on top of the game.",
                      isOn: $draft.value.settings.hud)
        }
    }

    private var upscaling: some View {
        SettingsSection(title: "Upscaling & Frame Generation", icon: "sparkles.tv.fill") {
            if entry.engine == .unreal {
                SettingRow(title: "Render scale (TSR upscaling)",
                           detail: "Renders at a lower resolution and upscales with Unreal's TSR, its built-in equivalent of FSR 2. Overrides the game's own resolution slider.") {
                    Picker("", selection: $draft.value.settings.upscaling) {
                        ForEach(UpscaleMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            } else {
                RowLabel(title: "Render scale",
                         detail: "Only available for Unreal Engine games. For other games, use the FSR or DLSS option in the game's own graphics settings.")
            }
            ToggleRow(title: "MetalFX for DLSS games",
                      detail: "Turns the game's NVIDIA DLSS into Apple MetalFX upscaling, and DLSS Frame Generation into MetalFX frame interpolation (adds some input lag). Also turn DLSS on in the game's settings. Does nothing in games without DLSS.",
                      isOn: $draft.value.settings.metalFX)
        }
    }

    private var display: some View {
        SettingsSection(title: "Display", icon: "display") {
            SettingRow(title: "Window mode",
                       detail: "Sent to the game as \(entry.engine.label) launch options.") {
                Picker("", selection: $draft.value.settings.windowMode) {
                    ForEach(WindowMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            SettingRow(title: "Resolution", detail: "Leave empty to use the game's own setting.") {
                HStack(spacing: 6) {
                    TextField("Width", text: $draft.value.settings.resWidth).frame(width: 64)
                    Text("×").foregroundStyle(Theme.textLo)
                    TextField("Height", text: $draft.value.settings.resHeight).frame(width: 64)
                }
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var advanced: some View {
        SettingsSection(title: "Advanced", icon: "wrench.and.screwdriver.fill") {
            VStack(alignment: .leading, spacing: 6) {
                RowLabel(title: "Launch arguments", detail: "Extra options passed to the program.")
                TextField("e.g. -dx11 -nosplash", text: $draft.value.settings.extraArgs)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 6) {
                RowLabel(title: "Environment variables", detail: "One KEY=value per line. Lines starting with # are ignored.")
                TextEditor(text: $draft.value.settings.extraEnv)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 70)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
            }
            ToggleRow(title: "Verbose logging",
                      detail: "Writes Wine warnings to the log. Slower; use it for troubleshooting.",
                      isOn: $draft.value.settings.verboseLog)
        }
    }

    private var command: some View {
        SettingsSection(title: "Launch command", icon: "terminal.fill") {
            Text(Launcher.commandPreview(for: entry))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.amber)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { confirmRemove.value = true } label: { Image(systemName: "trash") }
                .buttonStyle(IconButton())
                .help("Remove from list")
            Button { autoOptimize() } label: { Label("Auto-Optimize", systemImage: "wand.and.stars") }
                .buttonStyle(GhostButton(tint: Theme.amber))
            Button("Reset") {
                entry.settings = AppSettings()
                note = "Settings reset to defaults. Click Save to keep them."
            }
            .buttonStyle(GhostButton())
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(GhostButton())
                .keyboardShortcut(.cancelAction)
            Button("Save & Play") {
                store.update(entry)
                store.launch(entry.id)
                dismiss()
            }
            .buttonStyle(GhostButton(tint: Theme.amber))
            Button("Save") {
                store.update(entry)
                dismiss()
            }
            .buttonStyle(AccentButton())
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(Theme.panel)
    }

    private func autoOptimize() {
        let changes = entry.optimize()
        if changes.isEmpty {
            note = "Already optimized for \(entry.engine.label)."
        } else {
            let bullets = changes.map { "• " + $0.prefix(1).uppercased() + $0.dropFirst() }
            note = "Optimized for \(entry.engine.label). Click Save to keep it:\n" + bullets.joined(separator: "\n")
        }
    }
}

// MARK: - Building blocks

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.uppercased(), systemImage: icon)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
        }
    }
}

struct RowLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textHi)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textLo)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 8)
            control
        }
    }
}

struct ToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.accent)
        }
    }
}

struct NoteBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Theme.amber)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textHi)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.35)))
    }
}
