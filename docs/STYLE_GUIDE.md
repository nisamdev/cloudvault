# CloudVault Design System - Style Guide

## Overview

CloudVault is a modern, family-focused cloud storage application. This style guide defines the design system, components, and patterns used throughout the web and mobile applications.

**Design Philosophy:**
- Clean, minimal aesthetic with purposeful use of gradients
- Family-first approach (welcoming, trustworthy, secure)
- Responsive-first design (mobile-friendly from start)
- Accessibility-focused (WCAG 2.1 AA compliance)
- Performance-optimized (lightweight, fast interactions)

---

## Quick Links

- **[Design Tokens](./DESIGN_TOKENS.md)** - Colors, spacing, typography
- **[Colors](./COLORS.md)** - Complete color palette
- **[Typography](./TYPOGRAPHY.md)** - Font sizes, weights, line-height
- **[Components](./COMPONENTS.md)** - UI component specs
- **[Patterns](./PATTERNS.md)** - Common interaction patterns
- **[Accessibility](./ACCESSIBILITY.md)** - A11y guidelines

---

## Brand Identity

### Logo & Wordmark
- **Logo**: Cloud icon + "CloudVault" text
- **Icon**: Gradient cloud (Indigo-600 to Purple-600)
- **Usage**: Top-left in navigation, auth pages
- **Clear Space**: Minimum 8px around logo
- **Minimum Size**: 32px height

### Brand Colors
```
Primary: #4F46E5 (Indigo-600)
Secondary: #9333EA (Purple-600)
Accent: #EC4899 (Pink-500)
```

### Brand Gradients
```
Main Gradient: Linear (135deg, #4F46E5 → #9333EA)
Warm Gradient: Linear (135deg, #F59E0B → #EF4444)
Cool Gradient: Linear (135deg, #0EA5E9 → #06B6D4)
```

---

## Grid & Layout

### Container Sizes
```
Mobile:     100% - 16px padding
Tablet:     688px (md)
Desktop:    1024px (lg)
Max-width:  1280px (xl)
```

### Breakpoints
```
Mobile:     < 768px   (no sidebar)
Tablet:     768px     (sidebar visible)
Desktop:    1024px    (full layout)
Large:      1280px+   (max content width)
```

### Spacing Scale
```
0:    0
0.5:  2px
1:    4px
1.5:  6px
2:    8px
3:    12px
4:    16px
6:    24px
8:    32px
12:   48px
16:   64px
20:   80px
24:   96px
32:   128px
```

### Grid
```
Base: 8px grid system
Gutters: 16px (mobile), 24px (tablet), 32px (desktop)
Columns: 4 (mobile), 8 (tablet), 12 (desktop)
```

---

## Responsive Strategy

### Mobile-First Approach
All styles start with mobile defaults, then add complexity with media queries.

```
Default (mobile):     < 768px
@media (min-width: 768px)    → Tablet
@media (min-width: 1024px)   → Desktop
@media (min-width: 1280px)   → Large Desktop
```

### Common Breakpoints
```
sm:   640px
md:   768px
lg:   1024px
xl:   1280px
2xl:  1536px
```

### Sidebar Behavior
```
Mobile:   Fixed overlay, hamburger menu
Tablet:   Static sidebar (always visible)
Desktop:  Same as tablet, wider content area
```

---

## Color System

### Semantic Colors

#### Primary (Interactive Elements)
```
Indigo-600: #4F46E5
  - Buttons, links, active states
  - Primary CTA (sign in, upload)
  - Focus rings
```

#### Secondary (Accents)
```
Purple-600: #9333EA
  - Gradients, hover states
  - Loading indicators
  - Success confirmations
```

#### Status Colors
```
Success:  #10B981 (Green-500)   → File uploaded, saved
Error:    #EF4444 (Red-500)     → Errors, delete actions
Warning:  #F59E0B (Amber-500)   → Low storage, confirmations
Info:     #3B82F6 (Blue-500)    → Notifications, tips
```

