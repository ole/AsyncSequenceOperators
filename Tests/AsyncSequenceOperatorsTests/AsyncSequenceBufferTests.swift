import AsyncSequenceOperators
import XCTest

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
final class AsyncSequenceBufferTests: XCTestCase {
  func testBuffer() async throws {
    let pipe = makePipe(of: String.self)

    let iterator = pipe.output.buffer(2).makeAsyncIterator()
    await AsyncAssertEqual(await iterator.bufferCount, 0)

    pipe.input.yield("a")
    await AsyncAssertEqual(await iterator.bufferCount, 0)

    pipe.input.yield("b")
    pipe.input.yield("c")
    pipe.input.yield("d")

    await AsyncAssertEqual(try await iterator.next(), "a")
    try await Task.sleep(nanoseconds: 100_000)
    await AsyncAssertEqual(await iterator.bufferCount, 2)

    pipe.input.finish()
    await AsyncAssertEqual(try await iterator.next(), "b")
    await AsyncAssertEqual(try await iterator.next(), "c")
  }

  func testBufferCount() async throws {
    let iterator = [1, 2, 3].async().buffer(3).makeAsyncIterator()
    _ = try await iterator.next()
    try await Task.sleep(nanoseconds: 100_000)
    await AsyncAssertEqual(await iterator.bufferCount, 2)
  }
}

#else

final class AsyncSequenceBufferTests: XCTestCase {
  func skippedBecauseNoAsyncSupport() throws {
    throw XCTSkip("Corelibs-XCTest doesn't support async test functions")
    #if swift(>=5.6)
    #error("Check if Corelibs-XCTest supports async test functions now")
    #endif
  }
}

#endif

func makePipe<Element>(
  of elementType: Element.Type = Element.self
) -> (input: AsyncStream<Element>.Continuation, output: AsyncStream<Element>) {
  var continuation: AsyncStream<Element>.Continuation? = nil
  let stream = AsyncStream<Element> {
    continuation = $0
  }
  return (continuation!, stream)
}

extension AsyncSequence {
  /// Collects all elements of the async sequence into an array.
  func collect() async throws -> [Element] {
    try await self.reduce(into: []) { partialResult, element in
      partialResult.append(element)
    }
  }
}

extension Sequence {
  /// Turns a sync Sequence into an AsyncSequence.
  func async() -> AsyncStream<Element> {
    let pipe = makePipe(of: Element.self)
    for x in self {
      pipe.input.yield(x)
    }
    pipe.input.finish()
    return pipe.output
  }
}
