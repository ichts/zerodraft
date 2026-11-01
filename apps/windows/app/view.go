package app

import (
	_ "embed"
	"fmt"

	"github.com/ELY-Open-Source/CrychicUI/button"
	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/licence"
	"github.com/ichts/zerodraft/apps/windows/room"
	"github.com/ichts/zerodraft/apps/windows/tokens"
)

//go:embed lockup.svg
var lockupSVG []byte

var lockup = ui.MustParseSVG(lockupSVG)

type uiState struct {
	durIdx, silIdx int
	field          string // the field's own value, per card
}

// View is the window content: the room while a session is open, one of the cards otherwise.
func (a *App) View(c *ui.Context) {
	a.ctx = c
	dark := c.Theme().Dark
	if a.surface == Session && a.rm != nil {
		a.rm.View(c.Key("room")) // one identity per surface, so a new surface's AutoFocus fires
		return
	}
	c.SetTheme(room.Theme(dark))
	c = c.Key(int(a.surface))
	a.ctx = c
	switch a.surface {
	case Home:
		a.homeView(c, dark)
	case Upgrade:
		a.upgradeView(c, dark)
	case Settings:
		a.settingsView(c, dark)
	case Rules:
		a.rulesView(c, dark)
	default:
		a.homeView(c, dark)
	}
}

// ---- the After vocabulary, drawn with mygo

type pal struct{ dark bool }

func (p pal) of(r tokens.Role) ui.Color { return room.Color(r, p.dark) }

func (p pal) ink() ui.Color    { return p.of(tokens.Ink) }
func (p pal) mute() ui.Color   { return p.of(tokens.Mute) }
func (p pal) chrome() ui.Color { return p.of(tokens.Chrome) }

// page is the window: the page colour with one centred card.
func page(c *ui.Context, p pal, label string, fn func()) {
	ui.Box(c).Fill().Label(label).Background(p.of(tokens.Page)).Justify(ui.Center).AlignItems(ui.Center).Children(fn)
}

// card is the white sheet with its ring and the one shadow (FirstLineCardView).
func card(c *ui.Context, p pal, width, padTop, padSide float32, fn func()) {
	el := ui.Column(c).Width(width).Padding(padTop, padSide).AlignItems(ui.Center).
		Background(p.of(tokens.Sheet)).Radius(tokens.RadiusCard).Border(1, p.of(tokens.SheetRing))
	el = shadows(el, p.dark)
	el.Children(fn)
}

func shadows(el ui.Element, dark bool) ui.Element {
	black := room.Alpha(ui.RGB(0, 0, 0), 0.05)
	if dark {
		return el.Shadow(0, 1, 1, 0, room.Alpha(ui.RGB(0, 0, 0), 0.25)).Shadow(0, 28, 28, 0, room.Alpha(ui.RGB(0, 0, 0), 0.60))
	}
	ink := room.Color(tokens.Ink, false)
	return el.Shadow(0, 1, 1, 0, black).Shadow(0, 12, 12, 0, room.Alpha(ink, 0.12)).Shadow(0, 36, 36, 0, room.Alpha(ink, 0.20))
}

func gap(c *ui.Context, h float32) { ui.Box(c).Height(h) }

// text is one role of text; centre is the card default.
func text(c *ui.Context, s string, size float32, weight int, col ui.Color) ui.Element {
	return ui.Text(c, s).FontSize(size).FontWeight(weight).TextColor(col).LineHeight(1.25)
}

func display(c *ui.Context, p pal, s string, size float32) ui.Element {
	return text(c, s, size, 600, p.ink()).TextAlign(ui.Center)
}

func sub(c *ui.Context, p pal, s string) ui.Element {
	return text(c, s, 15, 400, p.mute()).TextAlign(ui.Center).LineHeight(1.4)
}

func smallLabel(c *ui.Context, p pal, s string) ui.Element {
	return text(c, s, 13, 600, p.chrome())
}

// primary is the 48 pt ink pill (FirstLineButtons.primary); outline the 48 pt sheet pill beside it.
func primary(c *ui.Context, label string) ui.Element {
	return button.Pill(c, label).Height(48).Padding(0, 24).FontSize(15).FontWeight(600).AlignSelf(ui.Center).Justify(ui.Center).AlignItems(ui.Center)
}

func secondary(c *ui.Context, p pal, label string) ui.Element {
	return button.Outline(c, label).Height(48).Padding(0, 20).FontSize(15).FontWeight(600).Radius(999).
		Background(p.of(tokens.Sheet)).AlignSelf(ui.Center).Justify(ui.Center).AlignItems(ui.Center)
}

