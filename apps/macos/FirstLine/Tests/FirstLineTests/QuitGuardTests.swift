/**
 * [INPUT]: 依赖 AppKit、App/FirstLineMain、App/RootWindowController、Session/SessionViewController、App/AppState
 * [OUTPUT]: 有未保留草稿时，关窗（Cmd+W、红灯）、退出（Cmd+Q、Dock）、Begin（Cmd+N）和 Home（Cmd+0）都先走房间自己的两步退出确认（沿用 `Press Esc again to leave and delete the draft.`），第二次才放行；没有可丢的文本时一律不问
 * [POS]: 关窗/退出静默丢稿缺陷的回归断言（真实 VM 记录见 docs/wid-mac-behavior.md 案例 85）；单元测试用与 Esc 相同的 `ExitConfirmation` 时钟，真实按键由 VM rig 驱动
 * [PROTOCOL]: 变更确认范围或放行规则时同步更新此头部与 docs/wid-decisions.md
 */

import AppKit
import Testing
@testable import WriteItDown

@MainActor
struct QuitGuardTests {
    private static let hint = "Press Esc again to leave and delete the draft."

    private final class Clock { var now: TimeInterval = 100 }

    private struct Fixture {
        let state: AppState
        let engine: SessionEngine
        let windowController: RootWindowController
        let delegate: FirstLineAppDelegate
        let clock: Clock
        let root: URL

        var window: NSWindow { windowController.window! }
        var room: SessionViewController? {
            (window.contentViewController as? RootContainerViewController)?.children.first as? SessionViewController
        }
    }

    private func fixture(typed: Bool = true) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let engineClock = Clock()
        let engine = SessionEngine(now: { engineClock.now })
        let state = licensedTestState(sessionEngine: engine, settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.updateDefaultDuration(300)
        state.startSession()
        let windowController = RootWindowController(appState: state)
        let fixture = Fixture(state: state, engine: engine, windowController: windowController,
                              delegate: FirstLineAppDelegate(appState: state, windowController: windowController),
                              clock: engineClock, root: root)
        let room = try #require(fixture.room)
        room.confirmationClock = { engineClock.now }
        if typed {
            engine.registerCommittedText("private draft")
            room.tick()
        }
        return fixture
    }

    private func hintLabel(_ room: SessionViewController?) -> NSTextField? {
        func walk(_ view: NSView) -> [NSTextField] {
            ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(walk)
        }
        guard let room else { return nil }
        return walk(room.view).first { $0.stringValue == Self.hint }
    }

    private func sendMenu(_ action: Selector, _ fixture: Fixture) -> Bool {
        let menu = MainMenuBuilder.buildMenu(appState: fixture.state, validationOwner: fixture.delegate)
        let item = menu.items.flatMap { $0.submenu?.items ?? [] }.first { $0.action == action }!
        return NSApplication.shared.sendAction(item.action!, to: item.target, from: item)
    }

    // MARK: - Close

