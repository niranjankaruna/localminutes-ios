#if os(iOS)
import Foundation
import Observation
import SwiftUI
import UIKit

/// TEST-FIRST boundary only. The actual scene/window observer and opaque cover
/// must remain unimplemented until hosted assertion RED is recorded.
@MainActor @Observable
final class RecordingPrivacyController {
    static let coverAccessibilityIdentifier = "localminutes.privacy.cover"
    private(set) var isObscured = false
    @ObservationIgnored private let center: NotificationCenter

    init(center: NotificationCenter = .default) { self.center = center }
    func attach(to window: UIWindow?) {}
}

/// This is the same root boundary used by the application and hosted window
/// tests. The window probe discovers the real owning window without replacing
/// capture resources or constructing a different application instance.
@MainActor
struct RecordingPrivacyRoot<Content: View>: View {
    let controller: RecordingPrivacyController
    private let content: Content

    init(controller: RecordingPrivacyController, @ViewBuilder content: () -> Content) {
        self.controller = controller; self.content = content()
    }

    var body: some View {
        content.background(RecordingPrivacyWindowAttachment(controller: controller).frame(width: 0, height: 0))
    }
}

@MainActor
private struct RecordingPrivacyWindowAttachment: UIViewRepresentable {
    let controller: RecordingPrivacyController
    func makeUIView(context: Context) -> RecordingPrivacyWindowProbe {
        RecordingPrivacyWindowProbe(controller: controller)
    }
    func updateUIView(_ view: RecordingPrivacyWindowProbe, context: Context) {
        view.controller = controller
        controller.attach(to: view.window)
    }
}

@MainActor
private final class RecordingPrivacyWindowProbe: UIView {
    weak var controller: RecordingPrivacyController?
    init(controller: RecordingPrivacyController) {
        self.controller = controller
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { return nil }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        controller?.attach(to: window)
    }
}
#endif
