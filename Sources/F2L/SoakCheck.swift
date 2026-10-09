import AppKit
import CoachCore
import Darwin

/// `F2L --soak [seconds]` runs Pip the way a learner leaves it (resting, a greeting, then a lesson with a circled target
/// and the walking Pip) without network, microphone, screen capture or keyboard focus, and reports how much CPU time
/// and memory F2L used in each phase, so a busy loop or a leak shows up as a number.
@MainActor
enum SoakCheck {
    struct Usage: Sendable { var cpu: Double; var memoryMB: Double }

    nonisolated static func usage() -> Usage {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return Usage(cpu: cpu, memoryMB: result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0)
    }

    static func run(seconds: Double) {
        let store = ConversationStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("f2l-soak-\(UUID().uuidString).json"))
        let companion = CompanionController(coach: CoachClient(apiKey: { "" }), store: store, testing: true)
        companion.show()
        Task { @MainActor in
            var lines: [String] = []
            var worst = 0.0
            @MainActor func phase(_ name: String, _ body: () -> Void) async {
                body()
                try? await Task.sleep(for: .seconds(1)) // let the phase settle (reveal animation, walking)
                let start = usage(), began = Date()
                try? await Task.sleep(for: .seconds(seconds))
                let end = usage(), elapsed = Date().timeIntervalSince(began)
                let percent = (end.cpu - start.cpu) / elapsed * 100
                worst = max(worst, percent)
                lines.append(String(format: "%@: %.1f%% CPU, %.0f MB (%+.1f MB)", name, percent, end.memoryMB, end.memoryMB - start.memoryMB))
            }
            await phase("resting Pip + greeting") { companion.sampleGreeting(); companion.revealSample() }
            await phase("lesson step") {
                companion.seedSample(question: "Select two ranges", reply: "Select both groups.",
                                     steps: ["Click A1, then hold Shift and click A4.", "Hold Command and drag from D1 to D4."])
                companion.revealSample()
            }
            let work = ScreenSpace.workArea(at: CGPoint(x: 400, y: 400))
            await phase("circle + walking Pip") { companion.simulateTarget(CGRect(x: work.minX + 220, y: work.minY + 240, width: 120, height: 32)) }
            await phase("after 50 more replies") {
                for i in 0..<50 { companion.seedSample(question: "Question \(i)", reply: "Answer \(i). Click the cell, then type.") }
                companion.revealSample()
            }
            // The heaviest per-step work: reading a window picture (Apple Vision), as each lesson step does.
            for attempt in ["first", "second"] {
                let before = usage(), began = Date()
                let readFailures = ScreenReadingCheck.run()
                let after = usage()
                lines.append(String(format: "reading a window picture (%@): %.2f s, %.2f s CPU, %.0f MB after%@", attempt, Date().timeIntervalSince(began),
                                    after.cpu - before.cpu, after.memoryMB, readFailures.isEmpty ? "" : " (" + readFailures.joined(separator: "; ") + ")"))
            }
            companion.shutdown()
            try? FileManager.default.removeItem(at: store.url)
            lines.forEach { print($0) }
            // Idle Pip should stay well under a few percent of one core.
            let ok = worst < 15
            print(ok ? "Soak check passed (worst \(String(format: "%.1f", worst))% CPU)" : "FAIL: F2L used \(String(format: "%.1f", worst))% CPU in one phase")
            fflush(stdout)
            exit(ok ? 0 : 1)
        }
    }
}
