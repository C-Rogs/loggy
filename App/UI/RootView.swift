import SwiftUI

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var home = HomeViewModel()

    @AppStorage("loggyAppearance") private var appearanceRaw: String = AppAppearance.system.rawValue

    private var loggyOLEDDarkPreference: Bool {
        (AppAppearance(rawValue: appearanceRaw) ?? .system) == .dark
    }

    var body: some View {
        HomeView(home: home)
            .environmentObject(env.appleHealth)
            .environmentObject(env.healthRecovery)
            .environment(\.loggyOLEDDarkUserPreference, loggyOLEDDarkPreference)
    }
}
