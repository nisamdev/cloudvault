# CloudVault Design System - Documentation

Complete design system documentation for CloudVault, a secure family cloud storage application.

---

## 📚 Documentation Files

### 1. **STYLE_GUIDE.md** - Main Reference
The foundational style guide covering:
- Brand identity
- Grid & layout system
- Color system & semantic colors
- Typography scale
- Button styles
- Forms & inputs
- Cards & containers
- Navigation patterns
- Shadows & borders
- Animations & transitions
- Accessibility guidelines
- Performance considerations
- Dark mode planning

**Start here** for overall design philosophy and standards.

---

### 2. **DESIGN_TOKENS.md** - Design Token Reference
Comprehensive token definitions:
- **Colors**: Primary, secondary, status colors, neutral grays
- **Spacing**: 4px-based scale (0-128px)
- **Typography**: Font families, sizes, weights, line heights
- **Border Radius**: SM (4px) to Full (50%)
- **Shadows**: XS to 2XL scale
- **Z-Index**: Layering system
- **Durations**: Animation timing scale
- **Timing Functions**: Easing curves
- **Breakpoints**: Responsive breakpoints
- **CSS Variables**: Complete variable set

**Use this** when implementing components in code. Includes CSS variable examples.

---

### 3. **COMPONENTS.md** - UI Component Specifications
Detailed specs for every component:
- **Buttons**: Primary, secondary, icon, danger variants
- **Forms**: Inputs, textareas, checkboxes, radios, toggles, selects
- **Cards**: Basic cards, file/list items, gallery tiles
- **Navigation**: Sidebars, sidebar items, top bar, breadcrumbs
- **Modals & Overlays**: Modals, overlays, toasts, notifications
- **Specialized**: Upload zones, progress bars, breadcrumbs, avatars, badges
- **Responsive Behavior**: Mobile, tablet, desktop breakpoints

**Reference this** when building Vue components. Each component includes:
- Anatomy (structure)
- Specs (padding, colors, fonts)
- States (default, hover, active, disabled, focus)
- Examples (HTML snippets)

---

### 4. **PATTERNS.md** - Interaction Patterns & Workflows
Common user interactions and workflows:
- **Navigation**: Sidebar, breadcrumbs
- **Forms**: Sign in/up, file upload, sharing, management
- **Lists & Grids**: File lists, image gallery, pagination
- **Modals & Dialogs**: Confirmations, forms, alerts
- **Search & Filter**: Search input, filter panel
- **Notifications**: Toasts, inline alerts
- **Loading & Progress**: Page loading, upload progress
- **Empty & Error States**: No content, load failures
- **Accessibility Patterns**: Keyboard navigation, focus management
- **Animation Patterns**: Fade, slide, scale, spin
- **Responsive Patterns**: Mobile sidebar, stacked layout, touch targets
- **Performance Patterns**: Lazy loading, virtual scrolling

**Use this** when building features. Shows complete user flows and interaction details.

---

### 5. **ACCESSIBILITY.md** - A11y Guidelines
Comprehensive accessibility guidelines (WCAG 2.1 Level AA):
- **Keyboard Navigation**: Tab order, common keys, skip links
- **Focus Management**: Focus traps, restoration, visible indicators
- **Color & Contrast**: Ratios, color-alone issues, testing
- **ARIA Attributes**: Labels, roles, live regions, hidden elements
- **Semantic HTML**: Proper elements, heading hierarchy, forms
- **Images & Icons**: Alt text, decorative vs informative
- **Forms & Errors**: Labels, error messaging, required fields
- **Screen Reader Testing**: Tools, checklist, commands
- **Motion & Animation**: prefers-reduced-motion, animation best practices
- **Common Issues**: Fixes for frequent accessibility problems
- **Testing Tools**: Automated and manual testing

**Reference this** when implementing components. Includes tools and testing checklist.

---

## 🎯 How to Use This Documentation

### For Designers
1. Start with **STYLE_GUIDE.md** for brand and layout
2. Reference **DESIGN_TOKENS.md** for exact colors, spacing
3. Use **COMPONENTS.md** for component specifications
4. Check **PATTERNS.md** for interaction details
5. Validate **ACCESSIBILITY.md** for inclusive design

### For Frontend Developers
1. Read **DESIGN_TOKENS.md** - understand the token system
2. Reference **COMPONENTS.md** - build components to spec
3. Check **PATTERNS.md** - implement correct interactions
4. Validate **ACCESSIBILITY.md** - ensure accessibility compliance
5. Refer to **STYLE_GUIDE.md** - understand broader system

