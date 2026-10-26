#if os(iOS)
import SwiftUI
import UIKit

/// Semantic colors from the approved FigCraft design. Native text styles keep
/// optical sizing, Dynamic Type and accessibility settings owned by iOS.
enum MinutesStyle {
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
            : UIColor(red: 0.851, green: 0.176, blue: 0.153, alpha: 1)
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

    static func bytes(_ value: Int64?, memory: Bool = false) -> String {
        guard let value, value >= 0 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: memory ? .memory : .file)
    }
}

struct MinutesButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primary: MinutesStyle.accent
        case .secondary: Color(uiColor: .tertiarySystemFill)
        case .destructive: MinutesStyle.recording
        }
    }

    private var foreground: Color {
        if kind == .secondary { return MinutesStyle.accent }
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

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 68, height: 68)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 21))
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                .accessibilityIdentifier(identifier)
            if let detail {
                Text(detail).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(MinutesButtonStyle())
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 36)
    }
}

struct MinutesMessage: View {
    let text: String
    var symbol = "info.circle"
    var isError = false

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(isError ? MinutesStyle.recording : MinutesStyle.accent)
        }
        .font(.callout)
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
            Text(title).font(.title2.weight(.semibold))
            if let detail { Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if let cancel {
                Button("Cancel", role: .cancel, action: cancel)
                    .buttonStyle(MinutesButtonStyle(kind: .secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    func minutesList() -> some View {
        scrollContentBackground(.hidden)
            .background(MinutesStyle.background)
            .tint(MinutesStyle.accent)
    }

    func minutesCard() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MinutesStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

enum MeetingContentTab: String, CaseIterable, Identifiable {
    case summary = "Summary", transcript = "Transcript", notes = "Notes", ask = "Ask"
    var id: Self { self }
}

/// A segmented picker at standard sizes; a horizontally scrolling row at
/// accessibility sizes so labels never shrink below the user's text setting.
struct MeetingContentPicker: View {
    @Binding var selection: MeetingContentTab
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(MeetingContentTab.allCases) { tab in
                        Button(tab.rawValue) { selection = tab }
                            .font(.body.weight(selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .background(selection == tab ? MinutesStyle.surface : Color.clear,
                                        in: Capsule())
                            .accessibilityIdentifier("meeting.tab.\(tab.id)")
                            .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                    }
                }
            }
        } else {
            Picker("Meeting content", selection: $selection) {
                ForEach(MeetingContentTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityIdentifier("meeting.content.tabs")
        }
    }
}
#endif
