import AppKit
import Carbon
import Testing
@testable import WriteItDown

@MainActor
struct RoomTests {
    // MARK: - Pure presentation

    @Test func clockFormatsAsMinutesAndSeconds() {
        #expect(RoomPresentation.clock(60) == "1:00")
        #expect(RoomPresentation.clock(3600) == "60:00")
        #expect(RoomPresentation.clock(0) == "0:00")
    }

    @Test func wipeReportUsesUnusedTimeAndLiveSentence() {
        #expect(RoomPresentation.wipeReport(unused: 52, canRestart: true) ==
            "DRAFT DELETED AT 0:52. TYPE TO START AGAIN.")
        #expect(RoomPresentation.wipeReport(unused: 52, canRestart: false) ==
            "DRAFT DELETED AT 0:52. ACTIVATE TO KEEP WRITING.")
    }

    @Test func keptReceiptMirrorsTheFailureReceipt() {
        #expect(RoomPresentation.keptReceipt(wordCount: 63, duration: 300) == "5 MINUTES. 63 WORDS.")
        #expect(RoomPresentation.keptReceipt(wordCount: 1, duration: 60) == "1 MINUTE. 1 WORD.")
        #expect(!RoomPresentation.keptReceipt(wordCount: 63, duration: 300).contains("KEPT"))
        #expect(RoomPresentation.wordLabel(0) == "0 words")
        #expect(RoomPresentation.wordLabel(1) == "1 word")
    }

    @Test func copyPutsExactDraftOnPasteboard() {
        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { board.releaseGlobally() }
        #expect(RoomPresentation.copy("First line\n第二行", to: board))
        #expect(board.string(forType: .string) == "First line\n第二行")
    }

    @Test func denyFeedbackIsInterruptible() {
        var feedback = DenyFeedbackState()
        feedback.begin()
        // A repeated blocked key restarts the short animation instead of being ignored.
        feedback.begin()
        #expect(feedback.outlineVisible)
        feedback.end()
        #expect(!feedback.outlineVisible)
        feedback.begin()
    }

    @Test func denyAnimationIsAShortTransformAndOpacityAnimation() throws {
        let fixture = try roomFixture()
        fixture.state.settings.reducedMotion = .never
        fixture.editor.deleteBackward(nil)
        fixture.room.tick()
        let paper = try #require(fixture.editor.enclosingScrollView?.superview)
        let shake = try #require(paper.layer?.animation(forKey: "deny-shake") as? CAKeyframeAnimation)
        #expect(shake.keyPath == "transform.translation.x")
        #expect(shake.duration <= 0.25)
        #expect(CATransform3DIsIdentity(paper.layer?.transform ?? CATransform3DIdentity))
        let outline = try #require(descendants(fixture.room.view, of: RoomWashView.self)
            .first { $0.fillColor == .clear })
        let flash = try #require(outline.layer?.animation(forKey: "deny-hairline") as? CAKeyframeAnimation)
        #expect(flash.keyPath == "opacity")
        #expect(flash.duration <= 0.25)

        // Interruptible: a second blocked key replaces the animation, not ignores it.
        let firstShake = shake
        fixture.clock.now += 0.05
        fixture.editor.deleteBackward(nil)
        fixture.room.tick()
        let nextShake = try #require(paper.layer?.animation(forKey: "deny-shake") as? CAKeyframeAnimation)
        #expect(nextShake !== firstShake)
    }

    @Test func reducedMotionDenyKeepsOnlyTheHairlineFlash() throws {
        let fixture = try roomFixture()
        fixture.state.settings.reducedMotion = .always
        fixture.editor.deleteBackward(nil)
        fixture.room.tick()
        let paper = try #require(fixture.editor.enclosingScrollView?.superview)
        #expect(paper.layer?.animation(forKey: "deny-shake") == nil, "Reduce Motion must not shake the paper")
        let outline = try #require(descendants(fixture.room.view, of: RoomWashView.self)
            .first { $0.fillColor == .clear })
        #expect(outline.layer?.animation(forKey: "deny-hairline") != nil)
    }

    @Test func escapeIsIgnoredWhileComposing() {
        #expect(!RoomPresentation.handlesEscape(isComposing: true))
        #expect(RoomPresentation.handlesEscape(isComposing: false))
    }

    @Test func exitConfirmationRequiresTwoRequestsInsideTheWindow() {
        var confirmation = ExitConfirmation(window: 2)
        let first = confirmation.request(now: 10)
        #expect(!first)
        #expect(confirmation.armedAt == 10)
        let second = confirmation.request(now: 11.9)
        #expect(second)
        #expect(confirmation.armedAt == nil)
        let late = confirmation.request(now: 20)
        #expect(!late)
        let expired = confirmation.request(now: 22.1)
        #expect(!expired)
        #expect(confirmation.armedAt == 22.1)
        confirmation.dismiss()
        #expect(confirmation.armedAt == nil)
    }

    // MARK: - Two-step exit in the room

    @Test func firstEscapeShowsHintAndSecondEscapeLeaves() throws {
        let fixture = try roomFixture()
        let room = fixture.room
        var now = 100.0
        room.exitConfirmation = ExitConfirmation(window: 2)
        room.confirmationClock = { now }
        room.requestExit()
        #expect(fixture.state.selectedSurface == .session)
        let hint = try #require(hintLabel(in: room))
        #expect(!hint.isHidden)
        #expect(hint.stringValue == "Press Esc again to leave and delete the draft.")
        #expect(fixture.engine.text == "private draft")
        now = 101.5
        room.requestExit()
        #expect(fixture.state.selectedSurface == .home)
        #expect(fixture.engine.phase == .idle)
        #expect(fixture.engine.text.isEmpty)
    }

    @Test func typingDismissesTheExitHint() throws {
        let fixture = try roomFixture()
        let room = fixture.room
        var now = 100.0
        room.exitConfirmation = ExitConfirmation(window: 2)
        room.confirmationClock = { now }
        room.requestExit()
        #expect(!(try #require(hintLabel(in: room))).isHidden)
        fixture.editor.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect((try #require(hintLabel(in: room))).isHidden)
        now = 101
        room.requestExit()
        #expect(fixture.state.selectedSurface == .session)
        #expect(!(try #require(hintLabel(in: room))).isHidden)
    }

    @Test func exitHintExpiresAfterTheConfirmationWindow() async throws {
        let fixture = try roomFixture()
        let room = fixture.room
        room.exitConfirmation = ExitConfirmation(window: 0.05)
        room.confirmationClock = { 100 }
        room.requestExit()
        let hint = try #require(hintLabel(in: room))
        #expect(!hint.isHidden)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(hint.isHidden)
        room.requestExit()
        #expect(fixture.state.selectedSurface == .session)
        #expect(!hint.isHidden)
    }

    @Test func clickExitAlsoNeedsConfirmation() throws {
        let fixture = try roomFixture()
        let room = fixture.room
        var now = 100.0
        room.exitConfirmation = ExitConfirmation(window: 2)
        room.confirmationClock = { now }
        let exit = try #require(exitButton(in: room))
        #expect(exit.title == "ESC - EXIT")
        exit.performClick(nil)
        #expect(fixture.state.selectedSurface == .session)
        #expect(!(try #require(hintLabel(in: room))).isHidden)
        now = 101
        exit.performClick(nil)
        #expect(fixture.state.selectedSurface == .home)
    }

    @Test func exitRemainsVisibleInEveryRoomPhase() throws {
        for phase in [SessionPhase.writing, .danger, .failure, .success] {
            let fixture = try roomFixture()
            advance(fixture, to: phase)
            fixture.room.view.layoutSubtreeIfNeeded()
            let exit = try #require(exitButton(in: fixture.room))
            #expect(!exit.isHiddenOrHasHiddenAncestor)
            #expect(exit.title == "ESC - EXIT")
        }
    }

    // MARK: - Room content

    @Test func roomHasNoTopLeftDurationPillInAnyPhase() throws {
        let forbidden = ["forward only", ", done", "1 minute,"]
        for phase in [SessionPhase.writing, .danger, .failure, .success] {
            let fixture = try roomFixture()
            advance(fixture, to: phase)
            let strings = visibleStrings(in: fixture.room.view)
            for token in forbidden {
                #expect(!strings.contains { $0.contains(token) }, "\(phase) still shows '\(token)'")
            }
        }
    }

    @Test func warningShowsTheLiveCaptionAndCountdown() throws {
        let fixture = try roomFixture()
        advance(fixture, to: .danger)
        fixture.room.view.layoutSubtreeIfNeeded()
        let fields = descendants(fixture.room.view, of: NSTextField.self)
        let caption = try #require(fields.first { $0.stringValue == "KEEP TYPING OR THE DRAFT IS DELETED." })
        #expect(!caption.isHiddenOrHasHiddenAncestor)
        let numeral = try #require(fields.first { $0.stringValue == "3" })
        #expect(!numeral.isHiddenOrHasHiddenAncestor)
        #expect((numeral.font?.pointSize ?? 0) > 100)
        #expect(sameColor(numeral.textColor, FirstLineColors.redNSColor))
        #expect(fields.contains { $0.stringValue == "0:55" })
        let exit = try #require(exitButton(in: fixture.room))
        #expect(!exit.isHiddenOrHasHiddenAncestor)
    }

    @Test func deletedStateShowsUnusedSentenceAndCountWithoutAHint() throws {
        let fixture = try roomFixture()
        fixture.editor.insertText("one sentence", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.clock.now = 8.1
        fixture.room.tick()
        #expect(fixture.engine.phase == .failure)
        let fields = descendants(fixture.room.view, of: NSTextField.self)
        let report = try #require(fields.first { $0.stringValue == "DRAFT DELETED AT 0:52. TYPE TO START AGAIN." })
        #expect(!report.isHiddenOrHasHiddenAncestor)
        #expect(sameColor(report.textColor, FirstLineColors.redNSColor))
        #expect(!fields.contains { $0.stringValue == "Start typing." },
                "the wiped room must not add an under-line hint")
        #expect(fields.contains { $0.stringValue == "1:00" })
        #expect(fields.contains { $0.stringValue == "0 words" })
        // The wiped screen is the kept screen's counterpart: a headline, a real
        // restart button and the red receipt as the detail.
        let heading = try #require(fields.first { $0.stringValue == "You stopped." })
        #expect(!heading.isHiddenOrHasHiddenAncestor)
        let buttons = descendants(fixture.room.view, of: NSButton.self)
        let beginAgain = try #require(buttons.first { $0.title == "Begin again" })
        #expect(!beginAgain.isHiddenOrHasHiddenAncestor)
        #expect(beginAgain.keyEquivalent == "\r")
        #expect(report.stringValue.hasPrefix("DRAFT DELETED AT"))
    }

    @Test func keptStateMatchesTheLiveCopyAndReceipt() throws {
        let fixture = try roomFixture(typed: false)
        fixture.editor.insertText("cant say this out loud but", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.editor.insertText("\ni dont want the promotion", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.editor.insertText("\npromotion. i want time", replacementRange: NSRange(location: NSNotFound, length: 0))
        for second in stride(from: 4.0, to: 60.0, by: 4.0) {
            fixture.clock.now = second
            fixture.engine.registerMarkedTextActivity()
        }
        fixture.clock.now = 60
        fixture.room.tick()
        #expect(fixture.engine.phase == .success)
        let fields = descendants(fixture.room.view, of: NSTextField.self)
        #expect(fields.contains { $0.stringValue == "You wrote it down." && !$0.isHidden })
        let receipt = try #require(fields.first { $0.stringValue == "1 MINUTE. 15 WORDS." })
        #expect(!receipt.isHiddenOrHasHiddenAncestor)
        let body = try #require(fields.first { $0.isSelectable && !$0.isEditable && $0.stringValue.contains("promotion") })
        #expect(body.alignment == .center)
        #expect(body.isHiddenOrHasHiddenAncestor == false)
        let buttons = descendants(fixture.room.view, of: NSButton.self)
        #expect(buttons.contains { $0.title == "COPY TEXT" && !$0.isHiddenOrHasHiddenAncestor })
        #expect(buttons.contains { $0.title == "RUN IT AGAIN" && !$0.isHiddenOrHasHiddenAncestor })
        #expect(buttons.contains { $0.title == "ESC - EXIT" && !$0.isHiddenOrHasHiddenAncestor })
        #expect(fields.contains { $0.stringValue == "0:00" })
        #expect(fields.contains { $0.stringValue == "15 words" })

        #expect(!fields.contains { $0.stringValue.contains("Not saved") })
        #expect(!fields.contains { $0.stringValue.contains("forward only") })
    }

    @Test func copiedStateSurvivesRoomRecreation() throws {
        let fixture = try roomFixture(typed: false)
        fixture.editor.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        for second in stride(from: 4.0, to: 60.0, by: 4.0) {
            fixture.clock.now = second
            fixture.engine.registerMarkedTextActivity()
        }
        fixture.clock.now = 60
        fixture.room.tick()
        #expect(fixture.engine.phase == .success)
        fixture.room.copyKeptText()
        #expect(fixture.engine.copiedKeptText)

        let recreated = SessionViewController(appState: fixture.state)
        window(recreated)
        let copy = try #require(descendants(recreated.view, of: NSButton.self).first { $0.title == "COPIED" })
        #expect(descendants(copy, of: NSTextField.self).contains { $0.stringValue == "COPIED" })
        recreated.view.window?.orderOut(nil)
    }

    @Test func copyButtonSwitchesToCopied() throws {
        let fixture = try roomFixture(typed: false)
        fixture.editor.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        for second in stride(from: 4.0, to: 60.0, by: 4.0) {
            fixture.clock.now = second
            fixture.engine.registerMarkedTextActivity()
        }
        fixture.clock.now = 60
        fixture.room.tick()
        let copy = try #require(descendants(fixture.room.view, of: NSButton.self).first { $0.title == "COPY TEXT" })
        fixture.room.view.layoutSubtreeIfNeeded()
        fixture.room.viewDidLayout()
        let originalWidth = copy.frame.width
        let copyLabel = try #require(descendants(copy, of: NSTextField.self).first { $0.stringValue == "COPY TEXT" })
        let originalPadding = copy.frame.width - copyLabel.intrinsicContentSize.width
        #expect(originalPadding >= 40 && originalPadding <= 56,
                "the pill carries \(originalPadding) pt of padding around COPY TEXT")
        copy.performClick(nil)
        fixture.room.view.layoutSubtreeIfNeeded()
        fixture.room.viewDidLayout()
        // The pill hugs its label, so COPIED is narrower; the row stays centred.
        #expect(copy.title == "COPIED")
        #expect(copy.frame.width < originalWidth, "the COPIED pill kept the widest label width")
        let copiedLabel = try #require(descendants(copy, of: NSTextField.self).first { $0.stringValue == "COPIED" })
        let copiedPadding = copy.frame.width - copiedLabel.intrinsicContentSize.width
        #expect(abs(copiedPadding - originalPadding) <= 2,
                "the pill padding changed from \(originalPadding) to \(copiedPadding) on COPIED")
        fixture.room.tick()
        let move = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0))
        fixture.room.mouseMoved(with: move)
        fixture.room.mouseExited(with: move)
        fixture.state.settings.writingFontSize = .large
        fixture.room.tick()
        #expect(copy.title == "COPIED")
        let kept = try #require(descendants(fixture.room.view, of: SessionKeptView.self).first)
        #expect(kept.draft == "draft")
        fixture.state.abandonSession()
        fixture.state.startSession(duration: 60)
        fixture.room.refreshRoom()
        #expect(copy.title == "COPY TEXT")
        #expect(kept.draft.isEmpty)
    }

    @Test func washRecoveryFadesOnceAndWarningInterruptsImmediately() throws {
        let fixture = try roomFixture()
        fixture.state.settings.reducedMotion = .never
        fixture.clock.now = 6.5
        fixture.room.tick()
        let wash = try #require(descendants(fixture.room.view, of: RoomWashView.self)
            .first { $0.alphaValue == 0.5 })
        #expect(wash.layer?.animation(forKey: "opacity") == nil)
        fixture.editor.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        let fade = try #require(wash.layer?.animation(forKey: "opacity") as? CABasicAnimation)
        #expect(fade.duration == 0.12)
        #expect((fade.fromValue as? Float) == 0.5)
        #expect((fade.toValue as? Float) == 0)
        var control: [Float] = [0, 0]
        fade.timingFunction?.getControlPoint(at: 1, values: &control)
        #expect(control == [0, 0])
        fixture.room.tick()
        #expect(wash.layer?.animation(forKey: "opacity")?.duration == 0.12)
        fixture.clock.now = 13
        fixture.room.tick()
        #expect(wash.alphaValue == 0.5)
        #expect(wash.layer?.animation(forKey: "opacity") == nil)
        fixture.state.settings.reducedMotion = .always
        fixture.editor.insertText("y", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(wash.alphaValue == 0)
        #expect(wash.layer?.animation(forKey: "opacity") == nil)
    }

    @Test func cutCleanupUsesTheSameWashFade() throws {
        let fixture = try roomFixture()
        fixture.state.settings.reducedMotion = .never
        fixture.clock.now = 8.1
        fixture.room.tick()
        let wash = try #require(descendants(fixture.room.view, of: RoomWashView.self)
            .first { $0.alphaValue == 1 })
        #expect(wash.layer?.animation(forKey: "opacity") == nil)
        fixture.room.endCutAnimation()
        #expect(wash.alphaValue == 0)
        #expect(wash.layer?.animation(forKey: "opacity")?.duration == 0.12)
    }

    @Test func warningCaptionUsesTheLiveMachineVoice() throws {
        let fixture = try roomFixture(typed: false)
        fixture.editor.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.clock.now = 5.1
        fixture.room.tick()
        #expect(fixture.engine.phase == .danger)
        let fields = descendants(fixture.room.view, of: NSTextField.self)
        let caption = try #require(fields.first { $0.stringValue == "KEEP TYPING OR THE DRAFT IS DELETED." })
        let kern = caption.attributedStringValue.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
        #expect(abs((kern ?? 0) - 0.52) < 0.01)
        #expect(caption.font?.pointSize == 13)
        let numeral = try #require(fields.first { $0.stringValue == "3" })
        #expect(abs((numeral.font?.pointSize ?? 0) - min(fixture.room.view.bounds.height * 0.18, 170)) < 1)
    }

    @Test func countAndExitFollowTheLivePhaseTone() throws {
        for phase in [SessionPhase.writing, .danger] {
            let fixture = try roomFixture()
            advance(fixture, to: phase)
            let fields = descendants(fixture.room.view, of: NSTextField.self)
            let count = try #require(fields.first { $0.stringValue.hasSuffix("words") })
            let exit = try #require(exitButton(in: fixture.room))
            let exitColor = exit.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            let expected = phase == .writing ? FirstLineColors.muteNSColor : FirstLineColors.chromeNSColor
            let countColor = count.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            #expect(sameColor(countColor, expected))
            #expect(sameColor(exitColor, expected))
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func keptStateFocusesCopyText(appearance: NSAppearance.Name) throws {
        let fixture = try roomFixture(typed: false)
        fixture.editor.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        for second in stride(from: 4.0, to: 60.0, by: 4.0) {
            fixture.clock.now = second
            fixture.engine.registerMarkedTextActivity()
        }
        fixture.clock.now = 60
        fixture.room.tick()
        #expect(fixture.engine.phase == .success)
        let window = try #require(fixture.room.view.window)
        window.appearance = NSAppearance(named: appearance)
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let copy = try #require(window.firstResponder as? NSButton)
        #expect(copy.title == "COPY TEXT")
        #expect(copy.focusRingType == .none)
        let outline = try #require(copy.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
        #expect(!outline.isHidden)
        #expect(outline.lineWidth == 2)
        // The primary ink pill draws one light ring on its edge: no dark margin
        // outside the ring, so it cannot read as a doubled outline.
        let outlines = copy.layer?.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
        #expect(outlines.count == 1, "the pill draws more than one ring")
        #expect(outline.frame == copy.bounds)
        #expect(outline.path?.boundingBox == CGRect(origin: .zero, size: outline.bounds.size))
        let stroke = try #require(outline.strokeColor)
        let ring = try #require(NSColor(cgColor: stroke))
        #expect(sameColor(ring, FirstLineColors.onInkNSColor, appearance: appearance))
        window.makeFirstResponder(nil)
        #expect(outline.isHidden)
        window.orderOut(nil)
    }

    @Test func keptCopyMatchesLiveHoverAndPressMotion() throws {
        let fixture = try roomFixture()
        fixture.state.settings.reducedMotion = .never
        advance(fixture, to: .success)
        let kept = try #require(descendants(fixture.room.view, of: SessionKeptView.self).first)
        let copy = kept.copyButton
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        copy.mouseEntered(with: event)
        #expect(copy.layer?.affineTransform().ty == 1)
        let motion = try #require(copy.layer?.animation(forKey: "transform") as? CABasicAnimation)
        #expect(motion.duration == 0.16)
        var control: [Float] = [0, 0]
        motion.timingFunction?.getControlPoint(at: 1, values: &control)
        #expect(abs(control[0] - 0.22) < 0.001)
        #expect(control[1] == 1)
        copy.highlight(true)
        #expect(abs((copy.layer?.affineTransform().a ?? 0) - 0.97) < 0.001)
        copy.highlight(false)
        copy.mouseExited(with: event)
        #expect(copy.layer?.affineTransform() == .identity)
        fixture.state.settings.reducedMotion = .always
        fixture.room.tick()
        copy.highlight(true)
        #expect(copy.layer?.animation(forKey: "transform") == nil)
    }

    @Test func longKeptDraftStaysReadableInsideItsOwnScroller() throws {
        let fixture = try roomFixture(typed: false)
        let long = (1...120).map { "line \($0) of the kept draft" }.joined(separator: "\n")
        fixture.editor.insertText(long, replacementRange: NSRange(location: NSNotFound, length: 0))
        for second in stride(from: 4.0, to: 60.0, by: 4.0) {
            fixture.clock.now = second
            fixture.engine.registerMarkedTextActivity()
        }
        fixture.clock.now = 60
        fixture.room.tick()
        fixture.room.view.layoutSubtreeIfNeeded()
        fixture.room.viewDidLayout()
        let kept = try #require(descendants(fixture.room.view, of: SessionKeptView.self).first)
        let scroll = kept.scrollView
        #expect(scroll.documentView!.frame.height > scroll.contentSize.height)
        #expect(scroll.documentView!.frame.height > 1000)
        #expect(!scroll.hasVerticalScroller)
        let before = scroll.contentView.bounds.origin.y
        scroll.contentView.scroll(to: NSPoint(x: 0, y: before + 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.origin.y > before)
        #expect(scroll.documentVisibleRect.maxY <= scroll.documentView!.bounds.maxY)
    }

    @Test func warnWashTracksSelectedSilenceLimit() {
        for limit in SilenceLimit.allCases {
            let warnAt = Double(limit.rawValue - 3)
            #expect(RoomPresentation.washOpacity(idle: warnAt - 0.1, reducesMotion: false, limit: limit) == 0)
            #expect(RoomPresentation.washOpacity(idle: warnAt, reducesMotion: false, limit: limit) == 0)
            #expect(RoomPresentation.washOpacity(idle: warnAt + 1.5, reducesMotion: false, limit: limit) == 0.5)
            #expect(RoomPresentation.washOpacity(idle: Double(limit.rawValue), reducesMotion: false, limit: limit) == 1)
            #expect(RoomPresentation.washOpacity(idle: warnAt, reducesMotion: true, limit: limit) == 1)
        }
    }

    @Test func homeRestoresStartButtonFocusWithoutStartingSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = licensedTestState(settingsStore: SettingsStore(configDirectory: root))
        state.startSession()
        state.abandonSession()
        let home = HomeViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = home
        home.viewDidAppear()
        let button = try #require(window.firstResponder as? NSButton)
        #expect(button.title == "Begin")
        #expect(button.accessibilityLabel() == "Begin writing")
        #expect(state.selectedSurface == .home)
        #expect(state.sessionEngine.phase == .idle)
    }

    @Test(arguments: ["commit", "replace", "cancel", "backspace", "selection"],
          ["ni", "かな", "한글", "👩‍🚒"])
    func inputClientCompositionNeverDenies(sequence: String, candidate: String) throws {
        let fixture = try roomFixture()
        let editor = fixture.editor
        let end = NSRange(location: NSNotFound, length: 0)
        editor.setMarkedText(candidate, selectedRange: NSRange(location: (candidate as NSString).length, length: 0),
                             replacementRange: end)
        #expect(fixture.engine.lastDenyAt == nil)
        switch sequence {
        case "commit":
            editor.insertText("你", replacementRange: end)
            #expect(editor.string == "private draft你")
        case "replace":
            editor.setMarkedText("你好", selectedRange: NSRange(location: 2, length: 0), replacementRange: editor.markedRange())
            editor.unmarkText()
            #expect(editor.string == "private draft你好")
        case "cancel":
            editor.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: editor.markedRange())
            editor.unmarkText()
            #expect(editor.string == "private draft")
        case "selection":
            editor.setSelectedRange(editor.markedRange())
            editor.deleteBackward(nil)
            #expect(fixture.engine.lastDenyAt == nil)
            editor.unmarkText()
        default:
            for _ in candidate {
                if !editor.hasMarkedText() {
                    editor.setMarkedText(candidate, selectedRange: NSRange(location: (candidate as NSString).length, length: 0),
                                         replacementRange: end)
                }
                editor.deleteBackward(nil)
                #expect(fixture.engine.lastDenyAt == nil)
            }
            editor.unmarkText()
        }
        #expect(!editor.hasMarkedText())
        #expect(fixture.engine.lastDenyAt == nil)
        switch sequence {
        case "commit", "replace", "cancel":
            #expect(fixture.engine.text == editor.string)
        default:
            #expect(fixture.engine.text == "private draft")
        }
        if sequence == "commit" {
            let committed = editor.string
            editor.deleteBackward(nil)
            #expect(fixture.engine.lastDenyAt != nil)
            #expect(editor.string == committed)
        }
    }

    // MARK: - Helpers

    private func roomFixture(typed: Bool = true) throws -> (room: SessionViewController, engine: SessionEngine,
                                         state: AppState, editor: AppendOnlyTextView, clock: RoomClock) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = RoomClock(0)
        let engine = SessionEngine(now: { clock.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state, confirmationNow: { clock.now })
        window(room)
        let editor = try #require(descendants(room.view, of: AppendOnlyTextView.self).first)
        if typed {
            editor.insertText("private draft", replacementRange: NSRange(location: NSNotFound, length: 0))
            room.tick()
        }
        return (room, engine, state, editor, clock)
    }

    @Test func firstPinyinKeyAfterAWipeThroughTheInputContext() throws {
        let fixture = try roomFixture(typed: false)
        let previous = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        defer { if let previous { TISSelectInputSource(previous) } }
        let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        let pinyin = sources.first { source in
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
            return (Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String)
                == "com.apple.inputmethod.SCIM.ITABC"
        }
        let selected = TISSelectInputSource(try #require(pinyin, "the Apple Pinyin input source is not enabled"))
        #expect(selected == noErr, "could not select the Apple Pinyin input source")
        let window = try #require(fixture.room.view.window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        fixture.room.viewDidAppear()
        window.makeFirstResponder(fixture.editor)
        let context = try #require(fixture.editor.inputContext)

        func key(_ chars: String, _ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                             timestamp: ProcessInfo.processInfo.systemUptime,
                             windowNumber: window.windowNumber, context: nil, characters: chars,
                             charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        }
        guard NSApp.isActive, window.isKeyWindow else {
            withKnownIssue("case 53 is unverified: the test host cannot activate a window for the input context") {
                #expect(NSApp.isActive && window.isKeyWindow, "the input context needs an active host window")
            }
            window.orderOut(nil)
            return
        }
        // A real marked composition, then the silence wipe, then the first key again.
        _ = context.handleEvent(key("n", 45))
        #expect(fixture.editor.hasMarkedText(), "the first Pinyin key did not start a marked composition")
        fixture.clock.now = 9
        fixture.room.tick()
        #expect(fixture.engine.phase == .failure)
        #expect(fixture.editor.string.isEmpty)
        _ = context.handleEvent(key("n", 45))
        #expect(fixture.editor.string.contains("n"),
                "the first Pinyin letter after a wipe was swallowed")
        #expect(fixture.engine.phase == .writing)
        window.orderOut(nil)
    }

    @Test func markedFirstKeyAfterAWipeKeepsTheSameRoom() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RoomClock(0)
        let engine = SessionEngine(now: { clock.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.startSession(duration: 60)
        let windowController = RootWindowController(appState: state)
        let container = try #require(windowController.window?.contentViewController as? RootContainerViewController)
        let room = try #require(container.children.first as? SessionViewController)
        let editor = try #require(descendants(room.view, of: AppendOnlyTextView.self).first)
        editor.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
        clock.now = 9
        room.tick()
        #expect(engine.phase == .failure)
        #expect(editor.string.isEmpty)

        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        #expect(engine.phase == .writing)
        #expect(container.children.first === room, "the first marked key recreated the room")
        #expect(descendants(room.view, of: AppendOnlyTextView.self).first === editor)
        #expect(editor.hasMarkedText())
        #expect(editor.string == "ni")
        windowController.close()
    }

    @Test func failureRestartWorksFromReturn() throws {
        let fixture = try roomFixture(typed: false)
        fixture.editor.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.clock.now = 9
        fixture.room.tick()
        #expect(fixture.engine.phase == .failure)
        let window = try #require(fixture.room.view.window)
        window.makeKeyAndOrderFront(nil)
        fixture.room.viewDidAppear()
        let ret = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
            keyCode: 36))
        #expect(window.performKeyEquivalent(with: ret), "Return did not reach Begin again")
        fixture.room.tick()
        #expect(fixture.engine.phase == .writing)
        #expect(fixture.editor.string.isEmpty)
        let heading = descendants(fixture.room.view, of: NSTextField.self)
            .first { $0.stringValue == "You stopped." }
        #expect(heading?.isHiddenOrHasHiddenAncestor == true)
        window.orderOut(nil)
    }

    private func window(_ room: SessionViewController) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = room
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.contentView?.layoutSubtreeIfNeeded()
        room.view.layoutSubtreeIfNeeded()
        room.viewDidLayout()
        RoomWindowKeeper.windows.append(window)
    }

    private func advance(_ fixture: (room: SessionViewController, engine: SessionEngine,
                                     state: AppState, editor: AppendOnlyTextView, clock: RoomClock),
                         to phase: SessionPhase) {
        switch phase {
        case .danger:
            fixture.clock.now = 5.1
        case .failure:
            fixture.clock.now = 8.1
        case .success:
            for second in stride(from: 4.0, to: 60.0, by: 4.0) {
                fixture.clock.now = second
                fixture.engine.registerMarkedTextActivity()
            }
            fixture.clock.now = 60
        default:
            break
        }
        fixture.room.tick()
        fixture.room.view.layoutSubtreeIfNeeded()
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(child, of: type)
        }
    }

    private func visibleStrings(in view: NSView) -> [String] {
        descendants(view, of: NSView.self).flatMap { child -> [String] in
            guard !child.isHiddenOrHasHiddenAncestor else { return [] }
            if let field = child as? NSTextField { return [field.stringValue] }
            if let button = child as? NSButton { return [button.title] }
            if let text = child as? NSTextView { return [text.string] }
            return []
        }
    }

    private func hintLabel(in room: SessionViewController) -> NSTextField? {
        descendants(room.view, of: NSTextField.self)
            .first { $0.stringValue == "Press Esc again to leave and delete the draft." }
    }

    private func exitButton(in room: SessionViewController) -> NSButton? {
        descendants(room.view, of: NSButton.self).first { $0.title == "ESC - EXIT" }
    }

    private func sameColor(_ lhs: NSColor?, _ rhs: NSColor, appearance: NSAppearance.Name = .aqua) -> Bool {
        guard let lhs else { return false }
        var left: NSColor?
        var right: NSColor?
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            left = lhs.usingColorSpace(.sRGB)
            right = rhs.usingColorSpace(.sRGB)
        }
        return left == right
    }
}

@MainActor
private enum RoomWindowKeeper {
    static var windows: [NSWindow] = []
}

private final class RoomClock {
    var now: TimeInterval
    init(_ now: TimeInterval) { self.now = now }
}