// link is a quiet text button (FirstLineLinkButton: 13 medium, chrome).
func link(c *ui.Context, p pal, label string) ui.Element {
	return button.Ghost(c, label).Padding(4, 8).FontSize(13).FontWeight(500).TextColor(p.chrome()).AlignSelf(ui.Center)
}

// status is the dot-and-sentence line (FirstLineStatusView).
func status(c *ui.Context, p pal, s string, bad bool, maxW float32) {
	dot, tc := room.Alpha(p.ink(), 0.35), p.chrome()
	if bad {
		dot, tc = p.of(tokens.Red), p.of(tokens.Red)
	}
	ui.Row(c).AlignItems(ui.Start).Gap(8).MaxWidth(maxW).Children(func() {
		ui.Box(c).Size(8, 8).Radius(2).Background(dot).Margin(6, 0, 0, 0)
		text(c, s, 13, 400, tc).LineHeight(1.35)
	})
}

// segmented is the 40 pt track with 34 pt pills (FirstLineSegmentedControl).
func segmented(c *ui.Context, p pal, sel *int, label string, items []string) {
	seg := ui.SegmentedBase(c, sel, len(items))
	seg.Track.Label(label).Padding(3).Gap(2).Radius(20).Background(p.of(tokens.SegmentTrack)).Height(40).AlignSelf(ui.Center).Children(func() {
		for i, it := range items {
			s := seg.Segment(i).Height(34).MinWidth(52).Padding(0, 14).Radius(17).Label(it).Justify(ui.Center).AlignItems(ui.Center)
			on := i == *sel
			col := p.chrome()
			if on {
				col = p.ink()
				s.Background(p.of(tokens.Sheet)).Border(1, p.of(tokens.Hair)).Shadow(0, 1, 2, 0, room.Alpha(p.of(tokens.Shadow), 0.12))
			}
			s.Children(func() { text(c, it, 14, 500, col).SingleLine() })
		}
	})
}

// field is the 44 pt text field of the activation card.
func (a *App) field(c *ui.Context, p pal, value *string, placeholder string) ui.Element {
	return ui.TextInput(c.Key("order"), value).Placeholder(placeholder).Label(placeholder).Width(464).Height(44).FontSize(17).AlignSelf(ui.Center).
		Background(p.of(tokens.Sheet)).Radius(tokens.RadiusControl).Border(1, p.of(tokens.HairStrong))
}

// ---- Home

func (a *App) homeView(c *ui.Context, dark bool) {
	p := pal{dark}
	snap := a.lic.Snapshot()
	if c.Shortcut(ui.Cmd, ui.KeyComma) {
		a.openSettings()
	}
	page(c, p, "Write It Down", func() {
		card(c, p, 560, 44, 48, func() {
			// the quiet "?" sits at the content's top right, 12 in from its edge (Mac rulesButton constraints)
			rules := link(c, p, "?").Label(tokens.HomeRulesHelp).Absolute().Top(44).Right(60).Size(28, 28).Padding(0)
			if rules.Clicked() {
				a.openRules()
			}
			ui.Box(c).Size(128, 16.25).Label(tokens.HomeLockupLabel).Role(ui.RoleImage).Draw(func(pp *ui.Painter, r ui.Rect) { pp.Icon(lockup, r, p.ink()) })
			gap(c, 20)
			display(c, p, tokens.HomeTitle, 34)
			gap(c, 24)
			smallLabel(c, p, tokens.HomeMinutes)
			gap(c, 8)
			mins := make([]string, len(tokens.DurationChoices))
			for i, d := range tokens.DurationChoices {
				mins[i] = fmt.Sprint(d / 60)
			}
			segmented(c, p, &a.ui.durIdx, "Session length", mins)
			a.setDuration(tokens.DurationChoices[a.ui.durIdx])
			gap(c, 20)
			smallLabel(c, p, tokens.HomeSilence)
			gap(c, 8)
			segmented(c, p, &a.ui.silIdx, tokens.HomeSilence, tokens.SilenceLabels)
			a.setSilence(tokens.SilenceChoices[a.ui.silIdx])
			gap(c, 26)
			begin := primary(c, tokens.HomeBegin).Label("Begin writing").AutoFocus()
			if begin.Clicked() || c.Shortcut(0, ui.KeyEnter) {
				a.Begin()
			}
			gap(c, 18)
			if !snap.Full {
				status(c, p, snap.AccessText, snap.TrialError != "", 400)
			}
			gap(c, 6)
			ui.Row(c).Gap(4).Justify(ui.Center).Children(func() {
				if link(c, p, tokens.SettingsTitle).Clicked() {
					a.openSettings()
				}
			})
		})
	})
}