#### Neutral (UI)
```
Gray-50:    #F9FAFB  → Page background
Gray-100:   #F3F4F6  → Input background, hover
Gray-200:   #E5E7EB  → Borders, disabled
Gray-300:   #D1D5DB  → Secondary borders
Gray-500:   #6B7280  → Secondary text
Gray-700:   #374151  → Primary text
Gray-900:   #111827  → Headings, emphasis
```

---

## Typography

### Font Stack
```css
font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 
             'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', sans-serif;
```

### Type Scale
```
Display: 32px (bold)      → Page titles
Heading 1: 24px (bold)    → Section titles
Heading 2: 20px (bold)    → Subsection titles
Heading 3: 18px (semibold) → Component titles
Body Large: 16px (regular) → Primary text
Body: 14px (regular)      → Secondary text
Label: 12px (medium)      → Form labels, captions
Caption: 12px (regular)   → Helper text, timestamps
```

### Font Weights
```
Regular:   400
Medium:    500
Semibold:  600
Bold:      700
```

### Line Heights
```
Headings: 1.2  (tight)
Body:     1.5  (comfortable)
Labels:   1.4  (normal)
```

### Letter Spacing
```
Normal:    0
Headings:  -0.5px (tight)
Uppercase: 0.05em
```

---

## Buttons

### Button Types

#### Primary Button
```
Background:   Gradient (Indigo-600 → Purple-600)
Text:         White
Padding:      12px 24px (desktop), 10px 16px (mobile)
Border:       None
Border-radius: 8px
Font-size:    14px (body) or 16px (button)
Font-weight:  600 (semibold)

States:
  Default:    Gradient visible
  Hover:      Darker gradient (Indigo-700 → Purple-700)
  Active:     Indigo-800
  Disabled:   Gray-200 text, Gray-100 bg, no cursor
  Loading:    Spinner + "Loading..." text
```

#### Secondary Button
```
Background:   Transparent
Border:       1px Gray-300
Text:         Gray-700
Padding:      12px 24px
Border-radius: 8px
Font-weight:  500

States:
  Default:    Gray-300 border
  Hover:      Gray-50 background
  Active:     Gray-100 background
  Disabled:   Gray-200 border, Gray-500 text
```

#### Icon Button
```
Size:         40px × 40px
Background:   Transparent
Icon:         Gray-600 (24px)
Border-radius: 8px
Padding:      8px

States:
  Default:    Transparent
  Hover:      Gray-100 background
  Active:     Gray-200 background
```

#### Danger Button
```
Background:   Red-500 or transparent
Text:         Red-600 (secondary) or White (primary)
Border:       1px Red-200 (secondary)
Hover:        Red-50 (secondary) or Red-600 (primary)
```

### Button Sizes
```
Small:    32px height, 12px 16px padding
Regular:  40px height, 12px 24px padding (default)
Large:    48px height, 16px 32px padding
```

---

## Forms

### Input Elements

#### Text Input
```
Height:           40px
Padding:          10px 12px
Border:           1px Gray-300
Border-radius:    6px
Background:       White
Font-size:        14px
Line-height:      1.5

States:
  Default:        Gray-300 border, Gray-900 text
  Focus:          2px Indigo-500 ring, Indigo-300 border
  Hover:          Gray-400 border
  Disabled:       Gray-100 background, Gray-400 text
  Error:          2px Red-500 ring, Red-300 border
  Success:        2px Green-500 ring, Green-300 border
```

#### Label
```
Font-size:    12px
Font-weight:  500
Color:        Gray-700
Margin-bottom: 6px
Display:      block
```

#### Helper Text
```
Font-size:    12px
Color:        Gray-600 (normal) or Red-600 (error)
Margin-top:   4px
```

#### Textarea
```
Same as text input
Padding:      12px
Min-height:   120px
Resize:       Vertical only
Line-height:  1.5
```

