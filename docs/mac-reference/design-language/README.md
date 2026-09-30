# The MacStats design language — native macOS (Tahoe) look, for reuse in other apps

**Status:** reference spec, 2026-09-29. Written so a fresh Claude session with no context can apply this look
to another macOS app. Companion documents that apply it to specific apps:

- JVoice → `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/docs/design-language/jvoice-native-redesign.md`
- BetterScreenshot → `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/docs/design-language/betterscreenshot-native-redesign.md`

**Source of truth (working code):** MacStats, a macOS menu-bar system monitor at
`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats` (branch `feat/polish-perf`). The files that
define the look are all in `Sources/MacStatsApp/`: `Design.swift` (tokens), `StatCard.swift` (card, card-button
and small-button styles), `OverviewView.swift` (header, footer, gauge), `BreakdownView.swift` (list rows, icons),
`Sparkline.swift` (graphs), `RootView.swift` (screen transition). Screenshots:
`docs/design-language/assets/macstats-overview.png` and `macstats-breakdown.png` (dark mode, macOS 26).

## What the user likes (the brief, in their words, summarised)

> "It looks like how an Apple native UI looks … very simple, the lines are very simple, the text is very simple,
> it's very subtle, especially with the squircles around the UI … the color scheme is slightly transparent …
> maybe even a little more transparent … that's how MacBook UI looks — a little bit transparent here and there."

What they dislike in their other apps: **all-black opaque backgrounds, little decorative dots on everything, and
layouts that don't look Mac-native.**

So the goal is not "a theme". It is: **use the system's own materials, shapes, type and colours, and add as
little custom decoration as possible.** When unsure, do what the equivalent Apple app does (Control Center,
the Battery menu, System Settings, Activity Monitor).

## Glossary

- **Material / vibrancy** — a translucent, blurred background that shows a softened version of whatever is behind
  the window (desktop, other windows). SwiftUI: `.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`…;
  AppKit: `NSVisualEffectView`. It automatically adapts to light/dark mode.
- **Liquid Glass** — macOS 26 (Tahoe)'s newest material for *floating* controls (toolbars, HUDs, palettes).
  SwiftUI `.glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)`; AppKit `NSGlassEffectView`.
  Only available on macOS 26+, so it needs availability checks (see "Toolchain rules").
- **Squircle / continuous corners** — Apple's rounded-corner curve, where the curvature ramps up smoothly instead
  of a circular arc meeting a straight line. It is what makes Apple UI look "soft". SwiftUI:
  `RoundedRectangle(cornerRadius: r, style: .continuous)`; Core Animation: `layer.cornerCurve = .continuous`.
  A plain `layer.cornerRadius` or `NSBezierPath(roundedRect:xRadius:yRadius:)` is **circular** — avoid.
- **Concentric corners** — when a rounded shape sits inside another, its radius = outer radius − the gap between
  them, so the two curves stay parallel. Apple does this everywhere.
- **Hairline** — a 0.5 pt line (one physical pixel on Retina), used for borders instead of 1 pt lines.
- **Semantic colours** — `Color.primary`, `.secondary`, `.tertiary` (and AppKit `labelColor`,
  `secondaryLabelColor`…): they change automatically between light and dark mode. Opposite of hard-coded
  `Color(white: 0.04)`.

## 1. Principles (in priority order)

1. **Translucent, never opaque.** Window and panel backgrounds are a system material. Content "surfaces" on top
   of the material are *tints* of `Color.primary` at 4–12 % opacity, so the blur shows through them.
   Never paint a solid black/white/grey rectangle behind content.
2. **Continuous corners everywhere**, concentric with their container.
3. **System typography** — text *styles* (`.headline`, `.callout`, `.caption2`…), not fixed point sizes;
   `monospacedDigit()` for changing numbers. No custom kerning, no 7–10 pt text.
4. **Semantic colour + one meaningful hue.** Text is primary/secondary/tertiary. Colour is only used where it
   carries meaning (one hue per metric/state, system colours `.green .blue .purple .yellow .red .orange`).
   Destructive = red (`role: .destructive`).
5. **No decoration without meaning.** No bullet dots before headings, no glows, no stacked shadows, no dotted
   separators. A small coloured dot is allowed only as a status indicator (e.g. memory pressure green/yellow/red).
6. **Follow the system appearance.** Light/dark comes from macOS; don't force `.darkAqua` unless the user picks
   an explicit override in Settings (and then default the override to "System").
7. **Calm motion.** Short ease-outs, no bouncing, nothing that loops forever. Numbers fade, they don't roll.
8. **Stable layout.** Fixed sizes for panels; placeholders take the same space as values; nothing jumps when
   data arrives.

## 2. Tokens (copy these numbers)

From `Sources/MacStatsApp/Design.swift`. Opacities are applied to `Color.primary` so they adapt to light/dark.

