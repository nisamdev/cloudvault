# Accessibility Guidelines

CloudVault follows WCAG 2.1 Level AA accessibility standards.

---

## Quick Checklist

- [ ] **Keyboard Navigation**: All features accessible via keyboard (no mouse required)
- [ ] **Focus States**: Clear, visible focus indicators (2px ring, 2px offset)
- [ ] **Color Contrast**: 4.5:1 for normal text, 3:1 for large text (WCAG AA)
- [ ] **Labels**: All inputs have associated labels or aria-label
- [ ] **ARIA**: Proper ARIA attributes on dynamic elements
- [ ] **Semantic HTML**: Use proper heading hierarchy, button vs div
- [ ] **Screen Readers**: Tested with NVDA, JAWS, or VoiceOver
- [ ] **Images**: All images have alt text (or aria-hidden="true" if decorative)
- [ ] **Modals**: aria-modal="true", trap focus, manage focus
- [ ] **Forms**: Error messages associated with inputs
- [ ] **Animations**: Respect prefers-reduced-motion
- [ ] **Touch Targets**: 44px minimum for mobile, 8px spacing

---

## Keyboard Navigation

### Focus Order

Must be logical and match visual order.

```
Expected order:
1. Search input
2. Sort dropdown
3. File list items (tab through each item)
   - Within item: share, more actions
4. Pagination controls

NOT recommended:
1. Footer (bottom)
2. Logo (top)
(Non-logical jumps confuse users)
```

### Navigation Keys

#### Global
```
Tab:        Next focusable element
Shift+Tab:  Previous focusable element
Enter:      Activate button, submit form, open link
Escape:     Close modal, cancel operation
```

#### Form
```
Tab:        Move between fields
Space:      Toggle checkbox or button
Enter:      Submit form, activate button
Arrow ↑↓:   Select option in dropdown
```

#### List/Menu
```
Arrow ↑↓:   Navigate items
Enter:      Select item
Space:      Toggle selection
Home:       First item
End:        Last item
```

### Skip Links

Add for large pages:

```html
<!-- At top of body, hidden by default -->
<a href="#main-content" class="sr-only">
  Skip to main content
</a>

<!-- Main content marker -->
<main id="main-content">
  ...
</main>

<!-- CSS to show on focus -->
.sr-only:focus {
  position: static;
  width: auto;
  height: auto;
  padding: 8px 16px;
  background: Indigo-600;
  color: white;
}
```

---

## Focus Management

### Focus Indicators

**Visible on all interactive elements**:

```css
:focus {
  outline: 2px solid #4F46E5;  /* Indigo-600 */
  outline-offset: 2px;
  box-shadow: 0 0 0 4px rgba(79, 70, 229, 0.1);  /* Light ring */
}
```

### Focus Trap (Modals)

Keep focus within modal while open:

```javascript
const modal = document.querySelector('[role="dialog"]');

// Find all focusable elements
const focusables = modal.querySelectorAll(
  'button, [href], input, select, textarea, [tabindex]'
);

const firstFocusable = focusables[0];
const lastFocusable = focusables[focusables.length - 1];

// On Tab at end: move to start
// On Shift+Tab at start: move to end

lastFocusable.addEventListener('keydown', (e) => {
  if (e.key === 'Tab' && !e.shiftKey) {
    e.preventDefault();
    firstFocusable.focus();
  }
});

firstFocusable.addEventListener('keydown', (e) => {
  if (e.key === 'Tab' && e.shiftKey) {
    e.preventDefault();
    lastFocusable.focus();
  }
});
```

### Focus Restoration

When closing modal, return focus to triggering button:

```javascript
const openButton = document.querySelector('[data-open="modal"]');
const modal = document.getElementById('modal');
const closeButton = modal.querySelector('.close');

openButton.addEventListener('click', () => {
  modal.showModal();
  // Focus modal itself
  modal.focus();
});

closeButton.addEventListener('click', () => {
  modal.close();
  // Restore focus to opening button
  openButton.focus();
});
```

---

## Color & Contrast

### Contrast Ratios

