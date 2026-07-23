import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case apps = "Apps"
    case cleanup = "Cleanup"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .apps: return "trash"
        case .cleanup: return "sparkles"
        }
    }
}

struct RootView: View {
    @State private var tab: Tab = .apps
    @StateObject private var appsVM = AppsViewModel()
    @StateObject private var cleanupVM = CleanupViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch tab {
            case .apps:    AppsView(vm: appsVM)
            case .cleanup: CleanupView(vm: cleanupVM)
            }
        }
        .task { await appsVM.loadApps() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppMark(size: 26)
            Text("Uninstaller")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Label(t.rawValue, systemImage: t.symbol).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// The trash-bin app mark, drawn in code so it needs no asset at runtime.
struct AppMark: View {
    var size: CGFloat = 26
    var body: some View {
        Image(systemName: "trash.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.66, height: size * 0.66)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}
