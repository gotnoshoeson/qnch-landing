# qnch — design brief

Paste this at the start of a Claude Design session so output matches qnch.network.
Values are lifted from `src/layouts/Base.astro`; keep them in step if the tokens change.

---

## The look in one line

Cypherpunk zine. Xerox and cut paper, not chrome and glow. Pure black, hard hairlines,
oversized condensed display type, one mint accent used sparingly.

## Tokens

| role | value |
|---|---|
| Background | `#000000` |
| Foreground | `#ffffff` |
| Accent (mint) | `#adebb3` |
| Mint, deeper (hover) | `#86efac` |
| Mint, analogous | `#adebd2` |
| Muted text | `#8a8a8a` |
| Dimmest text / markers | `#5a5a5a` |
| Hairline rule | `rgba(255,255,255,0.16)` |
| Rule, stronger | `rgba(255,255,255,0.32)` |
| Mint rule | `rgba(173,235,179,0.4)` |

Mint is the **only** accent. One per view — a rule, a numeral, a single payoff word.
If two things are mint, one of them is wrong.

## Type

- **Display:** Anton, uppercase, letter-spacing `-0.03em` to `-0.045em`, line-height `0.85`–`0.95`.
  Set it big and let it dominate. Fallback `'Arial Narrow', sans-serif`.
- **Body / labels:** JetBrains Mono. Fallback `ui-monospace, 'SF Mono', Menlo, monospace`.
  Small mono set like a margin annotation — `0.62`–`0.72rem`, letter-spacing `0.16em`–`0.24em`,
  uppercase for labels and captions.
- Body copy runs ~`0.85`–`0.9rem`, line-height `1.75`, at `rgba(255,255,255,0.78)`.

No third typeface.

## Rules of construction

- **1px hairlines**, hard corners. `border-radius: 0` everywhere.
- **No shadows, no blur, no glow.** The only blur in the codebase is the sticky nav's backdrop.
- Flat blocks with an optional fractal-noise overlay at ~4.5% opacity, `mix-blend-mode: overlay`.
- Slight rotations — `0.5deg` to `1.5deg` — on stamps, callout tags, pulled numerals. Never more.
- Asymmetry over centring. Break the axis deliberately; let a second line step right.
- Oversized section numerals (`01`, `02`) as **stroked outlines**, `-webkit-text-stroke: 1px`
  in mint at 40% alpha, sitting half off-grid behind the heading.
- Hard-cut inversion is available for one block per page: white ground, black type, mint
  swapped for a darker green (`#158a3f`) so it stays legible.

## Banned

Neon glow. Purple/cyan gradients. Matrix rain. Glitch text. Lock, shield, fist or raised-hand
icons. Rounded corners. Drop shadows. Stock photography. Any gradient at all.

## Diagram conventions

Diagrams sit in a hairline-framed plate with a small uppercase mono caption beneath.
Target **1248px** wide. Prefer SVG.

- Nodes: hairline-stroked rectangles or circles on black, white labels.
- Connections: 1px white lines. Direction shown with a small solid arrowhead, not a gradient.
- Exactly one element in mint — the outcome, the payoff, or the thing the diagram is *about*.
- Labels in mono, uppercase, `0.62rem`-equivalent, letter-spacing `0.2em`.
- No fills except black and the single mint accent. No opacity ramps to fake depth.
- If SVG, use `font-family: ui-monospace, monospace` rather than embedding a font subset.

### Diagrams currently specced

| page | caption | ratio | what it must show |
|---|---|---|---|
| `/discovery` | namespace resolution — search to direct stream | 16:7 | A search resolving through the network to one artist node, then audio streaming point-to-point back to the browser. **The network is consulted only to find the node; the audio path never touches it.** |
| `/revenue` | payment flow — fan to splitter to payee | 16:7 | A payment entering the contract and splitting two ways, artist share accumulating until withdrawal. **Nothing routes through a Station-controlled account at any point.** |
| `/dashboard` | contract deploy order — treasury before payees | 16:7 | Treasury, Fan Club and Storefront, and the one-way payee choice the latter two make at deploy. **The arrow is drawn once and cannot be redrawn.** |
| `/fansociety` | generations over a career — each cohort sealed by the next | 16:6 | Successive generations as bands on a timeline; unlimited membership while open, permanent closure when the next opens, later releases granting access to specific earlier cohorts. |
| `/fansociety` | gated playback — the check your node runs | 4:5 | Play pressed on a gated track, wallet's held generations read, node serving or refusing. **The check runs on the artist's own server.** |

The bolded clause in each is the point of the diagram. If it isn't legible at a glance,
the diagram has failed regardless of how it looks.

## Voice, if any copy is generated

Flat, declarative, specific. Numbers where numbers exist. State the mechanism, not the feeling.

Never: empower, revolutionize, reclaim, unleash, seamless, game-changing, disrupt, journey,
"the future of music". No tricolon slogans. No exclamation points. No rhetorical-question headings.
