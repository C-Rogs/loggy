import Charts
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var appleHealth: AppleHealthWorkoutService
    @EnvironmentObject private var healthRecovery: HealthRecoveryService
    @ObservedObject var home: HomeViewModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @AppStorage("loggyAppearance") private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("loggyDismissedHomeGettingStarted") private var dismissedGettingStarted = false

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
    @State private var readinessInsight: ReadinessInsight?
    @State private var readinessLoading = false
    @State private var showReadinessLearnMore = false
    @State private var coachReadinessInsight: ReadinessInsight?
    @State private var coachReadinessLoading = false
    @State private var pastWorkoutsSearch = ""
    @State private var importFraction: Double?
    @State private var importStatus = ""

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    /// First-run hints until the user completes a workout or dismisses the banner.
    private var showGettingStartedBanner: Bool {
        !dismissedGettingStarted && home.completed.isEmpty && home.activeSummary == nil
    }

    private var filteredPastWorkouts: [WorkoutListItem] {
        let q = pastWorkoutsSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return home.completed }
        return home.completed.filter { item in
            let title = (item.title ?? "").lowercased()
            if title.contains(q) { return true }
            let when = item.startedAt.formatted(date: .abbreviated, time: .shortened).lowercased()
            return when.contains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if showGettingStartedBanner {
                    Section {
                        HomeGettingStartedBanner(onDismiss: { dismissedGettingStarted = true })
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Getting started")
                    }
                }

                if healthRecovery.recoveryInsightsEnabled {
                    Section {
                        ReadinessHeroView(
                            insight: readinessInsight,
                            isLoading: readinessLoading,
                            onLearnMore: { showReadinessLearnMore = true }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Readiness")
                    }
                }

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

                    Text(
                        "Coach suggests a workout title (and optional readiness from Apple Health). You add exercises next—there’s no auto-generated program."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        startEmptyWorkoutQuick()
                    } label: {
                        Text("Start empty workout")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(home.activeSummary != nil)
                    Text("Same as Coach, without the sheet—opens an empty session so you can train immediately.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Start")
                }
                .listRowBackground(Color.clear)

                if !healthRecovery.recoveryInsightsEnabled {
                    Section {
                        Toggle(
                            "Show recovery insights",
                            isOn: Binding(
                                get: { healthRecovery.recoveryInsightsEnabled },
                                set: { healthRecovery.setRecoveryInsightsEnabled($0) }
                            )
                        )
                        Text(
                            "Optional summary from sleep and HRV in Apple Health (usually from Apple Watch). Separate from live heart rate during workouts."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Button("Allow sleep & HRV access…") {
                            Task { await healthRecovery.requestAuthorization() }
                        }
                    } header: {
                        Text("Recovery")
                    }
                }

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
                        .accessibilityLabel("Completed training volume by calendar week")
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
                    NavigationLink("Statistics") {
                        StatisticsHubView()
                    }
                } header: {
                    Text("Library")
                } footer: {
                    Text("Templates save repeatable routines. Exercise directory lists everything you can log. Statistics summarize trends.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if home.completed.isEmpty {
                        Text("When you finish a workout, it appears here. Start one from Coach below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else if filteredPastWorkouts.isEmpty {
                        Text("No workouts match your search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredPastWorkouts) { item in
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
                } header: {
                    Text("Past workouts")
                }
            }
            .searchable(text: $pastWorkoutsSearch, prompt: "Search past workouts")
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
                        .accessibilityLabel("Settings")
                        Button {
                            try? home.refresh(env: env)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh home")
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
                            Button("Allow workout & heart-rate access…") {
                                Task { await appleHealth.requestAuthorization() }
                            }
                            Text("Saves strength-training workouts plus a rough active-energy estimate for Activity rings. BPM and post-workout charts read from Health (usually written by Apple Watch) during an active session.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Recovery insights", isOn: Binding(
                                get: { healthRecovery.recoveryInsightsEnabled },
                                set: { healthRecovery.setRecoveryInsightsEnabled($0) }
                            ))
                            Button("Allow sleep & HRV access…") {
                                Task { await healthRecovery.requestAuthorization() }
                            }
                            Text("Uses sleep and heart rate variability from Apple Health for advisory readiness on Home—not live workout streaming.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Section("Data & privacy") {
                            Text(
                                "Workouts live in a database on this iPhone only. There’s no Loggy account and no cloud sync yet—everything works offline."
                            )
                            .font(.subheadline)
                            Text(
                                "Apple Health is optional: you can write workouts and energy, and read sleep/HRV for recovery hints. Export anytime below."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Section("Data") {
                            Button("Import Hevy CSV…") { showImporter = true }
                            Text("In Hevy, export your backup CSV, then pick that file here to bring history into Loggy.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Export workouts CSV…") {
                                exportCSV()
                            }
                            Text("Your log stays only on this iPhone until you export. Save a CSV occasionally as a backup outside Loggy.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Section("About") {
                            Text("Export is a Loggy-native CSV of completed sessions and sets for spreadsheets or backup.")
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
            .sheet(isPresented: $showReadinessLearnMore) {
                ReadinessLearnMoreSheet()
                    .environment(\.loggyOLEDDarkUserPreference, loggyOLEDDark)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCoachStart) {
                NavigationStack {
                    Form {
                        if healthRecovery.recoveryInsightsEnabled {
                            Section {
                                ReadinessHeroView(
                                    insight: coachReadinessInsight,
                                    isLoading: coachReadinessLoading,
                                    compact: true,
                                    onLearnMore: {}
                                )
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                            }
                        }
                        Section {
                            TextField("Workout title", text: $coachTitleDraft)
                            Text("Edit the title if you like. The session starts with no exercises—you’ll add them from the workout screen.")
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
                    importError = nil
                    importSummary = nil
                    isImporting = true
                    importFraction = 0
                    importStatus = "Reading file…"
                    Task {
                        let importer = env.hevyImporter
                        defer {
                            Task { @MainActor in
                                isImporting = false
                                importFraction = nil
                                importStatus = ""
                            }
                        }
                        do {
                            let accessed = url.startAccessingSecurityScopedResource()
                            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                            let data = try Data(contentsOf: url)
                            let filename = url.lastPathComponent
                            let res = try await Task.detached(priority: .userInitiated) {
                                try importer.importCSV(data: data, filename: filename) { p, msg in
                                    Task { @MainActor in
                                        importFraction = p
                                        importStatus = msg
                                    }
                                }
                            }.value
                            await MainActor.run {
                                if res.skippedDuplicate {
                                    importSummary = "Skipped duplicate import (same file hash)."
                                } else {
                                    importSummary = "Imported \(res.importedWorkouts) workout(s)."
                                }
                                try? home.refresh(env: env)
                            }
                        } catch {
                            await MainActor.run {
                                importError = UserFacingError.message(for: error)
                            }
                        }
                    }
                case let .failure(err):
                    importError = UserFacingError.message(for: err)
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
                if isImporting {
                    VStack(spacing: 12) {
                        if let f = importFraction {
                            ProgressView(value: f, total: 1.0)
                                .accessibilityValue("\(Int(f * 100)) percent")
                        } else {
                            ProgressView()
                                .accessibilityLabel("Importing workouts")
                        }
                        Text(importStatus.isEmpty ? "Importing…" : importStatus)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                        Text("Large Hevy exports can take a minute—Loggy works through each workout in order.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
            .alert("Workout in progress", isPresented: $showActiveWorkoutBlockedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You already have a workout in progress. Continue it from above, or finish or discard it from the workout screen.")
            }
            .onAppear {
                try? home.refresh(env: env)
            }
            .task(id: healthRecovery.recoveryInsightsEnabled) {
                await refreshReadinessHero()
            }
        }
    }

    private func prepareCoachStart() {
        coachTitleDraft = (try? env.sessionCoach.suggestedSessionTitle()) ?? "Workout"
        coachReadinessLoading = true
        coachReadinessInsight = nil
        Task {
            if healthRecovery.recoveryInsightsEnabled {
                coachReadinessInsight = await healthRecovery.fetchReadinessInsight()
            } else {
                coachReadinessInsight = nil
            }
            coachReadinessLoading = false
        }
    }

    private func refreshReadinessHero() async {
        guard healthRecovery.recoveryInsightsEnabled else {
            readinessInsight = nil
            readinessLoading = false
            return
        }
        readinessLoading = true
        readinessInsight = await healthRecovery.fetchReadinessInsight()
        readinessLoading = false
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

    /// Opens an active session immediately (no coach sheet)—same as Coach with default title behavior.
    private func startEmptyWorkoutQuick() {
        guard home.activeSummary == nil else {
            showActiveWorkoutBlockedAlert = true
            return
        }
        if let id = try? env.workouts.createEmptyActiveSession(title: nil) {
            LoggyFeedback.primaryActionTap()
            path.append(.active(id))
        }
    }

    private func exportCSV() {
        do {
            let data = try env.csvExporter.exportCompletedWorkoutsCSV()
            exportDocument = CSVExportDocument(data: data)
            showExport = true
        } catch {
            exportError = UserFacingError.message(for: error)
        }
    }
}

// MARK: - Getting started (first-run hints)

private struct HomeGettingStartedBanner: View {
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Use Coach & start workout to open an empty session.")
                Text("2. Add exercises from the workout screen.")
                Text("3. Log sets in each row; tap the checkmark to complete a set. The rest timer runs next.")
                Text("Tip: Start empty workout (below) skips the coach sheet when you’re in a hurry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LoggyTheme.elevatedGroupedCard(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        )
    }
}

