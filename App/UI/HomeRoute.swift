import Foundation

/// Navigation destinations for the home `NavigationStack`.
public enum HomeRoute: Hashable {
    case active(String)
    case history(String)
    /// Completed (or non-active) workout inline editor.
    case editor(String)
}
