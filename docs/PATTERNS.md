# Design Patterns & Interactions

Common patterns and interaction models used throughout CloudVault.

---

## Navigation Patterns

### Primary Navigation (Sidebar)

**Structure**:
```
CloudVault (Logo)
├─ Main Items
│  ├─ Files (active)
│  ├─ Images
│  ├─ Shared
│  └─ Trash
├─ Divider
├─ Family Section
│  └─ Family Name + Manage button
├─ Divider
├─ Storage Indicator
└─ Bottom Actions
   ├─ Settings
   └─ Sign Out
```

**Mobile Interaction**:
```
1. User clicks hamburger icon (top-left)
2. Sidebar slides in from left
3. Overlay dims content
4. User clicks item → navigates
5. Sidebar auto-closes after navigation
6. Or: User clicks overlay to close
```

**Desktop Interaction**:
```
1. Sidebar always visible
2. Click item → highlights + navigates
3. Current page = active state with left border
4. No auto-close behavior
```

---

### Breadcrumb Navigation

**Pattern**:
```
Home > Files > Insurance Documents > Current Document

• Home: Links to dashboard
• Files: Links to files list
• Insurance Documents: Links to folder
• Current Document: Text (non-clickable)
```

**Interaction**:
```
Click any breadcrumb → Navigate to that level
Shows context of current position
Helps users understand hierarchy
```

---

## Form Patterns

### Sign In Flow

**Step 1: Credentials**
```
┌─ Email input
├─ Password input
├─ Remember me checkbox
├─ Forgot password link
└─ Sign In button
```

**Interaction**:
```
1. User enters email + password
2. Click "Sign In"
3. Loading state: button shows spinner + "Signing in..."
4. Success: Navigate to dashboard
5. Error: Show error toast, fields remain filled (except password)
6. Forgot password link: Opens password reset modal
```

---

### Sign Up Flow (Multi-step)

**Step 1: Account Creation**
```
┌─ Full Name
├─ Email
├─ Password (with strength indicator)
├─ Confirm Password
├─ Terms checkbox
└─ Create Account button
```

**Step 2: Family Setup**
```
┌─ Family Name
├─ Member Emails (repeatable field)
└─ Continue button
```

**Interaction**:
```
1. Form Step 1: Validate inputs, check email uniqueness
2. Click Create Account
3. Email verification (optional, can skip to family setup)
4. Step 2: Add family members (optional)
5. Skip or add members
6. Click Continue → Dashboard
```

---

### File Upload

**Modal / Inline Pattern**:

**Before Upload**:
```
┌─ Upload Zone
│  ├─ Icon (cloud + up arrow)
│  ├─ Primary text: "Drop files here or click"
│  └─ Secondary text: "Max 500MB per file"
└─ Click or drag-drop
```

**During Upload**:
```
┌─ File Name
├─ Progress bar (animated fill)
├─ "50% • 125 MB uploaded"
└─ Pause button
```

**After Upload**:
```
┌─ Success icon (green checkmark)
├─ File Name
├─ "Uploaded • 2.4 MB"
└─ Auto-remove from upload list after 3 seconds
   OR permanent if multiple uploads
```

**Error Handling**:
```
┌─ Error icon (red)
├─ File Name
├─ Error message: "File too large" or "Upload failed"
└─ Retry button
```

**Interaction Flow**:
```
1. Click upload zone
   → File picker opens
   
2. Select file(s)
   → Shows preview of selected files
   
3. Confirm upload
   → Starts upload with progress
   
4. On success
   → Shows success state
   → Auto-adds to file list
   → Clears upload zone
   
5. On error
   → Shows error message
   → Retry button available
   → Keep file selected for quick retry
```

---

### File Management (Share Dialog)

**Pattern**:
```
┌─ Share with Family section
│  ├─ Toggle "Share with family"
│  ├─ Member list (checkboxes)
│  └─ Role selection per member
│
├─ Divider
│
└─ Public Link section
   ├─ Generated link (readonly, copyable)
   ├─ Expires in dropdown
   ├─ Require password toggle
   └─ Password input (if enabled)
```