#### Select Dropdown
```
Height:       40px
Padding:      10px 12px
Border:       1px Gray-300
Border-radius: 6px
Background:   White
Font-size:    14px
Appearance:   None (custom arrow)
```

#### Checkbox & Radio
```
Size:           18px × 18px
Border:         1px Gray-300
Border-radius:  4px (checkbox), 50% (radio)
Checked:        Indigo-600 background, White checkmark
Focus:          2px Indigo-300 ring
Margin-right:   8px
```

#### Toggle Switch
```
Width:        48px
Height:       24px
Background:   Gray-300 (off) / Indigo-600 (on)
Border-radius: 12px
Indicator:    12px circle, white
Animation:    Smooth 0.2s transition
```

---

## Modals & Overlays

### Modal
```
Max-width:        448px (mobile: 90vw)
Background:       White
Border-radius:    16px
Shadow:           0 20px 25px rgba(0, 0, 0, 0.15)
Z-index:          50
Padding:          24px (default)

Header:
  Font-size:      18px
  Font-weight:    700
  Padding:        24px
  Border-bottom:  1px Gray-200
  Display:        flex, justify-between, align-center

Footer:
  Padding:        24px
  Border-top:     1px Gray-200
  Button spacing: 12px gap
```

### Overlay
```
Background:       rgba(0, 0, 0, 0.5)
Z-index:          40 (below modal)
Backdrop-filter:  None (simpler, faster)
Animation:        Fade in 0.3s ease-in
```

### Notification Toast
```
Max-width:        400px
Padding:          16px
Border-radius:    8px
Position:         Fixed bottom-right (32px from edge)
Shadow:           0 10px 15px rgba(0, 0, 0, 0.1)
Z-index:          60
Animation:        Slide up 0.3s ease-out

Types:
  Success:        Green-50 bg, Green-800 text, Green-500 icon
  Error:          Red-50 bg, Red-800 text, Red-500 icon
  Info:           Blue-50 bg, Blue-800 text, Blue-500 icon
  Warning:        Amber-50 bg, Amber-800 text, Amber-500 icon
```

---

## Cards & Containers

### Card
```
Background:       White
Border:           1px Gray-200
Border-radius:    12px
Padding:          24px
Shadow:           None (default) or 0 1px 3px rgba(0, 0, 0, 0.1)
Hover:            Border-color → Gray-300 (subtle highlight)
```

### File Item / List Row
```
Display:          Flex (mobile), Grid (desktop)
Padding:          12px
Border:           1px Gray-200
Border-radius:    8px
Gap:              16px
Align-items:      Center
Hover:            Gray-50 background, border-color → Gray-300

Columns (Desktop):
  1. Icon (40px)
  2. Name & Date (flex-1)
  3. Size (120px)
  4. Actions (auto)
```

### Gallery Tile
```
Aspect-ratio:     1:1 (square)
Background:       Gray-200
Border-radius:    8px
Overflow:         Hidden
Transition:       transform 0.2s
Hover:            transform scale(1.05)

Overlay (on hover):
  Position:       Absolute (inset: 0)
  Background:     rgba(0, 0, 0, 0.5)
  Opacity:        0 → 1 on hover
  Display:        Flex center
  Color:          White
  Font-size:      12px
```

---

## Navigation

### Sidebar
```
Width:            256px
Background:       White
Border-right:     1px Gray-200
Position:         Fixed (mobile, hidden), Static (tablet+)
Height:           100vh
Overflow-y:       Auto
Z-index:          40 (mobile)
Transform:        translateX(-100%) (mobile hidden)

Mobile Behavior:
  Hidden by default
  Toggle with hamburger
  Overlay on content
```

### Sidebar Item
```
Padding:          12px 16px
Margin-bottom:    8px
Border-radius:    8px
Font-weight:      500
Color:            Gray-600
Cursor:           Pointer
Transition:       all 0.2s

States:
  Default:        Gray-600 text
  Hover:          Gray-50 background
  Active:         Indigo-50 background, Indigo-600 text
                  Left border (4px Indigo-600)
  Disabled:       Gray-400 text, no pointer
```