**Required contrast**:
```
Normal text (< 18px):      4.5:1 (WCAG AA)
Large text (≥ 18px):       3:1 (WCAG AA)
UI components (borders):   3:1 (WCAG AA)

Better:
  Level AAA:  7:1 (normal), 4.5:1 (large)
```

### Testing Contrast

Tools:
- WebAIM Contrast Checker: webaim.org/resources/contrastchecker
- WAVE Browser Extension
- Lighthouse (Chrome DevTools)

### Color Palette Contrast

**Good combinations**:
```
Gray-900 on Gray-50:        21:1 ✅ AAA
Gray-700 on Gray-50:        9:1 ✅ AAA
Indigo-600 on White:        9.2:1 ✅ AAA
Gray-600 on Gray-50:        7:1 ✅ AA/AAA
```

**Avoid**:
```
Gray-400 on White:          2.6:1 ❌ Fail
Gray-300 on Gray-50:        1.5:1 ❌ Fail
Indigo-400 on Indigo-100:   1.7:1 ❌ Fail
```

### Color Alone

Never rely on color alone to convey information:

```
❌ WRONG: "Red = error, Green = success"
✅ RIGHT: Red icon + "Error:" text, Green icon + "Success:" text

❌ WRONG: Red highlight for important
✅ RIGHT: Red + italic + icon + "Important:"
```

---

## ARIA Attributes

### Common Attributes

#### aria-label
```html
<!-- Icon button without visible label -->
<button aria-label="Close dialog">
  ✕
</button>

<!-- Not needed: -->
<button>Close</button> <!-- Already has label -->
```

#### aria-labelledby
```html
<h2 id="modal-title">Share File</h2>
<div role="dialog" aria-labelledby="modal-title">
  <!-- Modal content -->
</div>
```

#### aria-describedby
```html
<input aria-describedby="password-hint" type="password">
<p id="password-hint">Min 8 characters, 1 uppercase, 1 number</p>
```

#### aria-live
```html
<!-- Announce updates to screen readers -->
<div aria-live="polite" aria-atomic="true">
  File uploaded successfully
</div>

<!-- aria-live values: -->
<!-- polite: Announce after current speech ends -->
<!-- assertive: Announce immediately -->
<!-- off: Don't announce (default) -->
```

#### aria-busy
```html
<!-- During loading -->
<div aria-busy="true">
  <i class="spinner"></i>
  Loading files...
</div>

<!-- After loading -->
<div aria-busy="false">
  Files loaded
</div>
```

#### aria-disabled
```html
<!-- For disabled elements (use actual disabled when possible) -->
<button aria-disabled="true" disabled>
  Cannot upload yet
</button>
```

#### aria-expanded
```html
<!-- For expandable elements -->
<button aria-expanded="false" aria-controls="menu">
  ☰ Menu
</button>

<nav id="menu" hidden>
  <!-- Menu items -->
</nav>

<!-- When clicked, toggle aria-expanded and hidden -->
```

#### aria-hidden
```html
<!-- Hide decorative elements from screen readers -->
<span aria-hidden="true">→</span>
<span class="sr-only">Next page</span>

<!-- Or decorative icons: -->
<i class="icon-star" aria-hidden="true"></i>
<span>Rating: 5 stars</span>
```

### Roles

```html
<!-- Main landmarks -->
<header role="banner">...</header>
<nav role="navigation">...</nav>
<main role="main">...</main>
<footer role="contentinfo">...</footer>
<aside role="complementary">...</aside>

<!-- Interactive -->
<div role="button" tabindex="0">Click me</div>
<div role="dialog" aria-modal="true">
  <button aria-label="Close">✕</button>
</div>

<!-- Form -->
<div role="alert">Error: Email required</div>
<div role="status">3 items selected</div>

<!-- Navigation -->
<ol role="listbox">
  <li role="option" aria-selected="true">Item 1</li>
</ol>
```

---

## Semantic HTML

### Use Correct Elements

```html
<!-- ❌ DON'T -->
<div onclick="upload()">Upload</div>

<!-- ✅ DO -->
<button onclick="upload()">Upload</button>

<!-- ❌ DON'T -->
<div role="link" onclick="navigate('/')">Home</div>

<!-- ✅ DO -->
<a href="/">Home</a>
```

### Heading Hierarchy