| Token | Value | Use |
|---|---|---|
| `panelCornerRadius` | 16 pt | Floating panel / popover corner (macOS 26 menus/popovers are ~16) |
| `panelInset` | 8 pt | Gap between the panel edge and the cards inside it |
| `cardCornerRadius` | `panelCornerRadius − panelInset` = 8 pt | Card corners (concentric) |
| `cardSpacing` | 6 pt | Gap between neighbouring cards |
| `cardPadding` | 12 pt horizontal, ~9 pt vertical | Card content inset |
| `headerHeight` | 30 pt | Title row, `.headline`, bottom-leading aligned, inset by `cardPadding` |
| `cardFill` | 0.05 (**user wants a touch more transparent → try 0.04**) | Card surface |
| `cardHoverFill` | 0.085 | Card under the pointer |
| `cardPressedFill` | 0.12 | Card while pressed (+ `scaleEffect(0.985)`) |
| `cardHairline` | 0.08, **0.5 pt** `strokeBorder` | Card border |
| Small button fill | 0.08 / hover 0.12 / pressed 0.16, radius 6, height 24, h-padding 10 | "Empty", "Quit" |
| List-row hover | 0.07, radius `cardCornerRadius − 4` | Rows inside a card |
| Track (empty part of a bar/gauge) | 0.08–0.10, `Capsule()` | Progress bars, gauges |
| App-icon clip | radius ≈ 23 % of icon size (5.5 pt at 24 pt), `.continuous` | App icons in lists |

