#if os(iOS)
import SwiftUI

@MainActor
struct IntelligenceProgressView: View {
    let title: String
    let detail: String
    var counterText: String? = nil
    var explanation: String? = nil
    let display: IntelligenceProgressDisplay
    let cancel: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headingLayout {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text("\(display.percentage)%")
                    .font(.title2.weight(.semibold)).monospacedDigit().fixedSize()
                    .accessibilityLabel("\(display.percentage) percent complete")
                    .accessibilityIdentifier("meeting.intelligence.percentage")
            }
            ProgressView(value: display.fraction)
                .accessibilityLabel("Generation progress")
                .accessibilityValue("\(display.percentage) percent")
                .accessibilityIdentifier("meeting.intelligence.progress")
            VStack(alignment: .leading, spacing: 8) {
                Text(detail).font(.subheadline.weight(.semibold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("meeting.intelligence.phase")
                if let counterText {
                    Text(counterText).font(.subheadline).monospacedDigit()
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("meeting.intelligence.counter")
                }
                if let explanation {
                    Text(explanation).font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("meeting.intelligence.explanation")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            timingLayout {
                metric("Elapsed", value: display.elapsedText, identifier: "meeting.intelligence.elapsed")
                metric("Estimated remaining", value: display.remainingText, identifier: "meeting.intelligence.remaining")
            }
            Button("Cancel", role: .cancel, action: cancel)
                .buttonStyle(MinutesButtonStyle(kind: .secondary))
        }
        .minutesCard()
        .accessibilityElement(children: .contain)
    }

    private var headingLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    }

    private var timingLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }

    private func metric(_ label: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
#endif
