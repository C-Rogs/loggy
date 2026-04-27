import SwiftUI
import UIKit

private struct ExerciseHowToTarget: Identifiable, Hashable {
    let id: String
}

struct ActiveWorkoutView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var appleHealth: AppleHealthWorkoutService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @StateObject private var vm: ActiveWorkoutViewModel

    @State private var showExercisePicker = false
    @State private var howToTarget: ExerciseHowToTarget?
    @State private var showFinishSheet = false
    @State private var confirmDiscardSession = false
    @State private var sessionExercisePendingRemoval: String?

    init(sessionId: String, env: AppEnvironment) {
        _vm = StateObject(wrappedValue: ActiveWorkoutViewModel(sessionId: sessionId, env: env))
    }

    var body: some View {
        ZStack {
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
                    .listRowBackground(Color.clear)

                    ForEach(Array(vm.exercises.enumerated()), id: \.element.id) { index, card in
                        Section {
                            exerciseHeader(card, index: index)
                            sets(card)
                        } header: {
                            EmptyView()
                        }
                        .listRowSeparator(.hidden, edges: .all)

                        if vm.currentExerciseIndex() == index, vm.sessionStatus != .discarded {
                            Section {
                                addExerciseAndSuggestionBlock
                            }
                            .listRowBackground(Color.clear)
                        }
                    }

                    if vm.exercises.isEmpty, vm.sessionStatus != .discarded {
                        Section {
                            addExerciseAndSuggestionBlock
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
            }

            if let visual = vm.restTimerVisual,
               vm.sessionStatus == .active,
               vm.restRemaining != nil
            {
                RestTimerScreenBorderOverlay(
                    visual: visual,
                    oledPreference: loggyOLEDDark,
                    colorScheme: colorScheme,
                    onSkip: { vm.skipRest() },
                    onAdjust: { vm.adjustRestTimer(by: $0) }
                )
                .transition(.opacity)
            }
        }
        .navigationTitle(vm.sessionStatus == .active ? " " : "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            if vm.sessionStatus == .active {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(vm.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Workout" : vm.sessionTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(formatClock(vm.elapsedSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 200)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Menu {
                            Button("Discard workout", systemImage: "trash", role: .destructive) {
                                confirmDiscardSession = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.body.weight(.medium))
                        }
                        Button("Finish") {
                            showFinishSheet = true
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .onAppear {
            vm.onAppear()
            if vm.sessionStatus == .active, let start = vm.sessionStartedAt {
                appleHealth.activeWorkoutScreenAppeared(sessionId: vm.sessionId, sessionStartedAt: start)
            }
        }
        .onDisappear {
            vm.onDisappear()
            appleHealth.activeWorkoutScreenDisappeared()
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet(onPickMany: { ids in
                vm.addExercises(exerciseIds: ids)
                showExercisePicker = false
            })
            .environmentObject(env)
        }
        .sheet(item: $howToTarget) { target in
            ExerciseHowToSheet(exerciseId: target.id)
                .environmentObject(env)
        }
        .sheet(isPresented: $showFinishSheet) {
            FinishWorkoutSummarySheet(
                title: vm.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Workout" : vm.sessionTitle,
                elapsedSeconds: vm.elapsedSeconds,
                volumeKg: vm.totalVolume,
                completedSets: vm.completedSetCount,
                totalReps: vm.totalRepCount,
                oledPreference: loggyOLEDDark,
                colorScheme: colorScheme,
                onConfirm: {
                    vm.finish()
                    showFinishSheet = false
                    dismiss()
                },
                onCancel: {
                    showFinishSheet = false
                }
            )
        }
        .confirmationDialog(
            "Discard this workout? Sets and exercises will be lost.",
            isPresented: $confirmDiscardSession,
            titleVisibility: .visible
        ) {
            Button("Discard workout", role: .destructive) {
                vm.discard()
                confirmDiscardSession = false
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove this exercise and all of its sets?",
            isPresented: Binding(
                get: { sessionExercisePendingRemoval != nil },
                set: { if !$0 { sessionExercisePendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove exercise", role: .destructive) {
                if let id = sessionExercisePendingRemoval {
                    vm.removeSessionExercise(sessionExerciseId: id)
                }
                sessionExercisePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                sessionExercisePendingRemoval = nil
            }
        }
    }

    private var addExerciseAndSuggestionBlock: some View {
        HStack(spacing: 0) {
            Button {
                showExercisePicker = true
            } label: {
                Label("Add exercise", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1)
                .padding(.vertical, 10)

            Group {
                if let sug = vm.suggestedNextExercise {
                    Button {
                        vm.addExercise(exerciseId: sug.id)
                    } label: {
                        VStack(spacing: 2) {
                            Text("Often next")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(sug.displayName)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
        .background(addExerciseBarFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme)
                        ? Color.white.opacity(0.1)
                        : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .padding(.vertical, 6)
    }

    private var addExerciseBarFill: AnyShapeStyle {
        if LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme) {
            AnyShapeStyle(Color(white: 0.1))
        } else {
            AnyShapeStyle(.regularMaterial)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Elapsed").font(.caption).foregroundStyle(.secondary)
                Text(formatClock(vm.elapsedSeconds)).font(.headline).monospacedDigit()
            }
            Spacer()
            if appleHealth.syncWorkoutsToHealthEnabled, let bpm = appleHealth.latestHeartRateBpm {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heart").font(.caption).foregroundStyle(.secondary)
                    Text("\(bpm)").font(.headline).monospacedDigit()
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Volume").font(.caption).foregroundStyle(.secondary)
                Text("\(Int(vm.totalVolume)) kg").font(.headline)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Sets").font(.caption).foregroundStyle(.secondary)
                Text("\(vm.completedSetCount)").font(.headline)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Reps").font(.caption).foregroundStyle(.secondary)
                Text("\(vm.totalRepCount)").font(.headline).monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(summaryStripFill, in: RoundedRectangle(cornerRadius: DesignTokens.materialCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var summaryStripFill: AnyShapeStyle {
        if LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme) {
            AnyShapeStyle(LoggyTheme.structuralBarFill(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        } else {
            AnyShapeStyle(.ultraThinMaterial)
        }
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
        .background(timerStripFill, in: RoundedRectangle(cornerRadius: DesignTokens.materialCornerRadius, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var timerStripFill: AnyShapeStyle {
        if LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme) {
            AnyShapeStyle(LoggyTheme.structuralBarFill(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        } else {
            AnyShapeStyle(.thinMaterial)
        }
    }

    private func exerciseHeader(_ card: SessionExerciseCard, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    howToTarget = ExerciseHowToTarget(id: card.exerciseId)
                } label: {
                    Text(card.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                if vm.sessionStatus != .discarded {
                    Menu {
                        Button {
                            vm.moveExercise(fromIndex: index, direction: -1)
                        } label: {
                            Label("Move up", systemImage: "arrow.up")
                        }
                        .disabled(index == 0)

                        Button {
                            vm.moveExercise(fromIndex: index, direction: 1)
                        } label: {
                            Label("Move down", systemImage: "arrow.down")
                        }
                        .disabled(index >= vm.exercises.count - 1)

                        Divider()

                        Button(role: .destructive) {
                            sessionExercisePendingRemoval = card.id
                        } label: {
                            Label("Remove exercise", systemImage: "minus.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                .fill(LoggyTheme.elevatedGroupedCard(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        )
        .shadow(color: .black.opacity(0.06), radius: DesignTokens.cardShadowRadius, y: DesignTokens.cardShadowY)
        .padding(.vertical, 6)
    }

    private func sets(_ card: SessionExerciseCard) -> some View {
        ForEach(card.sets) { set in
            SetRow(
                mode: card.exerciseMode,
                set: set,
                canMutate: vm.sessionStatus != .discarded,
                oledPreference: loggyOLEDDark,
                colorScheme: colorScheme,
                onChange: { w, r, dkm, dur, rpe in
                    vm.updateSet(setId: set.id, weight: w, reps: r, distanceKm: dkm, duration: dur, rpe: rpe)
                },
                onComplete: {
                    vm.completeSet(sessionExerciseId: card.id, setId: set.id)
                }
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    vm.completeSet(sessionExerciseId: card.id, setId: set.id)
                } label: {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    vm.deleteSet(setId: set.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            if vm.isCurrentSet(sessionExerciseId: card.id, setId: set.id), vm.sessionStatus != .discarded {
                Button {
                    vm.addSet(sessionExerciseId: card.id, cloneFromSetId: set.id)
                } label: {
                    Label("Add set", systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private func formatClock(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct FinishWorkoutSummarySheet: View {
    let title: String
    let elapsedSeconds: Int
    let volumeKg: Double
    let completedSets: Int
    let totalReps: Int
    let oledPreference: Bool
    let colorScheme: ColorScheme
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private func formatClock(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .listRowBackground(Color.clear)
                    LabeledContent("Duration", value: formatClock(elapsedSeconds))
                    LabeledContent("Volume", value: "\(Int(volumeKg)) kg")
                    LabeledContent("Sets completed", value: "\(completedSets)")
                    LabeledContent("Reps (logged)", value: "\(totalReps)")
                }
                Section {
                    Button("Finish & save") {
                        onConfirm()
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                    Button("Keep editing") {
                        onCancel()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LoggyTheme.groupedCanvas(oledPreference: oledPreference, colorScheme: colorScheme))
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                LoggyTheme.navigationBarBackground(oledPreference: oledPreference, colorScheme: colorScheme),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Perimeter of the screen rect starting at top center (notch / Dynamic Island line), clockwise.
private struct ScreenBorderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let shortest = min(rect.width, rect.height)
        let cornerRadius = min(62, shortest * 0.23)
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: width / 2, y: 0))

        path.addLine(to: CGPoint(x: width - cornerRadius, y: 0))
        path.addArc(
            center: CGPoint(x: width - cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: width, y: height - cornerRadius))
        path.addArc(
            center: CGPoint(x: width - cornerRadius, y: height - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: cornerRadius, y: height))
        path.addArc(
            center: CGPoint(x: cornerRadius, y: height - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        path.addArc(
            center: CGPoint(x: cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: width / 2, y: 0))

        return path
    }
}

private struct RestTimerScreenBorderOverlay: View {
    let visual: RestTimerVisual
    let oledPreference: Bool
    let colorScheme: ColorScheme
    let onSkip: () -> Void
    let onAdjust: (Int) -> Void

    private var oledCanvas: Bool {
        LoggyTheme.isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme)
    }

    private var chipFill: AnyShapeStyle {
        oledCanvas ? AnyShapeStyle(Color(white: 0.12)) : AnyShapeStyle(.thinMaterial)
    }

    var body: some View {
        // Timestamp-driven: progress = remaining / total so the trimmed arc shrinks toward rest end (countdown from notch start).
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let total = max(visual.endsAt.timeIntervalSince(visual.startedAt), 0.001)
            let remainingInterval = max(0, visual.endsAt.timeIntervalSince(timeline.date))
            let progress = CGFloat(min(1, remainingInterval / total))
            let remainingSeconds = max(0, Int(ceil(remainingInterval)))

            ZStack {
                GeometryReader { geometry in
                    let safeArea = geometry.safeAreaInsets
                    ZStack {
                        ScreenBorderShape()
                            .stroke(Color.orange.opacity(0.35), lineWidth: 10)
                            .padding(.top, -safeArea.top)
                            .padding(.bottom, -safeArea.bottom)
                            .padding(.leading, -safeArea.leading)
                            .padding(.trailing, -safeArea.trailing)

                        ScreenBorderShape()
                            .trim(from: 0, to: progress)
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [.cyan, .blue, .purple, .cyan]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .padding(.top, -safeArea.top)
                            .padding(.bottom, -safeArea.bottom)
                            .padding(.leading, -safeArea.leading)
                            .padding(.trailing, -safeArea.trailing)
                            .animation(.linear(duration: 0.05), value: progress)
                    }
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack {
                    Spacer()
                    Text("\(remainingSeconds)s")
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            oledCanvas
                                ? AnyShapeStyle(Color(white: 0.12))
                                : AnyShapeStyle(.ultraThinMaterial),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        onAdjust(-15)
                    } label: {
                        Text("−15s")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(chipFill, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(chipFill, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAdjust(15)
                    } label: {
                        Text("+15s")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(chipFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }
}

private struct SetRow: View {
    let mode: ExerciseMode
    let set: SetRowModel
    let canMutate: Bool
    let oledPreference: Bool
    let colorScheme: ColorScheme
    let onChange: (Double?, Int?, Double?, Int?, Double?) -> Void
    let onComplete: () -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var durText: String = ""
    @State private var distText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
                Text(set.previousDisplay)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }

            HStack(alignment: .center, spacing: 8) {
                fieldsBlock
                    .layoutPriority(1)

                Button(action: onComplete) {
                    Image(systemName: set.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(set.status == .completed ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canMutate)
                .accessibilityLabel(set.status == .completed ? "Completed" : "Mark complete")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LoggyTheme.setRowSurface(oledPreference: oledPreference, colorScheme: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LoggyTheme.setRowStroke(oledPreference: oledPreference, colorScheme: colorScheme), lineWidth: 1)
        )
        .onAppear { syncFromSet(set) }
        .onChange(of: set) { _, new in
            syncFromSet(new)
        }
    }

    @ViewBuilder
    private var fieldsBlock: some View {
        switch mode {
        case .weightReps, .bodyweightReps:
            HStack(spacing: 8) {
                compactField("kg", text: $weightText, keyboard: .decimalPad) {
                    onChange(Double(weightText.replacingOccurrences(of: ",", with: ".")), Int(repsText), nil, nil, nil)
                }
                compactField("reps", text: $repsText, keyboard: .numberPad) {
                    onChange(Double(weightText.replacingOccurrences(of: ",", with: ".")), Int(repsText), nil, nil, nil)
                }
            }
        case .duration:
            compactField("sec", text: $durText, keyboard: .numberPad) {
                onChange(nil, nil, nil, Int(durText), nil)
            }
        case .distanceDuration:
            HStack(spacing: 8) {
                compactField("km", text: $distText, keyboard: .decimalPad) {
                    onChange(nil, nil, Double(distText.replacingOccurrences(of: ",", with: ".")), Int(durText), nil)
                }
                compactField("sec", text: $durText, keyboard: .numberPad) {
                    onChange(nil, nil, Double(distText.replacingOccurrences(of: ",", with: ".")), Int(durText), nil)
                }
            }
        }
    }

    private var label: String {
        switch set.setType {
        case .warmup: return "W"
        case .normal: return "\(set.setIndex + 1)"
        default: return set.setType.rawValue.uppercased()
        }
    }

    private func compactField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        commit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .disabled(!canMutate)
                .onSubmit(commit)
                .onChange(of: text.wrappedValue) { _, _ in commit() }
        }
        .frame(maxWidth: .infinity)
    }

    private func syncFromSet(_ set: SetRowModel) {
        weightText = set.weightKg.map { String($0) } ?? ""
        repsText = set.reps.map(String.init) ?? ""
        durText = set.durationSeconds.map(String.init) ?? ""
        distText = set.distanceKm.map { String($0) } ?? ""
    }
}
