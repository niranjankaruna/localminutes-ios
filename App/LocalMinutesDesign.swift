#if os(iOS)
import SwiftUI
import UIKit

/// Shared native surfaces and controls. Let iOS own optical sizing, navigation,
/// sheet gestures and system dialogs; adapt custom content to accessibility.
enum MinutesStyle {
    static let pageInset: CGFloat = 20
    static let readableWidth: CGFloat = 760
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1)
            : UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)
    })
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.439, green: 0.678, blue: 1, alpha: 1)
            : UIColor(red: 0, green: 0.396, blue: 0.831, alpha: 1)
    })
    static let recording = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.412, blue: 0.38, alpha: 1)
            : UIColor(red: 0.76, green: 0.13, blue: 0.11, alpha: 1)
    })

    static func timestamp(samples: Int64) -> String {
        duration(seconds: max(0, samples) / 16_000)
    }

    static func duration(seconds: Int64) -> String {
        let seconds = max(0, seconds)
        if seconds >= 3_600 {
            return String(format: "%02lld:%02lld:%02lld", seconds / 3_600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02lld:%02lld", seconds / 60, seconds % 60)
    }

    static func meetingDuration(samples: Int64) -> String {
        let seconds = max(0, samples) / 16_000
        if seconds < 60 { return "\(seconds) sec" }
        if seconds < 3_600 { return "\(seconds / 60) min" }
        return "\(seconds / 3_600) hr \(seconds / 60 % 60) min"
    }

    static func bytes(_ value: Int64?, memory: Bool = false) -> String {
        guard let value, value >= 0 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: memory ? .memory : .file)
    }
}

struct MinutesButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, destructiveSecondary }
    var kind: Kind = .primary
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primary: MinutesStyle.accent
        case .secondary: MinutesStyle.accent.opacity(0.08)
        case .destructive: MinutesStyle.recording
        case .destructiveSecondary: MinutesStyle.recording.opacity(0.1)
        }
    }

    private var foreground: Color {
        if kind == .secondary { return MinutesStyle.accent }
        if kind == .destructiveSecondary { return MinutesStyle.recording }
        return colorScheme == .dark ? Color(uiColor: .black) : .white
    }
}

struct MinutesPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
    }
}

struct MinutesEmptyState: View {
    let title: String
    let symbol: String
    var detail: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var identifier: String = ""
    var actionIdentifier: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.largeTitle.weight(.regular))
                .foregroundStyle(MinutesStyle.accent)
                .frame(minWidth: 76, minHeight: 76)
                .background(MinutesStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
            if let detail {
                Text(detail).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(MinutesButtonStyle())
                    .accessibilityIdentifier(actionIdentifier)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: 440)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

struct MinutesMessage: View {
    let text: String
    var symbol = "info.circle"
    var isError = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isError && symbol == "info.circle" ? "exclamationmark.circle.fill" : symbol)
                .foregroundStyle(isError ? MinutesStyle.recording : MinutesStyle.accent)
                .accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .font(.callout)
        .lineSpacing(3)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MinutesStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct MinutesProgress: View {
    let title: String
    var detail: String? = nil
    var cancel: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let cancel {
                Button("Cancel", role: .cancel, action: cancel)
                    .buttonStyle(MinutesButtonStyle(kind: .secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    func minutesList() -> some View {
        scrollContentBackground(.hidden)
            .background(MinutesStyle.background)
            .tint(MinutesStyle.accent)
            .listStyle(.insetGrouped)
    }

    func minutesCard() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(MinutesSurface())
    }

    func minutesChrome() -> some View { modifier(MinutesChrome()) }
    func minutesSheet(compact: Bool = false) -> some View { modifier(MinutesSheet(compact: compact)) }
}

private struct MinutesSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .background(MinutesStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(contrast == .increased ? Color.primary.opacity(0.5) : .clear, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct MinutesChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency || contrast == .increased { MinutesStyle.background }
            else { Rectangle().fill(.regularMaterial) }
        }
    }
}

private struct MinutesSheet: ViewModifier {
    let compact: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    func body(content: Content) -> some View {
        content
            .presentationDetents(compact && !typeSize.isAccessibilitySize ? [.medium, .large] : [.large])
            .presentationDragIndicator(.visible)
            .tint(MinutesStyle.accent)
    }
}

/// A menu preserves full-size labels when segmented controls cannot grow with
/// accessibility text. Both presentations retain native selection semantics.
struct MinutesChoicePicker<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [Selection]
    let label: (Selection) -> String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel(title)
                    .accessibilityValue(label(selection))
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(MinutesStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            } else {
                picker.pickerStyle(.segmented).frame(minHeight: 44)
            }
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in Text(label(option)).tag(option) }
        }
    }
}

struct MinutesLabeledValue: View {
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        layout {
            Text(title).foregroundStyle(.primary)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
            Text(value).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    }
}

struct MinutesActions<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) { content }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { content }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { content }
            }
        }
    }
}

enum MeetingContentTab: String, CaseIterable, Identifiable {
    case summary = "Summary", transcript = "Transcript", notes = "Notes", ask = "Ask"
    var id: Self { self }
}

struct MeetingContentPicker: View {
    @Binding var selection: MeetingContentTab
    var body: some View {
        MinutesChoicePicker(title: "Meeting content", selection: $selection,
            options: MeetingContentTab.allCases, label: { $0.rawValue })
            .accessibilityIdentifier("meeting.content.tabs")
    }
}
#endif