**Interaction**:
```
1. Click Share button on file
2. Share modal opens (with file info at top)
3. Toggle "Share with family" → Shows members
4. Select members to share with
5. Toggle public link → Generates link
6. Click copy button → "Copied to clipboard"
7. Set expiration: 7/30/90 days or Never
8. (Optional) Enable password
9. Click "Save Changes" → Confirms, closes modal
10. Show toast: "File shared successfully"
```

**Visual Feedback**:
```
Before:   Blue toggle (off)
Active:   Indigo toggle (on), members visible
Copying:  Button shows "Copied!" then "Copy" again
Success:  Toast notification
```

---

## List & Grid Patterns

### File List with Pagination

**Pattern**:
```
┌─ Header
│  ├─ Title: "My Files"
│  ├─ View toggle (list/grid)
│  ├─ Sort dropdown
│  └─ Filter options
│
├─ File list
│  ├─ File 1 (with actions on hover)
│  ├─ File 2
│  └─ File 3
│
└─ Footer
   ├─ "Showing 1-10 of 45 files"
   ├─ Page size selector: "10 | 25 | 50"
   └─ Pagination buttons: < 1 2 3 4 5 >
```

**Interaction**:
```
1. Load page: Shows first 10 files
2. Click file row: Opens detail modal or navigates
3. Right-click: Context menu (copy link, delete, etc.)
4. Hover: Shows action buttons (share, delete, more)
5. Click sort: Reorders list
6. Click next page: Loads next 10 items
7. Click page number: Jumps to that page
```

---

### Image Gallery with Infinite Scroll

**Pattern**:
```
┌─ Upload area (at top)
│
├─ Grid of thumbnails (3-6 columns responsive)
│  ├─ Tile 1 (with hover overlay)
│  ├─ Tile 2
│  └─ Tile 3
│
└─ Loading skeleton (at bottom, while scrolling)
   └─ "More images loading..."
```

**Interaction**:
```
1. Load page: Shows first 20 images
2. Scroll down
3. At bottom: Load next 20 images (auto-load)
4. Show skeleton loaders while fetching
5. Hover tile: Show date overlay
6. Click tile: Open lightbox (fullscreen preview)
7. In lightbox: Show prev/next buttons
8. Close lightbox: Click X or click outside
```

---

## Modal & Dialog Patterns

### Confirmation Dialog

**Scenario**: Delete file, confirm action

**Pattern**:
```
┌─ Icon (warning or info)
├─ Title: "Delete File?"
├─ Message: "This action cannot be undone."
├─ File name preview: "document.pdf"
│
└─ Footer
   ├─ Cancel button (secondary)
   └─ Delete button (danger/red)
```

**Interaction**:
```
1. User clicks delete
2. Modal appears with warning
3. User reads message
4. Click "Cancel" → Close modal, nothing happens
5. Click "Delete" → File deleted, modal closes, show success toast
```

**Keyboard**:
```
Escape → Close (same as Cancel)
Tab → Focus between buttons
Enter → Confirm (if focused on Delete)
```

---

### Form Modal

**Scenario**: Edit settings, change password

**Pattern**:
```
┌─ Header: "Change Password"
├─ Body
│  ├─ Current Password input
│  ├─ New Password input (with strength indicator)
│  ├─ Confirm Password input
│  └─ Password requirements (visual list)
│
└─ Footer
   ├─ Cancel button
   └─ Save Changes button
```

**Interaction**:
```
1. User fills form
2. Validation: Real-time feedback
   - Current password wrong? Show error
   - New password weak? Show strength meter
   - Passwords don't match? Show warning
3. Enable Save button only when valid
4. Click Save → Loading state
5. Success → Show toast, modal closes
6. Error → Show error message, keep form
```

---

## Search & Filter Patterns

### Search Input

**Pattern**:
```
┌─ Search icon (left side)
├─ Input field (placeholder: "Search files...")
├─ Debounce 300ms (wait after user stops typing)
└─ Results appear below (dropdown or inline)
```

**Interaction**:
```
1. User types: "tax"
2. Wait 300ms
3. Show results in dropdown:
   - tax_2024.pdf (matching name)
   - annual_tax_filing (matching content)
   - 2024 taxes (matching metadata)
4. Click result → Navigate/open
5. Clear input → Close results
6. Click X icon → Clear input
```

**States**:
```
Empty:        Placeholder text visible
Focused:      Cursor visible, hint text
Typing:       Placeholder hidden
Loading:      Spinner on right
Results:      Dropdown below with items
No results:   "No files found"
Error:        "Search temporarily unavailable"
```

