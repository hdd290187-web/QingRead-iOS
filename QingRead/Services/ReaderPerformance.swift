import Foundation

/// Fixed operation names only: no book text, title, file path, or user identifiers.
enum ReaderWork: String, CaseIterable {
    case fileRead, attributedText, pagination, scrollLayout, cellConfiguration
    case scrollCallback, chapterUpdate, progressCommit
}

enum ReaderPerformance {
    @discardableResult
    static func measure<T>(_ work: ReaderWork, _ operation: () throws -> T) rethrows -> T {
        #if DEBUG
        guard ReaderPerformanceRecorder.shared.enabled else { return try operation() }
        let start = ProcessInfo.processInfo.systemUptime
        let onMain = Thread.isMainThread
        let interval = ReaderPerformanceRecorder.shared.begin(work)
        defer { ReaderPerformanceRecorder.shared.end(work, interval: interval, start: start, onMain: onMain) }
        #endif
        return try operation()
    }
}

#if DEBUG
import UIKit
import OSLog
import Darwin

final class ReaderPerformanceRecorder {
    static let shared = ReaderPerformanceRecorder()
    private let launchEnabled = ProcessInfo.processInfo.arguments.contains("--reader-performance")
    private var testEnabled = false
    private let lock = NSLock()
    var enabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return launchEnabled || testEnabled
    }
    private let signposter = OSSignposter(subsystem: "com.hdd290187.qingread", category: "ReaderPerformance")
    private var operations: [String: [Double]] = [:]
    private var mainOperations: [String: [Double]] = [:]
    private var viewport: [String: Any] = [:]
    func enableForTesting(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        testEnabled = enabled; operations.removeAll(); mainOperations.removeAll()
    }
    func recordViewport(width: CGFloat, height: CGFloat, visibleLines: Int) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        viewport = ["width": width, "height": height, "initialVisibleLines": visibleLines]
    }
    func begin(_ work: ReaderWork) -> OSSignpostIntervalState {
        signposter.beginInterval("ReaderWork", "operation=\(work.rawValue, privacy: .public)")
    }
    func end(_ work: ReaderWork, interval: OSSignpostIntervalState, start: Double, onMain: Bool) {
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        signposter.endInterval("ReaderWork", interval)
        lock.lock(); defer { lock.unlock() }
        operations[work.rawValue, default: []].append(milliseconds)
        if onMain { mainOperations[work.rawValue, default: []].append(milliseconds) }
    }
    func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        func summarize(_ samples: [Double]) -> [String: Any] {
            let sorted = samples.sorted()
            return ["count": samples.count, "totalMs": samples.reduce(0, +), "maxMs": sorted.last ?? 0,
                    "p95Ms": sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]]
        }
        return ["operations": operations.mapValues(summarize), "mainThreadOperations": mainOperations.mapValues(summarize), "viewport": viewport]
    }
}

/// Display-link sampling observes native UIScrollView tracking/deceleration. It
/// never changes the scroll offset, refresh rate, or the system's natural inertia.
@MainActor
final class ReaderFrameProbe: NSObject {
    private weak var table: UITableView?
    private var displayLink: CADisplayLink?
    private var frames: [Double] = []
    private var budgets: [Double] = []
    private var previousTimestamp: CFTimeInterval?
    private var wasActive = false
    private var peakResidentBytes: UInt64 = 0
    private var ticks = 0
    func attach(to table: UITableView) {
        guard ReaderPerformanceRecorder.shared.enabled else { return }
        displayLink?.invalidate(); self.table = table
        previousTimestamp = nil; wasActive = false
        let link = CADisplayLink(target: self, selector: #selector(sample(_:)))
        link.add(to: .main, forMode: .common); displayLink = link
    }
    @objc private func sample(_ link: CADisplayLink) {
        guard let table else { stop(); return }
        let active = table.isTracking || table.isDragging || table.isDecelerating
        if active, wasActive, let previousTimestamp {
            frames.append((link.timestamp - previousTimestamp) * 1000)
            budgets.append(max(0.001, link.targetTimestamp - link.timestamp) * 1000)
        }
        previousTimestamp = link.timestamp; wasActive = active
        ticks += 1
        if ticks % 30 == 0 {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
            let capacity = Int(count)
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            if status == KERN_SUCCESS { peakResidentBytes = max(peakResidentBytes, UInt64(info.resident_size)) }
        }
    }
    func stop() {
        displayLink?.invalidate(); displayLink = nil
        guard ReaderPerformanceRecorder.shared.enabled else { return }
        var report = ReaderPerformanceRecorder.shared.snapshot()
        let sorted = frames.sorted()
        report["activeScrollFrames"] = frames.count
        report["frameP95Ms"] = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
        report["frameMaxMs"] = sorted.last ?? 0
        report["framesOver1_5Budgets"] = zip(frames, budgets).filter { $0.0 > $0.1 * 1.5 }.count
        report["peakResidentBytes"] = peakResidentBytes
        report["environment"] = "\(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion)"
        #if targetEnvironment(simulator)
        report["simulator"] = true
        #else
        report["simulator"] = false
        #endif
        report["fixture"] = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--uitest-performance=") }?.components(separatedBy: "=").last ?? "manual"
        report["baseline"] = ProcessInfo.processInfo.arguments.contains("--reader-baseline")
        let immutableReport = report
        guard let data = try? JSONSerialization.data(withJSONObject: immutableReport, options: [.prettyPrinted, .sortedKeys]) else { return }
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ReaderPerformance", isDirectory: true)
        let fixture = immutableReport["fixture"] as? String ?? "manual"
        let variant = immutableReport["baseline"] as? Bool == true ? "baseline" : "optimized"
        let destination = root.appendingPathComponent("\(fixture)-\(variant).json")
        // Reopening/background checks must not overwrite an active gesture sample
        // with a second session that contains no actual scrolling.
        if let previous = try? Data(contentsOf: destination),
           let value = try? JSONSerialization.jsonObject(with: previous) as? [String: Any],
           (value["activeScrollFrames"] as? Int ?? 0) > frames.count { return }
        // A dedicated synthetic-test report, separate from the library and books.
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? data.write(to: destination, options: .atomic)
        frames.removeAll(); budgets.removeAll()
    }
    deinit { displayLink?.invalidate() }
}
#endif