### For Mobile/React Native Developers
1. Study **DESIGN_TOKENS.md** - adapt tokens for native
2. Review **COMPONENTS.md** - map to native components
3. Understand **PATTERNS.md** - native interaction conventions
4. Ensure **ACCESSIBILITY.md** - native accessibility APIs
5. Reference **STYLE_GUIDE.md** - overall principles

### For Project Managers / Product Owners
1. Skim **STYLE_GUIDE.md** - understand design direction
2. Review **PATTERNS.md** - see planned workflows
3. Check **ACCESSIBILITY.md** - compliance guarantees

---

## 🎨 Design System Quick Links

### Colors
```
Primary:      Indigo-600 (#4F46E5)
Secondary:    Purple-600 (#9333EA)
Success:      Green-500 (#10B981)
Error:        Red-500 (#EF4444)
Warning:      Amber-500 (#F59E0B)
Info:         Blue-500 (#3B82F6)
Neutral:      Gray scale (50-900)
```

See **DESIGN_TOKENS.md** for complete palette.

### Typography
```
Display:    32px bold
H1:         28px bold
H2:         24px bold
H3:         20px semibold
Body Lg:    16px regular
Body:       14px regular (default)
Label:      12px medium
Caption:    12px regular
```

See **DESIGN_TOKENS.md** for font stack and line heights.

### Spacing Scale
```
0    0px      6    24px
0.5  2px      8    32px
1    4px      12   48px
1.5  6px      16   64px
2    8px      20   80px
3    12px     24   96px
4    16px     32   128px
```

See **DESIGN_TOKENS.md** for complete scale.

### Breakpoints
```
Mobile:   < 640px (default)
Tablet:   768px (md)
Desktop:  1024px (lg)
Large:    1280px (xl)
```

See **DESIGN_TOKENS.md** for media query syntax.

---

## 🔧 Implementation

### Using Tailwind CSS
All examples in **COMPONENTS.md** use Tailwind utility classes.

```html
<!-- Example from COMPONENTS.md -->
<button class="
  px-6 py-2 
  bg-gradient-to-r from-indigo-600 to-purple-600 
  text-white 
  rounded-lg 
  font-semibold 
  hover:shadow-md 
  transition-all duration-200
">
  Sign In
</button>
```

### Using CSS Variables
See **DESIGN_TOKENS.md** for complete CSS variable reference:

```css
:root {
  --color-primary-600: #4F46E5;
  --spacing-4: 16px;
  --radius-md: 8px;
  --font-size-body: 14px;
}

.button {
  padding: var(--spacing-4);
  background: var(--color-primary-600);
  border-radius: var(--radius-md);
  font-size: var(--font-size-body);
}
```

### Using SCSS
See **DESIGN_TOKENS.md** for SCSS variable examples:

```scss
$color-primary: #4F46E5;
$spacing-base: 16px;
$radius-md: 8px;

.button {
  padding: $spacing-base;
  border-radius: $radius-md;
  background: $color-primary;
}
```

---

## 📱 Responsive Strategy

### Mobile-First Approach
All styles default to mobile, enhanced with breakpoints:

```css
/* Mobile first */
.sidebar {
  position: fixed;
  transform: translateX(-100%);
}

/* Tablet + Desktop */
@media (min-width: 768px) {
  .sidebar {
    position: static;
    transform: translateX(0);
  }
}
```

### Breakpoint Usage
- **Default**: < 768px (mobile, no sidebar)
- **md (768px)**: Tablet (sidebar visible)
- **lg (1024px)**: Desktop (full layout)
- **xl (1280px)**: Large screens (max-width containers)

See **STYLE_GUIDE.md** section 2 and **PATTERNS.md** for detailed responsive patterns.

---

## ♿ Accessibility Compliance

### Target: WCAG 2.1 Level AA

**Key Requirements**:
- ✅ Keyboard navigation (Tab, Arrow keys, Enter)
- ✅ Focus indicators (2px Indigo-500 ring)
- ✅ Color contrast (4.5:1 for normal text)
- ✅ Semantic HTML (button vs div, proper headings)
- ✅ ARIA labels (aria-label, aria-labelledby)
- ✅ Screen reader tested (NVDA, VoiceOver, JAWS)
- ✅ Error messages (aria-describedby, role="alert")
- ✅ Focus management (focus trap in modals)
- ✅ Motion (respect prefers-reduced-motion)
- ✅ Touch targets (44px minimum on mobile)

See **ACCESSIBILITY.md** for detailed guidelines, testing procedures, and common fixes.

---

## 🧪 Testing Checklist

### Before Launch

**Visual Testing**:
- [ ] All screens tested at mobile, tablet, desktop sizes
- [ ] Colors match design tokens
- [ ] Spacing matches grid (8px base)
- [ ] Typography matches scale
- [ ] Shadows and borders correct

