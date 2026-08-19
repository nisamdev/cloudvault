# Design Tokens

A complete reference of all design tokens used in CloudVault.

## Color Tokens

### Primary Color
```
Name:        Indigo
Primary:     #4F46E5 (Indigo-600)
Dark:        #4338CA (Indigo-700)
Darker:      #3730A3 (Indigo-800)
Light:       #818CF8 (Indigo-400)
Lighter:     #C7D2FE (Indigo-200)
Lightest:    #EEF2FF (Indigo-50)

CSS Variables:
--color-primary-50:   #EEF2FF
--color-primary-100:  #E0E7FF
--color-primary-200:  #C7D2FE
--color-primary-300:  #A5B4FC
--color-primary-400:  #818CF8
--color-primary-500:  #6366F1
--color-primary-600:  #4F46E5 (main)
--color-primary-700:  #4338CA
--color-primary-800:  #3730A3
--color-primary-900:  #312E81
```

### Secondary Color
```
Name:        Purple
Secondary:   #9333EA (Purple-600)
Dark:        #7E22CE (Purple-700)
Light:       #A78BFA (Purple-400)
Lightest:    #F3E8FF (Purple-50)

CSS Variables:
--color-secondary-600: #9333EA (main)
--color-secondary-700: #7E22CE
```

### Accent Colors

#### Success
```
Base:        #10B981 (Green-500)
Light:       #D1FAE5 (Green-100)
Lightest:    #F0FDF4 (Green-50)
Dark:        #047857 (Green-700)

--color-success-50:  #F0FDF4
--color-success-500: #10B981
--color-success-700: #047857
```

#### Error / Danger
```
Base:        #EF4444 (Red-500)
Light:       #FEE2E2 (Red-100)
Lightest:    #FEF2F2 (Red-50)
Dark:        #DC2626 (Red-600)

--color-error-50:  #FEF2F2
--color-error-500: #EF4444
--color-error-600: #DC2626
```

#### Warning
```
Base:        #F59E0B (Amber-500)
Light:       #FEF3C7 (Amber-100)
Lightest:    #FFFBEB (Amber-50)
Dark:        #D97706 (Amber-600)

--color-warning-50:  #FFFBEB
--color-warning-500: #F59E0B
--color-warning-600: #D97706
```

#### Info
```
Base:        #3B82F6 (Blue-500)
Light:       #DBEAFE (Blue-100)
Lightest:    #EFF6FF (Blue-50)
Dark:        #1D4ED8 (Blue-700)

--color-info-50:  #EFF6FF
--color-info-500: #3B82F6
--color-info-700: #1D4ED8
```

### Neutral Colors
```
Gray-50:    #F9FAFB  (lightest background)
Gray-100:   #F3F4F6  (light background)
Gray-200:   #E5E7EB  (borders, dividers)
Gray-300:   #D1D5DB  (disabled, secondary borders)
Gray-400:   #9CA3AF  (secondary icons)
Gray-500:   #6B7280  (secondary text)
Gray-600:   #4B5563  (body text, icons)
Gray-700:   #374151  (strong text)
Gray-800:   #1F2937  (headings)
Gray-900:   #111827  (darkest text)

CSS Variables:
--color-gray-50:   #F9FAFB
--color-gray-100:  #F3F4F6
--color-gray-200:  #E5E7EB
--color-gray-300:  #D1D5DB
--color-gray-400:  #9CA3AF
--color-gray-500:  #6B7280
--color-gray-600:  #4B5563
--color-gray-700:  #374151
--color-gray-800:  #1F2937
--color-gray-900:  #111827
```

### Gradient Tokens

#### Main Gradient (Indigo → Purple)
```
Direction:   135deg
Color 1:     #4F46E5 (Indigo-600)
Color 2:     #9333EA (Purple-600)

CSS:
background: linear-gradient(135deg, #4F46E5 0%, #9333EA 100%);

Tailwind:
from-indigo-600 via-purple-600 to-purple-600
```

