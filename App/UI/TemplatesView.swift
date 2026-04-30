import SwiftUI
import UIKit

struct TemplatesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark
    @StateObject private var vm = TemplatesViewModel()

    @State private var newName: String = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New template name", text: $newName)
                    Button("Create") {
                        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        try? vm.create(name: newName, env: env)
                        newName = ""
                    }
                }
            }

            Section("Templates") {
                if vm.templates.isEmpty {
                    Text("No templates yet. Name one above to create it, then add exercises—or log workouts from Coach and organize them here later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(vm.templates) { t in
                    NavigationLink(value: HomeRoute.templateDetail(t.id)) {
                        Text(t.name)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            try? vm.delete(id: t.id, env: env)
                        } label: {
                            Text("Delete")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Templates")
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .task { try? vm.refresh(env: env) }
    }
}

struct TemplateDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark
    @StateObject private var vm = TemplatesViewModel()

    let templateId: String
    var homePath: Binding<[HomeRoute]>
    @State private var showPicker = false
    @State private var rows: [TemplateExerciseRow] = []
    @State private var showActiveWorkoutBlockedAlert = false
    @State private var startErrorMessage: String?

    var body: some View {
        List {
            Section {
                Button("Start workout from this template") {
                    startFromTemplate()
                }

                Button("Add exercise…") { showPicker = true }
            }

            Section {
                Text("Set target weight, reps, and set count for each exercise. These pre-fill planned sets when you start this template.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Exercises") {
                if rows.isEmpty {
                    Text("Add exercises to this template first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink {
                            ExerciseInfoView(exerciseId: row.exercise.id)
                        } label: {
                            ExerciseSummaryRowLabel(exercise: row.exercise, style: .list)
                        }
                        TemplateExerciseTargetsCell(
                            row: row,
                            onSave: { sc, rmin, rmax, w, dur, dkm in
                                try? env.templates.updateTemplateExerciseTargets(
                                    templateExerciseId: row.id,
                                    targetSetCount: sc,
                                    targetRepMin: rmin,
                                    targetRepMax: rmax,
                                    targetWeightKg: w,
                                    targetDurationSeconds: dur,
                                    targetDistanceKm: dkm
                                )
                            }
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Template")
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet { exerciseId in
                try? vm.addExercise(templateId: templateId, exerciseId: exerciseId, env: env)
                showPicker = false
                reloadTemplateRows()
            }
            .environmentObject(env)
        }
        .alert("Workout in progress", isPresented: $showActiveWorkoutBlockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You already have a workout in progress. Continue it from Home, or finish or discard it from the workout screen.")
        }
        .alert("Could not start", isPresented: Binding(
            get: { startErrorMessage != nil },
            set: { if !$0 { startErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { startErrorMessage = nil }
        } message: {
            Text(startErrorMessage ?? "")
        }
        .task {
            try? vm.refresh(env: env)
            reloadTemplateRows()
        }
    }

    private func startFromTemplate() {
        if (try? env.workouts.activeSessionSummary()) != nil {
            showActiveWorkoutBlockedAlert = true
            return
        }
        do {
            let sessionId = try env.workouts.startSessionFromTemplate(templateId: templateId, title: nil)
            LoggyFeedback.primaryActionTap()
            homePath.wrappedValue = [HomeRoute.active(sessionId)]
        } catch RepositoryError.activeSessionAlreadyExists {
            showActiveWorkoutBlockedAlert = true
        } catch {
            startErrorMessage = UserFacingError.message(for: error)
        }
    }

    private func reloadTemplateRows() {
        rows = (try? env.templates.listTemplateExerciseRows(templateId: templateId)) ?? []
    }
}

/// Inline targets editor for one template exercise row; commits on each control change.
private struct TemplateExerciseTargetsCell: View {
    let row: TemplateExerciseRow
    let onSave: (Int?, Int?, Int?, Double?, Int?, Double?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @State private var setCount: Int = 3
    @State private var weightText = ""
    @State private var repMinText = ""
    @State private var repMaxText = ""
    @State private var durationText = ""
    @State private var distanceText = ""

    var body: some View {
        let fieldFill = Color(UIColor.secondarySystemFill)
        let fieldStroke = Color.primary.opacity(
            LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme) ? 0.14 : 0.1
        )

        VStack(alignment: .leading, spacing: 8) {
            Stepper("Sets: \(setCount)", value: $setCount, in: 1 ... 40)
                .font(.caption.weight(.semibold))
                .onChange(of: setCount) { _, _ in pushSave() }

            switch row.exercise.exerciseMode {
            case .weightReps:
                HStack(spacing: 6) {
                    templateSmallField("kg", text: $weightText, keyboard: .decimalPad, fieldFill: fieldFill, fieldStroke: fieldStroke)
                        .onChange(of: weightText) { _, _ in pushSave() }
                    templateSmallField("reps min", text: $repMinText, keyboard: .numberPad, fieldFill: fieldFill, fieldStroke: fieldStroke)
                        .onChange(of: repMinText) { _, _ in pushSave() }
                    templateSmallField("reps max", text: $repMaxText, keyboard: .numberPad, fieldFill: fieldFill, fieldStroke: fieldStroke)
                        .onChange(of: repMaxText) { _, _ in pushSave() }
                }
            case .bodyweightReps:
                HStack(spacing: 6) {
                    templateSmallField("reps min", text: $repMinText, keyboard: .numberPad, fieldFill: fieldFill, fieldStroke: fieldStroke)
                        .onChange(of: repMinText) { _, _ in pushSave() }
                    templateSmallField("reps max", text: $repMaxText, keyboard: .numberPad, fieldFill: fieldFill, fieldStroke: fieldStroke)
                        .onChange(of: repMaxText) { _, _ in pushSave() }
                }
            case .duration:
                templateSmallField("sec", text: $durationText, keyboard: .numberPad, fieldFill: fieldFill, fieldStroke: fieldStroke)
                    .onChange(of: durationText) { _, _ in pushSave() }
            case .distanceDuration:
                HStack(spacing: 6) {
                    templateSmallField("km", text: $distanceText, keyboard: .decimalPad, fieldFill: fieldFill, fieldStroke: fieldStroke)
                        .onChange(of: distanceText) { _, _ in pushSave() }
                    templateSmallField("sec", text: $durationText, keyboard: .numberPad, fieldFill: fieldFill, fieldStroke: fieldStroke)
                        .onChange(of: durationText) { _, _ in pushSave() }
                }
            }
        }
        .onAppear {
            syncFromRow()
        }
        .onChange(of: row.id) { _, _ in
            syncFromRow()
        }
    }

    private func syncFromRow() {
        setCount = max(row.targetSetCount ?? 3, 1)
        weightText = LoggyMetricDisplay.kgForTextField(row.targetWeightKg)
        repMinText = row.targetRepMin.map(String.init) ?? ""
        repMaxText = row.targetRepMax.map(String.init) ?? ""
        durationText = row.targetDurationSeconds.map(String.init) ?? ""
        distanceText = LoggyMetricDisplay.kmForTextField(row.targetDistanceKm)
    }

    private func pushSave() {
        let w = parseDouble(weightText)
        let rMin = parseInt(repMinText)
        let rMax = parseInt(repMaxText)
        let dur = parseInt(durationText)
        let dkm = parseDouble(distanceText)
        onSave(setCount, rMin, rMax, w, dur, dkm)
    }

    private func parseDouble(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return Double(t)
    }

    private func parseInt(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return Int(t)
    }

    private func templateSmallField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        fieldFill: Color,
        fieldStroke: Color
    ) -> some View {
        TextField(title, text: text)
            .font(.caption.weight(.semibold))
            .multilineTextAlignment(.trailing)
            .keyboardType(keyboard)
            .textFieldStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(fieldFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(fieldStroke, lineWidth: 1)
            )
            .frame(minWidth: 36, idealWidth: 48, maxWidth: 72)
            .lineLimit(1)
    }
}
