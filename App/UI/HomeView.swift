import Charts
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var appleHealth: AppleHealthWorkoutService
    @ObservedObject var home: HomeViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @AppStorage("loggyAppearance") private var appearanceRaw: String = AppAppearance.system.rawValue

    @State private var path: [HomeRoute] = []
    @State private var importError: String?
    @State private var importSummary: String?
    @State private var isImporting = false
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showCoachStart = false
    @State private var coachTitleDraft: String = ""
    @State private var exportDocument: CSVExportDocument?
    @State private var showExport = false
    @State private var exportError: String?
    @State private var showActiveWorkoutBlockedAlert = false

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let active = home.activeSummary {
                    Section {
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
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme)
                                    ? Color.green.opacity(0.18)
                                    : Color.green.opacity(0.12)
                            )
                    )
                }

                Section {
                    Button {
                        if home.activeSummary != nil {
                            showActiveWorkoutBlockedAlert = true
                        } else {
                            prepareCoachStart()
                            showCoachStart = true
                        }
                    } label: {
                        Label("Coach & start workout", systemImage: "sparkles")
                            .font(.headline)
                    }
                    .help(
                        home.activeSummary != nil
                            ? "Finish or discard the active workout before starting another."
                            : "Suggest a title and start an empty workout."
                    )

                    Text("Coach suggests a session title only—you add exercises after starting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Start")
                }
                .listRowBackground(Color.clear)

                if !home.weeklyVolume.isEmpty {
                    Section {
                        Chart(home.weeklyVolume) { row in
                            BarMark(
                                x: .value("Week", row.weekKey),
                                y: .value("kg", row.totalKg)
                            )
                            .foregroundStyle(.indigo.gradient)
                        }
                        .frame(height: 200)
                        Text("Completed workout volume by calendar week (last ~4 months).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Weekly volume")
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink("Templates") {
                        TemplatesView()
                    }
                    NavigationLink("Exercise directory") {
                        ExerciseDirectoryView()
                    }
                } header: {
                    Text("Library")
                }

                Section {
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
                } header: {
                    Text("Past workouts")
                }
            }
            .scrollContentBackground(.hidden)
            .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
            .navigationTitle("Loggy")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case let .active(id):
                    ActiveWorkoutView(sessionId: id, env: env)
                case let .history(id):
                    WorkoutSessionAnalysisView(homePath: $path, sessionId: id)
                case let .editor(id):
                    ActiveWorkoutView(sessionId: id, env: env)
                }
            }
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        Button {
                            try? home.refresh(env: env)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .toolbarBackground(
                LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $home.showRecovery) {
                if let active = home.activeSummary {
                    SessionRecoveryView(sessionId: active.sessionId) {
                        home.showRecovery = false
                        try? home.refresh(env: env)
                    }
                    .presentationDetents([.medium])
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    Form {
                        Section("Appearance") {
                            Picker("", selection: $appearanceRaw) {
                                ForEach(AppAppearance.allCases) { mode in
                                    Text(mode.title).tag(mode.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.inline)
                        }
                        Section("Apple Health") {
                            Toggle("Save workouts to Health", isOn: Binding(
                                get: { appleHealth.syncWorkoutsToHealthEnabled },
                                set: { appleHealth.setSyncWorkoutsToHealthEnabled($0) }
                            ))
                            Button("Allow Health access…") {
                                Task { await appleHealth.requestAuthorization() }
                            }
                            Text("Saves strength-training workouts plus a rough active-energy estimate for Activity rings. BPM and post-workout charts read from Health (usually written by Apple Watch). A separate watchOS app is optional; HealthKit is the supported path for wrist heart rate on iPhone.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Section("Data") {
                            Button("Import Hevy CSV…") { showImporter = true }
                            Button("Export workouts CSV…") {
                                exportCSV()
                            }
                        }
                        Section("About") {
                            Text("Export is a Loggy-native CSV of completed sessions and sets.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
                    .toolbarBackground(
                        LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
                        for: .navigationBar
                    )
                    .toolbarBackground(.visible, for: .navigationBar)
                }
                .environment(\.loggyOLEDDarkUserPreference, loggyOLEDDark)
            }
            .sheet(isPresented: $showCoachStart) {
                NavigationStack {
                    Form {
                        Section {
                            TextField("Workout title", text: $coachTitleDraft)
                            Text("You can edit the title before starting. The workout starts empty.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Section {
                            Button("Start workout") {
                                startWithCoachTitle()
                            }
                            .fontWeight(.semibold)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
                    .navigationTitle("Coach")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showCoachStart = false }
                        }
                    }
                    .toolbarBackground(
                        LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
                        for: .navigationBar
                    )
                    .toolbarBackground(.visible, for: .navigationBar)
                }
                .environment(\.loggyOLEDDarkUserPreference, loggyOLEDDark)
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
            .fileExporter(
                isPresented: $showExport,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "loggy-export.csv"
            ) { _ in
                exportDocument = nil
            }
            .alert("Import", isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })) {
                Button("OK", role: .cancel) { importSummary = nil }
            } message: { Text(importSummary ?? "") }
            .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) { importError = nil }
            } message: { Text(importError ?? "") }
            .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: { Text(exportError ?? "") }
            .overlay {
                if isImporting { ProgressView("Importing…").padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            .alert("Workout in progress", isPresented: $showActiveWorkoutBlockedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You already have a workout in progress. Continue it from above, or finish or discard it from the workout screen.")
            }
            .onAppear {
                try? home.refresh(env: env)
            }
        }
    }

    private func prepareCoachStart() {
        coachTitleDraft = (try? env.sessionCoach.suggestedSessionTitle()) ?? "Workout"
    }

    private func startWithCoachTitle() {
        guard home.activeSummary == nil else { return }
        let title = coachTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = try? env.workouts.createEmptyActiveSession(title: title.isEmpty ? nil : title) {
            LoggyFeedback.primaryActionTap()
            showCoachStart = false
            path.append(.active(id))
        }
    }

    private func exportCSV() {
        do {
            let data = try env.csvExporter.exportCompletedWorkoutsCSV()
            exportDocument = CSVExportDocument(data: data)
            showExport = true
        } catch {
            exportError = String(describing: error)
        }
    }
}