#### Warm Gradient (Amber → Red)
```
Direction:   135deg
Color 1:     #F59E0B (Amber-500)
Color 2:     #EF4444 (Red-500)

CSS:
background: linear-gradient(135deg, #F59E0B 0%, #EF4444 100%);
```

#### Cool Gradient (Cyan → Blue)
```
Direction:   135deg
Color 1:     #0EA5E9 (Cyan-500)
Color 2:     #06B6D4 (Sky-500)

CSS:
background: linear-gradient(135deg, #0EA5E9 0%, #06B6D4 100%);
```

---

## Spacing Tokens

### Scale (4px base)
```
0:    0
0.5:  2px   (--spacing-0: 2px)
1:    4px   (--spacing-1: 4px)
1.5:  6px   (--spacing-1_5: 6px)
2:    8px   (--spacing-2: 8px)
3:    12px  (--spacing-3: 12px)
4:    16px  (--spacing-4: 16px)
5:    20px  (--spacing-5: 20px)
6:    24px  (--spacing-6: 24px)
7:    28px  (--spacing-7: 28px)
8:    32px  (--spacing-8: 32px)
10:   40px  (--spacing-10: 40px)
12:   48px  (--spacing-12: 48px)
14:   56px  (--spacing-14: 56px)
16:   64px  (--spacing-16: 64px)
20:   80px  (--spacing-20: 80px)
24:   96px  (--spacing-24: 96px)
32:   128px (--spacing-32: 128px)
```

### Common Spacing Usage
```
Padding:
  Buttons:          px-4 py-2 (16px 8px)
  Cards:            p-6 (24px)
  Page:             p-4 md:p-6 (16px mobile, 24px desktop)
  Input:            px-3 py-2 (12px 8px)

Margin:
  Components:       mb-4 (16px bottom)
  Sections:         mb-8 (32px bottom)
  Groups:           gap-4 (16px)

Gap (Flexbox/Grid):
  Tight:            gap-2 (8px)
  Normal:           gap-4 (16px)
  Loose:            gap-6 (24px)
```

---

## Typography Tokens

### Font Family
```
Font Stack:
  -apple-system
  BlinkMacSystemFont
  'Segoe UI'
  'Roboto'
  'Oxygen'
  'Ubuntu'
  'Cantarell'
  sans-serif

CSS Variable:
--font-family-base: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', sans-serif
```

### Font Size Scale
```
Display:      32px (bold)         --font-size-display: 32px
H1:           28px (bold)         --font-size-h1: 28px
H2:           24px (bold)         --font-size-h2: 24px
H3:           20px (semibold)     --font-size-h3: 20px
H4:           18px (semibold)     --font-size-h4: 18px
Body Large:   16px (regular)      --font-size-body-lg: 16px
Body:         14px (regular)      --font-size-body: 14px
Body Small:   13px (regular)      --font-size-body-sm: 13px
Label:        12px (medium)       --font-size-label: 12px
Caption:      12px (regular)      --font-size-caption: 12px
```

### Font Weight Scale
```
Light:      300  --font-weight-light: 300
Regular:    400  --font-weight-regular: 400
Medium:     500  --font-weight-medium: 500
Semibold:   600  --font-weight-semibold: 600
Bold:       700  --font-weight-bold: 700
```

### Line Height Scale
```
Tight:      1.2  (headings)       --line-height-tight: 1.2
Normal:     1.4  (labels)         --line-height-normal: 1.4
Relaxed:    1.5  (body)           --line-height-relaxed: 1.5
Loose:      1.8  (large text)     --line-height-loose: 1.8
```

### Letter Spacing
```
Tight:      -0.5px (headings)     --letter-spacing-tight: -0.5px
Normal:     0      (body)         --letter-spacing-normal: 0
Wide:       0.05em (uppercase)    --letter-spacing-wide: 0.05em
Wider:      0.1em  (emphasis)     --letter-spacing-wider: 0.1em
```

### Text Styles (Combined)

#### Display (Hero Text)
```
Font-size:      32px
Font-weight:    700 (bold)
Line-height:    1.2
Letter-spacing: -0.5px
Color:          Gray-900
```

#### Heading 1
```
Font-size:      28px
Font-weight:    700 (bold)
Line-height:    1.2
Color:          Gray-900
```

