import SwiftUI

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var home = HomeViewModel()

    var body: some View {
        HomeView(home: home)
            .environmentObject(env.appleHealth)
    }
}
