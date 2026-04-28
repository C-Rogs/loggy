import Foundation

public enum MuscleDisplayName {
    /// Human-readable label for a stored taxonomy slug (e.g. `upper back` → `Upper back`).
    public static func forStoredSlug(_ slug: String) -> String {
        let t = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return slug }
        return t.split(separator: " ")
            .map { part in
                let s = String(part)
                guard let c = s.first else { return s }
                return String(c).uppercased() + s.dropFirst()
            }
            .joined(separator: " ")
    }
}
