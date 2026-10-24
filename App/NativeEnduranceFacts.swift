#if os(iOS)
import Foundation

enum NativeEnduranceFacts {
    // TEST-FIRST OS boundary only. Actual resident/battery/thermal/route probes
    // remain absent until native measurement assertions have observed RED.
    static func current(visibility: MetricsVisibility) -> EnduranceSystemFacts {
        .init(visibility: visibility)
    }
}
#endif