```html
<!-- ✅ CORRECT -->
<h1>CloudVault</h1>
<h2>My Files</h2>
<h3>Recent files</h3>

<!-- ❌ WRONG -->
<h1>CloudVault</h1>
<h3>My Files</h3>  <!-- Skips h2 -->
<h2>Recent files</h2>  <!-- Out of order -->
```

### Form Elements

```html
<!-- ✅ CORRECT -->
<label for="email">Email</label>
<input id="email" type="email">

<!-- Also acceptable (implicit label) -->
<label>
  Email
  <input type="email">
</label>

<!-- ❌ WRONG -->
<input type="email" placeholder="Email">  <!-- No label -->
<span>Email</span>
<input type="email">  <!-- Not connected -->
```

### Lists

```html
<!-- ✅ CORRECT -->
<ul>
  <li>Item 1</li>
  <li>Item 2</li>
</ul>

<!-- ❌ WRONG -->
<div>
  <div>Item 1</div>
  <div>Item 2</div>
</div>
```

---

## Images & Icons

### Image Alt Text

**Informative images**:
```html
<!-- ✅ Good alt text -->
<img src="photo.jpg" alt="Family vacation at Lake Tahoe, August 2024">

<!-- ❌ Bad -->
<img src="photo.jpg" alt="image">
<img src="photo.jpg" alt="photo.jpg">
```

**Decorative images**:
```html
<!-- ✅ Hide from screen readers -->
<img src="divider.svg" alt="">
<i class="icon-star" aria-hidden="true"></i>

<!-- ❌ Don't describe decorative -->
<img src="line.svg" alt="decorative line">
```

**Icons with text**:
```html
<!-- ✅ Icon + text combo -->
<i class="icon-download" aria-hidden="true"></i>
<span>Download</span>

<!-- ✅ Alt on icon-only button -->
<button aria-label="Download file">
  <i class="icon-download"></i>
</button>

<!-- ❌ Redundant -->
<button>
  <i class="icon-download"></i>
  Download
</button> + aria-label="Download" (duplicate)
```

---

## Forms & Errors

### Input Labels

```html
<!-- ✅ Connected label -->
<label for="password">Password</label>
<input id="password" type="password" required>

<!-- Error message connected -->
<input id="email" aria-describedby="email-error">
<span id="email-error" role="alert">Email is invalid</span>
```

### Error Messaging

```html
<!-- ✅ Announce errors -->
<div role="alert">
  <strong>Error:</strong> Email is required
</div>

<!-- With input highlight -->
<div>
  <label for="email">Email *</label>
  <input id="email" aria-describedby="email-error" aria-invalid="true">
  <span id="email-error" role="alert">Email is required</span>
</div>
```

### Required Fields

```html
<!-- ✅ Mark required -->
<label for="name">
  Name
  <span aria-label="required">*</span>
</label>
<input id="name" required aria-required="true">

<!-- Aria-required for non-HTML5 forms -->
```

---

## Screen Reader Testing

### Tools
- **NVDA** (Windows, free)
- **JAWS** (Windows, paid)
- **VoiceOver** (Mac, free)
- **TalkBack** (Android, free)

### Testing Checklist

```
[ ] Page title matches content
[ ] Headings in logical order (h1, h2, h3...)
[ ] All buttons have accessible labels
[ ] Form inputs have associated labels
[ ] Form errors announced clearly
[ ] Links have descriptive text (not "click here")
[ ] Images have meaningful alt text
[ ] Focus order is logical
[ ] Focus indicators visible
[ ] Modals trapped (focus loops within)
[ ] Instructions clear without visual cues only
[ ] Contrast ratios meet 4.5:1 minimum
```

### Testing Commands

**NVDA (Windows)**:
```
Insert + F7: Toggle browse/focus mode
Insert + H: Toggle heading navigation
Insert + L: Navigate links
Insert + G: Navigate graphics
Insert + T: Navigate tables
```

**VoiceOver (Mac)**
```
VO = Control + Option (by default)
VO + Right Arrow: Next element
VO + Left Arrow: Previous element
VO + Space: Activate/interact
VO + U: Web rotor (navigate headings, etc.)
```

---

