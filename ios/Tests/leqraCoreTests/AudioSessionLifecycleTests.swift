import XCTest
@testable import leqraCore

@MainActor
final class AudioSessionLifecycleTests: XCTestCase {
    private enum Failure: Error { case activation, readiness }

    @MainActor private final class Gate {
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if open { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            open = true
            let pending = waiters; waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    @MainActor private final class Backend {
        var events: [String] = []
        var activation: (@MainActor () async throws -> Void)?
        var deactivation: (@MainActor () async -> Void)?
        var readiness: (@MainActor () throws -> Void)?

        func lifecycle() -> AudioSessionLifecycle {
            AudioSessionLifecycle(activate: { [self] in
                events.append("activate")
                try await activation?()
                events.append("activated")
            }, deactivate: { [self] in
                events.append("deactivate")
                await deactivation?()
                events.append("deactivated")
            }, ready: { [self] in
                events.append("ready")
                try readiness?()
            }, failed: { [self] in events.append("failed") })
        }
    }

    func testPauseDuringActivationCleansUpWithoutStartingPlayback() async {
        let backend = Backend(), started = Gate(), completion = Gate()
        backend.activation = { started.release(); await completion.wait() }
        let lifecycle = backend.lifecycle(), activation = lifecycle.request(true)
        await started.wait()
        let pause = lifecycle.request(false)
        XCTAssertEqual(backend.events, ["activate"])
        completion.release()
        await activation.value; await pause.value
        XCTAssertEqual(backend.events, ["activate", "activated", "deactivate", "deactivated"])
    }

    func testActivationPauseResumeCoalescesToLatestIntentWithoutDeactivating() async {
        let backend = Backend(), started = Gate(), completion = Gate()
        backend.activation = { started.release(); await completion.wait() }
        let lifecycle = backend.lifecycle(), activation = lifecycle.request(true)
        await started.wait()
        let supersededPause = lifecycle.request(false), resume = lifecycle.request(true)
        completion.release()
        await activation.value; await supersededPause.value; await resume.value
        XCTAssertEqual(backend.events, ["activate", "activated", "ready"])
    }

    func testResumeWaitsForAlreadySubmittedDeactivation() async {
        let backend = Backend(), started = Gate(), completion = Gate()
        backend.deactivation = { started.release(); await completion.wait() }
        let lifecycle = backend.lifecycle()
        await lifecycle.request(true).value
        let pause = lifecycle.request(false)
        await started.wait()
        let resume = lifecycle.request(true)
        XCTAssertEqual(backend.events, ["activate", "activated", "ready", "deactivate"])
        completion.release()
        await pause.value; await resume.value
        XCTAssertEqual(backend.events, ["activate", "activated", "ready", "deactivate", "deactivated",
                                        "activate", "activated", "ready"])
    }

    func testSupersededPauseIsSkippedBeforeItReachesTheSystem() async {
        let backend = Backend(), lifecycle = backend.lifecycle()
        await lifecycle.request(true).value
        let pause = lifecycle.request(false), resume = lifecycle.request(true)
        await pause.value; await resume.value
        XCTAssertEqual(backend.events, ["activate", "activated", "ready", "ready"])
    }

    func testSupersededUnsubmittedActivationDoesNotTouchTheSystem() async {
        let backend = Backend(), lifecycle = backend.lifecycle()
        let activate = lifecycle.request(true), pause = lifecycle.request(false)
        await activate.value; await pause.value
        XCTAssertEqual(backend.events, [])
    }

    func testActivationErrorCleansUpAndCanRetry() async {
        let backend = Backend()
        backend.activation = { throw Failure.activation }
        let lifecycle = backend.lifecycle()
        await lifecycle.request(true).value
        XCTAssertEqual(backend.events, ["activate", "deactivate", "deactivated", "failed"])
        backend.activation = nil
        await lifecycle.request(true).value
        XCTAssertEqual(backend.events, ["activate", "deactivate", "deactivated", "failed",
                                        "activate", "activated", "ready"])
    }

    func testReadinessErrorDeactivatesBeforeReportingFailureAndCanRetry() async {
        let backend = Backend()
        backend.readiness = { throw Failure.readiness }
        let lifecycle = backend.lifecycle()
        await lifecycle.request(true).value
        XCTAssertEqual(backend.events, ["activate", "activated", "ready", "deactivate", "deactivated", "failed"])
        backend.readiness = nil
        await lifecycle.request(true).value
        XCTAssertEqual(backend.events.suffix(3), ["activate", "activated", "ready"])
    }

    func testSupersededFailureCannotDisableANewerPlaybackRequest() async {
        let backend = Backend(), started = Gate(), completion = Gate()
        backend.activation = { started.release(); await completion.wait(); throw Failure.activation }
        let lifecycle = backend.lifecycle(), first = lifecycle.request(true)
        await started.wait()
        let resume = lifecycle.request(true)
        backend.activation = nil
        completion.release()
        await first.value; await resume.value
        XCTAssertEqual(backend.events, ["activate", "deactivate", "deactivated", "activate", "activated", "ready"])
    }

    func testErrorCleanupCompletesBeforeNewActivationEvenWhenItSuspends() async {
        let backend = Backend(), cleaning = Gate(), completion = Gate()
        backend.readiness = { throw Failure.readiness }
        backend.deactivation = { cleaning.release(); await completion.wait() }
        let lifecycle = backend.lifecycle(), first = lifecycle.request(true)
        await cleaning.wait()
        let resume = lifecycle.request(true)
        backend.readiness = nil
        XCTAssertEqual(backend.events, ["activate", "activated", "ready", "deactivate"])
        completion.release()
        await first.value; await resume.value
        XCTAssertEqual(backend.events, ["activate", "activated", "ready", "deactivate", "deactivated",
                                        "activate", "activated", "ready"])
    }

    func testQueuedTeardownFinishesAfterTheOwnersReferenceIsReleased() async {
        let backend = Backend(), started = Gate(), completion = Gate()
        backend.activation = { started.release(); await completion.wait() }
        var lifecycle: AudioSessionLifecycle? = backend.lifecycle()
        let activation = lifecycle!.request(true)
        await started.wait()
        let teardown = lifecycle!.request(false)
        let remaining = { [weak lifecycle] in lifecycle }
        lifecycle = nil
        XCTAssertNotNil(remaining(), "The submitted operation retains its serialized cleanup owner")
        completion.release()
        await activation.value; await teardown.value
        XCTAssertEqual(backend.events, ["activate", "activated", "deactivate", "deactivated"])
        XCTAssertNil(remaining(), "Completed task chains must not retain the coordinator")
    }

    func testCancelingACompletionFenceDoesNotLoseSubmittedSessionState() async {
        let backend = Backend(), started = Gate(), completion = Gate()
        backend.activation = { started.release(); await completion.wait() }
        let lifecycle = backend.lifecycle(), activation = lifecycle.request(true)
        await started.wait()
        activation.cancel()
        let pause = lifecycle.request(false)
        completion.release()
        await activation.value; await pause.value
        XCTAssertEqual(backend.events, ["activate", "activated", "deactivate", "deactivated"])
    }

    func testFastInterruptionEndReactivatesEvenWhenItsPauseWasSuperseded() async {
        let backend = Backend(), lifecycle = backend.lifecycle()
        await lifecycle.request(true).value
        lifecycle.invalidateActivation()
        let pause = lifecycle.request(false), resume = lifecycle.request(true)
        await pause.value; await resume.value
        XCTAssertEqual(backend.events, ["activate", "activated", "ready", "activate", "activated", "ready"],
                       "The OS invalidated the old activation even though the queued pause was skipped")
    }

    func testInterruptionDuringSubmittedActivationCannotValidateTheNewSession() async {
        let backend = Backend(), started = Gate(), completion = Gate()
        var submissions = 0
        backend.activation = {
            submissions += 1
            if submissions == 1 { started.release(); await completion.wait() }
        }
        let lifecycle = backend.lifecycle(), activation = lifecycle.request(true)
        await started.wait()
        lifecycle.invalidateActivation()
        let pause = lifecycle.request(false), resume = lifecycle.request(true)
        completion.release()
        await activation.value; await pause.value; await resume.value
        XCTAssertEqual(backend.events, ["activate", "activated", "activate", "activated", "ready"])
    }

    func testInvalidatedInFlightActivationSuppressesReadinessUntilExplicitRecovery() async {
        let backend = Backend(), started = Gate(), completion = Gate()
        backend.activation = { started.release(); await completion.wait() }
        let lifecycle = backend.lifecycle(), activation = lifecycle.request(true)
        await started.wait()
        lifecycle.invalidateActivation()
        completion.release()
        await activation.value
        XCTAssertEqual(backend.events, ["activate", "activated"])
        backend.activation = nil
        await lifecycle.request(true).value
        XCTAssertEqual(backend.events, ["activate", "activated", "activate", "activated", "ready"])
    }

    func testInvalidationKeepsConfirmedActivationOwnedForTeardown() async {
        let backend = Backend(), lifecycle = backend.lifecycle()
        await lifecycle.request(true).value
        lifecycle.invalidateActivation()
        await lifecycle.request(false).value
        XCTAssertEqual(backend.events, ["activate", "activated", "ready", "deactivate", "deactivated"])
    }
}
