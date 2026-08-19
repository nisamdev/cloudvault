# Components

Detailed specifications for all UI components used in CloudVault.

## Buttons

### Button - Primary

**Purpose**: Main call-to-action buttons (Sign in, Upload, Save, etc.)

**Anatomy**:
```
┌─ Icon (optional, 20px)
│  └─ 8px gap
└─ Label (14px semibold)
```

**States**:
```
Default:    Indigo-600 to Purple-600 gradient
Hover:      Indigo-700 to Purple-700 gradient + shadow-md
Active:     Indigo-800 to Purple-800 gradient + inset shadow
Disabled:   Gray-200 background, Gray-400 text
Loading:    Spinner icon + "Loading..." text + disabled
Focus:      2px Indigo-500 ring with 2px offset
```

**Sizes**:
```
Small:      32px h, 12px 16px p, 12px font
Medium:     40px h, 12px 24px p, 14px font (default)
Large:      48px h, 16px 32px p, 16px font
```

**Specs**:
```
Padding:        12px 24px
Height:         40px
Border-radius:  8px
Font-weight:    600 (semibold)
Box-shadow:     sm on default, md on hover
Cursor:         pointer (enabled), not-allowed (disabled)
Transition:     all 0.2s ease-out
```

**Example**:
```html
<button class="px-6 py-2 bg-gradient-to-r from-indigo-600 to-purple-600 
               text-white rounded-lg font-semibold hover:shadow-md 
               transition-all duration-200">
  Sign In
</button>
```

---

### Button - Secondary

**Purpose**: Alternative actions (Cancel, Learn more, etc.)

**Anatomy**:
```
Same as primary but with border + transparent background
```

**States**:
```
Default:    Gray-300 border, Gray-700 text, transparent bg
Hover:      Gray-300 border, Gray-700 text, Gray-50 bg
Active:     Gray-400 border, Gray-900 text, Gray-100 bg
Disabled:   Gray-200 border, Gray-400 text
Focus:      2px Indigo-300 ring
```

**Specs**:
```
Padding:        12px 24px
Height:         40px
Border:         1px Gray-300
Border-radius:  8px
Background:     Transparent (white when in dark region)
Font-weight:    500 (medium)
Transition:     all 0.2s ease-out
```

---

### Button - Icon

**Purpose**: Icon-only actions (close, menu, settings)

**Anatomy**:
```
┌─ Icon (24px)
└─ Centered in 40×40px area
```

**Specs**:
```
Width/Height:   40px
Icon:           24px
Border-radius:  8px
Background:     Transparent
Hover bg:       Gray-100
Active bg:      Gray-200
Transition:     0.2s ease-out
```

---

### Button - Danger

**Purpose**: Destructive actions (Delete, Remove)

**Anatomy**:
```
Same button structure
Icon + Label or Icon-only
```

**States - Outline** (Recommended):
```
Default:    Red-200 border, Red-600 text
Hover:      Red-100 bg, Red-700 text
Active:     Red-50 bg, Red-800 text
```

**States - Solid**:
```
Default:    Red-500 bg, White text
Hover:      Red-600 bg, White text
Active:     Red-700 bg, White text
```

---

## Forms

### Text Input

**Anatomy**:
```
┌─ Label (12px medium, Gray-700)
├─ Input field
│  ├─ Placeholder text (Gray-400)
│  └─ Optional suffix icon
└─ Helper text (12px, Gray-600) or Error text (Red-600)
```

**Specs**:
```
Height:         40px
Padding:        10px 12px
Font-size:      14px
Border:         1px Gray-300
Border-radius:  6px
Background:     White
Placeholder:    Gray-400
```

**States**:
```
Default:        Gray-300 border, Gray-900 text
Hover:          Gray-400 border
Focus:          2px Indigo-500 ring, Indigo-300 border
Disabled:       Gray-100 bg, Gray-400 text, Gray-200 border
Error:          Red-300 border, 2px Red-500 ring
Success:        Green-300 border, Green-500 checkmark icon
Loading:        Spinner icon on right
```

**Spacing**:
```
Label to input:     6px
Input to helper:    4px
Input gap:          8px (between label and input)
```

**Example**:
```html
<div class="mb-4">
  <label class="block text-sm font-medium text-gray-700 mb-1">
    Email Address
  </label>
  <input type="email" 
         placeholder="you@example.com"
         class="w-full px-3 py-2 border border-gray-300 rounded-lg 
                focus:ring-2 focus:ring-indigo-500 outline-none">
  <p class="text-xs text-gray-600 mt-1">We'll never share your email</p>
</div>
```

---

### Textarea

**Extends**: Text Input

**Specs**:
```
Min-height:     120px
Padding:        12px
Resize:         Vertical only
Line-height:    1.5
Font-size:      14px
Border-radius:  6px
```

