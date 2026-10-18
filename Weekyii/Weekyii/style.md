# Weekyii Style Guide

This document captures the visual language used by the Weekyii presentation deck and can be reused for future pages, product shots, and marketing materials.

## Core Direction

- Mood: dark, cinematic, ritual-like.
- Reference tone: Lord of the Rings inspired, but restrained and product-focused.
- Visual goal: make the page feel like a weekly oath, not a generic task app.
- Primary impression: warm gold on deep charcoal, with generous breathing room and a strong typographic hierarchy.

## Color System

Use a dark base with warm metallic accents.

```css
--bg-primary: #0b0a08;
--bg-secondary: #12100d;
--bg-ember: #1a1510;
--text-primary: #efe6d6;
--text-secondary: #b9ad9a;
--accent-gold: #c9a15a;
--accent-ember: #b06a2b;
--accent-moss: #4b5b3f;
--accent-glow: rgba(201, 161, 90, 0.35);
```

Rules:

- Background should stay near-black, never pure black.
- Gold is the primary accent for borders, chapter labels, bullets, and focus highlights.
- Ember and moss are secondary atmosphere colors, used sparingly.
- Avoid flat monochrome blocks. Add layered gradients and soft halos.

## Typography

Two-font system:

- Display font: `Cinzel Decorative`
- Body font: `Cormorant Garamond`

Typography rules:

- Titles should feel ceremonial and stately.
- Body copy should feel editorial and readable.
- Use uppercase for chapter labels and small meta text.
- Keep letter spacing wide on labels, tighter on body copy.
- Prefer line-based title composition over long single-line headlines.

Recommended scale:

```css
--title-size: clamp(1.7rem, 5.4vw, 4.4rem);
--h2-size: clamp(1.4rem, 3.8vw, 2.8rem);
--h3-size: clamp(1.12rem, 2.7vw, 1.92rem);
--body-size: clamp(0.88rem, 1.7vw, 1.22rem);
--small-size: clamp(0.72rem, 1.05vw, 0.94rem);
```

## Layout Philosophy

The deck uses a full-viewport stage layout:

- One slide per screen.
- No scrolling inside the slide.
- Each page should distribute content across the whole frame.
- Avoid content clustering in the center.
- Left/right balance should feel intentional, not accidental.

Typical composition patterns:

- Title slide: left editorial block + right stat cards.
- Content slide: left bullet list + right panel grid.
- Process slide: four-step horizontal flow or four cards.
- Module slide: two-column layout with cards and supporting text.

## Spacing

Spacing should feel large, deliberate, and cinematic.

- Use `clamp()` everywhere.
- Keep title and body separated by visible breathing room.
- Use wide gaps between major regions.
- Avoid compressing all content into one dense band.

Practical guidance:

- Title to subtitle: medium gap, never touching.
- Subtitle to badges/cards: generous gap.
- Card grids: consistent gaps and even alignment.
- Avoid forcing too many blocks into a single row.

## Component Language

### Cards

- Thin gold border.
- Dark translucent fill.
- Soft inner shadow.
- Rounded corners, but not overly soft.
- Cards should feel like artifact panels.

### Badges

- Small pill shape.
- Gold outline and subtle warm fill.
- Used for short status phrases only.

### Chapter Labels

- Small uppercase meta line.
- Gold or muted gold.
- Often paired with a thin horizontal line.

### Lists

- Gold star/diamond bullet marker.
- Short, direct sentences.
- One idea per line.

## Background Treatment

Use layered atmospheric backgrounds:

- Central or balanced radial glows.
- Warm diffuse halos.
- Very subtle left/right color variation.
- Fine grain or vignette is acceptable if it stays understated.

Avoid:

- Strong left-only lighting.
- Bright neon gradients.
- Flat solid-color screens.

## Motion

Motion should be gentle and theatrical.

- Use staggered reveals.
- Keep transitions smooth and slow.
- Favor opacity and translate animations.
- Do not use busy micro-interactions everywhere.

Motion intent:

- Reveal feels like a curtain opening.
- Navigation feels like page switching, not scrolling.
- Decorative motion should never compete with reading.

## Page-Specific Rules

- Slide 1: strongest visual hierarchy, largest title, cleanest layout.
- Slide 2: use four-part problem framing, evenly balanced cards.
- Slide 4: keep the four-step engine readable and aligned.
- Slide 7: use a spacious grid and a clear fourth card for the regret mechanism.
- Slides with more text: reduce card density and widen line spacing.

## Do / Don’t

Do:

- Use warm gold as the organizing accent.
- Keep the deck dark and calm.
- Let the typography do most of the visual work.
- Fill the page with balanced negative space.

Don’t:

- Don’t stack everything in the middle.
- Don’t overuse the same lighting direction.
- Don’t make every card look identical in weight.
- Don’t let decorative effects overpower the text.

## Source Of Truth

This style guide reflects the rebuilt presentation:

- `docs/weekyii-lotr-slides-rebuilt.html`

When in doubt, match the rebuilt deck rather than inventing a new look.