**Functional Testing**:
- [ ] All buttons clickable and functional
- [ ] Forms submit with validation
- [ ] Navigation works in all directions
- [ ] Modals open/close correctly
- [ ] Animations smooth (no jank)

**Accessibility Testing**:
- [ ] Keyboard navigation works (Tab through all elements)
- [ ] Focus indicators visible
- [ ] Color contrast passes (4.5:1+)
- [ ] Screen reader tested (at least one)
- [ ] ARIA labels present where needed
- [ ] No time limits or warnings

**Performance Testing**:
- [ ] Page load < 3 seconds
- [ ] Images lazy-loaded
- [ ] No layout shifts (CLS < 0.1)
- [ ] LCP < 2.5 seconds
- [ ] Touch responsive (< 100ms delay)

---

## 📦 Deliverables

### Design Files
- Figma file with all components
- Color swatches (ASE for Photoshop/Illustrator)
- Icon set (SVG)

### Code
- Component library (Vue 3)
- CSS/Tailwind utilities
- SCSS mixins
- JavaScript utilities

### Documentation
- **This file** (README)
- **5 markdown guides** (linked below)
- Component storybook
- API documentation
- Developer setup guide

---

## 🚀 Getting Started

### Step 1: Read the Guides
1. **STYLE_GUIDE.md** (15 min) - Understand the system
2. **DESIGN_TOKENS.md** (10 min) - Learn token definitions
3. **COMPONENTS.md** (20 min) - See component specs
4. **PATTERNS.md** (15 min) - Study interaction workflows
5. **ACCESSIBILITY.md** (15 min) - Learn a11y requirements

**Total: ~75 minutes to get familiar**

### Step 2: Reference During Development
- Keep **DESIGN_TOKENS.md** open while coding
- Use **COMPONENTS.md** for component specs
- Check **PATTERNS.md** for interaction details
- Validate with **ACCESSIBILITY.md**

### Step 3: Test & Validate
1. Visual: Compare to screenshot in **COMPONENTS.md**
2. Functional: Follow workflow in **PATTERNS.md**
3. Accessible: Validate with checklist in **ACCESSIBILITY.md**

---

## 📋 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Aug 2026 | Initial design system release |
| - | - | Mobile app guidance (Phase 2) |
| - | - | Dark mode (Phase 2+) |
| - | - | Advanced components (Phase 3) |

---

## 🔗 Quick Navigation

**Main Files**:
- 📖 **[STYLE_GUIDE.md](./STYLE_GUIDE.md)** - Main reference
- 🎨 **[DESIGN_TOKENS.md](./DESIGN_TOKENS.md)** - Token definitions
- 🧩 **[COMPONENTS.md](./COMPONENTS.md)** - Component specs
- 🔄 **[PATTERNS.md](./PATTERNS.md)** - Interaction patterns
- ♿ **[ACCESSIBILITY.md](./ACCESSIBILITY.md)** - A11y guidelines

**HTML Prototype**:
- 🎬 **[cloudvault_ui_prototype.html](./cloudvault_ui_prototype.html)** - Interactive demo

**Implementation Guides**:
- ⚡ **[QUICK_REFERENCE.md](./QUICK_REFERENCE.md)** - Quick checklist
- 📋 **[PHASE1_IMPLEMENTATION_GUIDE.md](./PHASE1_IMPLEMENTATION_GUIDE.md)** - Dev roadmap

---

## 💬 Questions?

**Component specifications unclear?**
→ See detailed anatomy and specs in **COMPONENTS.md**

**How should users interact?**
→ Check **PATTERNS.md** for workflow examples

**Is my implementation accessible?**
→ Validate with **ACCESSIBILITY.md** checklist

**Need exact color/spacing?**
→ Reference **DESIGN_TOKENS.md**

**Want to understand the overall design?**
→ Read **STYLE_GUIDE.md**

---

## 📄 License & Usage

These design system files are internal CloudVault documentation.

- ✅ Use for CloudVault development
- ✅ Share within team
- ✅ Update and maintain
- ❌ Do not share publicly without permission
- ❌ Do not use for competing products

---

**Last Updated**: August 2026  
**Design System Version**: 1.0  
**Compliance**: WCAG 2.1 Level AA  
**Maintained By**: CloudVault Design & Engineering Team

---

## 📞 Contact

For questions about the design system:
- Design Lead: [contact info]
- Engineering Lead: [contact info]
- #design-system Slack channel

---

**Start here → Read STYLE_GUIDE.md → Reference DESIGN_TOKENS.md → Build with COMPONENTS.md → Validate with ACCESSIBILITY.md** ✅