---

### Checkbox

**Anatomy**:
```
┌─ Square (18×18px)
└─ Label text (14px) at 8px right
```

**Specs**:
```
Size:           18×18px
Border:         1px Gray-300
Border-radius:  4px
Checked bg:     Indigo-600
Check color:    White (SVG or ✓)
Focus:          2px Indigo-300 ring
Margin-right:   8px
Cursor:         pointer
```

**States**:
```
Unchecked:      Gray-300 border, White bg
Checked:        Indigo-600 bg, White checkmark
Hover:          Gray-400 border
Disabled:       Gray-200 border, Gray-100 bg
Focus:          Ring visible
```

---

### Radio Button

**Anatomy**:
```
┌─ Circle (18×18px)
└─ Label text (14px) at 8px right
```

**Specs**:
```
Size:           18×18px
Border:         1px Gray-300
Border-radius:  50%
Checked bg:     Indigo-600
Inner circle:   White (4px radius)
Focus:          2px Indigo-300 ring
```

---

### Select Dropdown

**Anatomy**:
```
┌─ Label (12px medium)
├─ Select field
│  ├─ Text (14px)
│  └─ Down arrow icon (right side)
└─ Helper text (optional)
```

**Specs**:
```
Height:         40px
Padding:        10px 12px
Border:         1px Gray-300
Border-radius:  6px
Background:     White
Font-size:      14px
Appearance:     None (custom styling)
Arrow:          SVG or pseudo-element
```

**Arrow Positioning**:
```
Right:          12px
Top:            50%
Transform:      translateY(-50%)
Icon:           Chevron Down (16px, Gray-600)
```

---

### Toggle Switch

**Anatomy**:
```
┌─ Track (48×24px)
│  └─ Indicator (12×12px)
└─ Label (optional, right side)
```

**Specs**:
```
Track width:    48px
Track height:   24px
Border-radius:  12px
Indicator size: 12px
Indicator gap:  6px from edge
Animation:      Smooth 0.2s ease-out
```

**States**:
```
Off:    Gray-300 track, White indicator (left)
On:     Indigo-600 track, White indicator (right)
Hover:  Darker shade
Focus:  2px ring around track
```

---

## Cards & Containers

### Card

**Anatomy**:
```
┌─ Card Container
│  ├─ Header (optional)
│  ├─ Body
│  └─ Footer (optional)
└─ Actions (hover)
```

**Specs**:
```
Background:     White
Border:         1px Gray-200
Border-radius:  12px
Padding:        24px (default)
Box-shadow:     None (default), md on hover
Transition:     border, shadow 0.2s ease-out
```

**Sections**:
```
Header:
  - Padding: 24px
  - Border-bottom: 1px Gray-200
  - Font-size: 18px, bold

Body:
  - Padding: 24px
  - Content area

Footer:
  - Padding: 24px
  - Border-top: 1px Gray-200
  - Action buttons
```

---

### File/List Item

**Anatomy**:
```
Mobile:
┌─ Icon | Name/Meta
│         └─ Delete button
└─ Meta (Size, Date)

Desktop:
┌─ Icon | Name/Meta | Size | Date | Actions
└─ All in one row
```

**Specs**:
```
Padding:        12px
Border:         1px Gray-200
Border-radius:  8px
Gap:            16px
Align:          center
Height:         60px (desktop), auto (mobile)
Hover:          Gray-50 bg, border-color → Gray-300
```

**Columns (Desktop)**:
```
1. Icon:        40px flex-shrink-0
2. Name/meta:   flex-1
3. Size:        120px text-right (hidden mobile)
4. Date:        120px text-right (hidden mobile)
5. Actions:     auto flex justify-end (hidden mobile)
```

---

### Gallery Tile

**Anatomy**:
```
┌─ Image/Color
│  └─ Overlay (on hover)
│     ├─ Date badge
│     └─ Select checkbox (optional)
└─ Caption (optional below)
```

**Specs**:
```
Aspect-ratio:   1:1 (square)
Border-radius:  8px
Overflow:       Hidden
Width:          Responsive grid
Transition:     transform 0.2s
Hover:          scale(1.05)
```

**Overlay**:
```
Position:       Absolute (inset: 0)
Background:     rgba(0, 0, 0, 0.5)
Opacity:        0 → 1 on hover
Display:        Flex center align
Color:          White, font-size 12px
Duration:       0.2s ease-out
```

---

## Navigation

### Sidebar

**Anatomy**:
```
┌─ Logo/Brand (top)
├─ Navigation items
├─ Family section
├─ Storage indicator
└─ Actions (bottom)
```

