import XCTest

func AsyncAssertEqual<T: Equatable>(
  _ expression1: @autoclosure () async throws -> T,
  _ expression2: @autoclosure () async throws -> T,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    let r1 = try await expression1()
    let r2 = try await expression2()
    XCTAssertEqual(r1, r2, message(), file: file, line: line)
  } catch {
    XCTFail("Thrown error: \(error)", file: file, line: line)
  }
}