// ---- Rules

func (a *App) rulesView(c *ui.Context, dark bool) {
	p := pal{dark}
	if c.Shortcut(0, ui.KeyEscape) || c.Shortcut(0, ui.KeyEnter) {
		a.closeRules()
	}
	page(c, p, tokens.RulesEyebrow, func() {
		card(c, p, 620, 40, 44, func() {
			ui.Column(c).Width(480).AlignItems(ui.Start).Children(func() {
				smallLabel(c, p, tokens.RulesEyebrow)
				gap(c, 10)
				text(c, tokens.RulesHeading, 34, 500, p.ink()).Font(roomSerif).LineHeight(1.1)
				gap(c, 12)
				text(c, tokens.RulesSub, 15, 400, p.mute()).LineHeight(1.4)
				gap(c, 24)
				for i, r := range [][2]string{{tokens.Rule1Title, tokens.Rule1Body}, {tokens.Rule2Title, tokens.Rule2Body}, {tokens.Rule3Title, tokens.Rule3Body}} {
					if i > 0 {
						gap(c, 18)
					}
					text(c, r[0], 13, 600, p.ink())
					gap(c, 4)
					text(c, r[1], 15, 400, p.mute()).LineHeight(1.4)
				}
				gap(c, 28)
			})
			done := primary(c, tokens.RulesDone).Label("Close how it works").AutoFocus()
			if done.Clicked() {
				a.closeRules()
			}
		})
	})
}

const roomSerif = "Newsreader, Zhuque Fangsong"

// ---- Upgrade (the activation card)

func (a *App) upgradeView(c *ui.Context, dark bool) {
	p := pal{dark}
	snap := a.lic.Snapshot()
	licensed := snap.Full
	if licensed && snap.Err != nil && snap.Err.Kind != licence.KindCleanupFailure {
		licensed = false
	}
	page(c, p, tokens.UpgradeTitle, func() {
		card(c, p, 560, 44, 48, func() {
			title, subtitle := tokens.UpgradeTitle, tokens.UpgradeSubtitle
			if licensed {
				title, subtitle = tokens.UpgradeTitleLicensed, tokens.UpgradeSubtitleLicensed
			}
			ui.Column(c).Width(464).AlignItems(ui.Center).Children(func() {
				display(c, p, title, 34)
				gap(c, 8)
				sub(c, p, subtitle).MaxWidth(440)
				gap(c, 26)
				if licensed {
					a.licensedBlock(c, p, snap)
					return
				}
				ui.Column(c).Width(464).AlignItems(ui.Start).Children(func() {
					smallLabel(c, p, tokens.UpgradeFieldLabel)
					gap(c, 8)
				})
				field := a.field(c, p, &a.key, tokens.UpgradePlaceholder).AutoFocus()
				if field.Changed() {
					a.emptyShown = false
					a.lic.ClearActivationError()
				}
				submit := field.Submitted()
				gap(c, 16)
				ui.Row(c).Gap(12).Justify(ui.Center).Children(func() {
					label := tokens.UpgradeActivate
					if snap.Activating {
						label = tokens.UpgradeActivating
					}
					act := primary(c, label).Disabled(snap.Activating)
					if (act.Clicked() || submit) && !snap.Activating {
						a.activate()
					}
					buyLabel := fmt.Sprintf(tokens.UpgradeBuyFormat, tokens.DisplayPrice)
					if snap.CheckingOut {
						buyLabel = tokens.UpgradeOpeningCheckout
					}
					buy := secondary(c, p, buyLabel).Disabled(!snap.CheckoutOK || snap.CheckingOut)
					if buy.Clicked() {
						a.buy()
					}
				})
				if msg, bad := a.feedback(snap); msg != "" {
					gap(c, 14)
					text(c, msg, 13, 400, pick(bad, p.of(tokens.Red), p.mute())).TextAlign(ui.Center).MaxWidth(440).LineHeight(1.35)
				}
				gap(c, 14)
				status(c, p, tokens.UpgradePricing, false, 440)
				if !snap.CheckoutOK {
					gap(c, 14)
					text(c, tokens.UpgradeCheckoutUnavailable, 13, 400, p.chrome()).MaxWidth(440)
				}
				gap(c, 6)
				if link(c, p, tokens.UpgradeWebTrial).Clicked() {
					a.openWebTrial()
				}
			})
		})
	})
}

