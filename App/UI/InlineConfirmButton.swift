import SwiftUI

/// Hevy-style two-tap inline confirmation. The first tap morphs the trigger in place to "Tap to confirm" with a destructive tint; a second tap inside the timeout invokes the action.
///
/// We use this instead of `.confirmationDialog` for trigger-anchored destructive actions because iOS always docks confirmation dialogs to the bottom of the screen, far from the source button (the user's exact complaint about "Discard workout" appearing nowhere near the trash).
struct InlineConfirmButton<Idle: View, Armed: View>: View {
    enum Style { case button, menuRow }

    let style: Style
    let role: ButtonRole?
    let timeout: TimeInterval
    let action: () -> Void
    @ViewBuilder let idleLabel: () -> Idle
    @ViewBuilder let armedLabel: () -> Armed

    @State private var isArmed = false
    @State private var revertWork: DispatchWorkItem?

    init(
        style: Style = .button,
        role: ButtonRole? = .destructive,
        timeout: TimeInterval = 3,
        action: @escaping () -> Void,
        @ViewBuilder idleLabel: @escaping () -> Idle,
        @ViewBuilder armedLabel: @escaping () -> Armed
    ) {
        self.style = style
        self.role = role
        self.timeout = timeout
        self.action = action
        self.idleLabel = idleLabel
        self.armedLabel = armedLabel
    }

    var body: some View {
        Button(role: role) {
            tap()
        } label: {
            Group {
                if isArmed { armedLabel() } else { idleLabel() }
            }
            .contentShape(Rectangle())
        }
        .onDisappear {
            revertWork?.cancel()
            revertWork = nil
        }
    }

    private func tap() {
        if isArmed {
            revertWork?.cancel()
            revertWork = nil
            isArmed = false
            LoggyFeedback.destructiveCommitted()
            action()
        } else {
            isArmed = true
            LoggyFeedback.destructiveArmed()
            scheduleRevert()
        }
    }

    private func scheduleRevert() {
        revertWork?.cancel()
        let work = DispatchWorkItem {
            isArmed = false
            LoggyFeedback.destructiveCancelled()
        }
        revertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }
}

extension InlineConfirmButton where Idle == Label<Text, Image>, Armed == Label<Text, Image> {
    /// Convenience for menu items: idle "Discard workout" with trash icon flips to "Tap to confirm" with exclamation icon.
    static func menuRow(
        title: String,
        confirmTitle: String = "Tap to confirm",
        systemImage: String = "trash",
        timeout: TimeInterval = 3,
        action: @escaping () -> Void
    ) -> InlineConfirmButton<Label<Text, Image>, Label<Text, Image>> {
        InlineConfirmButton<Label<Text, Image>, Label<Text, Image>>(
            style: .menuRow,
            role: .destructive,
            timeout: timeout,
            action: action,
            idleLabel: { Label(title, systemImage: systemImage) },
            armedLabel: { Label(confirmTitle, systemImage: "exclamationmark.triangle.fill") }
        )
    }
}
