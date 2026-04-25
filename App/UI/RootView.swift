import SwiftUI

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var home = HomeViewModel()

    var body: some View {
        HomeView(home: home)
            .task {
                try? home.refresh(env: env)
            }
    }
}