**Scaling the radii for bigger windows:** keep the concentric rule. A regular window's content cards use 10–12 pt
(System Settings' grouped sections are ~10–12); a floating HUD pill is fully rounded (`Capsule()`); a 64 pt app
mark uses ~14 pt (22 %).

## 3. Components (reference implementations)

All from MacStats; paste and adapt.

### Card surface
```swift
/// The inset card surface: a faint fill (the blurred window shows through) and a hairline,
/// with continuous (squircle) corners concentric with the panel.
struct CardBackground: View {
    var fill: Double = Design.cardFill
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
        shape.fill(Color.primary.opacity(fill))
            .overlay(shape.strokeBorder(Color.primary.opacity(Design.cardHairline), lineWidth: 0.5))
    }
}
```

### Whole card as a button (hover + press feedback)
```swift
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverCard(isPressed: configuration.isPressed) { configuration.label }
    }
    private struct HoverCard<Label: View>: View {
        let isPressed: Bool
        @ViewBuilder let label: Label
        @State private var hovering = false
        var body: some View {
            label
                .background(CardBackground(fill: isPressed ? Design.cardPressedFill
                                            : hovering ? Design.cardHoverFill : Design.cardFill))
                .scaleEffect(isPressed ? 0.985 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: isPressed)
                .onHover { hovering = $0 }
        }
    }
}
```
A tappable card shows a trailing `Image(systemName: "chevron.right").font(.caption.weight(.semibold))
.foregroundStyle(.secondary)`; non-tappable cards reserve the same space (opacity 0) so columns line up.

### Small secondary button
`SubtleButtonStyle` in `Sources/MacStatsApp/StatCard.swift`: `.callout.weight(.medium)` label, 24 pt tall,
10 pt side padding, continuous radius 6, `Color.primary` fill 0.08 → 0.12 hover → 0.16 pressed, `.tertiary` text
when disabled. For *primary* actions in a real window, prefer the native `.borderedProminent` (or `.glassProminent`
on macOS 26) instead of inventing a style.

### Card content typography (the "stat card")
```swift
VStack(alignment: .leading, spacing: 2) {
    Text("CPU").font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)   // uppercase label
    Text("18%").font(.title3).fontWeight(.semibold).monospacedDigit()               // value
        .contentTransition(.interpolate).animation(.easeInOut(duration: 0.25), value: number)
    Text("45°C").font(.caption2).foregroundStyle(.secondary)                          // meta line
}
```
Uppercase section labels are `.caption2` semibold secondary — **no dot before them, no manual kerning**.

### List row inside a card
24 pt icon clipped to `RoundedRectangle(cornerRadius: 5.5, style: .continuous)`, `.callout` name, a 4 pt
capsule bar (track 0.08, fill in the metric colour), a trailing `.callout.semibold.monospacedDigit` value in a
fixed-width frame. Hover → a `Color.primary.opacity(0.07)` continuous-rounded highlight (radius
`cardCornerRadius − 4`), eased 0.12 s. Rows sit in one card with 4 pt padding; no dividers between rows.

### Gauge / progress bar
`Capsule()` track `Color.primary.opacity(0.1)` + a `Capsule()` fill in the state colour, 8 pt tall (4 pt inside
rows), width animated `.smooth(duration: 0.3–0.4)`.

### Graph (sparkline)
Gradient area (`color.opacity(0.45)` → `0`, top → bottom) under a 1.6 pt line with round caps/joins; **no end
dot** (the user asked for it removed); a 0.5 pt baseline at `Color.primary.opacity(0.1)`; monotone curve (no
overshoot); new data slides in with one linear offset animation per sample. See `Sparkline.swift` +
`Sources/MacStatsCore/SparklineGeometry.swift`.

### Header / footer
Header: the title in `.headline`, bottom-leading in a 30 pt row. Footer: small buttons in `SubtleButtonStyle`,
secondary info in `.caption`/`.caption2` `.tertiary` on the right.

### Screen transition (drill-in)
Same fixed size for both screens; push = new screen `.move(edge: .trailing).combined(with: .opacity)`, old
screen `.offset(x: −30 % width).combined(with: .opacity)`, `.snappy(duration: 0.3)`, clipped.

## 4. Motion rules

| Interaction | Animation |
|---|---|
| Hover highlight | `.easeOut(duration: 0.12)` |
| Press | `.easeOut(duration: 0.08)` + `scaleEffect(0.985)` |
| Changing number | `.contentTransition(.interpolate)` + `.easeInOut(duration: 0.25)` (the user found rolling `.numericText` too busy) |
| Bars / gauges | `.smooth(duration: 0.3–0.4)` |
| Screen push | `.snappy(duration: 0.3)` |
| Window appearance | Instant, fully populated first frame (Apple's own menu-bar panels do not fade in) |

Never: `repeatForever` animations or `TimelineView(.animation)` running while idle (they cost CPU forever),
spring bounces, animated path morphs every frame.

## 5. Materials — which one where

| Surface | macOS 14–15 (fallback) | macOS 26 (Tahoe) |
|---|---|---|
| Menu-bar popover | `MenuBarExtra(.window)` gives the system material for free — keep it | same |
| Regular window (Settings, editor) | Window background = system (`.windowBackground`), sidebars `NSVisualEffectView(.sidebar)`; content cards = `CardBackground` tints | same; titlebar/toolbars get Liquid Glass automatically when built with the 26 SDK |
| Floating HUD / pill / palette / toolbar over content | `NSVisualEffectView` material `.hudWindow` (or SwiftUI `.ultraThinMaterial` / `.regularMaterial`) clipped to a continuous shape | `.glassEffect(.regular, in: .capsule)` / `NSGlassEffectView` |
| Popover (info, menus) | `NSPopover` / `NSMenu` (native) | native (auto-glass) |
| Alerts | `NSAlert` (native) | native |

**Transparency level:** the user wants it "slightly transparent, maybe a little more". Prefer the thinner
materials (`.ultraThinMaterial`/`.thinMaterial`, glass `.regular`) and keep card tints ≤ 0.05. Do not go fully
clear (`.clear` glass) behind text — legibility first; check text contrast over a busy, bright wallpaper.

Apple's rule for Liquid Glass: it's for the **floating control layer**, not for content, and **don't stack glass on
glass** (no glass cards inside a glass panel — inside glass use the `CardBackground` tints).

## 6. Toolchain rules (both target apps build with SwiftPM + Command Line Tools, deployment target macOS 14)

- Every macOS 26 API needs a runtime check: `if #available(macOS 26, *) { … } else { fallback }`.
- If the app's CI builds with an older SDK (Xcode 16 = macOS 15 SDK), the code must also compile there: wrap glass
  code in `#if compiler(>=6.2)` … `#endif` (Swift 6.2 ships with the macOS 26 SDK), with the material fallback in
  both branches. Otherwise CI fails with "cannot find 'glassEffect' in scope".
- Materials (`.ultraThinMaterial` etc., `NSVisualEffectView`) and `.continuous` corners work on macOS 14 with no
  checks.
- AppKit layers: set `layer.cornerCurve = .continuous` whenever you set `layer.cornerRadius`; for bezier paths,
  build the shape with SwiftUI `RoundedRectangle(cornerRadius:style: .continuous).path(in:)` and convert via
  `.cgPath`, instead of `NSBezierPath(roundedRect:xRadius:yRadius:)`.

## 7. Checklist for "is it native yet?"

- [ ] No opaque black/white/grey background on any window, panel or pill.
- [ ] Every rounded shape is `.continuous` (grep `cornerRadius`, `RoundedRectangle(`, `NSBezierPath(roundedRect`).
- [ ] Nested corners are concentric.
- [ ] Borders are 0.5 pt hairlines at ≤ 0.1 opacity; ≤ 1 soft shadow per floating element (system shadow only).
- [ ] Text uses text styles; nothing below `.caption2` (~10 pt); numbers `monospacedDigit()`.
- [ ] No decorative dots/bullets; status dots only where they mean something.
- [ ] Colours are semantic; destructive actions are red.
- [ ] Follows system light/dark by default; looks right in both.
- [ ] Hover + press feedback on custom clickable things.
- [ ] Nothing animates while idle; nothing jumps when data arrives.
- [ ] Checked by eye in light and dark mode, over a bright and a dark wallpaper.
