import SwiftUI

struct ExercisePickerSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = ExerciseDirectoryViewModel()

    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            List(vm.exercises) { ex in
                Button(ex.displayName) {
                    onPick(ex.id)
                    dismiss()
                }
            }
            .searchable(text: $vm.query)
            .navigationTitle("Pick exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { try? vm.refresh(env: env) }
            .onChange(of: vm.query) { _, _ in
                try? vm.refresh(env: env)
            }
        }
    }
}
