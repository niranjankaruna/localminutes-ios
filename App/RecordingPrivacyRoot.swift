#if os(iOS)
import Foundation
import Observation
import SwiftUI
import UIKit

/// Covers only the attached window. Scene transitions never acquire or release
/// recording resources; the app-owned capture coordinator remains independent.
@MainActor @Observable
final class RecordingPrivacyController {
    static let coverAccessibilityIdentifier = "localminutes.privacy.cover"
    private(set) var isObscured = false
    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored private weak var window: UIWindow?
    @ObservationIgnored private var cover: UIView?
    @ObservationIgnored private var hiddenContent: [(UIView, Bool)] = []
    @ObservationIgnored private var observation: RecordingPrivacyObservation?

    init(center: NotificationCenter = .default) { self.center = center }

    func attach(to window: UIWindow?) {
        guard self.window !== window else { return }
        reveal()
        observation = nil
        self.window = window
        guard let window, let scene = window.windowScene else { return }

        let observation = RecordingPrivacyObservation(center: center)
        for name in [UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                     UIScene.didActivateNotification] {
            let activationEvent = name == UIScene.didActivateNotification
            observation.tokens.append(center.addObserver(forName: name, object: scene, queue: .main) {
                [weak self, weak window, weak scene] notification in
                let matchesOwningScene = notification.object as? UIScene === scene
                // The main operation queue invokes this synchronously for UIKit's
                // main-thread scene notifications. No Task or animation delays
                // protection until after the OS snapshot boundary.
                MainActor.assumeIsolated {
                    guard let self, let window, let scene,
                          self.window === window,
                          window.windowScene === scene,
                          matchesOwningScene else { return }
                    if activationEvent {
                        self.reveal()
                    } else {
                        self.obscure(window)
                    }
                }
            })
        }
        self.observation = observation
        if scene.activationState == .background || scene.activationState == .foregroundInactive {
            obscure(window)
        }
    }

    private func obscure(_ window: UIWindow) {
        let cover: UIView
        if let existing = self.cover {
            cover = existing
        } else {
            cover = UIView(frame: window.bounds)
            cover.accessibilityIdentifier = Self.coverAccessibilityIdentifier
            cover.backgroundColor = .black
            cover.isOpaque = true
            cover.alpha = 1
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.cover = cover
        }
        // UIKit may place the hosting controller inside a transition container.
        // Hide both that window container and the actual hosted content root;
        // accessibilityElementsHidden is not inherited as a property value.
        var contentViews = window.subviews
        if let rootView = window.rootViewController?.viewIfLoaded { contentViews.append(rootView) }
        for view in contentViews where view !== cover {
            if !hiddenContent.contains(where: { $0.0 === view }) {
                hiddenContent.append((view, view.accessibilityElementsHidden))
            }
            view.accessibilityElementsHidden = true
        }
        cover.frame = window.bounds
        cover.isHidden = false
        window.addSubview(cover)
        window.bringSubviewToFront(cover)
        isObscured = true
    }

    private func reveal() {
        cover?.removeFromSuperview()
        cover = nil
        for (view, wasHidden) in hiddenContent { view.accessibilityElementsHidden = wasHidden }
        hiddenContent.removeAll()
        isObscured = false
    }

    deinit {
        // UIKit cleanup stays on its actor even if the last reference is released
        // elsewhere. Observer removal is independently synchronous and thread-safe.
        let cover = cover
        let hiddenContent = hiddenContent
        Task { @MainActor in
            cover?.removeFromSuperview()
            for (view, wasHidden) in hiddenContent { view.accessibilityElementsHidden = wasHidden }
        }
    }
}

/// Tokens are mutated only while attaching on the main actor. NotificationCenter
/// permits removal from the thread which releases this lifetime holder.
private final class RecordingPrivacyObservation: @unchecked Sendable {
    let center: NotificationCenter
    var tokens: [any NSObjectProtocol] = []
    init(center: NotificationCenter) { self.center = center }
    deinit { for token in tokens { center.removeObserver(token) } }
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