    @Test func closingTheWindowOverALiveDraftAsksFirstAndTheRepeatCloses() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(f.state.hasUnkeptDraft)
        #expect(!f.windowController.windowShouldClose(f.window))
        #expect(f.engine.text == "private draft")
        #expect(f.engine.phase == .writing)
        #expect(f.state.selectedSurface == .session)
        #expect(try #require(hintLabel(f.room)).isHidden == false)
        f.clock.now += 1.5
        #expect(f.windowController.windowShouldClose(f.window))
        #expect(f.engine.text.isEmpty, "a confirmed close is the writer deleting the draft")
        #expect(!f.state.hasUnkeptDraft, "the quit that follows the close has nothing left to ask about")
    }

    @Test func theCloseWindowCommandAsksEvenWhenTheRoomHidesTheTrafficLights() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        // `performClose` does nothing while the lights are hidden; the command must still reach the question.
        f.windowController.closeWindow()
        #expect(f.engine.text == "private draft")
        #expect(try #require(hintLabel(f.room)).isHidden == false)
        f.windowController.closeWindow()
        #expect(f.engine.text.isEmpty)
    }

    @Test func theCloseConfirmationExpiresWithTheTwoSecondWindow() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(!f.windowController.windowShouldClose(f.window))
        f.clock.now += 2.5
        #expect(!f.windowController.windowShouldClose(f.window), "an expired confirmation asks again")
        #expect(f.engine.text == "private draft")
    }

    @Test func closingWithNothingTypedYetNeverAsks() throws {
        let f = try fixture(typed: false)
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(!f.state.hasUnkeptDraft)
        #expect(f.windowController.windowShouldClose(f.window))
    }

    // MARK: - Quit

    @Test func quittingOverALiveDraftCancelsOnceThenTerminates() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(f.delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(f.engine.text == "private draft")
        #expect(try #require(hintLabel(f.room)).isHidden == false)
        f.clock.now += 1
        #expect(f.delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }

    @Test func quittingWithNothingToLoseTerminatesAtOnce() throws {
        let f = try fixture(typed: false)
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(f.delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }

    @Test func aKeptDraftAndAStoppedRoomNeverAsk() throws {
        let kept = try fixture()
        defer { try? FileManager.default.removeItem(at: kept.root) }
        for second in stride(from: 4.0, through: 300, by: 4.0) {
            kept.clock.now = 100 + second
            kept.engine.registerMarkedTextActivity()
        }
        kept.clock.now = 400
        kept.room?.tick()
        #expect(kept.engine.phase == .success)
        #expect(!kept.state.hasUnkeptDraft)
        #expect(kept.delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)

        let stopped = try fixture()
        defer { try? FileManager.default.removeItem(at: stopped.root) }
        stopped.clock.now += 30
        stopped.room?.tick()
        #expect(stopped.engine.phase == .failure)
        #expect(!stopped.state.hasUnkeptDraft)
        #expect(stopped.windowController.windowShouldClose(stopped.window))
    }

    // MARK: - The other acts that would delete the draft

    @Test func beginAndHomeAskBeforeTheyThrowTheDraftAway() throws {
        let begin = try fixture()
        defer { try? FileManager.default.removeItem(at: begin.root) }
        #expect(sendMenu(#selector(FirstLineAppDelegate.newPiece(_:)), begin))
        #expect(begin.engine.text == "private draft")
        #expect(try #require(hintLabel(begin.room)).isHidden == false)
        #expect(sendMenu(#selector(FirstLineAppDelegate.newPiece(_:)), begin))
        #expect(begin.engine.text.isEmpty)

        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home.root) }
        #expect(sendMenu(#selector(FirstLineAppDelegate.goHome(_:)), home))
        #expect(home.engine.text == "private draft")
        #expect(home.state.selectedSurface == .session)
        #expect(sendMenu(#selector(FirstLineAppDelegate.goHome(_:)), home))
        #expect(home.state.selectedSurface == .home)
        #expect(home.engine.text.isEmpty)
    }

    @Test func theEscapeActAndTheCloseActShareOneConfirmation() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let room = try #require(f.room)
        room.requestExit()
        #expect(f.windowController.windowShouldClose(f.window), "Esc armed it, the close is the second act")
    }

    // MARK: - A session left running behind Settings

    @Test func aDraftRunningBehindSettingsBringsTheWriterBackToTheRoomToConfirm() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.state.openSettings()
        #expect(f.state.selectedSurface == .settings)
        #expect(f.state.hasUnkeptDraft)
        #expect(!f.windowController.windowShouldClose(f.window))
        #expect(f.state.selectedSurface == .session)
        #expect(f.engine.text == "private draft")
        #expect(try #require(hintLabel(f.room)).isHidden == false)
        #expect(f.windowController.windowShouldClose(f.window))
    }
}