**Specs**:
```
Width:          256px
Background:     White
Border-right:   1px Gray-200
Height:         100vh
Position:       Fixed (mobile), Static (tablet+)
Overflow-y:     Auto
Z-index:        40 (mobile)

Mobile:
  Position:     Fixed, left: 0
  Transform:    translateX(-100%) hidden
  On-open:      translateX(0), z-40
  Overlay:      Dim background on content
```

**Sections**:
```
Logo:           p-4, border-bottom Gray-200
Navigation:     p-4, space-y-2
Family:         p-4, border-top Gray-200
Storage:        p-4, border-top Gray-200
Footer:         p-4, border-top Gray-200, absolute bottom
```

### Sidebar Item

**Anatomy**:
```
┌─ Icon (20px)
├─ 8px gap
└─ Text (14px)
```

**Specs**:
```
Padding:        12px 16px
Border-radius:  8px
Font-weight:    500
Cursor:         Pointer
Transition:     0.2s ease-out
Gap:            12px
```

**States**:
```
Default:        Gray-600 text, transparent bg
Hover:          Gray-50 bg
Active:         Indigo-50 bg, Indigo-600 text
                4px left border Indigo-600
Disabled:       Gray-400 text, cursor: not-allowed
```

---

### Top Navigation Bar

**Anatomy**:
```
┌─ Left (Logo/Menu toggle)
├─ Center (Title/Breadcrumb)
└─ Right (Search, Notifications, Avatar)
```

**Specs**:
```
Height:         64px
Padding:        16px 24px (desktop), 12px 16px (mobile)
Background:     White
Border-bottom:  1px Gray-200
Position:       Fixed or sticky
Z-index:        30
Box-shadow:     0 1px 3px rgba(0, 0, 0, 0.1)
Display:        Flex justify-between align-center
```

**Sections**:
```
Left:
  - Hamburger (mobile)
  - Title/Breadcrumb

Center:
  - Page title
  - Breadcrumb

Right:
  - Search icon
  - Notifications icon (with badge)
  - Avatar (40px)
```

---

## Modals & Overlays

### Modal

**Anatomy**:
```
┌─ Header
│  ├─ Title (18px bold)
│  └─ Close button (icon)
├─ Content
│  └─ Body content (scrollable if needed)
└─ Footer
   └─ Action buttons
```

**Specs**:
```
Max-width:      448px
Max-height:     90vh (allows scroll)
Background:     White
Border-radius:  16px
Box-shadow:     xl (0 20px 25px -5px rgba(0, 0, 0, 0.1))
Z-index:        50
Overflow:       Hidden (header/footer), Auto (body)

Sections:
  Header:
    - Padding: 24px
    - Border-bottom: 1px Gray-200
    - Display: flex justify-between align-center
    
  Body:
    - Padding: 24px
    - Max-height: calc(90vh - 200px)
    - Overflow-y: auto
    
  Footer:
    - Padding: 24px
    - Border-top: 1px Gray-200
    - Display: flex gap-3
    - Justify: flex-end
```

**Mobile Responsive**:
```
Max-width:      90vw (on mobile)
Max-height:     95vh (full screen minus top/bottom)
Border-radius:  8px (bottom) for slide-up effect
Position:       fixed bottom-0 left-0 (slide-up from bottom)
```

---

### Overlay / Backdrop

**Specs**:
```
Position:       Fixed (inset: 0)
Background:     rgba(0, 0, 0, 0.5)
Z-index:        40 (below modal)
Animation:      Fade 0.3s ease-in
Cursor:         pointer (close on click)
Blur:           Optional (0px for simplicity)
```

---

### Toast / Notification

**Anatomy**:
```
┌─ Icon (20px, colored)
├─ Title & message
└─ Close button (optional)
```

**Specs**:
```
Max-width:      400px
Padding:        16px
Border-radius:  8px
Position:       Fixed, bottom-right
Margin:         32px from edge
Z-index:        60
Box-shadow:     lg
Animation:      slideUp 0.3s ease-out

Types (backgrounds):
  Success:      Green-50, Green-800 text, Green-500 icon
  Error:        Red-50, Red-800 text, Red-500 icon
  Info:         Blue-50, Blue-800 text, Blue-500 icon
  Warning:      Amber-50, Amber-800 text, Amber-500 icon
```

**Duration**:
```
Auto-close:     4000ms (4 seconds)
Dismissible:    X button to close immediately
```

---

## Forms - Specialized

### Upload Zone

**Anatomy**:
```
┌─ Dashed border
├─ Icon (48px)
├─ Primary text
└─ Secondary text
```

**Specs**:
```
Border:         2px dashed Gray-300
Border-radius:  12px
Padding:        32px
Text-align:     center
Background:     White
Hover bg:       Indigo-50
Hover border:   Indigo-400
Cursor:         pointer
Transition:     0.2s ease-out

Text:
  Primary:      14px bold, Gray-700
  Secondary:    12px regular, Gray-500
```

