import Foundation
@testable import WriteItDown

/// Test-only checkout double. It never creates a real session or charge.
final class MockCheckoutClient: CheckoutClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<URL, Error>
    private var storedCalls = 0

    init(result: Result<URL, Error> = .success(URL(string: "https://checkout.stripe.com/c/pay/test")!)) {
        storedResult = result
    }

    var isConfigured: Bool { true }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }

    func createCheckoutSession() async throws -> URL {
        try nextResult()
    }

    private func nextResult() throws -> URL {
        lock.lock()
        storedCalls += 1
        let result = storedResult
        lock.unlock()
        return try result.get()
    }
}
