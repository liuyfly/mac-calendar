import Foundation

/// A tiny assertion harness.
///
/// XCTest and swift-testing both ship with full Xcode, not with the Command
/// Line Tools, so `swift test` is unavailable here. These tests are compiled
/// straight against the sources by `scripts/run_tests.sh` instead. Swapping
/// this file for a real XCTest target is a drop-in change once Xcode is
/// installed.
enum TestRunner {
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var currentSuite = ""

    static func suite(_ name: String, _ body: () -> Void) {
        currentSuite = name
        let before = failures.count
        body()
        let failed = failures.count - before
        let mark = failed == 0 ? "✓" : "✗"
        print("  \(mark) \(name)\(failed == 0 ? "" : "  (\(failed) failed)")")
    }

    static func expect(_ condition: Bool, _ message: @autoclosure () -> String,
                       line: UInt = #line) {
        checks += 1
        if !condition {
            failures.append("[\(currentSuite):\(line)] \(message())")
        }
    }

    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                                          _ context: @autoclosure () -> String = "",
                                          line: UInt = #line) {
        checks += 1
        if actual != expected {
            let suffix = context().isEmpty ? "" : " — \(context())"
            failures.append("[\(currentSuite):\(line)] expected \(expected), got \(actual)\(suffix)")
        }
    }

    static func report() -> Int32 {
        print("")
        if failures.isEmpty {
            print("All \(checks) checks passed.")
            return 0
        }
        print("\(failures.count) of \(checks) checks failed:")
        for failure in failures { print("  • \(failure)") }
        return 1
    }
}

func expect(_ condition: Bool, _ message: @autoclosure () -> String = "", line: UInt = #line) {
    TestRunner.expect(condition, message(), line: line)
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                               _ context: @autoclosure () -> String = "",
                               line: UInt = #line) {
    TestRunner.expectEqual(actual, expected, context(), line: line)
}

/// Local noon on the given day, matching how the app builds its grid.
func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar.date(from: DateComponents(
        year: year, month: month, day: dayOfMonth, hour: 12))!
}
