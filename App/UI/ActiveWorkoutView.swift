import SwiftUI

struct ActiveWorkoutView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm: ActiveWorkoutViewModel

    @State private var showExercisePicker = false

    init(sessionId: String, env: AppEnvironment) {
        _vm = StateObject(wrappedValue: ActiveWorkoutViewModel(sessionId: sessionId, env: env))
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryStrip

            if let rest = vm.restRemaining, vm.sessionStatus == .active {
                timerStrip(rest: rest)
            }

            List {
                Section {
                    TextField("Workout title", text: Binding(get: { vm.sessionTitle }, set: { vm.updateSessionTitle($0) }))
                        .disabled(vm.sessionStatus == .discarded)
                }

                ForEach(vm.exercises) { card in
                    Section {
                        exerciseHeader(card)
                        sets(card)
                    }
                }
            }
        }
        .navigationTitle(vm.sessionStatus == .active ? "Active workout" : "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if vm.sessionStatus != .discarded {
                        Button {
                            showExercisePicker = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }

                    if vm.sessionStatus == .active {
                        Button("Finish") {
                            vm.finish()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet { exerciseId in
                vm.addExercise(exerciseId: exerciseId)
                showExercisePicker = false
            }
            .environmentObject(env)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Elapsed").font(.caption).foregroundStyle(.secondary)
                Text(formatClock(vm.elapsedSeconds)).font(.headline).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Volume").font(.caption).foregroundStyle(.secondary)
                Text("\(Int(vm.totalVolume)) kg").font(.headline)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Sets").font(.caption).foregroundStyle(.secondary)
                Text("\(vm.completedSetCount)").font(.headline)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func timerStrip(rest: Int) -> some View {
        HStack {
            Image(systemName: "timer")
            Text("Rest \(rest)s")
                .monospacedDigit()
            Spacer()
            Button("Skip") { vm.skipRest() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private func exerciseHeader(_ card: SessionExerciseCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.displayName).font(.title3.weight(.semibold))
                Spacer()
                if vm.sessionStatus != .discarded {
                    Menu {
                        Button("Add set") {
                            vm.addSet(sessionExerciseId: card.id, cloneFromSetId: card.sets.last?.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }

            TextField("Exercise notes", text: Binding(
                get: { card.notes ?? "" },
                set: { vm.updateNotes(sessionExerciseId: card.id, notes: $0) }
            ), axis: .vertical)
            .disabled(vm.sessionStatus == .discarded)

            HStack {
                Text("Rest target").font(.caption).foregroundStyle(.secondary)
                Stepper(value: Binding(
                    get: { card.targetRestSeconds ?? 90 },
                    set: { vm.updateRestTarget(sessionExerciseId: card.id, seconds: $0) }
                ), in: 0...600, step: 15) {
                    Text("\(card.targetRestSeconds ?? 90)s").font(.caption).monospacedDigit()
                }
                .disabled(vm.sessionStatus == .discarded)
            }
        }
        .padding(.vertical, 6)
    }

    private func sets(_ card: SessionExerciseCard) -> some View {
        ForEach(card.sets) { set in
            SetRow(
                mode: card.exerciseMode,
                set: set,
                canMutate: vm.sessionStatus != .discarded,
                onChange: { w, r, dkm, dur, rpe in
                    vm.updateSet(setId: set.id, weight: w, reps: r, distanceKm: dkm, duration: dur, rpe: rpe)
                },
                onComplete: {
                    vm.completeSet(sessionExerciseId: card.id, setId: set.id)
                },
                onDelete: {
                    vm.deleteSet(setId: set.id)
                }
            )
            .listRowSeparator(.visible)
        }
    }

    private func formatClock(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct SetRow: View {
    let mode: ExerciseMode
    let set: SetRowModel
    let canMutate: Bool
    let onChange: (Double?, Int?, Double?, Int?, Double?) -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var durText: String = ""
    @State private var distText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if set.status == .completed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }

            HStack(spacing: 8) {
                Text("Prev").frame(width: 52, alignment: .leading).font(.caption2).foregroundStyle(.secondary)
                Text(set.previousDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            switch mode {
            case .weightReps, .bodyweightReps:
                HStack(spacing: 10) {
                    field("kg", text: $weightText, keyboard: .decimalPad) {
                        onChange(Double(weightText.replacingOccurrences(of: ",", with: ".")), Int(repsText), nil, nil, nil)
                    }
                    field("reps", text: $repsText, keyboard: .numberPad) {
                        onChange(Double(weightText.replacingOccurrences(of: ",", with: ".")), Int(repsText), nil, nil, nil)
                    }
                }
            case .duration:
                field("sec", text: $durText, keyboard: .numberPad) {
                    onChange(nil, nil, nil, Int(durText), nil)
                }
            case .distanceDuration:
                HStack(spacing: 10) {
                    field("km", text: $distText, keyboard: .decimalPad) {
                        onChange(nil, nil, Double(distText.replacingOccurrences(of: ",", with: ".")), Int(durText), nil)
                    }
                    field("sec", text: $durText, keyboard: .numberPad) {
                        onChange(nil, nil, Double(distText.replacingOccurrences(of: ",", with: ".")), Int(durText), nil)
                    }
                }
            }

            HStack {
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                    .disabled(!canMutate)
                Spacer()
                Button(action: onComplete) {
                    Image(systemName: set.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(!canMutate)
            }
        }
        .padding(.vertical, 6)
        .onAppear { syncFromSet(set) }
        .onChange(of: set) { _, new in
            syncFromSet(new)
        }
    }

    private func syncFromSet(_ set: SetRowModel) {
        weightText = set.weightKg.map { String($0) } ?? ""
        repsText = set.reps.map(String.init) ?? ""
        durText = set.durationSeconds.map(String.init) ?? ""
        distText = set.distanceKm.map { String($0) } ?? ""
    }

    private var label: String {
        switch set.setType {
        case .warmup: return "W"
        case .normal: return "\(set.setIndex + 1)"
        default: return set.setType.rawValue.uppercased()
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: KeyboardType, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
                .disabled(!canMutate)
                .onSubmit(commit)
                .onChange(of: text.wrappedValue) { _, _ in commit() }
        }
        .frame(maxWidth: .infinity)
    }
}
