import SwiftUI

/// Inline **ⓘ** control so screens stay clean — calculation detail lives in a popover (see ``presentationCompactAdaptation``).
struct LoggyInfoTipButton: View {
    let title: String
    let message: String
    var accessibilityLabel: String = "More information"
    /// Optional second step (e.g. open the full educational sheet).
    var moreLabel: String?
    var onMore: (() -> Void)?

    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $showDetail) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let moreLabel, let onMore {
                        Button(moreLabel) {
                            showDetail = false
                            onMore()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(14)
                .frame(minWidth: 260, maxWidth: 320, alignment: .leading)
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}