### Top Navigation Bar
```
Background:       White
Border-bottom:    1px Gray-200
Padding:          16px 24px (desktop), 12px 16px (mobile)
Height:           64px
Display:          Flex, justify-between, align-center
Position:         Fixed or sticky
Z-index:          30
Shadow:           0 1px 3px rgba(0, 0, 0, 0.1)
```

### Breadcrumb
```
Font-size:        14px
Color:            Gray-600
Gap:              8px separator
Link color:       Indigo-600
Link hover:       Indigo-700, underline
Current:          Gray-900, bold (non-link)
```

---

## Icons

### Icon System
```
Set:              Font Awesome 6.4
Weight:           Solid
Sizes:            16px, 20px, 24px, 32px, 48px
Color:            Inherited from parent element

Usage:
  Navigation:     24px, Gray-600
  Buttons:        20px, inherit color from button
  Badges:         16px, inherit from badge color
  Large displays: 32px+, primary color
```

### Icon Spacing
```
Icon + Text:      8px gap
Icon-only button: Centered in 40×40px area
```

---

## Shadows

### Shadow Scale
```
None:       box-shadow: none
SM:         0 1px 2px 0 rgba(0, 0, 0, 0.05)
Base:       0 1px 3px 0 rgba(0, 0, 0, 0.1), 
            0 1px 2px 0 rgba(0, 0, 0, 0.06)
MD:         0 4px 6px -1px rgba(0, 0, 0, 0.1),
            0 2px 4px -1px rgba(0, 0, 0, 0.06)
LG:         0 10px 15px -3px rgba(0, 0, 0, 0.1),
            0 4px 6px -2px rgba(0, 0, 0, 0.05)
XL:         0 20px 25px -5px rgba(0, 0, 0, 0.1),
            0 10px 10px -5px rgba(0, 0, 0, 0.04)
2XL:        0 25px 50px -12px rgba(0, 0, 0, 0.25)
```

### Usage
```
Buttons:          SM
Cards:            Base or MD
Modals:           XL
Dropdowns:        MD
Hover effects:    MD
```

---

## Borders & Radius

### Border Styles
```
Width:    1px (standard), 2px (focus), 4px (thick)
Color:    Gray-200 (light), Gray-300 (medium)
Style:    Solid
```

### Border Radius
```
SM:   4px    → Small elements, inputs
Base: 6px    → Buttons, form fields
MD:   8px    → Cards, containers
LG:   12px   → Larger containers
XL:   16px   → Modals, major sections
Full: 50%    → Circles, avatars
```

---

## Animations & Transitions

### Timing Functions
```
Ease-in:      cubic-bezier(0.4, 0, 1, 1)
Ease-out:     cubic-bezier(0, 0, 0.2, 1)
Ease-in-out:  cubic-bezier(0.4, 0, 0.2, 1)
Linear:       linear
```

### Durations
```
Fast:         0.15s
Normal:       0.3s
Slow:         0.5s
Slower:       0.7s
```

### Common Animations

#### Fade In
```css
animation: fadeIn 0.3s ease-in;
@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}
```

#### Slide In (from top)
```css
animation: slideInUp 0.3s ease-out;
@keyframes slideInUp {
  from { transform: translateY(20px); opacity: 0; }
  to { transform: translateY(0); opacity: 1; }
}
```

#### Scale (hover)
```css
transition: transform 0.2s ease-out;
&:hover { transform: scale(1.05); }
```

#### Spin (loading)
```css
animation: spin 1s linear infinite;
@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
```

---

## Accessibility

### Focus States
```
All interactive elements:
  Outline: 2px solid Indigo-500
  Outline-offset: 2px
  Visible on keyboard navigation
  Visible on click (except mouse clicks for buttons)
```