**Interactive**:
```
Click:          Triggers file input
Drag-over:      Border-color → Indigo-400, background → Indigo-50
Drop:           Validates and uploads
```

---

### Progress Bar

**Anatomy**:
```
┌─ Label (optional)
├─ Track (background)
│  └─ Fill (foreground)
└─ Percentage (optional, right)
```

**Specs**:
```
Height:         8px (normal), 4px (thin), 12px (thick)
Border-radius:  4px
Background:     Gray-200
Fill:           Linear gradient (Indigo → Purple)
Fill width:     Percentage value (0-100%)
Transition:     width 0.3s ease-out
```

**States**:
```
Default:        Gray-200 bg, gradient fill
Indeterminate:  Animated gradient (0-100-0 loop)
Complete:       100% fill, Green-500 (optional)
```

---

### Breadcrumb

**Anatomy**:
```
Home > Category > Subcategory > Current
  |       |           |           |
  Link    Link        Link     Text
```

**Specs**:
```
Font-size:      14px
Gap:            8px separator
Separator:      "/" or ">" (Gray-400)

Link:
  Color:        Indigo-600
  Hover:        Indigo-700, underline
  Cursor:       pointer

Current (last):
  Color:        Gray-900
  Font-weight:  600
  Non-clickable
```

---

## Miscellaneous

### Avatar

**Anatomy**:
```
┌─ Circle
│  ├─ Initials (2 chars)
│  └─ or Image
└─ Badge (optional, bottom-right)
```

**Sizes**:
```
Small:      32px
Medium:     40px (default)
Large:      48px
XL:         64px
```

**Specs**:
```
Border-radius:  50%
Background:     Gradient (Indigo-600 to Purple-600)
Color:          White
Font-weight:    600
Font-size:      16px (40px avatar)
Display:        Flex center align
```

**Badge**:
```
Position:       Absolute, bottom-right
Size:           12px
Background:     Status color (Green-500, Red-500)
Border:         2px White
Border-radius:  50%
```

---

### Badge / Label

**Anatomy**:
```
┌─ Icon (optional, 14px)
├─ Text (12px)
└─ Close icon (optional, 14px)
```

**Sizes**:
```
Small:      28px h, 8px 12px p
Medium:     32px h, 12px 16px p
Large:      36px h, 12px 20px p
```

**Variants**:
```
Solid:      Colored background
Outline:    Colored border + transparent bg
Subtle:     Colored background at 20% opacity
```

**Colors** (using colored variants):
```
Primary:    Indigo
Secondary:  Purple
Success:    Green
Error:      Red
Warning:    Amber
Info:       Blue
```

---

### Empty State

**Anatomy**:
```
┌─ Icon (64px, Gray-400)
├─ Title (18px bold, Gray-900)
├─ Description (14px, Gray-600)
└─ CTA Button
```

**Specs**:
```
Padding:        48px 24px
Text-align:     center
Min-height:     400px
Display:        Flex flex-col center justify-center
Background:     White or Gray-50
```

---

### Divider / Separator

**Specs**:
```
Height:         1px
Background:     Gray-200
Margin:         24px 0 (vertical)
Margin:         0 16px (horizontal)
Opacity:        100% or 50% (subtle)
```

---

### Spinner / Loading

**Specs**:
```
Size:           24px × 24px (default)
Stroke:         3px
Color:          Indigo-600
Animation:      Spin 1s linear infinite
Background:     Circular progress arc
```

```css
@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
```

---

### Skeleton Loader

**Usage**:
```
Show while loading content
Placeholder for each element (text, image, etc.)
```

**Specs**:
```
Background:     Gray-200
Border-radius:  Match element's radius
Animation:      Pulse (fade 0.5s ease-in-out, infinite)
Height/Width:   Match expected content
```

```css
@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}
```

---

## Responsive Behavior

### Mobile (< 768px)
```
- Sidebar: Hidden, toggle with hamburger
- Modals: Full-width (90vw), slide from bottom
- Buttons: Full-width in forms
- File rows: Vertical stack, hide size column
- Gallery: 2-3 columns instead of 4+
- Navigation: Hamburger menu, stack vertically
```

### Tablet (768px - 1023px)
```
- Sidebar: Visible, can collapse
- Modals: Max-width 448px, center
- Buttons: Auto-width, inline with others
- File rows: Show size, hide some actions
- Gallery: 3-4 columns
- Navigation: Visible
```

### Desktop (1024px+)
```
- Sidebar: Always visible
- Modals: Max-width 448px, center
- Buttons: Standard sizing
- File rows: Full row, all actions visible
- Gallery: 5-6+ columns
- Navigation: Full layout
```

---

**Last Updated**: August 2026  
**Version**: 1.0
