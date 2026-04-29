import Foundation

/// Cancels a pending delayed task and schedules `operation` after `nanoseconds` on the main actor.
enum MainActorDebouncer {
    static func reschedule(
        _ task: inout Task<Void, Never>?,
        nanoseconds: UInt64 = 280_000_000,
        operation: @escaping @MainActor () -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            operation()
        }
    }
}