### Color Contrast
```
Text on background:
  Normal text:    4.5:1 (WCAG AA)
  Large text:     3:1 (WCAG AA)
  UI components:  3:1 (WCAG AA)

Examples:
  Gray-900 on White:       21:1 ✅
  Gray-600 on White:       7:1 ✅
  Gray-500 on White:       4.5:1 ✅
  Gray-400 on White:       2.6:1 ❌ (not accessible)
```

### ARIA Labels
```
Required for:
  Icon-only buttons:  aria-label="Action name"
  Form inputs:        aria-label or <label>
  Modals:             aria-labelledby, aria-describedby
  Loading states:     aria-busy="true"
  Disabled elements:  aria-disabled="true"
```

### Keyboard Navigation
```
Tab:       Move forward through interactive elements
Shift+Tab: Move backward
Enter:     Activate buttons, open links, confirm modals
Escape:    Close modals, cancel operations
Arrow:     Navigate select options, sliders
Space:     Toggle checkboxes, activate buttons
```

---

## Performance Considerations

### File Size Budget
```
CSS:      < 50KB (gzipped)
Icons:    < 100KB (Font Awesome CDN)
Fonts:    System fonts (no downloads)
Images:   Optimized, lazy-loaded
SVGs:     Inline or sprite sheet
```

### Animation Performance
```
Use:      transform, opacity
Avoid:    left, top, width, height (triggers reflow)
GPU:      will-change: transform for smooth 60fps
Duration: Keep under 0.5s for most interactions
```

### Lazy Loading
```
Images:   Intersection Observer
Modals:   Render only when open
Sidebars: Static on desktop, overlay on mobile
Lists:    Virtual scrolling for 100+ items
```

---

## Interaction Patterns

### Hover Effects
```
Buttons:       Darker color + subtle lift (shadow increase)
Links:         Underline
Cards:         Slight lift + shadow increase
Icons:         Color change
Images:        Subtle zoom (1.05x)
```

### Click / Active States
```
Buttons:       Darker background, inset shadow
Navigation:    Background highlight + left border
Checkboxes:    Filled with checkmark
Forms:         Focus ring visible
```

### Disabled States
```
Background:    Gray-100
Text:          Gray-400
Border:        Gray-300
Cursor:        not-allowed
Opacity:       0.5 (optional)
No hover:      State doesn't change
```

### Loading States
```
Button:        Spinner + "Loading..." text, disabled
List:          Skeleton loaders
Upload:        Progress bar with percentage
Search:        Debounce 300ms, show spinner
Refresh:       Rotate icon animation
```

---

## Dark Mode (Future)

Reserved for Phase 2+. Current design is light-mode only.

```
Planned colors:
  Background:   #1a1a1a (Gray-900)
  Surface:      #2d2d2d (Gray-800)
  Text:         #f9fafb (Gray-50)
  Border:       #404040 (Gray-700)
```

---

## Component Checklist

When creating any component, ensure:

- [ ] Responsive (mobile, tablet, desktop)
- [ ] Accessible (focus states, labels, ARIA)
- [ ] Keyboard navigable
- [ ] Performance optimized (no unnecessary re-renders)
- [ ] Dark mode ready (CSS variables)
- [ ] Internationalization (text i18n)
- [ ] Error states handled
- [ ] Loading states included
- [ ] Disabled states respected
- [ ] Touch-friendly (40px min tap target)

---

## Resources

- **Tailwind CSS**: Utility-first CSS framework used for styling
- **Font Awesome**: Icon library (6.4+)
- **Figma**: Design files (link to design file)
- **Component Library**: Vue 3 components (GitHub repo)

---

## Questions?

Design consistency is key. If something doesn't align with this guide:

1. **Check first**: Review this document and linked guides
2. **Ask team**: Slack #design channel
3. **File issue**: Document discrepancy for team review
4. **Update guide**: Keep this living document current

---

**Last Updated**: August 2026  
**Version**: 1.0  
**Maintained By**: Design & Engineering Team
