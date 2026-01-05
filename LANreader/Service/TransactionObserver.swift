import StoreKit

actor TransactionObserver {

    private var updates: Task<Void, Never>?

    init() {}

    func start() {
        guard updates == nil else { return }
        updates = Task(priority: .background) {
            for await verificationResult in Transaction.updates {
                await self.handle(updatedTransaction: verificationResult)
            }
        }
    }

    func cancel() {
        updates?.cancel()
        updates = nil
    }

    private func handle(updatedTransaction verificationResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verificationResult else {
            // Ignore unverified transactions.
            return
        }

        await transaction.finish()
    }
}
