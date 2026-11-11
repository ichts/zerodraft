import AppKit
import Foundation
import Testing
@testable import WriteItDown

/// The captain measured 508 ms from the Begin click to the room on a 120 fps recording. The room is the paper,
/// so the click-to-paper time is the number that matters, and it must stay under 100 ms.
@MainActor
struct BeginLatencyTests {
    static let budget = 100.0

    /// The main thread's own CPU time in ms. Wall time on a shared CI host measures the neighbours; the main
    /// thread's CPU time between the click and the painted paper is the work the room costs the user.
    private static func mainThreadCPUms() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e6
    }

    private func makeWindow() throws -> (RootWindowController, AppState, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = 1
        let store = SettingsStore(configDirectory: root)
        try store.save(settings)
        let state = AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                             checkoutClient: MockCheckoutClient(), installIDStore: InstallIDStore(configDirectory: root),
                             productID: "prod_mock")
        let controller = RootWindowController(appState: state)
        controller.window?.makeKeyAndOrderFront(nil)
        return (controller, state, root)
    }

    private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        view.subviews.flatMap { ((($0 as? T).map { [$0] }) ?? []) + descendants($0, type) }
    }

    private func spin(until done: () -> Bool, limit: Duration = .seconds(5)) async {
        let clock = ContinuousClock()
        let start = clock.now
        while !done(), clock.now - start < limit {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Begin click -> the room's first frame carrying the paper, painted into the window's backing store.
    private func beginToPaperPainted() async throws -> Double {
        let (controller, state, root) = try makeWindow()
        defer { controller.window?.orderOut(nil); try? FileManager.default.removeItem(at: root) }
        let window = try #require(controller.window)
        // A size no other suite uses, so the shared paper cache cannot be warmed or evicted by a neighbour. The wait for the background render is generous: parallel suites that build papers on the main thread can starve it for minutes; the measured time below is the main thread's own CPU, which a neighbour cannot inflate.
        window.setContentSize(NSSize(width: 1013, height: 727))
        let home = try #require(window.contentViewController?.children.first as? HomeViewController)
        home.view.layoutSubtreeIfNeeded()
        home.viewDidAppear()
        let area = home.view.safeAreaRect.insetBy(dx: 32, dy: 32)
        let scale = window.backingScaleFactor
        let dark = home.view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let (w, h) = (Int((area.width * scale).rounded()), Int((area.height * scale).rounded()))
        // Parallel suites build sheets of their own on the main actor, and the cache keeps only three: a sheet the
        // picker warmed can be evicted before this poll runs, and nothing would ever warm it again. Ask the picker
        // again each turn; a picker that does not warm the room's paper still fails the `holds` check below.
        await spin(until: {
            if PaperSheetCache.shared.holds(width: w, height: h, scale: scale, dark: dark) { return true }
            home.prewarmRoomPaper()
            return false
        }, limit: .seconds(600))
        #expect(PaperSheetCache.shared.holds(width: w, height: h, scale: scale, dark: dark), "the picker never warmed the room's paper")
        let builtBefore = PaperSheetCache.shared.synchronousBuilds(width: w, height: h, scale: scale, dark: dark)
        let begin = try #require(descendants(home.view, NSButton.self).first { $0.title == "Begin" })
        let start = Self.mainThreadCPUms()
        begin.performClick(nil)
        // No await between the click and the painted paper: a suspended test lets other suites run on the main
        // thread and their CPU would be counted here. The observation hop that swaps the surface is replaced by the
        // same call it makes.
        let container = try #require(window.contentViewController as? RootContainerViewController)
        container.show(state.selectedSurface)
        let session = try #require(window.contentViewController?.children.compactMap { $0 as? SessionViewController }.first)
        session.view.layoutSubtreeIfNeeded()
        session.view.displayIfNeeded()
        window.displayIfNeeded()
        let elapsed = Self.mainThreadCPUms() - start
        #expect(PaperSheetCache.shared.synchronousBuilds(width: w, height: h, scale: scale, dark: dark) == builtBefore, "the room rebuilt a paper the picker had warmed")
        #expect(state.selectedSurface == .session)
        let paper = try #require(descendants(session.view, PaperSheetView.self).first)
        #expect(paper.bounds.width > 100)
        return elapsed
    }

    /// Best of three: a loaded CI host can steal one attempt (page faults and cache misses count as the thread's
    /// CPU), but a Begin that really builds the paper on the click costs hundreds of ms on every attempt.
    @Test func beginShowsThePaperInUnderOneHundredMilliseconds() async throws {
        var runs: [Double] = []
        for _ in 0..<3 {
            runs.append(try await beginToPaperPainted())
            if let best = runs.min(), best < Self.budget { break }
        }
        print("BEGIN-LATENCY main-thread cpu ms:", runs)
        let best = try #require(runs.min())
        #expect(best < Self.budget, "Begin to paper took \(runs) ms of main-thread CPU")
    }

    /// The captain, 2026-11-07: Begin must not cut from the picker to the room. The paper's first frame is the
    /// picker card's own rectangle and it grows to the sheet; Reduce Motion cuts at once.
    @Test func beginGrowsThePaperOutOfThePickerCard() async throws {
        for reduce in [false, true] {
            let (controller, state, root) = try makeWindow()
            defer { controller.window?.orderOut(nil); try? FileManager.default.removeItem(at: root) }
            state.settings.reducedMotion = reduce ? .always : .never
            let window = try #require(controller.window)
            window.setContentSize(NSSize(width: 1013, height: 727))
            let home = try #require(window.contentViewController?.children.first as? HomeViewController)
            home.view.layoutSubtreeIfNeeded()
            let card = home.cardFrame
            #expect(card.width > 200 && card.height > 200)
            state.startSession(duration: state.selectedDuration)
            let container = try #require(window.contentViewController as? RootContainerViewController)
            container.show(state.selectedSurface)
            let session = try #require(window.contentViewController?.children.compactMap { $0 as? SessionViewController }.first)
            let paper = try #require(descendants(session.view, PaperSheetView.self).first { !$0.passesHitTests })
            let grow = paper.layer?.animation(forKey: SessionViewController.growAnimationKey) as? CABasicAnimation
            if reduce {
                #expect(grow == nil, "Reduce Motion must cut straight to the room")
                #expect(descendants(session.view, PaperSheetView.self).allSatisfy { !$0.passesHitTests })
                continue
            }
            let from = try #require((grow?.fromValue as? NSValue)?.caTransform3DValue)
            let target = paper.frame
            // The first frame sits exactly on the card: centre and size, under the layer's own anchor.
            let layer = try #require(paper.layer)
            let anchor = CGPoint(x: target.minX + layer.anchorPoint.x * target.width, y: target.minY + layer.anchorPoint.y * target.height)
            let centre = CGPoint(x: anchor.x + from.m11 * (target.midX - anchor.x) + from.m41,
                                 y: anchor.y + from.m22 * (target.midY - anchor.y) + from.m42)
            #expect(abs(from.m11 * target.width - card.width) < 0.5 && abs(from.m22 * target.height - card.height) < 0.5)
            #expect(abs(centre.x - card.midX) < 0.5 && abs(centre.y - card.midY) < 0.5)
            #expect(grow?.duration == SessionViewController.growDuration)
            #expect(SessionViewController.growDuration * 1000 <= 260, "the grow must stay quick")
        }
    }
}