## Motion & Animation

### prefers-reduced-motion

Respect user preferences for animations:

```css
/* Default animation */
button {
  transition: all 0.3s ease-out;
}

/* Disable if user prefers reduced motion */
@media (prefers-reduced-motion: reduce) {
  * {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

### Animated Indicators

Don't rely on animation alone:

```css
/* ❌ Not accessible -->
@keyframes blink { /* blinking only */ }

/* ✅ Combine animation with text/icon -->
.loading {
  animation: spin 1s linear infinite;
}
.loading::after {
  content: " Loading...";
}
```

---

## Testing Tools

### Automated Testing

**Browser Extensions**:
- [WAVE](https://wave.webaim.org/extension/) - Accessibility audit
- [axe DevTools](https://www.deque.com/axe/devtools/) - Automated testing
- [Lighthouse](https://developers.google.com/web/tools/lighthouse) - Built into Chrome

**Command Line**:
```bash
# pa11y (CLI accessibility testing)
npm install -g pa11y
pa11y http://localhost:3000/dashboard

# axe-core
npm install axe-core
```

### Manual Testing

```bash
# Test with keyboard only
1. Remove mouse
2. Use Tab, Shift+Tab, Enter, Arrow keys
3. Navigate entire page
4. Complete all tasks

# Test with screen reader
1. Enable VoiceOver/NVDA/JAWS
2. Navigate page
3. Read aloud in natural order
4. No garbled or confusing output
```

---

## Accessibility Standards

### WCAG 2.1 Levels

**Level A**: Basic compliance
**Level AA**: Recommended, covers 80%+ of issues ✅ (Target)
**Level AAA**: Enhanced, more complex to achieve

### Section 508 (US)
Compliance with federal accessibility standards (public sector)

### ADA (Americans with Disabilities Act)
Applies to businesses, requires "readily achievable" access

---

## Common Issues & Fixes

### Issue: Missing Focus Indicator

```css
/* ❌ Removed default outline -->
button:focus {
  outline: none;
}

/* ✅ Add custom indicator -->
button:focus {
  outline: 2px solid #4F46E5;
  outline-offset: 2px;
}
```

### Issue: Low Contrast Text

```css
/* ❌ Gray text on light bg -->
.secondary-text {
  color: #9CA3AF;  /* Gray-400, 2.6:1 contrast */
}

/* ✅ Use darker gray -->
.secondary-text {
  color: #6B7280;  /* Gray-500, 4.5:1 contrast */
}
```

### Issue: Div as Button

```html
<!-- ❌ Not keyboard/SR accessible -->
<div onclick="submit()" class="button">
  Submit
</div>

<!-- ✅ Use semantic button -->
<button onclick="submit()">
  Submit
</button>
```

### Issue: Icon-Only Button

```html
<!-- ❌ No label -->
<button>✕</button>

<!-- ✅ Add aria-label -->
<button aria-label="Close dialog">
  ✕
</button>
```

---

## Resources

- [WebAIM](https://webaim.org/) - Web accessibility articles
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/) - Official specs
- [A11y Project](https://www.a11yproject.com/) - Community resources
- [ARIA Authoring Practices](https://www.w3.org/WAI/ARIA/apg/) - ARIA examples
- [Accessible Name Computation](https://www.w3.org/TR/accname-1.2/) - How screen readers find labels

---

## Checklist for Developers

Before shipping any feature:

- [ ] Tested with keyboard only (no mouse)
- [ ] Focus indicators visible on all interactive elements
- [ ] Color contrast tested (4.5:1 minimum)
- [ ] Form inputs have labels
- [ ] Error messages clear and associated with inputs
- [ ] Images have meaningful alt text
- [ ] ARIA roles/labels used correctly
- [ ] Heading hierarchy logical
- [ ] Modals trap focus
- [ ] Animations respect prefers-reduced-motion
- [ ] Tested with at least one screen reader (NVDA or VoiceOver)
- [ ] No time limits without warning
- [ ] Touch targets 44px+ on mobile
- [ ] Page works without JavaScript (graceful degradation)

---

**Last Updated**: August 2026  
**Version**: 1.0  
**Compliance Target**: WCAG 2.1 Level AA
