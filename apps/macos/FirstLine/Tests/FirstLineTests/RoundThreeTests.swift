import AppKit
import Testing
@testable import WriteItDown

@MainActor
struct RoundThreeTests {
    // MARK: - Card alignment

    @Test func licensedCardCentresStartWritingAndPreLicenceGroup() throws {
        let licensed = UpgradeViewController(appState: licensedTestState())
        let window = makeWindow(licensed)
        let card = try #require(descendants(of: licensed.view, of: FirstLineCardView.self).first)
        let content = card.contentView
        let start = try #require(descendants(of: content, of: NSButton.self).first { $0.title == "Start writing" })
        assertCentred(start, in: content, "licensed Start writing")

        let inactive = UpgradeViewController(appState: try trialState(used: 3))
        let inactiveWindow = makeWindow(inactive)
        let inactiveCard = try #require(descendants(of: inactive.view, of: FirstLineCardView.self).first)
        let inactiveContent = inactiveCard.contentView
        let activate = try #require(descendants(of: inactiveContent, of: NSButton.self).first { $0.title == "Activate" })
        let buy = try #require(descendants(of: inactiveContent, of: NSButton.self).first { $0.title.hasPrefix("Buy a license") })
        let activateRect = inactiveContent.convert(activate.bounds, from: activate)
        let buyRect = inactiveContent.convert(buy.bounds, from: buy)
        let groupCentre = (min(activateRect.minX, buyRect.minX) + max(activateRect.maxX, buyRect.maxX)) / 2
        #expect(abs(groupCentre - inactiveContent.bounds.midX) <= 1,
                "pre-licence action group must stay centred as a unit")
        window.orderOut(nil)
        inactiveWindow.orderOut(nil)
    }

    @Test func inkFocusLayerSurvivesPresentationCopies() throws {
        let button = FirstLineInkFocusButton(frame: NSRect(x: 0, y: 0, width: 140, height: 44))
        let ring = try #require(button.layer?.sublayers?.first)
        let copy = CALayer(layer: ring)
        #expect(copy.bounds == ring.bounds)
        #expect(copy.frame == ring.frame)
    }

    @Test func primaryPillsHugTheEdgeWhileOutlineAndQuietControlsKeepTheOuterRing() throws {
        let action = #selector(NSResponder.selectAll(_:))
        let primary = try #require(FirstLineButtons.primary(title: "Begin", target: nil, action: action)
            as? FirstLineInkFocusButton)
        let roomPrimary = try #require(FirstLineButtons.roomPrimary(title: "COPY TEXT", target: nil,
                                                                   action: action, reducesMotion: { true })
            as? FirstLineInkFocusButton)
        let secondary = try #require(FirstLineButtons.secondary(title: "RUN IT AGAIN", target: nil, action: action)
            as? FirstLineInkFocusButton)
        let quiet = try #require(FirstLineButtons.link(title: "ESC - EXIT", target: nil, action: action)
            as? FirstLineInkFocusButton)
        #expect(primary.inkFocusRingInset == 0)
        #expect(roomPrimary.inkFocusRingInset == 0)
        #expect(secondary.inkFocusRingInset == 3)
        #expect(quiet.inkFocusRingInset == 3)
    }

    // MARK: - Picker access line

    @Test func licensedPickerHidesAccessLineAndTrialPickerKeepsIt() throws {
        let licensed = HomeViewController(appState: licensedTestState())
        _ = makeWindow(licensed)
        let licensedTexts = descendants(of: licensed.view, of: NSTextField.self).map(\.stringValue)
        #expect(licensedTexts.contains("License active.") == false ||
                descendants(of: licensed.view, of: NSTextField.self)
                    .filter { $0.stringValue == "License active." }
                    .allSatisfy(\.isHiddenOrHasHiddenAncestor))

        let trial = HomeViewController(appState: try trialState(used: 2))
        _ = makeWindow(trial)
        let trialLine = try #require(descendants(of: trial.view, of: NSTextField.self)
            .first { $0.stringValue == "Free trial: 1 of 3 sessions left." })
        #expect(!trialLine.isHiddenOrHasHiddenAncestor)
    }

    // MARK: - Ink focus on every control

    @Test func everyCardControlUsesTheInkFocusRingInLightAndDark() throws {
        let now = MutableRoundClock(0)
        let engine = SessionEngine(now: { now.now })
        let roomState = licensedTestState(sessionEngine: engine,
                                          settingsStore: SettingsStore(configDirectory: tempRoot()),
                                          installIDStore: InstallIDStore(configDirectory: tempRoot()))
        roomState.startSession(duration: 60)
        let room = SessionViewController(appState: roomState)
        _ = room.view
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        editor.insertText("one line of draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        for second in stride(from: 4.0, to: 60.0, by: 4.0) {
            now.now = second
            engine.registerMarkedTextActivity()
        }
        now.now = 60
        room.tick()

        let cards: [(String, NSViewController)] = [
            ("picker", HomeViewController(appState: try trialState(used: 2))),
            ("activation", UpgradeViewController(appState: try trialState(used: 3))),
            ("licensed", UpgradeViewController(appState: licensedTestState())),
            ("settings", SettingsViewController(appState: licensedTestState())),
            ("settings-updates", SettingsViewController(appState: licensedTestState(),
                                                       updateSettings: StubUpdateSettings())),
            ("room", SessionViewController(appState: licensedTestState())),
            ("kept", room),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, controller) in cards {
                let window = makeWindow(controller, appearance: appearance)
                let controls = descendants(of: controller.view, of: NSButton.self)
                #expect(!controls.isEmpty, "\(name) has no buttons")
                for control in controls {
                    #expect(control.focusRingType == .none, "\(name) control \(control.title) falls back to the system ring")
                    let ringing = try #require(control as? FirstLineInkFocusRinging,
                                               "\(name) control \(control.title) has no ink ring")
                    window.makeFirstResponder(control)
                    control.needsDisplay = true
                    control.displayIfNeeded()
                    #expect(ringing.showsInkFocusRing, "\(name) control \(control.title) did not show the ink ring")
                    let ringColor = resolved(ringing.inkFocusRingColor, appearance)
                    let ink = resolved(FirstLineColors.inkNSColor, appearance)
                    // Ink-filled pills use the light inner ring (single outline); every
                    // other control uses the ink ring.
                    let fill = control.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }
                    let isInkPill = fill.map { resolved($0, appearance) == ink } ?? false
                    let expected = isInkPill ? resolved(FirstLineColors.onInkNSColor, appearance) : ink
                    #expect(ringColor == expected, "\(name) control \(control.title) ring is not the expected token")
                }
                window.orderOut(nil)
            }
        }
    }

    // MARK: - Empty caret and placeholder

    @Test func emptyCaretAndCountPromptShareTheInsertionColumnWithTheFirstGlyph() throws {
        let state = licensedTestState()
        state.startSession()
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        let paper = try #require(editor.enclosingScrollView?.superview)
        let container = try #require(editor.textContainer)
        room.view.layoutSubtreeIfNeeded()

        // No hint near the line. The bottom-right count slot carries the instruction
        // in the count's own style until the first keystroke.
        #expect(!descendants(of: room.view, of: NSTextField.self).contains { $0.stringValue == "Start typing." },
                "the empty room still shows an under-line hint")
        let prompt = try #require(descendants(of: room.view, of: NSTextField.self)
            .first { $0.stringValue == "Type to start" })
        #expect(!prompt.isHiddenOrHasHiddenAncestor)
        #expect(prompt.font?.pointSize == 13, "the prompt does not use the count style")

        // The writing line holds only the caret at the centred insertion point.
        let emptyCaret = editor.caretRectForCurrentInsertionPoint()
        let insertionX = editor.textContainerOrigin.x + container.containerSize.width / 2
        #expect(abs(emptyCaret.midX - insertionX) <= 1, "empty caret is not on the centred insertion point")
        let lineBaseline = try #require(editor.currentInsertionBaseline())
        let lineBaselineInPaper = paper.convert(NSPoint(x: 0, y: lineBaseline), from: editor).y

        // The first typed character is rendered at the caret; the count becomes the
        // word count; the line baseline does not move.
        editor.insertText("A", replacementRange: NSRange(location: NSNotFound, length: 0))
        room.view.layoutSubtreeIfNeeded()
        let layout = try #require(editor.layoutManager)
        layout.ensureLayout(for: container)
        let glyphBox = layout.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: container)
        #expect(abs(editor.textContainerOrigin.x + glyphBox.midX - emptyCaret.midX) <= 1,
                "the first glyph appears away from the empty caret")
        let typedBaseline = try #require(editor.currentInsertionBaseline())
        let typedBaselineInPaper = paper.convert(NSPoint(x: 0, y: typedBaseline), from: editor).y
        #expect(abs(typedBaselineInPaper - lineBaselineInPaper) <= 1, "the writing line moved on the first key")
        let typedCaret = editor.caretRectForCurrentInsertionPoint()
        #expect(abs(typedCaret.minY - emptyCaret.minY) <= 1, "the caret jumped vertically on the first key")
        #expect(prompt.stringValue == "1 word", "the count did not replace the prompt on the first key")
        window.orderOut(nil)
    }

    @Test func compositionRendersOnTheWritingLineAndReplacesTheCountPrompt() throws {
        let state = licensedTestState()
        state.startSession()
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        let container = try #require(editor.textContainer)
        let emptyBaseline = try #require(editor.currentInsertionBaseline())
        let prompt = try #require(descendants(of: room.view, of: NSTextField.self)
            .first { $0.stringValue == "Type to start" })

        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        room.refreshRoom()
        room.view.layoutSubtreeIfNeeded()
        #expect(editor.hasMarkedText())
        #expect(prompt.stringValue == "0 words", "the composition did not replace the count prompt")

        // The composition is laid into the writing line: centred in the measure and
        // on the same baseline, not in a separate position.
        let layout = try #require(editor.layoutManager)
        layout.ensureLayout(for: container)
        let marked = editor.markedRange()
        let line = layout.lineFragmentUsedRect(forGlyphAt: layout.glyphIndexForCharacter(at: marked.location),
                                               effectiveRange: nil)
        let lineCentre = editor.textContainerOrigin.x + line.midX
        let measureCentre = editor.textContainerOrigin.x + container.containerSize.width / 2
        #expect(abs(lineCentre - measureCentre) <= 1, "the composition is not centred on the writing line")
        #expect(abs(try #require(editor.currentInsertionBaseline()) - emptyBaseline) <= 1,
                "the composition baseline differs from the writing line baseline")
        window.orderOut(nil)
    }

    // MARK: - Full sheet and room bars

    @Test func sheetFillsTheWindowAndKeepsTheReadableColumn() throws {
        for size in [NSSize(width: 1040, height: 720), NSSize(width: 1600, height: 1000)] {
            let state = licensedTestState()
            state.startSession()
            let room = SessionViewController(appState: state)
            let window = makeWindow(room, size: size)
            let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
            let scroll = try #require(editor.enclosingScrollView)
            let paper = try #require(scroll.superview)
            let insets = room.view.safeAreaInsets
            let bounds = room.view.bounds
            #expect(abs(paper.frame.minX - (insets.left + 32)) <= 1, "sheet leading margin at \(size)")
            #expect(abs(paper.frame.maxX - (bounds.maxX - insets.right - 32)) <= 1, "sheet trailing margin at \(size)")
            #expect(abs(paper.frame.minY - (insets.bottom + 32)) <= 1, "sheet bottom margin at \(size)")
            #expect(abs(paper.frame.maxY - (bounds.maxY - insets.top - 32)) <= 1, "sheet top margin at \(size)")
            let font = FirstLineTypography.writingNSFont(size: state.settings.writingFontSize.points)
            let character = ("0" as NSString).size(withAttributes: [.font: font]).width
            let expected = min(CGFloat(state.settings.writingAlignment.measureCharacters) * character,
                               scroll.bounds.width - 16)
            let measured = try #require(editor.textContainer).containerSize.width
            #expect(abs(measured - expected) <= 6, "writing column is \(measured), expected \(expected)")
            #expect(measured / character >= 55 && measured / character <= 70,
                    "column must stay a readable 60-70 characters (the 62ch cap fits the sheet)")
            window.orderOut(nil)
        }
    }

    @Test func roomBarRunsOneContinuousLinearAnimation() throws {
        let now = MutableRoundClock(0)
        let engine = SessionEngine(now: { now.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: tempRoot()),
                                      installIDStore: InstallIDStore(configDirectory: tempRoot()))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        let paper = try #require(editor.enclosingScrollView?.superview)
        paper.needsDisplay = true
        paper.displayIfNeeded()
        let bars = descendants(of: room.view, of: FirstLineFillBar.self)
        // One bar only: the bottom silence bar was removed because it pulled the eye
        // away from the writing line.
        #expect(bars.count == 1, "the room must not carry a second (bottom) bar")
        let top = try #require(bars.first)
        #expect(abs(top.frame.height - 2) <= 0.5)
        #expect(abs(top.frame.maxY - paper.bounds.maxY) <= 1, "the session bar is pinned to the paper top")
        #expect(abs(top.frame.width - paper.bounds.width) <= 1)
        #expect(paper.layer?.masksToBounds == true, "the bar is clipped by the sheet's rounded rect")
        #expect(paper.layer?.cornerRadius == FirstLineRadius.sheet)
        #expect(top.toolTip == nil)
        #expect(top.accessibilityLabel() == nil, "the bar is the only indicator: no label")
        #expect(abs(top.fraction - 1) <= 0.01, "the bar starts full")
        #expect(top.fractionAnimation == nil, "an idle bar has no animation")
        #expect(resolved(top.fillColor, .aqua) == resolved(FirstLineColors.inkNSColor, .aqua))

        now.now = 4
        engine.registerCommittedText("a")
        room.tick()
        for second in stride(from: 8.0, through: 28.0, by: 4.0) {
            now.now = second
            engine.registerCommittedText("a")
        }
        let animation = try #require(top.fractionAnimation,
                                     "the first input must start one continuous bar animation")
        #expect(abs((animation.duration) - 60) <= 0.01, "the animation spans the remaining session time")
        var start: [Float] = [0, 0]
        var end: [Float] = [0, 0]
        animation.timingFunction?.getControlPoint(at: 0, values: &start)
        animation.timingFunction?.getControlPoint(at: 1, values: &end)
        #expect(animation.timingFunction === CAMediaTimingFunction(name: .linear) ||
                (start == [0, 0] && end == [1, 1]), "the bar animation is linear")
        #expect(top.fraction == 0, "the model target is empty while the layer animates")
        // The visible bar must start full and shrink; a model-only animation from 0 to 0
        // draws no bar at all (the fourth hands-on report).
        let from = try #require(animation.fromValue as? NSNumber).doubleValue
        let to = try #require(animation.toValue as? NSNumber).doubleValue
        #expect(abs(from - Double(top.bounds.width)) <= 0.5,
                "the bar animation starts at \(from) pt, not the full \(top.bounds.width) pt")
        #expect(abs(to) <= 0.5, "the bar animation must end empty")
        // Visible and shrinking in the running window, not just in the model.
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let presented = try #require(top.presentedWidth, "the bar has no presentation layer")
        #expect(presented > 0, "the bar is invisible in the running window")
        #expect(presented < top.bounds.width, "the bar is not shrinking")

        now.now = 30
        engine.registerCommittedText("a")
        room.tick()
        #expect(top.fractionAnimation === animation, "a tick must not restart the bar animation")

        now.now = 60
        room.tick()
        #expect(top.fraction == 0, "the bar empties at the session end")
        #expect(top.fractionAnimation == nil, "the bar animation ends with the session")
        window.orderOut(nil)
    }

    @Test func newSessionBarRestartsFromFullAfterAWipe() throws {
        let now = MutableRoundClock(0)
        let engine = SessionEngine(now: { now.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: tempRoot()),
                                      installIDStore: InstallIDStore(configDirectory: tempRoot()))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        let bar = try #require(descendants(of: room.view, of: FirstLineFillBar.self).first)
        editor.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))

        now.now = 9
        room.tick()
        #expect(engine.phase == .failure)
        #expect(bar.fraction == 0)

        editor.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        room.tick()
        #expect(engine.phase == .writing)
        let animation = try #require(bar.fractionAnimation, "the new session has no bar animation")
        let from = try #require(animation.fromValue as? NSNumber).doubleValue
        #expect(abs(from - Double(bar.bounds.width)) <= 0.5,
                "the new session bar starts at \(from) pt, not the full \(bar.bounds.width) pt")

        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let presented = try #require(bar.presentedWidth, "the new session bar has no presentation layer")
        #expect(presented > 0, "the new session bar is invisible")
        window.orderOut(nil)
    }

    @Test func reducedMotionBarStepsWithoutAnimation() throws {
        let now = MutableRoundClock(0)
        let engine = SessionEngine(now: { now.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: tempRoot()),
                                      installIDStore: InstallIDStore(configDirectory: tempRoot()))
        state.settings.reducedMotion = .always
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        room.barNow = { now.now }
        let window = makeWindow(room)
        let top = try #require(descendants(of: room.view, of: FirstLineFillBar.self).first)
        #expect(abs(top.fraction - 1) <= 0.01)

        now.now = 4
        engine.registerCommittedText("a")
        room.tick()
        #expect(top.fractionAnimation == nil, "Reduce Motion must not animate the bar")
        for second in stride(from: 8.0, through: 28.0, by: 4.0) {
            now.now = second
            engine.registerCommittedText("a")
        }
        now.now = 30
        engine.registerCommittedText("a")
        room.tick()
        #expect(top.fractionAnimation == nil)
        #expect(abs(top.fraction - engine.remaining / engine.duration) <= 0.02,
                "the reduced-motion bar steps with the remaining time")
        now.now = 60
        room.tick()
        #expect(top.fraction == 0)
        window.orderOut(nil)
    }

    @Test func writingAlignmentNamesTheColumnMeasure() {
        #expect(WritingAlignment.centered.label == "Narrow column")
        #expect(WritingAlignment.left.label == "Wide column")
        #expect(WritingAlignment.centered.measureCharacters == 62)
        #expect(WritingAlignment.left.measureCharacters == 70)
    }

    // MARK: - IME composition paths

    @Test func markedBackspaceAndCandidateKeysPassThroughWithoutDeny() throws {
        let (editor, deny) = makeEditor()
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        editor.deleteBackward(nil)
        #expect(deny.count == 0)

        for candidateKey in ["1", "2", " ", "\n"] {
            editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            let marked = editor.markedRange()
            editor.insertText(candidateKey, replacementRange: marked)
            #expect(deny.count == 0, "candidate key \(candidateKey.debugDescription) denied")
        }
        #expect(deny.count == 0)
    }

    @Test func commitReplacingMarkedRangeAfterUnmarkDoesNotDeny() throws {
        let (editor, deny) = makeEditor()
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = editor.markedRange()
        editor.insertText("你好", replacementRange: marked)
        #expect(deny.count == 0)
        #expect(editor.string == "你好")
        #expect(!editor.hasMarkedText())

        editor.setMarkedText("shijie", selectedRange: NSRange(location: 6, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let secondMarked = editor.markedRange()
        editor.unmarkText()
        editor.insertText("世界", replacementRange: secondMarked)
        #expect(deny.count == 0)
        #expect(editor.string == "你好世界")
    }

    @Test func markedReplacementAndDeleteCommandDoNotDeny() throws {
        let (editor, deny) = makeEditor()
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.replaceCharacters(in: editor.markedRange(), with: "zhongguo")
        #expect(deny.count == 0)
        #expect(!AppendOnlyInputPolicy.shouldDenyCommand(#selector(NSResponder.deleteBackward(_:)), hasMarkedText: true))
        #expect(!AppendOnlyInputPolicy.shouldDenyCommand(Selector(("moveLeft:")), hasMarkedText: true))
        #expect(AppendOnlyInputPolicy.shouldDenyCommand(#selector(NSResponder.deleteBackward(_:)), hasMarkedText: false))
    }

    @Test func japaneseKoreanAndShuangpinSequencesStayCompositionSafe() throws {
        for (name, marked, committed) in [
            ("japanese", "にほん", "日本"),
            ("korean", "한국", "한국"),
            ("shuangpin", "ni", "你"),
            ("pinyin", "nihao", "你好"),
        ] {
            let (editor, deny) = makeEditor()
            editor.setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            let range = editor.markedRange()
            editor.deleteBackward(nil)
            #expect(deny.count == 0, "\(name) backspace denied")
            editor.insertText(committed, replacementRange: range)
            #expect(deny.count == 0, "\(name) commit denied")
            #expect(editor.string.contains(committed))
            editor.deleteBackward(nil)
            #expect(deny.count == 1, "\(name) committed deletion must deny")
        }
    }

    // MARK: - Warning placement and the exit row

    @Test func warningInkSitsUnderTheWritingLine() throws {
        for size in [NSSize(width: 1040, height: 720), NSSize(width: 1600, height: 1000),
                     NSSize(width: 1728, height: 1117)] {
            let now = MutableRoundClock(0)
            let engine = SessionEngine(now: { now.now })
            let state = licensedTestState(sessionEngine: engine,
                                          settingsStore: SettingsStore(configDirectory: tempRoot()),
                                          installIDStore: InstallIDStore(configDirectory: tempRoot()))
            state.startSession(duration: 60)
            let room = SessionViewController(appState: state)
            let window = makeWindow(room, size: size)
            let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
            let paper = try #require(editor.enclosingScrollView?.superview)
            // No descenders, so the last ink row of the line is its baseline.
            editor.insertText("hello there", replacementRange: NSRange(location: NSNotFound, length: 0))
            now.now = 6.5
            room.tick()
            room.view.layoutSubtreeIfNeeded()
            room.viewDidLayout()
            room.view.layoutSubtreeIfNeeded()
            room.view.displayIfNeeded()

            let rep = try #require(room.view.bitmapImageRepForCachingDisplay(in: room.view.bounds))
            room.view.cacheDisplay(in: room.view.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / room.view.bounds.width
            let paperTopFromRoomTop = room.view.bounds.height - paper.frame.maxY
            let baseline = try #require(editor.currentInsertionBaseline())
            let baselineFromTop = paperTopFromRoomTop
                + (paper.bounds.maxY - paper.convert(NSPoint(x: 0, y: baseline), from: editor).y)
            let x = (room.view.bounds.midX - 250)...(room.view.bounds.midX + 250)
            let y = (baselineFromTop - 60)...(paperTopFromRoomTop + paper.bounds.height - 40)
            let runs = inkRowRuns(in: rep, scale: scale, x: x, y: y) { colour in
                let luma = 0.2126 * colour.redComponent + 0.7152 * colour.greenComponent + 0.0722 * colour.blueComponent
                return luma < 0.6
            }
            #expect(runs.count >= 3, "expected writing line, numeral and caption ink at \(size), got \(runs)")
            guard runs.count >= 3 else { break }
            let baselineRow = CGFloat(runs[0].max)
            let numeralTop = CGFloat(runs[1].min)
            let numeralBottom = CGFloat(runs[1].max)
            let captionTop = CGFloat(runs[2].min)
            let numeralDrop = (numeralTop - baselineRow) / scale
            let captionDrop = (captionTop - numeralBottom) / scale
            #expect(numeralDrop >= 40 && numeralDrop <= 48,
                    "numeral ink top is \(numeralDrop) pt under the writing baseline at \(size)")
            #expect(captionDrop >= 16 && captionDrop <= 24,
                    "caption ink top is \(captionDrop) pt under the numeral ink at \(size)")
            window.orderOut(nil)
        }
    }

    @Test func stoppedScreenHoldsTheDeletionValueAndAControlFreeBlock() throws {
        let now = MutableRoundClock(0)
        let engine = SessionEngine(now: { now.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: tempRoot()),
                                      installIDStore: InstallIDStore(configDirectory: tempRoot()))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        editor.insertText("hello there", replacementRange: NSRange(location: NSNotFound, length: 0))
        now.now = 9
        room.tick()
        room.endCutAnimation()
        room.view.layoutSubtreeIfNeeded()
        room.viewDidLayout()
        room.view.layoutSubtreeIfNeeded()
        let fields = descendants(of: room.view, of: NSTextField.self).filter { !$0.isHiddenOrHasHiddenAncestor }
        // The instruments carry the deletion: the clock froze at the unused time and the bar
        // holds that same fraction, so no sentence has to repeat it (D-056).
        #expect(fields.contains { $0.stringValue == "0:52" })
        #expect(!fields.contains { $0.stringValue == "1:00" })
        let bar = try #require(descendants(of: room.view, of: FirstLineFillBar.self).first)
        #expect(abs(bar.fraction - CGFloat(52.0 / 60.0)) < 0.01)
        #expect(!descendants(of: room.view, of: NSTextField.self).contains { $0.stringValue == "Start typing." })
        // The block stays on the Mac offset at a tall sheet, and the writing line stays put.
        let block = try #require(fields.first { $0.stringValue == "You stopped." })
        let paper = try #require(editor.enclosingScrollView?.superview)
        let blockFrame = paper.convert(block.bounds, from: block)
        let topFromPaper = paper.bounds.maxY - blockFrame.maxY
        #expect(abs(topFromPaper - 72) <= 0.5, "the stopped block sits at \(topFromPaper) pt from the paper top")
        let baseline = try #require(editor.currentInsertionBaseline())
        let baselineInPaper = paper.convert(NSPoint(x: 0, y: baseline), from: editor).y
        let note = try #require(fields.first { $0.stringValue == "Draft deleted." })
        let noteFrame = paper.convert(note.bounds, from: note)
        #expect(noteFrame.minY - baselineInPaper > 40, "the block never reaches the writing line")
        window.orderOut(nil)
    }

    @Test func restartRefillsTheInstrumentsTheStoppedScreenFroze() throws {
        let now = MutableRoundClock(0)
        let engine = SessionEngine(now: { now.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: tempRoot()),
                                      installIDStore: InstallIDStore(configDirectory: tempRoot()))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        editor.insertText("hello there", replacementRange: NSRange(location: NSNotFound, length: 0))
        now.now = 9
        room.tick()
        let bar = try #require(descendants(of: room.view, of: FirstLineFillBar.self).first)
        #expect(abs(bar.fraction - CGFloat(52.0 / 60.0)) < 0.01)
        let beginAgain = try #require(descendants(of: room.view, of: NSButton.self)
            .first { $0.title == "Begin again" })
        beginAgain.performClick(nil)
        room.view.layoutSubtreeIfNeeded()
        let fields = descendants(of: room.view, of: NSTextField.self).filter { !$0.isHiddenOrHasHiddenAncestor }
        #expect(fields.contains { $0.stringValue == "1:00" })
        #expect(!fields.contains { $0.stringValue == "0:52" })
        #expect(abs(bar.fraction - 1) < 0.01, "a new session refills the bar")
        #expect(descendants(of: room.view, of: NSTextField.self)
            .allSatisfy { $0.stringValue != "Draft deleted." || $0.isHiddenOrHasHiddenAncestor })
        window.orderOut(nil)
    }

    @Test func stateChangesDoNotMoveTheRoomChromeOrTheWritingAnchor() throws {
        let now = MutableRoundClock(0)
        let engine = SessionEngine(now: { now.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: tempRoot()),
                                      installIDStore: InstallIDStore(configDirectory: tempRoot()))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        let paper = try #require(editor.enclosingScrollView?.superview)
        let timer = try #require(descendants(of: room.view, of: NSTextField.self).first { $0.stringValue == "1:00" })
        let count = try #require(descendants(of: room.view, of: NSTextField.self).first { $0.stringValue == "Type to start" })
        let exit = try #require(descendants(of: room.view, of: NSButton.self).first { $0.title == "ESC - EXIT" })

        // Fixed edges only: the clock's text width changes, its right edge must not.
        func chrome() -> [CGFloat] {
            [timer.frame.maxX, timer.frame.midY, count.frame.maxX, count.frame.midY,
             exit.frame.minX, exit.frame.maxY, exit.frame.midY]
        }
        func baseline() throws -> CGFloat {
            let y = try #require(editor.currentInsertionBaseline())
            return paper.convert(NSPoint(x: 0, y: y), from: editor).y
        }
        let restChrome = chrome()
        let restBaseline = try baseline()

        editor.insertText("hello", replacementRange: NSRange(location: NSNotFound, length: 0))
        room.tick()
        room.view.layoutSubtreeIfNeeded()
        room.viewDidLayout()
        room.view.layoutSubtreeIfNeeded()
        for (index, value) in chrome().enumerated() {
            #expect(abs(value - restChrome[index]) <= 0.5, "chrome edge \(index) moved after typing")
        }
        #expect(abs(try baseline() - restBaseline) <= 1, "the writing baseline moved after typing")

        now.now = 5.6
        room.tick()
        room.view.layoutSubtreeIfNeeded()
        room.viewDidLayout()
        room.view.layoutSubtreeIfNeeded()
        for (index, value) in chrome().enumerated() {
            #expect(abs(value - restChrome[index]) <= 0.5, "chrome edge \(index) moved into the warning")
        }
        #expect(abs(try baseline() - restBaseline) <= 1, "the writing baseline moved into the warning")
        window.orderOut(nil)
    }

    @Test func exitHintSharesTheExitRowBaselineAndTypeStyle() throws {
        let state = licensedTestState()
        state.startSession()
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        room.exitConfirmation = ExitConfirmation(window: 60)
        room.requestExit()
        room.view.layoutSubtreeIfNeeded()

        let exit = try #require(descendants(of: room.view, of: NSButton.self).first { $0.title == "ESC - EXIT" })
        let hint = try #require(descendants(of: room.view, of: NSTextField.self)
            .first { $0.attributedStringValue.string == "Press Esc again to leave and delete the draft." })
        #expect(!hint.isHidden)

        // Same role, same type style: face, size, weight and tracking.
        let exitTitle = try #require(exit.attributedTitle)
        let hintText = hint.attributedStringValue
        let exitFont = try #require(exitTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let hintFont = try #require(hintText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(exitFont.fontName == hintFont.fontName)
        #expect(exitFont.pointSize == hintFont.pointSize)
        #expect(exitFont.fontDescriptor.symbolicTraits == hintFont.fontDescriptor.symbolicTraits)
        let exitKern = try #require(exitTitle.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat)
        let hintKern = try #require(hintText.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat)
        // Caps keep their tracking; sentence case drops it, so its lowercase is not
        // letterspaced. The row still shares one baseline and line box.
        #expect(abs(exitKern - 0.52) <= 0.01, "ESC - EXIT lost its caps tracking")
        #expect(abs(hintKern) <= 0.01, "the sentence-case confirmation still carries caps tracking")

        // Same baseline: read the first ink row of each run from one rendered frame.
        // The count shares the row too, with its own type role.
        let count = try #require(descendants(of: room.view, of: NSTextField.self)
            .first { ($0.stringValue == "Type to start" || $0.stringValue.hasSuffix("words"))
                && !$0.isHiddenOrHasHiddenAncestor })
        let rows = try firstInkRows(of: [exit, hint, count], in: room.view)
        #expect(abs(rows[0] - rows[1]) <= 1,
                "ESC - EXIT and its confirmation are not on one baseline (\(rows))")
        #expect(abs(rows[0] - rows[2]) <= 1,
                "the word count is not on the ESC - EXIT baseline (\(rows))")
        window.orderOut(nil)
    }

    /// Topmost ink row of each view's text, in one rendered frame.
    private func firstInkRows(of views: [NSView], in root: NSView) throws -> [Int] {
        root.layoutSubtreeIfNeeded()
        let rep = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / max(root.bounds.width, 1)
        return try views.map { view in
            let frame = root.convert(view.bounds, from: view)
            let x0 = Int(frame.minX * scale) + 1
            let x1 = min(Int(frame.maxX * scale) - 1, rep.pixelsWide - 1)
            let y0 = max(Int((root.bounds.height - frame.maxY) * scale) - 1, 0)
            let y1 = min(Int((root.bounds.height - frame.minY) * scale) + 1, rep.pixelsHigh - 1)
            for y in y0...y1 {
                for x in x0...x1 {
                    guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let luma = 0.2126 * colour.redComponent + 0.7152 * colour.greenComponent + 0.0722 * colour.blueComponent
                    if luma < 0.6 { return y }
                }
            }
            throw NoRenderedText(view: String(describing: type(of: view)))
        }
    }

    /// Contiguous ink row runs in one rendered frame; a gap of at most 4 pt keeps
    /// glyph internals together and separates text lines.
    private func inkRowRuns(in rep: NSBitmapImageRep, scale: CGFloat,
                            x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>,
                            isInk: (NSColor) -> Bool) -> [(min: Int, max: Int)] {
        let x0 = max(Int(x.lowerBound * scale), 0)
        let x1 = min(Int(x.upperBound * scale), rep.pixelsWide - 1)
        let y0 = max(Int(y.lowerBound * scale), 0)
        let y1 = min(Int(y.upperBound * scale), rep.pixelsHigh - 1)
        guard x0 < x1, y0 < y1 else { return [] }
        var rows: [Int] = []
        for row in y0...y1 {
            var hasInk = false
            for column in x0...x1 {
                guard let colour = rep.colorAt(x: column, y: row)?.usingColorSpace(.sRGB),
                      colour.alphaComponent > 0.4 else { continue }
                if isInk(colour) { hasInk = true; break }
            }
            if hasInk { rows.append(row) }
        }
        var runs: [(min: Int, max: Int)] = []
        let gap = Int(ceil(8 * scale / 2))
        for row in rows {
            if let last = runs.last, row - last.max <= gap {
                runs[runs.count - 1].max = row
            } else {
                runs.append((row, row))
            }
        }
        return runs
    }

    // MARK: - Helpers

    private func assertCentred(_ control: NSControl, in content: NSView, _ label: String) {
        let rect = content.convert(control.bounds, from: control)
        #expect(abs(rect.midX - content.bounds.midX) <= 1, "\(label) is not centred in the card content")
    }

    private func makeWindow(_ controller: NSViewController,
                            appearance: NSAppearance.Name = .aqua,
                            size: NSSize = NSSize(width: 1040, height: 720)) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentViewController = controller
        window.setContentSize(size)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidAppear()
        controller.view.layoutSubtreeIfNeeded()
        WindowKeeper.windows.append(window)
        return window
    }

    private func makeEditor() -> (AppendOnlyTextView, DenyCounter) {
        let editor = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        editor.configureSessionTypography()
        let counter = DenyCounter()
        editor.onDeny = { counter.count += 1 }
        return (editor, counter)
    }

    private func trialState(used: Int) throws -> AppState {
        let root = tempRoot()
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = used
        let store = SettingsStore(configDirectory: root)
        try store.save(settings)
        return AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                        checkoutClient: MockCheckoutClient(), installIDStore: InstallIDStore(configDirectory: root),
                        productID: "prod_mock")
    }

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func resolved(_ color: NSColor, _ appearance: NSAppearance.Name) -> NSColor? {
        var result: NSColor?
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB)
        }
        return result
    }

    private func descendants<T: NSView>(of view: NSView, of type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, of: type)
        }
    }
}

@MainActor
private enum WindowKeeper {
    static var windows: [NSWindow] = []
}

private final class MutableRoundClock {
    var now: TimeInterval
    init(_ now: TimeInterval) { self.now = now }
}

private struct NoRenderedText: Error, CustomStringConvertible {
    let view: String
    var description: String { "no rendered text found in \(view)" }
}

private final class DenyCounter {
    var count = 0
}
