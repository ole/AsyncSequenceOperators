extension AsyncSequence {
  public func buffer(_ size: Int) -> BufferedAsyncSequence<Self> {
    BufferedAsyncSequence(base: self, size: size)
  }
}

public struct BufferedAsyncSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element

  public let bufferSize: Int
  private let base: Base

  public init(base: Base, size: Int) {
    precondition(size > 0, "Buffer size '\(size)' must be a positive number")
    self.base = base
    self.bufferSize = size
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base, bufferSize: bufferSize)
  }

  public actor Iterator: AsyncIteratorProtocol {
    let base: Base
    let bufferSize: Int
    private var buffer: [Result<Element, Error>] = []
    private var didStartFillBuffer: Bool = false
    private var baseIsExhausted: Bool = false
    private var nextCanProceed: CheckedContinuation<Void, Never>? = nil
    private var fillBufferCanProceed: CheckedContinuation<Void, Never>? = nil

    public init(base: Base, bufferSize: Int) {
      precondition(bufferSize > 0, "Buffer size '\(bufferSize)' must be a positive number")
      self.base = base
      self.bufferSize = bufferSize
    }

    /// The number of elements currently sitting in the buffer.
    /// Useful for unit tests for this type, but may also be interesting to regular clients.
    public var bufferCount: Int {
      self.buffer.count
    }

    public func next() async throws -> Element? {
      if !didStartFillBuffer {
        Task {
          await fillBuffer()
        }
      }

      guard !(self.buffer.isEmpty && self.baseIsExhausted) else {
        // We have delivered all elements.
        return nil
      }

      if self.buffer.isEmpty {
        // Wait until `fillBuffer` has added at least one element to the buffer.
        await withCheckedContinuation { continuation in
          self.nextCanProceed = continuation
        }
      }

      switch self.buffer.first {
      case let e?:
        self.buffer.removeFirst()
        if self.buffer.count <= self.bufferSize {
          // Signal `fillBuffer`
          self.fillBufferCanProceed?.resume()
          self.fillBufferCanProceed = nil
        }
        return try e.get()
      case nil:
        // There's no item in the buffer despite our waiting for `nextCanProceed` above
        // → `base` must be exhausted.
        assert(self.baseIsExhausted)
        return nil
      }
    }

    /// Starts filling the buffer with elements from `base` and keeps the buffer full
    /// as elements are removed from the buffer.
    ///
    /// Must be called exactly once when iteration starts from inside a `Task { … }`.
    private func fillBuffer() async {
      precondition(!self.didStartFillBuffer, "Must not call fillBuffer more than once")
      self.didStartFillBuffer = true

      self.buffer.reserveCapacity(bufferSize)
      var iterator = self.base.makeAsyncIterator()
      while true {
        if self.buffer.count >= self.bufferSize {
          // Wait until buffer has capacity.
          await withCheckedContinuation { continuation in
            self.fillBufferCanProceed = continuation
          }
        }
        defer {
          self.nextCanProceed?.resume()
          self.nextCanProceed = nil
        }
        do {
          if let n = try await iterator.next() {
            self.buffer.append(.success(n))
          } else {
            self.baseIsExhausted = true
            // `base` is exhausted → end iteration
            return
          }
        } catch {
          self.buffer.append(.failure(error))
          // Error thrown by base → end iteration
          return
        }
      }
    }
  }
}
