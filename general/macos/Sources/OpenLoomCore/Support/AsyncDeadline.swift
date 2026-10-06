import Foundation

/// A framework may ignore Task cancellation. A deadline must return without joining that task.
/// Late framework completions are ignored; callers must check cancellation before committing files/state.
public enum AsyncDeadline {
    public static func run<Value: Sendable>(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let completion = Completion<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard completion.install(continuation) else { return }
                let worker = Task {
                    do { try Task.checkCancellation(); completion.resolve(.success(try await operation())) }
                    catch { completion.resolve(.failure(error)) }
                }
                completion.register(worker)
                let timer = Task {
                    do { try await Task.sleep(for: timeout) } catch { return }
                    completion.resolve(.failure(OpenLoomError.processingTimedOut))
                }
                completion.register(timer)
            }
        } onCancel: {
            completion.resolve(.failure(CancellationError()))
        }
    }

    private final class Completion<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Value, any Error>?
        private var continuation: CheckedContinuation<Value, any Error>?
        private var tasks: [Task<Void, Never>] = []

        func install(_ continuation: CheckedContinuation<Value, any Error>) -> Bool {
            let result: Result<Value, any Error>? = lock.withLock {
                if let result { return result }
                self.continuation = continuation
                return nil
            }
            if let result { continuation.resume(with: result) }
            return result == nil
        }

        func register(_ task: Task<Void, Never>) {
            let finished = lock.withLock {
                if result != nil { return true }
                tasks.append(task)
                return false
            }
            if finished { task.cancel() }
        }

        func resolve(_ result: Result<Value, any Error>) {
            let pending: (CheckedContinuation<Value, any Error>?, [Task<Void, Never>])? = lock.withLock {
                guard self.result == nil else { return nil }
                self.result = result
                let pending = (continuation, tasks)
                continuation = nil
                tasks = []
                return pending
            }
            guard let pending else { return }
            for task in pending.1 { task.cancel() }
            pending.0?.resume(with: result)
        }
    }
}