#### Heading 2
```
Font-size:      24px
Font-weight:    700 (bold)
Line-height:    1.2
Color:          Gray-900
```

#### Heading 3
```
Font-size:      20px
Font-weight:    600 (semibold)
Line-height:    1.4
Color:          Gray-900
```

#### Body Large (Primary)
```
Font-size:      16px
Font-weight:    400 (regular)
Line-height:    1.5
Color:          Gray-700
```

#### Body (Secondary)
```
Font-size:      14px
Font-weight:    400 (regular)
Line-height:    1.5
Color:          Gray-600
```

#### Label (Form)
```
Font-size:      12px
Font-weight:    500 (medium)
Line-height:    1.4
Color:          Gray-700
Letter-spacing: 0 (normal)
```

#### Caption (Helper)
```
Font-size:      12px
Font-weight:    400 (regular)
Line-height:    1.4
Color:          Gray-500
```

---

## Border Radius Tokens

```
None:    0          (--radius-none: 0)
SM:      4px        (--radius-sm: 4px)
Base:    6px        (--radius-base: 6px)
MD:      8px        (--radius-md: 8px)
LG:      12px       (--radius-lg: 12px)
XL:      16px       (--radius-xl: 16px)
Full:    50%        (--radius-full: 50%)
```

### Usage
```
Inputs/Buttons:     6px (base)
Icons buttons:      8px (md)
Cards:              12px (lg)
Modals:             16px (xl)
Avatars:            50% (full circle)
Images:             8-12px (lg)
```

---

## Shadow Tokens

### Shadow Scale
```
None:   none
        --shadow-none: none

XS:     0 1px 2px 0 rgba(0, 0, 0, 0.05)
        --shadow-xs: 0 1px 2px 0 rgba(0, 0, 0, 0.05)

SM:     0 1px 3px 0 rgba(0, 0, 0, 0.1),
        0 1px 2px 0 rgba(0, 0, 0, 0.06)
        --shadow-sm: 0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px 0 rgba(0, 0, 0, 0.06)

MD:     0 4px 6px -1px rgba(0, 0, 0, 0.1),
        0 2px 4px -1px rgba(0, 0, 0, 0.06)
        --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)

LG:     0 10px 15px -3px rgba(0, 0, 0, 0.1),
        0 4px 6px -2px rgba(0, 0, 0, 0.05)
        --shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)

XL:     0 20px 25px -5px rgba(0, 0, 0, 0.1),
        0 10px 10px -5px rgba(0, 0, 0, 0.04)
        --shadow-xl: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04)

2XL:    0 25px 50px -12px rgba(0, 0, 0, 0.25)
        --shadow-2xl: 0 25px 50px -12px rgba(0, 0, 0, 0.25)
```

### Usage
```
Buttons:           --shadow-sm
Hover state:       --shadow-md
Cards:             --shadow-base or --shadow-md
Modals:            --shadow-xl
Dropdowns:         --shadow-lg
Elevated container:--shadow-2xl
Focus indicator:   --shadow-md (color: indigo)
```

---

## Z-Index Scale

```
Hide:          -1         (z-index: -1)
Base:          0          (z-index: 0)
Dropdown:      10         (z-index: 10)
Sticky:        20         (z-index: 20)
Fixed:         30         (z-index: 30)
Overlay:       40         (z-index: 40)
Modal:         50         (z-index: 50)
Toast:         60         (z-index: 60)
Tooltip:       70         (z-index: 70)
Dropdown-menu: 80         (z-index: 80)
```

---

## Duration Tokens

### Animation Durations
```
Fast:         150ms  --duration-fast: 150ms
Normal:       300ms  --duration-normal: 300ms (default)
Slow:         500ms  --duration-slow: 500ms
Slower:       700ms  --duration-slower: 700ms
```

### Usage
```
Micro-interactions: 150ms (hover, focus)
Modals/overlays:    300ms (fade, slide)
Animations:         300-500ms
Longer states:      500ms+
```

---

## Timing Function Tokens