// feedback is the one line under the buttons: this attempt's error, the empty-field prompt, or the standing
// licence state (Mac UpgradeViewController.refreshLicense). bad is the red tone.
func (a *App) feedback(s licence.Snapshot) (string, bool) {
	if s.Err != nil {
		return s.Err.Error(), true
	}
	if a.emptyShown {
		return tokens.UpgradeEnterFirst, true
	}
	hide := s.Status == licence.Inactive && s.TrialError == ""
	if hide {
		return "", false
	}
	bad := s.TrialError != "" || s.Status == licence.Revoked || s.Status == licence.Invalid
	return s.AccessText, bad && !s.Validating
}

func (a *App) licensedBlock(c *ui.Context, p pal, s licence.Snapshot) {
	if s.Err != nil && s.Err.Kind == licence.KindCleanupFailure {
		text(c, tokens.UpgradeCleanupActive+"\n"+s.Err.Error(), 13, 400, p.of(tokens.Red)).TextAlign(ui.Center).MaxWidth(440)
		gap(c, 14)
	}
	start := primary(c, tokens.UpgradeStartWriting).AutoFocus()
	if start.Clicked() || c.Shortcut(0, ui.KeyEnter) {
		a.startWriting()
	}
}

func pick[T any](b bool, yes, no T) T {
	if b {
		return yes
	}
	return no
}

// ---- Settings (licence and about)

func (a *App) settingsView(c *ui.Context, dark bool) {
	p := pal{dark}
	snap := a.lic.Snapshot()
	if c.Shortcut(0, ui.KeyEscape) {
		a.closeSettings()
	}
	page(c, p, tokens.SettingsTitle, func() {
		card(c, p, 560, 40, 48, func() {
			ui.Column(c).Width(464).AlignItems(ui.Start).Children(func() {
				ui.Row(c).Width(464).Justify(ui.SpaceBetween).AlignItems(ui.Center).Children(func() {
					text(c, tokens.SettingsTitle, 28, 600, p.ink())
					if link(c, p, tokens.SettingsDone).Clicked() {
						a.closeSettings()
					}
				})
				gap(c, 24)
				text(c, tokens.SettingsLicense, 15, 600, p.ink())
				gap(c, 10)
				stateText := snap.StatusText
				if !snap.Full && snap.Err != nil {
					stateText = snap.Err.Error()
				}
				text(c, stateText, 13, 400, pick(!snap.Full && (snap.Err != nil || snap.Status == licence.Revoked || snap.Status == licence.Invalid), p.of(tokens.Red), p.mute())).LineHeight(1.35)
				if snap.Full {
					if !snap.ActivatedAt.IsZero() {
						gap(c, 2)
						text(c, fmt.Sprintf(tokens.SettingsActivated, snap.ActivatedAt.Local().Format("Jan 2, 2006, 3:04 PM")), 13, 400, p.mute())
					}
					if !snap.ValidatedAt.IsZero() {
						gap(c, 2)
						text(c, fmt.Sprintf(tokens.SettingsLastValidated, snap.ValidatedAt.Local().Format("Jan 2, 2006, 3:04 PM")), 13, 400, p.mute())
					}
				} else {
					gap(c, 14)
					ui.Divider(c).Width(464).Background(p.of(tokens.Hair))
					gap(c, 14)
					text(c, tokens.SettingsExplanation, 13, 400, p.mute())
					gap(c, 10)
					field := a.field(c, p, &a.key, tokens.SettingsFieldPlaceholder)
					if field.Changed() {
						a.lic.ClearActivationError()
					}
					submit := field.Submitted()
					gap(c, 12)
					ui.Row(c).Width(464).Gap(12).Justify(ui.End).Children(func() {
						label := pick(snap.Activating, tokens.UpgradeActivating, tokens.UpgradeActivate)
						act := primary(c, label).Disabled(snap.Activating)
						if (act.Clicked() || submit) && !snap.Activating {
							a.activate()
						}
						buy := secondary(c, p, fmt.Sprintf(tokens.UpgradeBuyFormat, tokens.DisplayPrice)).Disabled(!snap.CheckoutOK || snap.CheckingOut)
						if buy.Clicked() {
							a.buy()
						}
					})
				}
				gap(c, 24)
				text(c, tokens.SettingsAbout, 15, 600, p.ink())
				gap(c, 10)
				ver := a.env.Version
				text(c, "Write It Down  -  "+fmt.Sprintf(tokens.SettingsVersionFormat, ver), 13, 400, p.mute())
			})
		})
	})
}
