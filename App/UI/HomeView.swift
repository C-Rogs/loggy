import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var home: HomeViewModel

    @State private var path: [HomeRoute] = []
    @State private var importError: String?
    @State private var importSummary: String?
    @State private var isImporting = false
    @State private var showImporter = false

    var body: some View {
        NavigationStack(path: $path) {
        List {
            if let active = home.activeSummary {
                Section("Active workout") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(active.title?.isEmpty == false ? active.title! : "Untitled workout")
                            .font(.headline)
                        Text("Started \(active.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        NavigationLink("Continue", value: HomeRoute.active(active.sessionId))
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Workouts") {
                Button("Start empty workout") {
                    guard home.activeSummary == nil else { return }
                    if let id = try? env.workouts.createEmptyActiveSession(title: nil) {
                        path.append(.active(id))
                    }
                }
                .disabled(home.activeSummary != nil)

                NavigationLink("Templates") {
                    TemplatesView()
                }

                NavigationLink("Exercise directory") {
                    ExerciseDirectoryView()
                }

                Button("Import Hevy CSV…") { showImporter = true }

                ForEach(home.completed) { item in
                    NavigationLink(value: HomeRoute.history(item.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title?.isEmpty == false ? item.title! : "Workout")
                            Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Volume \(Int(item.totalVolumeKg)) kg · \(item.totalSetCount) sets")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Loggy")
        .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case let .active(id):
                ActiveWorkoutView(sessionId: id, env: env)
            case let .history(id):
                ActiveWorkoutView(sessionId: id, env: env)
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    try? home.refresh(env: env)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $home.showRecovery) {
            if let active = home.activeSummary {
                SessionRecoveryView(sessionId: active.sessionId) {
                    home.showRecovery = false
                    try? home.refresh(env: env)
                }
                .presentationDetents([.medium])
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case let .success(url):
                isImporting = true
                importError = nil
                importSummary = nil
                Task {
                    defer { isImporting = false }
                    do {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        let res = try env.hevyImporter.importCSV(data: data, filename: url.lastPathComponent)
                        if res.skippedDuplicate {
                            importSummary = "Skipped duplicate import (same file hash)."
                        } else {
                            importSummary = "Imported \(res.importedWorkouts) workout(s)."
                        }
                        try? home.refresh(env: env)
                    } catch {
                        importError = String(describing: error)
                    }
                }
            case let .failure(err):
                importError = String(describing: err)
            }
        }
        .alert("Import", isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })) {
            Button("OK", role: .cancel) { importSummary = nil }
        } message: { Text(importSummary ?? "") }
        .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
        .overlay {
            if isImporting { ProgressView("Importing…").padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12)) }
        }
        .onAppear {
            try? home.refresh(env: env)
        }
        }
    }
}

private enum HomeRoute: Hashable {
    case active(String)
    case history(String)
}
