#if os(iOS)
import Foundation
import UIKit

/// App-owned bridge to the existing request-scoped intelligence cleanup path.
/// Memory warnings must never cancel recording or a different heavy resource.
@MainActor
final class IntelligenceMemoryPressureMonitor {
    // Test-first seam: the observer and cancellation behavior await hosted RED.
    init(center: NotificationCenter = .default,
         activeSession: @escaping @MainActor () -> IntelligenceSession?) {}
}
#endif
