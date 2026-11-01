import SwiftUI

/// The app-wide Settings window (⌘,).
struct AppSettingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let experimental = Runtime.installedExperimental
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accentGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textHi)
                    Text("Options that apply to every app.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textLo)
                }
            }

            SettingsSection(title: "Experimental", icon: "flask.fill") {
                ToggleRow(title: "Experimental GPTK runtimes",
                          detail: "Adds newer Game Porting Toolkit betas to each app's version picker. They run on a custom Wine and in a separate Windows environment, so your normal setup is never touched. Expect bugs.",
                          isOn: $store.experimentalEnabled)
                if experimental.isEmpty {
                    RowLabel(title: "None installed",
                             detail: "Build one with build-crossover-wine.sh, then add it with install-gptk-runtime.sh --experimental (both in ~/Developer/WindowsAppRunner).")
                } else {
                    ForEach(experimental) { runtime in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: store.experimentalEnabled ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(store.experimentalEnabled ? Theme.accent : Theme.textLo)
                            RowLabel(title: runtime.name,
                                     detail: [runtime.baseWine.map { "Runs on \($0)." },
                                              "Windows environment: \(runtime.prefix.path.replacingOccurrences(of: Paths.home.path, with: "~"))"]
                                        .compactMap { $0 }.joined(separator: " "))
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(Theme.bg)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}
