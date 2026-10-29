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

    @Test func stoppedScreenAnnouncementCarriesTheUnusedTime() {
        #expect(RoomPresentation.failureAnnouncement(unused: 52, obstacle: .none) ==
            "You stopped. Draft deleted. 0:52 unused.")
        #expect(RoomPresentation.failureAnnouncement(unused: 0, obstacle: .none) ==
            "You stopped. Draft deleted. 0:00 unused.")
    }

    @Test func stoppedScreenAnnouncementNamesOnlyTheReasonThatIsTrue() {
        #expect(RoomPresentation.failureAnnouncement(unused: 52, obstacle: .trialSpent) ==
            "You stopped. Draft deleted. 0:52 unused. Three free sessions used. A license is needed to keep writing.")
        // Licence residue, a trial-access error or a cleanup failure also block a restart, and none
        // of them means the free sessions were used up (D-070).
        #expect(RoomPresentation.failureAnnouncement(unused: 52, obstacle: .licenseNeeded) ==
            "You stopped. Draft deleted. 0:52 unused. A license is needed to keep writing.")
        #expect(RoomPresentation.failurePillHelp(obstacle: .none) == "Return starts a new session.")
        #expect(RoomPresentation.failurePillHelp(obstacle: .trialSpent) ==
            "Three free sessions used. Return opens activation to keep writing.")
        #expect(RoomPresentation.failurePillHelp(obstacle: .licenseNeeded) ==
            "Return opens activation to keep writing.")
    }

    @Test func stoppedScreenAnnouncementAnnouncesTheTrialEndAtTheLastWipe() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = RoomClock(0)
        let engine = SessionEngine(now: { clock.now })
        let store = SettingsStore(configDirectory: root)
        var saved = try store.load()
        saved.trialSessionsUsed = 2
        try store.save(saved)
        let state = AppState(sessionEngine: engine, settingsStore: store,
                             licenseClient: MockLicenseClient(),
                             installIDStore: InstallIDStore(configDirectory: root),
                             productID: "prod_mock")
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state, confirmationNow: { clock.now })
        window(room)
        let editor = try #require(descendants(room.view, of: AppendOnlyTextView.self).first)
        editor.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.settings.trialSessionsUsed == 3)
        #expect(!state.canStartSession)
        clock.now = 9
        room.tick()
        #expect(engine.phase == .failure)
        #expect(room.stoppedAnnouncement.hasPrefix("You stopped. Draft deleted."))
        #expect(room.stoppedAnnouncement.hasSuffix(
            "Three free sessions used. A license is needed to keep writing."))
        let beginAgain = try #require(descendants(room.view, of: NSButton.self)
            .first { $0.title == "Begin again" })
        #expect(beginAgain.accessibilityHelp() ==
            "Three free sessions used. Return opens activation to keep writing.")
    }

    @Test func keptReceiptNamesTheDurationAndCount() {
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
        #expect(sameColor(numeral.textColor, FirstLineColors.paperDangerNSColor))
        #expect(fields.contains { $0.stringValue == "0:55" })
        let exit = try #require(exitButton(in: fixture.room))
        #expect(!exit.isHiddenOrHasHiddenAncestor)
    }

    @Test func stoppedScreenStatesTheDeletionAndTakesTheChromeOff() throws {
        let fixture = try roomFixture()
        fixture.editor.insertText("one sentence", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.clock.now = 8.1
        fixture.room.tick()
        fixture.room.endCutAnimation()
        fixture.room.view.layoutSubtreeIfNeeded()
        #expect(fixture.engine.phase == .failure)
        let fields = descendants(fixture.room.view, of: NSTextField.self)
        let visible = fields.filter { !$0.isHiddenOrHasHiddenAncestor }
        // The block says what happened, once: no receipt sentence and no second instruction.
        #expect(!visible.contains { $0.stringValue.hasPrefix("DRAFT DELETED AT") })
        #expect(!visible.contains { $0.stringValue.contains("TYPE TO START AGAIN") })
        #expect(!visible.contains { $0.stringValue == "Start typing." },
                "the wiped room must not add an under-line hint")
        let heading = try #require(visible.first { $0.stringValue == "You stopped." })
        let note = try #require(visible.first { $0.stringValue == "Draft deleted." })
        #expect((note.font?.pointSize ?? 0) == 15)
        #expect(sameColor(note.textColor, FirstLineColors.paperQuietNSColor))
        #expect(!heading.isHiddenOrHasHiddenAncestor)
        // No red text survives on the stopped screen; red is the pen and the deadline only.
        for field in visible {
            #expect(!sameColor(field.textColor, FirstLineColors.redNSColor),
                    "\"\(field.stringValue)\" is red on the stopped screen")
        }
        // Session chrome off: the stopped sheet carries no clock and no bar as a receipt, and
        // the count returns to the words it can state (D-070).
        #expect(!visible.contains { $0.stringValue.contains(":") }, "the clock is still on the stopped sheet")
        #expect(visible.contains { $0.stringValue == "0 words" })
        let timer = try #require(fields.first { $0.stringValue == "1:00" })
        #expect(timer.isHiddenOrHasHiddenAncestor, "the clock is part of the stopped screen")
        let bar = try #require(descendants(fixture.room.view, of: FirstLineFillBar.self).first)
        #expect(bar.isHiddenOrHasHiddenAncestor, "the session bar is part of the stopped screen")
        let beginAgain = try #require(descendants(fixture.room.view, of: NSButton.self)
            .first { $0.title == "Begin again" })
        #expect(!beginAgain.isHiddenOrHasHiddenAncestor)
        #expect(beginAgain.keyEquivalent == "\r")
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

        // The receipt owns the count; the corner slot is silent in this state (D-074).
        let cornerCount = try #require(fields.first { $0.stringValue == "15 words" })
        #expect(cornerCount.isHiddenOrHasHiddenAncestor, "the kept corner count is silent")
        let visible = visibleStrings(in: fixture.room.view).joined(separator: " ").lowercased()
        #expect(visible.components(separatedBy: "15 words").count - 1 == 1,
                "the kept screen prints the count once, in the receipt: \(visible)")

        // One caption under the actions says what the writer must do with the draft.
        let caption = try #require(fields.first { $0.stringValue == SessionKeptView.unsavedCaption })
        #expect(!caption.isHiddenOrHasHiddenAncestor)
        let copy = try #require(descendants(fixture.room.view, of: NSButton.self).first { $0.title == "COPY TEXT" })
        let captionFrame = fixture.room.view.convert(caption.bounds, from: caption)
        let copyFrame = fixture.room.view.convert(copy.bounds, from: copy)
        let receiptFrame = fixture.room.view.convert(receipt.bounds, from: receipt)
        #expect(captionFrame.maxY <= copyFrame.minY, "the caption sits under the action row")
        #expect(abs(captionFrame.midX - receiptFrame.midX) < 0.5, "the caption shares the kept block's centre")
        #expect(abs((caption.font?.pointSize ?? 0) - FirstLineTypography.smallMediumNSFont.pointSize) < 0.01,
                "the caption uses the room's small caption face")
        let captionInk = caption.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let receiptInk = receipt.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        func resolved(_ color: NSColor?, _ name: NSAppearance.Name) -> [CGFloat] {
            var parts: [CGFloat] = []
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                let rgb = color?.usingColorSpace(.sRGB)
                parts = [rgb?.redComponent ?? -1, rgb?.greenComponent ?? -1, rgb?.blueComponent ?? -1]
            }
            return parts
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            #expect(resolved(captionInk, name) == resolved(FirstLineColors.paperQuietNSColor, name)
                    && resolved(captionInk, name) == resolved(receiptInk, name),
                    "the caption is the receipt's quiet paper role, which clears 7:1 on the Wheat sheet (\(name))")
        }

        // Adding the caption moves nothing else: hiding it leaves the heading, receipt and
        // actions exactly where they were; only the flexible draft area gives way.
        let heading = try #require(fields.first { $0.stringValue == "You wrote it down." })
        func frames() -> [NSRect] {
            fixture.room.view.layoutSubtreeIfNeeded()
            return [heading, receipt, copy].map { fixture.room.view.convert($0.bounds, from: $0) }
        }
        let withCaption = frames()
        caption.isHidden = true
        let withoutCaption = frames()
        caption.isHidden = false
        for (index, (with, without)) in zip(withCaption, withoutCaption).enumerated() {
            #expect(abs(with.minY - without.minY) < 0.5, "kept block element \(index) moved when the caption was added")
            #expect(abs(with.midX - without.midX) < 0.5, "kept block element \(index) moved horizontally")
        }

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

    /// The ramp moves the sheet's colour, not the view's alpha, so the paper keeps one grain layer under
    /// the alarm; the recovery still leaves on the 120 ms fade (D-056).
    @Test func washRecoveryFadesOnceAndWarningInterruptsImmediately() throws {
        let fixture = try roomFixture()
        fixture.state.settings.reducedMotion = .never
        fixture.clock.now = 6.5
        fixture.room.tick()
        let wash = try #require(descendants(fixture.room.view, of: PaperWashView.self)
            .first { $0.fraction == 0.5 })
        #expect(wash.alphaValue == 1)
        #expect(wash.layer?.animation(forKey: "opacity") == nil)
        fixture.editor.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        let fade = try #require(wash.layer?.animation(forKey: "opacity") as? CABasicAnimation)
        #expect(fade.duration == 0.12)
        #expect((fade.fromValue as? Float) == 1)
        #expect((fade.toValue as? Float) == 0)
        #expect(wash.fraction == 0.5, "the wash leaves on the fade still carrying its warmth, not cut to plain paper")
        var control: [Float] = [0, 0]
        fade.timingFunction?.getControlPoint(at: 1, values: &control)
        #expect(control == [0, 0])
        fixture.room.tick()
        #expect(wash.layer?.animation(forKey: "opacity")?.duration == 0.12)
        #expect(wash.fraction == 0.5, "a tick during the fade keeps the tint until the fade ends")
        fixture.clock.now = 13
        fixture.room.tick()
        #expect(wash.fraction == 0.5)
        #expect(wash.alphaValue == 1)
        #expect(wash.layer?.animation(forKey: "opacity") == nil)
        fixture.state.settings.reducedMotion = .always
        fixture.editor.insertText("y", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(wash.alphaValue == 0)
        #expect(wash.layer?.animation(forKey: "opacity") == nil)
    }

    /// A warn tick moves only the wash's colour: the texture layer is drawn once per field and never again
    /// while the alarm ramps, and it lands on the sheet's own grain, so nothing on the paper moves or flickers.
    @Test func warnTicksNeverRepaintThePaperTexture() throws {
        let fixture = try roomFixture()
        fixture.state.settings.reducedMotion = .never
        let view = fixture.room.view
        let paper = try #require(descendants(view, of: PaperSheetView.self).first)
        let wash = try #require(descendants(view, of: PaperWashView.self).first)
        func settle() {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            CATransaction.flush()
        }
        func render() throws -> [(Double, Double, Double)] {
            settle()
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / view.bounds.width
            let origin = (x: Int(paper.frame.midX * scale), y: Int((view.bounds.height - paper.frame.maxY + 80) * scale))
            var pixels: [(Double, Double, Double)] = []
            for y in origin.y..<origin.y + 40 {
                for x in origin.x..<origin.x + 40 {
                    let colour = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    pixels.append((Double(colour.redComponent), Double(colour.greenComponent), Double(colour.blueComponent)))
                }
            }
            return pixels
        }
        let plain = try render()
        fixture.clock.now = 5.2
        fixture.room.tick()
        #expect(wash.alphaValue == 1 && wash.fraction > 0)
        let washed = try render()

        let count = Double(plain.count)
        let offset = zip(washed, plain).reduce(0.0) { $0 + ($1.0.1 - $1.1.1) } / count
        let residual = (zip(washed, plain).reduce(0.0) { $0 + pow($1.0.1 - $1.1.1 - offset, 2) } / count).squareRoot()
        #expect(residual < 0.01, "the washed grain does not sit on the sheet's grain: residual \(residual)")

        settle()
        let paints = wash.texturePaints
        #expect(paints > 0, "the texture layer was never painted")
        for now in [5.5, 6.0, 6.5, 7.0, 7.5] {
            fixture.clock.now = now
            fixture.room.tick()
            settle()
            #expect(wash.texturePaints == paints, "a warn tick at \(now) s repainted the paper texture")
        }
    }

    @Test func cutCleanupUsesTheSameWashFade() throws {
        let fixture = try roomFixture()
        fixture.state.settings.reducedMotion = .never
        fixture.clock.now = 8.1
        fixture.room.tick()
        let wash = try #require(descendants(fixture.room.view, of: PaperWashView.self)
            .first { $0.alphaValue == 1 })
        #expect(wash.layer?.animation(forKey: "opacity") == nil)
        #expect(wash.deep)
        fixture.room.endCutAnimation()
        #expect(wash.alphaValue == 0)
        #expect(wash.layer?.animation(forKey: "opacity")?.duration == 0.12)
        #expect(wash.deep && wash.fraction == 1, "the cut leaves on the fade, still the deep step")
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

    /// The count and the exit link sit on the Wheat sheet, so they take the sheet's one quiet role in
    /// every phase: the wall's mute and chrome would sink below the 7:1 floor on the paper (D-056).
    @Test func countAndExitKeepThePaperQuietRoleInEveryPhase() throws {
        for phase in [SessionPhase.writing, .danger] {
            let fixture = try roomFixture()
            advance(fixture, to: phase)
            let fields = descendants(fixture.room.view, of: NSTextField.self)
            let count = try #require(fields.first { $0.stringValue.hasSuffix("words") })
            let exit = try #require(exitButton(in: fixture.room))
            let exitColor = exit.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            let countColor = count.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            #expect(sameColor(countColor, FirstLineColors.paperQuietNSColor))
            #expect(sameColor(exitColor, FirstLineColors.paperQuietNSColor))
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
