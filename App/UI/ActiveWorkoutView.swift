import SwiftUI
import UIKit

private struct ExerciseHowToTarget: Identifiable, Hashable {
    let id: String
}

private struct ReplaceExerciseTarget: Identifiable, Hashable {
    var id: String { sessionExerciseId }
    let sessionExerciseId: String
    let currentExerciseId: String
    let exerciseMode: ExerciseMode
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
    @State private var showRenameWorkout = false
    @State private var renameWorkoutDraft = ""
    @State private var restTargetPickerExerciseId: String?
    @State private var restTargetPickerDraftSeconds: Int = 90
    @State private var notesSheetExerciseId: String?
    @State private var notesSheetDraft: String = ""
    @State private var replaceExerciseTarget: ReplaceExerciseTarget?

    init(sessionId: String, env: AppEnvironment) {
        _vm = StateObject(wrappedValue: ActiveWorkoutViewModel(sessionId: sessionId, env: env))
    }

    private static let cardSectionRowInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

    /// Toast + perimeter only while countdown is strictly positive (hides at 0 instead of lingering).
    private var showingActiveRestChrome: Bool {
        vm.sessionStatus == .active
            && (vm.restRemaining ?? 0) > 0
            && vm.restTimerVisual != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryStrip

            List {
                if vm.sessionStatus != .active {
                    Section {
                        TextField("Workout title", text: Binding(get: { vm.sessionTitle }, set: { vm.updateSessionTitle($0) }))
                            .disabled(vm.sessionStatus == .discarded)
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(Array(vm.exercises.enumerated()), id: \.element.id) { index, card in
                    let rowCount = exerciseSectionRowCount(card: card)
                    Section {
                        exerciseCardTitleRow(card: card, index: index)
                            .listRowSeparator(.hidden, edges: .all)
                            .listRowInsets(Self.cardSectionRowInsets)
                            .listRowBackground(exerciseCardListRowBackground(rowIndex: 0, totalRows: rowCount))

                        exerciseCardNotesRow(card: card)
                            .listRowSeparator(.hidden, edges: .all)
                            .listRowInsets(Self.cardSectionRowInsets)
                            .listRowBackground(exerciseCardListRowBackground(rowIndex: 1, totalRows: rowCount))

                        exerciseCardRestPickerRow(card: card)
                            .listRowSeparator(.hidden, edges: .all)
                            .listRowInsets(Self.cardSectionRowInsets)
                            .listRowBackground(exerciseCardListRowBackground(rowIndex: 2, totalRows: rowCount))

                        exerciseSetTableHeader(mode: card.exerciseMode)
                            .listRowSeparator(.hidden, edges: .all)
                            .listRowInsets(Self.cardSectionRowInsets)
                            .listRowBackground(exerciseCardListRowBackground(rowIndex: 3, totalRows: rowCount))

                        ForEach(Array(card.sets.enumerated()), id: \.element.id) { rowIdx, set in
                            SetRow(
                                mode: card.exerciseMode,
                                set: set,
                                canMutate: vm.sessionStatus != .discarded,
                                oledPreference: loggyOLEDDark,
                                colorScheme: colorScheme,
                                embeddedInTable: true,
                                isAlternatingShaded: rowIdx % 2 == 1,
                                onChange: { w, r, dkm, dur, rpe in
                                    vm.updateSet(setId: set.id, weight: w, reps: r, distanceKm: dkm, duration: dur, rpe: rpe)
                                },
                                onToggleCompletion: {
                                    vm.toggleSetCompletion(sessionExerciseId: card.id, setId: set.id)
                                }
                            )
                            .listRowSeparator(.hidden, edges: .all)
                            .listRowInsets(Self.cardSectionRowInsets)
                            .listRowBackground(exerciseCardListRowBackground(rowIndex: 4 + rowIdx, totalRows: rowCount))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if vm.sessionStatus != .discarded, card.sets.count > 1 {
                                    Button(role: .destructive) {
                                        vm.deleteSet(setId: set.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .contextMenu {
                                if vm.sessionStatus != .discarded, card.sets.count > 1 {
                                    Button(role: .destructive) {
                                        vm.deleteSet(setId: set.id)
                                    } label: {
                                        Label("Delete set", systemImage: "trash")
                                    }
                                }
                            }
                        }

                        if vm.sessionStatus != .discarded {
                            Button {
                                vm.addSet(sessionExerciseId: card.id, cloneFromSetId: card.sets.last?.id)
                            } label: {
                                Label("Add set", systemImage: "plus")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 1)
                                    .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden, edges: .all)
                            .listRowInsets(Self.cardSectionRowInsets)
                            .listRowBackground(exerciseCardListRowBackground(rowIndex: rowCount - 1, totalRows: rowCount))
                        }
                    }
                    .listSectionSpacing(4)

                    if index == vm.exercises.count - 1, vm.sessionStatus != .discarded {
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
            .environment(\.defaultMinListRowHeight, 28)
            .scrollContentBackground(.hidden)
            .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        }
        .overlay {
            if showingActiveRestChrome, let visual = vm.restTimerVisual {
                RestTimerPerimeterOnly(visual: visual)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if showingActiveRestChrome, let visual = vm.restTimerVisual {
                RestTimerToastBar(
                    visual: visual,
                    oledPreference: loggyOLEDDark,
                    colorScheme: colorScheme,
                    onSkip: { vm.skipRest() },
                    onAdjust: { vm.adjustRestTimer(by: $0) }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.restRemaining)
        .navigationTitle(vm.sessionStatus == .active ? " " : "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(
            ActiveWorkoutNavigationBarChromeForRestRing(
                restRingObscuresBar: showingActiveRestChrome,
                oledPreference: loggyOLEDDark,
                colorScheme: colorScheme
            )
        )
        .toolbar {
            if vm.sessionStatus == .active {
                ToolbarItem(placement: .principal) {
                    Text(vm.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Workout" : vm.sessionTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Text(formatClock(vm.elapsedSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Menu {
                            Button("Rename workout…") {
                                renameWorkoutDraft = vm.sessionTitle
                                showRenameWorkout = true
                            }
                            Divider()
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
        .onReceive(NotificationCenter.default.publisher(for: .loggyActiveWorkoutMutated)) { note in
            guard let sid = note.object as? String, sid == vm.sessionId else { return }
            vm.reload()
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet(onPickMany: { ids in
                vm.addExercises(exerciseIds: ids)
                showExercisePicker = false
            })
            .environmentObject(env)
        }
        .sheet(item: $howToTarget) { target in
            NavigationStack {
                ExerciseInfoView(exerciseId: target.id, showDismissInToolbar: true)
                    .environmentObject(env)
            }
        }
        .sheet(item: $replaceExerciseTarget) { target in
            ReplaceExerciseSheet(
                currentExerciseId: target.currentExerciseId,
                exerciseMode: target.exerciseMode,
                onPick: { newId in
                    vm.replaceSessionExercise(sessionExerciseId: target.sessionExerciseId, newExerciseId: newId)
                }
            )
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
                },
                onDiscard: {
                    vm.discard()
                    showFinishSheet = false
                    dismiss()
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
        .alert("Rename workout", isPresented: $showRenameWorkout) {
            TextField("Workout title", text: $renameWorkoutDraft)
            Button("Save") {
                vm.updateSessionTitle(renameWorkoutDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                showRenameWorkout = false
            }
            Button("Cancel", role: .cancel) {
                showRenameWorkout = false
            }
        } message: {
            Text("This title appears in the header and in your history.")
        }
        .sheet(isPresented: Binding(
            get: { restTargetPickerExerciseId != nil },
            set: { if !$0 { restTargetPickerExerciseId = nil } }
        )) {
            NavigationStack {
                VStack(spacing: 0) {
                    Picker("Rest duration", selection: $restTargetPickerDraftSeconds) {
                        ForEach(Self.restTargetSecondChoices, id: \.self) { sec in
                            Text(formatRestTimerHuman(sec)).tag(sec)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxHeight: 180)
                }
                .navigationTitle("Rest timer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            restTargetPickerExerciseId = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if let id = restTargetPickerExerciseId {
                                vm.updateRestTarget(sessionExerciseId: id, seconds: restTargetPickerDraftSeconds)
                            }
                            restTargetPickerExerciseId = nil
                        }
                    }
                }
            }
            .presentationDetents([.height(280)])
        }
        .sheet(isPresented: Binding(
            get: { notesSheetExerciseId != nil },
            set: { if !$0 { notesSheetExerciseId = nil } }
        )) {
            NavigationStack {
                TextEditor(text: $notesSheetDraft)
                    .font(.body)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .navigationTitle("Exercise notes")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                notesSheetExerciseId = nil
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let trimmed = notesSheetDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                if let id = notesSheetExerciseId {
                                    vm.updateNotes(sessionExerciseId: id, notes: trimmed)
                                }
                                notesSheetExerciseId = nil
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func exerciseSectionRowCount(card: SessionExerciseCard) -> Int {
        let addRow = vm.sessionStatus != .discarded ? 1 : 0
        return 4 + card.sets.count + addRow
    }

    @ViewBuilder
    private func exerciseCardListRowBackground(rowIndex: Int, totalRows: Int) -> some View {
        let fill = LoggyTheme.elevatedGroupedCard(oledPreference: loggyOLEDDark, colorScheme: colorScheme)
        let r = DesignTokens.cardCornerRadius
        let isFirst = rowIndex == 0
        let isLast = rowIndex == totalRows - 1
        let stroke = LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme)
            ? Color.white.opacity(0.08)
            : Color.primary.opacity(0.06)

        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? r : 0,
            bottomLeadingRadius: isLast ? r : 0,
            bottomTrailingRadius: isLast ? r : 0,
            topTrailingRadius: isFirst ? r : 0,
            style: .continuous
        )
        .fill(fill)
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: isFirst ? r : 0,
                bottomLeadingRadius: isLast ? r : 0,
                bottomTrailingRadius: isLast ? r : 0,
                topTrailingRadius: isFirst ? r : 0,
                style: .continuous
            )
            .strokeBorder(stroke, lineWidth: isFirst || isLast ? 1 : 0)
        )
        .shadow(
            color: .black.opacity(isLast ? 0.06 : 0),
            radius: isLast ? DesignTokens.cardShadowRadius : 0,
            y: isLast ? DesignTokens.cardShadowY : 0
        )
    }

    private func exerciseCardTitleRow(card: SessionExerciseCard, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                howToTarget = ExerciseHowToTarget(id: card.exerciseId)
            } label: {
                Text(card.displayName)
                    .font(.headline.weight(.semibold))
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

                    Button {
                        replaceExerciseTarget = ReplaceExerciseTarget(
                            sessionExerciseId: card.id,
                            currentExerciseId: card.exerciseId,
                            exerciseMode: card.exerciseMode
                        )
                    } label: {
                        Label("Replace exercise…", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Divider()

                    Button(role: .destructive) {
                        sessionExercisePendingRemoval = card.id
                    } label: {
                        Label("Remove exercise", systemImage: "minus.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func exerciseCardNotesRow(card: SessionExerciseCard) -> some View {
        let trimmed = (card.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            guard vm.sessionStatus != .discarded else { return }
            notesSheetExerciseId = card.id
            notesSheetDraft = card.notes ?? ""
        } label: {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if trimmed.isEmpty {
                    Text("Notes")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(trimmed)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vm.sessionStatus == .discarded)
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func exerciseCardRestPickerRow(card: SessionExerciseCard) -> some View {
        let seconds = Self.snapRestTargetSeconds(card.targetRestSeconds)
        return Button {
            guard vm.sessionStatus != .discarded else { return }
            restTargetPickerExerciseId = card.id
            restTargetPickerDraftSeconds = seconds
        } label: {
            Text("⏱️ Rest Timer: \(seconds)s")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(vm.sessionStatus == .discarded)
        .padding(.horizontal, 16)
        .padding(.vertical, 1)
    }

    private var addExerciseAndSuggestionBlock: some View {
        HStack(spacing: 0) {
            Button {
                showExercisePicker = true
            } label: {
                Label("Add exercise", systemImage: "plus.circle.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1)
                .padding(.vertical, 6)

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
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
        .background(addExerciseBarFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme)
                        ? Color.white.opacity(0.1)
                        : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .padding(.vertical, 4)
    }

    private var addExerciseBarFill: AnyShapeStyle {
        if LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme) {
            AnyShapeStyle(Color(white: 0.1))
        } else {
            AnyShapeStyle(.regularMaterial)
        }
    }

    private var summaryStrip: some View {
        let healthOn = appleHealth.syncWorkoutsToHealthEnabled
        return VStack(alignment: .leading, spacing: 6) {
            healthSyncStatusLine(healthOn: healthOn)
            HStack(spacing: 8) {
                summaryMetricColumn(title: "Elapsed", value: formatClock(vm.elapsedSeconds))
                Spacer(minLength: 0)
                summaryMetricColumn(title: "Volume", value: "\(Int(vm.totalVolume)) kg")
                Spacer(minLength: 0)
                summaryMetricColumn(title: "Sets", value: "\(vm.completedSetCount)")
                Spacer(minLength: 0)
                summaryMetricColumn(title: "Reps", value: "\(vm.totalRepCount)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(summaryStripFill, in: RoundedRectangle(cornerRadius: DesignTokens.materialCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .padding(.horizontal, 0)
        .padding(.top, 8)
    }

    private func healthSyncStatusLine(healthOn: Bool) -> some View {
        let bpm = appleHealth.latestHeartRateBpm
        let energyText: String? = {
            guard healthOn, let start = vm.sessionStartedAt else { return nil }
            if let hk = appleHealth.cumulativeActiveEnergyHealthKitKcal, hk > 0.5 {
                return "\(Int(hk)) kcal"
            }
            let est = appleHealth.estimatedSessionEnergyKcalSoFar(sessionStartedAt: start)
            return "~\(Int(est)) kcal"
        }()
        return HStack(alignment: .center, spacing: 6) {
            if healthOn {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Live sync active")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 6, height: 6)
                Text("Health sync off")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if healthOn, bpm != nil || energyText != nil {
                HStack(spacing: 4) {
                    if let bpm {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.9))
                            Text("\(bpm) bpm")
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if bpm != nil, energyText != nil {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let energyText {
                        Text(energyText)
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
        )
    }

    private func summaryMetricColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryStripFill: AnyShapeStyle {
        if LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme) {
            AnyShapeStyle(LoggyTheme.structuralBarFill(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        } else {
            AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private func formatRestTimerHuman(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0, s > 0 { return "\(m)m \(s)s" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    /// 0…600 s in 15 s steps for rest target picker.
    private static let restTargetSecondChoices: [Int] = Array(stride(from: 0, through: 600, by: 15))

    private static func snapRestTargetSeconds(_ raw: Int?) -> Int {
        let v = max(0, min(600, raw ?? 90))
        let rounded = (Double(v) / 15.0).rounded() * 15
        return max(0, min(600, Int(rounded)))
    }

    @ViewBuilder
    private func exerciseSetTableHeader(mode: ExerciseMode) -> some View {
        HStack(spacing: 4) {
            Text("SET")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            Text("PREVIOUS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch mode {
            case .weightReps:
                Text("KG")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                Text("REPS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            case .bodyweightReps:
                Text("REPS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .trailing)
            case .duration:
                Text("SEC")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            case .distanceDuration:
                Text("KM")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                Text("SEC")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            Image(systemName: "checkmark.circle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme) ? 0.08 : 0.04))
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
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscardFromSummary = false

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
                Section {
                    Button("Discard workout…", role: .destructive) {
                        confirmDiscardFromSummary = true
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Discard removes this session from history. Use if the workout was started by mistake or is invalid.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
            .confirmationDialog(
                "Discard this workout? Nothing will be saved.",
                isPresented: $confirmDiscardFromSummary,
                titleVisibility: .visible
            ) {
                Button("Discard workout", role: .destructive) {
                    onDiscard()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

/// Bottom toast for rest: does not reserve vertical space in the scroll stack (no nav bar jump).
private struct RestTimerToastBar: View {
    let visual: RestTimerVisual
    let oledPreference: Bool
    let colorScheme: ColorScheme
    let onSkip: () -> Void
    let onAdjust: (Int) -> Void

    private var oledCanvas: Bool {
        LoggyTheme.isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme)
    }

    private var toastFill: AnyShapeStyle {
        if oledCanvas {
            AnyShapeStyle(Color(white: 0.14).opacity(0.72))
        } else {
            AnyShapeStyle(.thinMaterial)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 0.12)) { timeline in
                let sec = max(0, Int(ceil(visual.endsAt.timeIntervalSince(timeline.date))))
                Text("\(sec)s")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .leading)
            }
            Spacer(minLength: 4)
            Button {
                onAdjust(-15)
            } label: {
                Text("−15")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                onAdjust(15)
            } label: {
                Text("+15")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            Button("Skip", action: onSkip)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            toastFill,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(oledCanvas ? 0.12 : 0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
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

/// Opaque nav bars draw above destination content and hide the top segment of the full-screen rest ring; hide bar chrome only while rest is active.
private struct ActiveWorkoutNavigationBarChromeForRestRing: ViewModifier {
    let restRingObscuresBar: Bool
    let oledPreference: Bool
    let colorScheme: ColorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if restRingObscuresBar {
            content.toolbarBackground(.hidden, for: .navigationBar)
        } else {
            content
                .toolbarBackground(
                    LoggyTheme.navigationBarBackground(oledPreference: oledPreference, colorScheme: colorScheme),
                    for: .navigationBar
                )
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private enum RestRingLayout {
    /// Physical screen rect in global coordinates (navigation content is inset; ring must use screen, not content size).
    static func screenBounds() -> CGRect {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first {
            return scene.screen.bounds
        }
        return .zero
    }
}

private struct RestTimerPerimeterOnly: View {
    let visual: RestTimerVisual

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { timeline in
            let total = max(visual.endsAt.timeIntervalSince(visual.startedAt), 0.001)
            let remainingInterval = max(0, visual.endsAt.timeIntervalSince(timeline.date))
            let progress = CGFloat(min(1, remainingInterval / total))

            GeometryReader { geometry in
                let localInGlobal = geometry.frame(in: .global)
                let screen = RestRingLayout.screenBounds()
                let offsetX = screen.minX - localInGlobal.minX
                let offsetY = screen.minY - localInGlobal.minY

                ZStack {
                    ScreenBorderShape()
                        .stroke(Color.orange.opacity(0.38), lineWidth: 9)

                    ScreenBorderShape()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.cyan, .blue, .purple, .cyan]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .animation(.linear(duration: 0.05), value: progress)
                }
                .frame(width: screen.width, height: screen.height)
                .offset(x: offsetX, y: offsetY)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            .allowsHitTesting(false)
        }
    }
}

private struct SetRow: View {
    let mode: ExerciseMode
    let set: SetRowModel
    let canMutate: Bool
    let oledPreference: Bool
    let colorScheme: ColorScheme
    var embeddedInTable: Bool = false
    var isAlternatingShaded: Bool = false
    let onChange: (Double?, Int?, Double?, Int?, Double?) -> Void
    let onToggleCompletion: () -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var durText: String = ""
    @State private var distText: String = ""

    private var rowBackground: Color {
        if embeddedInTable {
            if set.status == .completed {
                return Color.green.opacity(LoggyTheme.isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme) ? 0.14 : 0.10)
            }
            if isAlternatingShaded {
                return Color.primary.opacity(LoggyTheme.isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme) ? 0.06 : 0.03)
            }
            return Color.clear
        }
        return Color.clear
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            Text(set.previousDisplay)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            fieldsInline

            Button(action: onToggleCompletion) {
                Image(systemName: set.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(set.status == .completed ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canMutate)
            .accessibilityLabel(set.status == .completed ? "Completed — tap to undo" : "Mark complete")
        }
        .padding(.vertical, embeddedInTable ? 2 : 6)
        .padding(.horizontal, embeddedInTable ? 16 : 10)
        .background(
            embeddedInTable
                ? rowBackground
                : LoggyTheme.setRowSurface(oledPreference: oledPreference, colorScheme: colorScheme)
        )
        .overlay(alignment: .bottom) {
            if !embeddedInTable {
                Divider()
            }
        }
        .onAppear { syncFromSet(set) }
        .onChange(of: set) { _, new in
            syncFromSet(new)
        }
    }

    @ViewBuilder
    private var fieldsInline: some View {
        switch mode {
        case .weightReps:
            HStack(spacing: 4) {
                inlineField("kg", text: $weightText, keyboard: .decimalPad) {
                    onChange(parseDouble(weightText), parseInt(repsText), nil, nil, nil)
                }
                inlineField("reps", text: $repsText, keyboard: .numberPad) {
                    onChange(parseDouble(weightText), parseInt(repsText), nil, nil, nil)
                }
            }
        case .bodyweightReps:
            inlineField("reps", text: $repsText, keyboard: .numberPad) {
                onChange(nil, parseInt(repsText), nil, nil, nil)
            }
        case .duration:
            inlineField("sec", text: $durText, keyboard: .numberPad) {
                onChange(nil, nil, nil, parseInt(durText), nil)
            }
        case .distanceDuration:
            HStack(spacing: 4) {
                inlineField("km", text: $distText, keyboard: .decimalPad) {
                    onChange(nil, nil, parseDouble(distText), parseInt(durText), nil)
                }
                inlineField("sec", text: $durText, keyboard: .numberPad) {
                    onChange(nil, nil, parseDouble(distText), parseInt(durText), nil)
                }
            }
        }
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

    private func inlineField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        commit: @escaping () -> Void
    ) -> some View {
        let fieldFill = Color(UIColor.secondarySystemFill)
        let fieldStroke = Color.primary.opacity(
            LoggyTheme.isOLEDDarkCanvas(oledPreference: oledPreference, colorScheme: colorScheme) ? 0.14 : 0.1
        )
        return TextField(title, text: text)
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
            .frame(minWidth: 40, idealWidth: 52, maxWidth: 76)
            .lineLimit(1)
            .disabled(!canMutate)
            .onSubmit(commit)
            .onChange(of: text.wrappedValue) { _, _ in commit() }
    }

    private var label: String {
        switch set.setType {
        case .warmup: return "W"
        case .normal: return "\(set.setIndex + 1)"
        default: return set.setType.rawValue.uppercased()
        }
    }

    private func syncFromSet(_ set: SetRowModel) {
        weightText = set.weightKg.map { String($0) } ?? ""
        repsText = set.reps.map(String.init) ?? ""
        durText = set.durationSeconds.map(String.init) ?? ""
        distText = set.distanceKm.map { String($0) } ?? ""
    }
}
