import Foundation

/// Wrappers around `assert` and `precondition` that take concrete
/// `Bool`/`String` values instead of `@autoclosure` parameters.
/// This moves the compiler-generated implicit closures out of calling
/// code and into this file, which can be excluded from coverage reports.

func assertExcludeCoverage(
    _ condition: Bool,
    _ message: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    assert(condition, message, file: file, line: line)
}

func preconditionExcludeCoverage(
    _ condition: Bool,
    _ message: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    precondition(condition, message, file: file, line: line)
}