---

### Filter Panel

**Pattern**:
```
┌─ Filter button (top-right)
│
└─ Expandable panel
   ├─ File Type: Checkbox list
   │  ├─ Documents
   │  ├─ Images
   │  └─ Videos
   │
   ├─ Date Range: Pickers
   │  ├─ From
   │  └─ To
   │
   ├─ Size: Radio buttons
   │  ├─ Any size
   │  ├─ < 1 MB
   │  ├─ 1-10 MB
   │  └─ > 10 MB
   │
   └─ Actions
      ├─ Clear all
      └─ Apply filters
```

**Interaction**:
```
1. Click filter button → Panel expands
2. Select filter options
3. Can combine multiple filters
4. Click "Apply" → Results update with loading state
5. Click "Clear all" → Resets all filters
6. Click outside panel or X → Panel closes (keeps selections)
```

---

## Notification Patterns

### Toast Notifications

**Success**:
```
┌─ Checkmark icon (green)
├─ "File uploaded successfully"
└─ Auto-close after 4 seconds
```

**Error**:
```
┌─ X icon (red)
├─ "Upload failed. Please try again."
├─ Action button (optional): "Retry"
└─ Auto-close after 6 seconds (longer for error)
```

**Info**:
```
┌─ Info icon (blue)
├─ "Storage nearly full"
└─ Action link (optional): "Upgrade plan"
```

**Placement**: Bottom-right, 32px from edges

**Stacking**: Multiple toasts stack upward, 12px gap

**Interaction**:
```
1. Action triggers
2. Toast appears with animation (slide up)
3. Auto-close after delay
4. OR: User clicks close (X button)
5. Toast disappears with animation
```

---

### Inline Alerts

**Usage**: Form errors, warnings in-page

**Pattern**:
```
┌─ Background (colored by type)
├─ Icon
├─ Message
└─ Close button (optional)
```

**Types**:
```
Error:    Red-50 bg, Red-800 text
Warning:  Amber-50 bg, Amber-800 text
Info:     Blue-50 bg, Blue-800 text
Success:  Green-50 bg, Green-800 text
```

**Persistence**: Stays on page until dismissed or condition resolves

---

## Loading & Progress Patterns

### Page Loading

**Pattern**:
```
1. Show skeleton loaders
   - Placeholder boxes with pulsing animation
   - Match layout of final content

2. While loading:
   - Show spinners on action buttons
   - Disable interactions (optional)
   - Show "Loading..." text

3. On complete:
   - Fade out skeleton
   - Fade in actual content
   - Fade duration: 0.3s
```

**Duration**:
```
Skeleton show time: 0.5-5s (actual load time)
Fade transition:    0.3s
```

---

### Upload Progress

**Pattern**:
```
During upload:
┌─ File name
├─ Progress bar (0-100%)
├─ "125 MB / 250 MB uploaded"
├─ Upload speed: "2.5 MB/s"
└─ Pause button

Options:
- Show percentage (50%)
- Show animated bar
- Show time remaining (calculated)
```

**Interaction**:
```
1. File upload starts
2. Progress bar animates
3. Show live stats (speed, time remaining)
4. User can pause (stops upload)
5. On complete: Show success, keep visible 2-3 seconds
6. Auto-clear from list
```

---

## Empty & Error States

### Empty State (No Files)

**Pattern**:
```
┌─ Large icon (64px, Gray-400)
│  └─ Cloud + folder icon
│
├─ Title: "No files yet"
├─ Description: "Upload files to get started"
│
└─ CTA Button: "Upload your first file"
```

**Interaction**:
```
Click button → Open upload dialog
Or drag-drop into area → Start upload
```

---

### Error State (Load Failed)

**Pattern**:
```
┌─ Error icon (Red, 64px)
├─ Title: "Couldn't load files"
├─ Message: "Something went wrong. Please try again."
│
└─ Actions
   ├─ Retry button
   └─ Contact support link
```

**Interaction**:
```
1. Load fails
2. Show error state
3. User clicks Retry
4. Attempt reload
5. On success: Replace error with content
6. On still fail: Show error message + support contact
```

---

## Accessibility Patterns

### Keyboard Navigation

