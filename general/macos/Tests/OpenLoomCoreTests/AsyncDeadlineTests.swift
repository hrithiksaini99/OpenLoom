import Foundation
import OpenLoomCore
import Testing

actor NonCooperativeOperation {
    private var value: Int?
    private var continuation: CheckedContinuation<Int, Never>?
    func wait() async -> Int {
        if let value { return value }
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ value: Int) {
        self.value = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@Suite struct AsyncDeadlineTests {
    @Test func missingFrameworkCallbackDoesNotHoldCallerIndefinitely() async throws {
        let framework = NonCooperativeOperation(), clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await AsyncDeadline.run(timeout: .milliseconds(25)) { await framework.wait() }
            Issue.record("Expected a deadline")
        } catch OpenLoomError.processingTimedOut {
            #expect(clock.now - start < .seconds(1))
        }
        await framework.finish(7) // A late completion must neither crash nor resume the caller twice.
    }

    @Test func cancellationReturnsWithoutJoiningNonCooperativeWork() async throws {
        let framework = NonCooperativeOperation()
        let task = Task { try await AsyncDeadline.run(timeout: .seconds(30)) { await framework.wait() } }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        await framework.finish(9)
    }

    @Test func normalCompletionAndFailureArePreserved() async throws {
        #expect(try await AsyncDeadline.run(timeout: .seconds(1)) { 42 } == 42)
        await #expect(throws: OpenLoomError.self) {
            _ = try await AsyncDeadline.run(timeout: .seconds(1)) { () -> Int in throw OpenLoomError.noMedia }
        }
    }

    @Test func cancellingDuringAnAlreadyStartedCallbackWaitReturnsPromptly() async throws {
        let framework = NonCooperativeOperation(), clock = ContinuousClock()
        let task = Task { try await AsyncDeadline.run(timeout: .seconds(30)) { await framework.wait() } }
        try await Task.sleep(for: .milliseconds(10))
        let start = clock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.now - start < .seconds(1))
        await framework.finish(1)
    }
}
