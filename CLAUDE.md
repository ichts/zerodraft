# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zero Draft is a distraction-free writing app with a "danger mechanic" - stop typing for 8 seconds and your text fades away. Built with Datastar framework for reactive state management. No build step required.

**Key Feature: Append-Only Writing** - Users can only add text, never delete or modify. This enforces "write without looking back".

## Development

**Quick Start:** Run a local HTTP server (required for ES modules):
```bash
python3 -m http.server 8000
# Open http://localhost:8000/index.html
```

**Static Deployment:** Compatible with Vercel, Netlify, or GitHub Pages.

**Live Demo:** https://zerodraft.ai-builders.space/

## Architecture

### Datastar Framework
Uses Datastar for declarative reactivity via `data-*` HTML attributes:
- `data-signals` - Reactive state variables (accessed with `$` prefix)
- `data-show` - Conditional display
- `data-class` - Dynamic CSS classes
- `data-on` - Event handlers
- `data-on-interval` - Timer intervals
- `data-text` - Text binding
- `data-style` - Inline style binding
- `data-effect` - Side effects

### State Machine
```
idle → writing → danger → failure
              ↘ success
```
- **Idle**: Duration selection via dropdown (3/5/10/15/20/30/60 min)
- **Writing**: Active session with timer, centered text, append-only input
- **Danger**: 5s no input triggers blur/pulse, 3s more clears text
- **Success**: Shows written text with copy/continue options, content saved to `savedContent`
- **Failure**: Current session text cleared, but previously saved content preserved with copy option

### Key Files
- `index.html` - Main Datastar-based implementation
- `prototype.html` - Legacy vanilla JS version (backup)
- `src/styles/global.css` - CSS variables and component styles
- `src/styles/animations.css` - Keyframe animations
- `zerodraft-prd.md` - Product requirements
- `docs/design-system.md` - Design specifications

### Signals (State)
Defined on `<body data-signals="...">`:
```javascript
screen: 'idle'          // idle | writing | success | failed
duration: 900           // Session duration in seconds
elapsed: 0              // Elapsed time in seconds
content: ''             // Current session text (new input only)
savedContent: ''        // Accumulated text from completed sessions
sessionActive: false    // Timer running flag
lastInputTime: 0        // Timestamp for danger detection
dangerActive: false     // Blur/pulse animation active
wordCount: 0            // Final word count
```

### Data Persistence
localStorage key `zerodraft_history` stores last 10 sessions:
```js
{ id, content, wordCount, duration, completedAt, status }
```

## Design System

### Colors
- Paper: `#FAFAF8` | Ink: `#1A1A1A`
- Danger: `#C1403D` | Success: `#2E5930`

### Fonts
- Chinese: LXGW WenKai (CDN)
- English/Code: IBM Plex Mono (Google Fonts)

### Typography
- Title: 96px, weight 200
- Tagline: 24px, weight 300
- Writing area: 28px, centered, line-height 1.6

### Writing UX
- Cursor positioned at ~38% from top (golden ratio area)
- Text centered horizontally (poetry-like layout)
- Zen mode: older lines fade via gradient overlay
- Auto-scroll to keep cursor in view

### Timing
- Danger trigger: 5 seconds no input
- Text clear: 3 seconds after danger (8s total)
- Transitions: fast (200ms), medium (400ms), slow (800ms)

### Responsive Breakpoints
- Tablet: 1023px
- Mobile: 768px

## Conventions

- Datastar signals: camelCase (`$sessionActive`)
- CSS classes: kebab-case (`.writing-area`)
- Animation names: kebab-case (`.gentle-blur`)
- Accessibility: WCAG AA compliant, respects `prefers-reduced-motion`

## Implementation Notes

- Timer uses `data-on-interval__duration.1s` with guard `if (!$sessionActive) return;`
- Append-only uses `data-on:keydown` to block Backspace/Delete
- Cut blocked with `data-on:cut__prevent="true"`
- Auto-focus on session start via `setTimeout(() => el.focus(), 100)`
- Zen mode: `has-multiple-lines` class toggles gradient overlay on multi-line input
- Success screen shows full text with fixed bottom actions ("复制" / "继续写")
- Session protection: completed session content stored in `savedContent`, survives subsequent failures