**Tab Order** (logical flow):
```
1. Search input
2. Filter button
3. View toggle buttons
4. Sort dropdown
5. File list items (each item)
   - Row itself (focus indicator)
   - Share button within row
   - More menu button within row
6. Pagination buttons
```

**Common Keys**:
```
Tab:        Move forward through focusable elements
Shift+Tab:  Move backward
Enter:      Activate button/link, open modal
Escape:     Close modal/menu, unfocus
Space:      Toggle checkbox, activate button
Arrow ↑↓:   Navigate list, select option
```

---

### Focus States

**Visual Indicator**:
```
Outline:        2px solid Indigo-500
Outline-offset: 2px
Visible on:     All interactive elements
Color contrast: Pass WCAG AA (4.5:1+)
```

**Special cases**:
```
Buttons:        Ring around button
Inputs:         Ring around input + border color change
Links:          Ring + underline
List items:     Ring + background color
```

---

### Color & Contrast

**Text on background**:
```
Gray-900 on White:     21:1 contrast ✅ AAA
Gray-700 on White:     9:1 contrast ✅ AAA
Gray-600 on White:     7.1:1 contrast ✅ AA
Gray-500 on White:     4.5:1 contrast ✅ AA
Gray-400 on White:     2.6:1 contrast ❌ FAIL
```

**Rule**: Don't use Gray-400 for important text

**Status colors**:
```
Red (error):    Always pair with icon or text label
Green (success):Pair with icon (not color-only)
Yellow (warn):  Ensure 4.5:1 contrast with text
```

---

## Animation Patterns

### Fade In

**Usage**: Page load, content appear

```
Animation:  fadeIn 0.3s ease-in
Delay:      Stagger by 100ms per element
Element 1:  0ms
Element 2:  100ms
Element 3:  200ms
```

---

### Slide In

**Usage**: Sidebar open, drawer appear

```
Direction:  Left to right (sidebar)
Animation:  slideIn 0.3s ease-out
Transform:  translateX(-100%) to translateX(0)
Easing:     ease-out (faster start, slower end)
```

---

### Scale

**Usage**: Hover effects, emphasis

```
On hover:
  Transform:  scale(1.05)
  Duration:   0.2s
  Easing:     ease-out
  
On click:
  Transform:  scale(0.95)
  Duration:   0.1s
  Easing:     ease-in
```

---

### Spin

**Usage**: Loading indicator

```
Animation:  spin 1s linear infinite
Keyframes:
  0%:       rotate(0deg)
  100%:     rotate(360deg)
Speed:      Constant (linear)
Direction:  Clockwise
```

---

## Responsive Patterns

### Mobile Sidebar

**Desktop**: Always visible
**Mobile**: Hidden by default

```
1. Hamburger button (top-left)
2. Click → Sidebar slides in from left
3. Overlay dims content (click to close)
4. Navigate → Sidebar auto-closes
5. Sidebar width: 80vw (max 256px)
```

---

### Stacked Layout (Mobile)

**Typical pattern**:
```
Desktop:          Mobile:
┌─ Sidebar       ┌─ Header
├─ Content       ├─ Content
└─ Details       └─ (Details in modal)
```

**Mobile triggers**:
- File actions in menu (kebab icon)
- Details in modal
- Modals stack full-screen

---

### Touch Targets

**Minimum size**: 44×44px (was 40×40px)

**For mobile**:
- Buttons: 48×48px recommended
- Icons: 44×44px minimum
- Spacing between: 8px gap
- Hover states: Subtle, not critical (no hover on touch)

---

## Performance Patterns

### Lazy Loading

**Images**:
```
Use Intersection Observer
Load when 50px before viewport
Show placeholder while loading
Fade in when ready
```

**Modals**:
```
Only render when open
Close → Unmount from DOM
Reduces memory footprint
```

**Lists**:
```
Virtual scrolling for 100+ items
Render only visible items
Load on-demand at scroll
```

---

## Mobile-First Examples

### File Upload (Mobile)

```
Mobile:
1. Touch upload area
2. File picker opens
3. Select from camera roll
4. Shows preview
5. Tap upload
6. Progress inline (in list)

Desktop:
1. Click or drag-drop
2. Shows file names
3. Progress inline or in upload panel
4. Can queue multiple files
```

---

**Last Updated**: August 2026  
**Version**: 1.0
