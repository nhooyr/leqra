/// Serializes audio-session changes while the UI can replace its playback intent.
/// The injected system operations must suspend or dispatch their blocking work.
@MainActor
public final class AudioSessionLifecycle {
    private let activate: @MainActor () async throws -> Void
    private let deactivate: @MainActor () async -> Void
    private let ready: @MainActor () throws -> Void
    private let failed: @MainActor () -> Void
    private var active = false
    private var activationStale = false
    private var activationEpoch: UInt64 = 0
    private var revision: UInt64 = 0
    private var transition: Task<Void, Never>?

    public init(activate: @escaping @MainActor () async throws -> Void,
                deactivate: @escaping @MainActor () async -> Void,
                ready: @escaping @MainActor () throws -> Void,
                failed: @escaping @MainActor () -> Void) {
        self.activate = activate
        self.deactivate = deactivate
        self.ready = ready
        self.failed = failed
    }

    /// Interruptions and route resets can invalidate a session without an app
    /// request. Preserve cleanup ownership while requiring fresh activation.
    public func invalidateActivation() {
        activationEpoch &+= 1
        activationStale = true
    }

    /// Returns a completion fence. Replace intent with another request rather
    /// than canceling the task: a submitted system operation still completes.
    @discardableResult
    public func request(_ desired: Bool) -> Task<Void, Never> {
        revision &+= 1
        let requestedRevision = revision, previous = transition
        let task = Task { @MainActor [self] in
            await previous?.value
            defer { if revision == requestedRevision { transition = nil } }
            guard revision == requestedRevision else { return }
            if desired {
                do {
                    if !active || activationStale {
                        let submittedEpoch = activationEpoch
                        try await activate()
                        // Even a superseded activation changed the real session.
                        // Its queued successor must be able to deactivate it.
                        active = true
                        if activationEpoch == submittedEpoch { activationStale = false }
                    }
                    guard revision == requestedRevision, !activationStale else { return }
                    try ready()
                } catch {
                    // Activation can partly succeed, and ready can start I/O
                    // before throwing. The injected cleanup handles both.
                    await deactivate()
                    active = false
                    if revision == requestedRevision { failed() }
                }
            } else if active {
                await deactivate()
                active = false
            }
        }
        transition = task
        return task
    }
}
