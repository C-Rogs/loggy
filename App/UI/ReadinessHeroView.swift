import SwiftUI

/// Glass summary card with staggered SF Symbol glyphs (recovery / readiness).
struct ReadinessHeroView: View {
    let insight: ReadinessInsight?
    var isLoading: Bool = false
    /// Smaller layout for the Coach start sheet.
    var compact: Bool = false
    var onLearnMore: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @State private var appeared = false

    private var cornerRadius: CGFloat { compact ? 14 : 18 }

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .accessibilityLabel("Loading readiness from Apple Health")
                    Text("Loading readiness…")
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(compact ? 12 : 16)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(cardFillStyle)
                )
                .accessibilityElement(children: .combine)
            } else if let insight {
                readinessCard(insight)
            }
        }
        .onAppear {
            prepareAppearAnimation()
        }
        .onChange(of: insight?.band) { _, _ in
            prepareAppearAnimation()
        }
    }

    private func prepareAppearAnimation() {
        guard !reduceMotion else {
            appeared = true
            return
        }
        appeared = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }

    private var cardFillStyle: AnyShapeStyle {
        if LoggyTheme.isOLEDDarkCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme) {
            return AnyShapeStyle(Color.white.opacity(0.06))
        }
        return AnyShapeStyle(Material.ultraThinMaterial)
    }

    private func readinessCard(_ insight: ReadinessInsight) -> some View {
        let accent = accentColor(for: insight.band)
        let corners = insight.glyphCorners
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardFillStyle)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.55),
                                    LoggyTheme.readinessAccentSecondary(for: insight.band, accent: accent),
                                    accent.opacity(0.38),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: accent.opacity(0.22), radius: compact ? 8 : 14, y: compact ? 4 : 6)

            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    primaryGlyph(symbol: insight.glyphPrimary, accent: accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.headline)
                            .font(compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(insight.subline)
                            .font(compact ? .caption2 : .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if insight.usesPersonalizedThresholds {
                            Label("Adapts to your Apple Health patterns", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(accent.opacity(0.92))
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if !compact {
                    Button(action: onLearnMore) {
                        Label("About this insight", systemImage: "info.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                }
            }
            .padding(compact ? EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 46) : EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 54))

            if corners.count > 0 {
                cornerGlyph(symbol: corners[0], accent: accent, delay: 0, rotation: -11)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(compact ? 10 : 14)
            }
            if corners.count > 1 {
                cornerGlyph(symbol: corners[1], accent: accent, delay: 0.07, rotation: 13)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, compact ? 8 : 10)
                    .padding(.top, compact ? 36 : 44)
            }
            if corners.count > 2 {
                cornerGlyph(symbol: corners[2], accent: accent, delay: 0.12, rotation: -9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(compact ? 8 : 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func accentColor(for band: ReadinessBand) -> Color {
        LoggyTheme.readinessAccent(for: band, oledPreference: loggyOLEDDark, colorScheme: colorScheme)
    }

    private func primaryGlyph(symbol: String, accent: Color) -> some View {
        let scale = appeared ? 1.0 : (reduceMotion ? 1.0 : 0.2)
        let offset = appeared ? 0.0 : (reduceMotion ? 0 : -12)
        return Image(systemName: symbol)
            .font(.system(size: compact ? 26 : 34, weight: .semibold))
            .foregroundStyle(accent)
            .scaleEffect(scale)
            .offset(y: offset)
            .modifier(SymbolBounceIfAvailable(isActive: appeared && !reduceMotion))
            .accessibilityHidden(true)
    }

    private func cornerGlyph(symbol: String, accent: Color, delay: Double, rotation: Double) -> some View {
        let scale = appeared ? 1.0 : (reduceMotion ? 1.0 : 0.25)
        let opacity = appeared ? 1.0 : (reduceMotion ? 1.0 : 0)
        return Image(systemName: symbol)
            .font(.system(size: compact ? 15 : 18, weight: .bold))
            .foregroundStyle(accent.opacity(0.88))
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(
                reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.68).delay(delay),
                value: appeared
            )
            .accessibilityHidden(true)
    }
}

/// Applies bounce symbol effect on iOS 17+ when reduce motion is off.
private struct SymbolBounceIfAvailable: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.symbolEffect(.bounce, value: isActive)
        } else {
            content
        }
    }
}

/// Educational copy for recovery insights (Apple Health sources).
struct ReadinessLearnMoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Loggy combines sleep duration and heart rate variability (HRV) from Apple Health when available. Apple Watch is the most common source.")
                        .font(.body)
                    Text("After enough mornings with sleep data—and enough daily HRV ratios—short sleep and HRV tiers gently adapt to you instead of generic population cutoffs.")
                        .font(.body)
                    Text("HRV here means SDNN—the same metric stored in Health. We compare a recent sample to your typical range over about two weeks.")
                        .font(.body)
                    Text("This is not a forecast of performance and not a machine-learning model—just transparent rules so the coach can set expectations on Home.")
                        .font(.body)
                    Text("This is guidance only—not medical advice. It does not replace your own judgment or a care team. Live BPM during workouts still appears only when a device writes heart rate to Health during training.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
            .navigationTitle("Recovery insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(
                LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