```
Linear:    linear
           --timing-linear: linear

Ease-in:   cubic-bezier(0.4, 0, 1, 1)
           --timing-ease-in: cubic-bezier(0.4, 0, 1, 1)

Ease-out:  cubic-bezier(0, 0, 0.2, 1)
           --timing-ease-out: cubic-bezier(0, 0, 0.2, 1)

Ease-in-out: cubic-bezier(0.4, 0, 0.2, 1)
             --timing-ease-in-out: cubic-bezier(0.4, 0, 0.2, 1)
```

### Usage
```
Entrance:    ease-out
Exit:        ease-in
Continuous:  linear
Interaction: ease-in-out
```

---

## Breakpoint Tokens

```
SM:   640px   (--breakpoint-sm: 640px)
MD:   768px   (--breakpoint-md: 768px)   <- Primary mobile/desktop split
LG:   1024px  (--breakpoint-lg: 1024px)
XL:   1280px  (--breakpoint-xl: 1280px)
2XL:  1536px  (--breakpoint-2xl: 1536px)
```

### Media Query Usage
```
Default:             < 640px (mobile)
@media (min-width: 768px):  Tablet+
@media (min-width: 1024px): Desktop+
@media (min-width: 1280px): Large desktop+
```

---

## CSS Variables (Complete)

Place in `:root` or `html` selector:

```css
:root {
  /* Colors */
  --color-primary-50: #EEF2FF;
  --color-primary-600: #4F46E5;
  --color-primary-700: #4338CA;
  --color-secondary-600: #9333EA;
  --color-success-500: #10B981;
  --color-error-500: #EF4444;
  --color-warning-500: #F59E0B;
  --color-info-500: #3B82F6;
  
  /* Grays */
  --color-gray-50: #F9FAFB;
  --color-gray-100: #F3F4F6;
  --color-gray-200: #E5E7EB;
  --color-gray-500: #6B7280;
  --color-gray-700: #374151;
  --color-gray-900: #111827;
  
  /* Spacing */
  --spacing-1: 4px;
  --spacing-2: 8px;
  --spacing-4: 16px;
  --spacing-6: 24px;
  --spacing-8: 32px;
  
  /* Typography */
  --font-family-base: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto';
  --font-size-body: 14px;
  --font-size-h1: 28px;
  --font-weight-regular: 400;
  --font-weight-bold: 700;
  --line-height-relaxed: 1.5;
  
  /* Borders & Radius */
  --radius-md: 8px;
  --radius-lg: 12px;
  
  /* Shadows */
  --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
  --shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
  
  /* Animations */
  --duration-normal: 300ms;
  --timing-ease-out: cubic-bezier(0, 0, 0.2, 1);
}
```

---

## Token Implementation

### In CSS
```css
.button {
  background: linear-gradient(135deg, var(--color-primary-600), var(--color-secondary-600));
  color: white;
  padding: var(--spacing-3) var(--spacing-4);
  border-radius: var(--radius-md);
  font-size: var(--font-size-body);
  font-weight: var(--font-weight-semibold);
  box-shadow: var(--shadow-md);
  transition: all var(--duration-normal) var(--timing-ease-out);
}
```

### In Tailwind CSS
```html
<button class="
  bg-gradient-to-br from-indigo-600 to-purple-600
  text-white
  px-4 py-2
  rounded-lg
  text-sm
  font-semibold
  shadow-md
  hover:shadow-lg
  transition-all duration-300
">
  Button
</button>
```

### In SCSS
```scss
$color-primary: #4F46E5;
$spacing-base: 16px;
$radius-md: 8px;

.card {
  padding: $spacing-base;
  border-radius: $radius-md;
  background-color: white;
}
```

### In JavaScript
```javascript
const tokens = {
  colors: {
    primary: '#4F46E5',
    secondary: '#9333EA',
  },
  spacing: {
    sm: '8px',
    md: '16px',
    lg: '24px',
  },
  radius: {
    md: '8px',
  },
};

// Usage
element.style.background = tokens.colors.primary;
element.style.padding = tokens.spacing.md;
```

---

**Last Updated**: August 2026
