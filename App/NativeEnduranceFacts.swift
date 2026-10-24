#if os(iOS)
import Foundation
import Darwin
import AVFoundation
import UIKit

@MainActor
enum NativeEnduranceFacts {
    static func current(visibility: MetricsVisibility) -> EnduranceSystemFacts {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let resident: Int64? = status == KERN_SUCCESS && info.resident_size > 0
            ? Int64(exactly: info.resident_size) : nil
        let thermal: EnduranceThermalState
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .unknown
        }
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let battery: EnduranceBatteryState
        switch device.batteryState {
        case .unknown: battery = .unknown
        case .unplugged: battery = .unplugged
        case .charging: battery = .charging
        case .full: battery = .full
        @unknown default: battery = .unknown
        }
        let level = device.batteryLevel
        let percent: Int? = level.isFinite && (0...1).contains(level) ? Int((level * 100).rounded()) : nil
        let inputs = AVAudioSession.sharedInstance().currentRoute.inputs
        let route: EnduranceAudioRoute
        if let port = inputs.first?.portType {
            switch port {
            case .builtInMic: route = .builtInMicrophone
            case .headsetMic: route = .headsetMicrophone
            case .bluetoothHFP: route = .bluetoothMicrophone
            case .usbAudio: route = .usbMicrophone
            default: route = .unknown
            }
        } else { route = .unavailable }
        return .init(residentMemoryBytes: resident, thermal: thermal,
            batteryLevelPercent: percent, batteryState: battery, route: route, visibility: visibility)
    }
}
#endif
