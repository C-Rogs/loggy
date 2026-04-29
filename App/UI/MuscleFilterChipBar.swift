import SwiftUI

/// Horizontal “All” + primary-muscle chips; binds to `exercise.primary_muscle_group` slug or `nil` for all.
struct MuscleFilterChipBar: View {
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", slug: nil)
                ForEach(MuscleTaxonomy.primaryFilterSlugs, id: \.self) { slug in
                    chip(
                        title: MuscleTaxonomy.filterChipLabel(forSlug: slug),
                        slug: slug
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func chip(title: String, slug: String?) -> some View {
        let isOn = slug == nil ? selection == nil : selection == slug
        return Button {
            selection = slug
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slug == nil ? "All muscles" : title)
        .accessibilityHint(slug == nil ? "Show exercises for every muscle" : "Filter by this muscle")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
