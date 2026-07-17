# First Line Web Design System

This is the visual constitution for all web-facing pages in this repo. When in doubt, use Kami.

## Direction

First Line web pages should feel like a restrained Mac writing tool rendered as a warm document: quiet, legible, and serious. The landing should sell the writing constraint, not fill space with support copy.

## Kami rules

- Canvas: parchment `#f5f4ed`, never pure white.
- Accent: one ink blue `#1B365D`.
- Neutrals: warm beige/ink only; no cool gray SaaS palette.
- Shadows: ring and whisper paper shadows only; no hard floating cards.
- Radii: controls `8px`; paper surfaces `16px`.
- Type: serif-led hierarchy using Charter/Georgia/Iowan-style fonts plus TsangerJinKai02 for Chinese.
- Shape language: document sections, paper panels, native controls. No pill buttons, decorative cards, gradients, blobs, or component-system ornaments.
- Page rhythm follows upstream Kami: max-width around `1120px`, parchment body, `88px 64px 120px` desktop page padding, hero bottom hairline, and `48-72px` section rhythm.
- Content lists are hairline rows, not floating cards. Use top/bottom borders for Trial, Privacy, FAQ, Help, and Status blocks.

## Type scale

The hero is the only large display moment.

- Hero title: `30-42px`, line-height about `1.32`, weight `500`.
- Section title: `20-28px`, or `20-22px` on small phones when the hero compresses, line-height about `1.28`, weight `500`, max width around `22ch`.
- Card title / FAQ question: `17-18px`, line-height about `1.35`, weight `500`.
- Body and section note: `15-16px`, line-height `1.6-1.65`.
- Kicker / metadata: `12-13px`, uppercase or compact only when it labels structure.

Never reuse hero `h2` display sizes for support, FAQ, privacy, release, or help sections.

## Section rules

- Extra sections are allowed only when they answer a real user question. Do not add trial, legal, help, privacy, or release blocks just to make the page feel complete.
- FAQ should be short: usually 2-4 questions such as privacy, trial sessions, and draft recovery.
- Sections should read like a product document: quiet dividers, clear text, low-density layout.
- Do not add a new visual motif for each section.
- Keep anchors discoverable, but links should look like editorial text links, not navigation pills.
- Do not rotate cards, stagger cards, add card walls, or use repeated lifted panels for support content.
- The landing should have one strong product claim, one writing/demo surface, and at most a small FAQ/footer unless the product surface truly needs more.

## Verification checklist

- The first thing seen is the product claim and writing surface, not support content.
- Section headings are visibly below the hero title in scale.
- Buttons use `8px` control radius.
- Paper surfaces/cards use `16px` paper radius.
- Browser QA checks desktop, mobile, anchors, trial launch, console errors, and horizontal overflow.
