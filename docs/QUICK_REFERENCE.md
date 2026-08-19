# CloudVault - Quick Reference

## 📋 Tech Stack Summary

```
Backend:
  Framework: Rails 8 (API mode)
  DB: PostgreSQL (ngrok local, later production)
  Cache: Redis (Sidekiq for background jobs)
  Storage: AWS S3 (file & image storage)
  Auth: JWT + OAuth2 (Google/GitHub)
  
Frontend:
  Framework: Vue 3 (Composition API)
  State: Pinia
  UI: Tailwind CSS + Headless UI
  HTTP: Axios
  Build: Vite
  
Dev Tools:
  Database: Docker Compose (PostgreSQL + Redis)
  Tunneling: ngrok (local to internet)
  Testing: RSpec (backend), Vitest (frontend)
  Deployment: Later (Phase 2)
```

---

## 🎯 Core Features Matrix

| Feature | Backend | Frontend | Comments |
|---------|---------|----------|----------|
| User Auth | JWT + OAuth2 | Login/Register UI | 15 min access token |
| Families | Model + API | Create/Invite UI | Email-based invites |
| File Upload | S3 + chunking | Dropzone UI | Progress tracking |
| File List | Paginated API | Table view | Sorting/filtering |
| Image Upload | S3 + thumbnails | Dropzone UI | Auto-thumbnail job |
| Image Gallery | API endpoint | Grid + lightbox | Lazy-load thumbnails |
| Sharing Links | SharedLink model | Modal UI | Time + password expiry |
| Permissions | PermissionChecker | Role badges | Viewer/Editor/Owner |
| Search | PostgreSQL FTS | Search bar | Files + images mixed |
| Versioning | FileVersion model | Version modal | Keep last 3 versions |
| Responsive | CORS headers | Mobile-first CSS | Desktop/Tablet/Mobile |

---

## 🗂️ Database Schema Quick View

```sql
Users (id, email, password_digest, storage_quota, storage_used)
Families (id, name, owner_id, family_storage_quota)
FamilyMembers (id, family_id, user_id, role)
  └─ Roles: 'owner', 'admin', 'editor', 'viewer'
  
Folders (id, user_id, parent_id, name)
Files (id, user_id, family_id, folder_id, name, mime_type, size, s3_key, file_type, visibility, thumbnail_s3_key)
  └─ file_type: 'file' | 'image'
  └─ visibility: 'private' | 'family' | 'shared_link'
  
FileVersions (id, file_id, version_number, s3_key)
  └─ Keep last 3 versions per file
  
SharedLinks (id, user_id, file_id, token, expires_at, password_digest)
FamilyInvitations (id, family_id, email, role, token, expires_at, accepted_at)
AuditLogs (id, user_id, file_id, action, ip_address, user_agent, metadata)
```

---

## 🚀 Week-by-Week Checklist

### Week 1: Foundation
- [ ] Rails API scaffold
- [ ] PostgreSQL + Redis (Docker Compose)
- [ ] User model + JWT auth
- [ ] OAuth2 setup (Google/GitHub)
- [ ] Vue 3 project scaffold
- [ ] Login/Register pages (UI only)
- [ ] ngrok setup for local tunneling
- **Goal**: Can login and get JWT token

### Week 2: Family Sharing
- [ ] Family model + schema
- [ ] FamilyMember model (roles)
- [ ] FamilyInvitation model
- [ ] Invite endpoints
- [ ] Family setup UI
- [ ] Invite family members UI
- **Goal**: Can create family and invite members by email

### Week 3: File Upload
- [ ] S3 configuration
- [ ] File model + schema
- [ ] FileUploader service
- [ ] Upload endpoint (multipart)
- [ ] File list endpoint (paginated)
- [ ] Download (presigned URL)
- [ ] File upload UI + progress
- [ ] File list component
- **Goal**: Can upload/download files

### Week 4: Images + Gallery
- [ ] Image processing (thumbnails)
- [ ] Image metadata extraction
- [ ] Gallery list endpoint
- [ ] Image gallery UI (grid)
- [ ] Lightbox modal
- [ ] Thumbnail lazy-loading
- [ ] Date-based grouping
- **Goal**: Can upload images and view in gallery

### Week 5: Versioning + Search
- [ ] FileVersion model
- [ ] Version endpoints
- [ ] Restore logic
- [ ] Search endpoint (FTS)
- [ ] Search UI
- [ ] File detail modal
- [ ] Trash/restore UI
- **Goal**: Can search files, view/restore versions

### Week 6: Sharing Links
- [ ] SharedLink model
- [ ] Share endpoints
- [ ] Public share view
- [ ] Share modal UI
- [ ] Copy link button
- [ ] Password protection
- [ ] Expiration dates
- **Goal**: Can create/revoke/expire share links

### Week 7: Permissions
- [ ] PermissionChecker service
- [ ] Row-level security tests
- [ ] Update visibility on files
- [ ] Role-based UI (show/hide edit)
- [ ] Permission error handling
- **Goal**: Only authorized users can access files

### Week 8: Polish + Responsive
- [ ] Mobile responsive design
- [ ] Hamburger menu
- [ ] Touch-friendly buttons
- [ ] Loading skeletons
- [ ] Error handling/retry
- [ ] Accessibility audit
- [ ] ARIA labels
- **Goal**: Works great on all devices

### Week 9: Testing + Security
- [ ] Unit tests (80%+ coverage)
- [ ] Integration tests
- [ ] Permission tests
- [ ] Rate limiting (Rack::Attack)
- [ ] Audit logging
- [ ] Security headers
- [ ] Input validation
- **Goal**: >80% coverage, security hardened

### Week 10: Docs + Demo
- [ ] README.md
- [ ] API documentation (Swagger)
- [ ] Security whitepaper
- [ ] Architecture diagrams
- [ ] Setup instructions
- [ ] Demo video
- [ ] GitHub Projects board
- **Goal**: Portfolio-ready

---

## 🔐 Security Checklist

- [ ] All endpoints require authentication (401 if missing)
- [ ] Row-level security (users only see own files)
- [ ] Family visibility enforced (members only)
- [ ] Rate limiting on auth endpoints (5 req/min)
- [ ] Rate limiting on API (100 req/min per user)
- [ ] S3 bucket private (no public ACL)
- [ ] File size limits (500MB per file, 256MB per user)
- [ ] Passwords hashed (bcrypt cost 12+)
- [ ] JWT tokens signed (RS256 asymmetric)
- [ ] Refresh tokens in httpOnly cookies (no XSS)
- [ ] HTTPS/TLS on all connections
- [ ] CORS restricted to known origins
- [ ] CSP headers set (Content-Security-Policy)
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (input sanitization)
- [ ] Audit logging (all file operations)
- [ ] Environment variables (no secrets in code)
- [ ] File upload validation (MIME type, magic bytes)

---

## 📊 API Endpoints Reference

### Auth
```
POST   /api/v1/auth/register          - Email/password signup
POST   /api/v1/auth/login             - Email/password login
POST   /api/v1/auth/oauth/google      - OAuth2 Google
POST   /api/v1/auth/refresh           - Refresh JWT token
POST   /api/v1/auth/logout            - Revoke session
```

### Files
```
POST   /api/v1/files/upload           - Upload file (multipart)
GET    /api/v1/files                  - List files (paginated)
GET    /api/v1/files/:id              - File metadata
GET    /api/v1/files/:id/download     - Presigned S3 URL
PATCH  /api/v1/files/:id              - Rename/move
DELETE /api/v1/files/:id              - Soft delete
POST   /api/v1/files/:id/restore      - Restore from trash
GET    /api/v1/files/:id/versions     - List versions
DELETE /api/v1/files/:id/versions/:num - Delete version
```

### Images
```
POST   /api/v1/images/upload          - Upload image
GET    /api/v1/images                 - Gallery list
GET    /api/v1/images/:id/thumbnail   - Thumbnail URL
```

### Families
```
POST   /api/v1/families               - Create family
GET    /api/v1/families/:id           - Get family
GET    /api/v1/families/:id/members   - List members
POST   /api/v1/families/:id/invite    - Send invite
PATCH  /api/v1/families/:id/members/:mid - Update role
DELETE /api/v1/families/:id/members/:mid - Remove member
```

### Sharing
```
POST   /api/v1/files/:id/shares       - Create share link
GET    /api/v1/shares/:token          - Access shared file (public)
PATCH  /api/v1/shares/:id             - Update expiration/password
DELETE /api/v1/shares/:id             - Revoke share
```

### Search
```
GET    /api/v1/search?q=term          - Full-text search
```

---

## 🎨 Vue 3 Component Tree

```
App.vue
├── RouterView
├── Navigation
│   ├── Logo
│   ├── SearchBar
│   └── UserMenu
│
└── MainView
    ├── Sidebar
    │   ├── FamilySelector
    │   ├── NavLinks
    │   │   ├── Files
    │   │   ├── Images
    │   │   ├── Shared
    │   │   └── Trash
    │   └── StorageIndicator
    │
    └── ContentArea
        ├── FilesView (or ImagesView)
        │   ├── Toolbar
        │   │   ├── ViewToggle (grid/list)
        │   │   ├── SortSelect
        │   │   └── FilterPanel
        │   │
        │   ├── FileUpload (dropzone)
        │   │
        │   └── FileList (or ImageGallery)
        │       └── FileItem (or ImageTile)
        │           ├── ContextMenu
        │           ├── ShareButton
        │           └── MoreActionsMenu
        │
        └── Modals
            ├── FileDetailModal
            │   ├── VersionSelector
            │   └── RestoreButton
            ├── ShareModal
            │   ├── LinkCopy
            │   ├── PasswordInput
            │   └── ExpirationPicker
            ├── FamilyInviteModal
            │   ├── EmailInput
            │   └── RoleSelector
            └── ConfirmDeleteModal
```

---

## 🛠️ Common Commands

### Backend (Rails)
```bash
# Setup
rails new backend --api --database=postgresql
cd backend
bundle install
rails db:create db:migrate

# Generate
rails generate model File name:string user:references
rails generate migration AddVisibilityToFiles visibility:string

# Run
bundle exec rails server -b 0.0.0.0
bundle exec sidekiq  # Background jobs
bundle exec rspec    # Tests

# Console
bundle exec rails console
```

### Frontend (Vue)
```bash
# Setup
npm create vite@latest frontend -- --template vue
cd frontend
npm install

# Run
npm run dev      # Dev server
npm run build    # Production build
npm run test     # Run tests

# Add packages
npm install pinia axios tailwindcss
```

### Docker
```bash
# Start services
docker-compose up

# View logs
docker-compose logs -f postgres

# Stop
docker-compose down
```

### ngrok Tunnel
```bash
# Install: brew install ngrok (macOS)

# Start tunnel (port 3000)
ngrok http 3000

# Output shows:
# Forwarding    https://abc123.ngrok.io -> http://localhost:3000
```

---

## 📈 Performance Targets

| Metric | Target | How to Measure |
|--------|--------|---|
| File upload | < 2 sec | Network tab in DevTools |
| File list load | < 500ms | API endpoint timing |
| Image gallery | < 1 sec | Page load time |
| Search response | < 300ms | API endpoint timing |
| API 99.9% uptime | < 5min downtime/month | Monitoring tool |
| Lighthouse score | > 90 | Lighthouse audit |
| Test coverage | > 80% | Simplecov report |

---

## 🚢 Deployment Roadmap

### Phase 1 (Now - Week 10)
- ✅ Local development only
- ✅ ngrok for testing sharing features
- ✅ GitHub repo with documentation

### Phase 2 (After MVP)
- Vercel for Vue frontend (free tier)
- DigitalOcean App Platform for Rails API ($20/month)
- AWS S3 bucket (production)

### Phase 3 (Future)
- Auto-scaling infrastructure
- CDN for images
- Multi-region redundancy

---

## 📚 Key Concepts to Master

1. **JWT Tokens**
   - Access token: Short-lived (15 min), stored in memory
   - Refresh token: Long-lived (7 days), stored in httpOnly cookie
   - Always send access token in Authorization header

2. **File Upload Flow**
   - Client: Send multipart form data in chunks
   - Backend: Validate, upload to S3, store metadata
   - Response: File ID + S3 key

3. **Family Sharing Model**
   - User creates family and invites via email
   - Invitee creates account (or logs in)
   - System creates FamilyMember record with role
   - Permissions checked on every file access

4. **Image Processing**
   - On upload: Generate thumbnail async (Sidekiq job)
   - Extract: Dimensions, EXIF, orientation
   - Store: Thumbnail on S3, metadata in DB

5. **Permission Checking**
   - Owner: Full access
   - Family member: Based on role (viewer/editor/owner)
   - Public link: Anyone with token

6. **Search Strategy**
   - PostgreSQL full-text search (good enough for MVP)
   - Index: file name, tags, metadata
   - Later: Elasticsearch for advanced features

---

## 🐛 Debugging Tips

### Rails
```ruby
# In console
rails c
user = User.first
user.files.count
file = user.files.first
file.update(visibility: 'family')

# Logs
tail -f log/development.log

# Database
rails db:drop db:create db:migrate db:seed
```

### Vue
```javascript
// Pinia DevTools (browser extension)
// Log store state: console.log($pinia)

// Network tab
// Check API calls, response times, errors

// Vue DevTools (browser extension)
// Inspect component props, events, lifecycle
```

### S3
```bash
# List uploaded files
aws s3 ls s3://my-bucket/files/

# Check file size
aws s3 ls s3://my-bucket/files/file-id/

# Delete test files
aws s3 rm s3://my-bucket/files/test-file
```

---

## 📞 Common Issues & Fixes

| Issue | Solution |
|-------|----------|
| CORS error | Update ngrok URL in `config/initializers/cors.rb` |
| S3 upload fails | Check AWS credentials, bucket name, region |
| JWT expired | Frontend should refresh token automatically |
| Thumbnail not generated | Check Sidekiq is running: `bundle exec sidekiq` |
| Database locked | `rails db:drop db:create db:migrate` |
| ngrok URL changed | Restart ngrok, update CORS config |
| Out of storage | Truncate old files: `File.where('created_at < ?', 30.days.ago).destroy_all` |

---

## 💾 Backup Checklist Before Submitting

- [ ] All tests passing (`bundle exec rspec`, `npm run test`)
- [ ] No console errors (check DevTools)
- [ ] No linting warnings (RuboCop, ESLint)
- [ ] Environment variables in .env (not in code)
- [ ] GitHub repo public with good README
- [ ] Live demo working (ngrok + local servers running)
- [ ] Commit message history clean
- [ ] No secrets in .git history
- [ ] README includes: Features, Tech Stack, How to Run
- [ ] Screenshots/GIFs in README

---

## 📝 Portfolio Talking Points

When interviewing, emphasize:

1. **Architecture**
   - Clear separation: API + Frontend
   - Scalable from single-server → microservices
   - Authentication & authorization patterns

2. **Family Sharing Model**
   - Row-level security
   - Role-based access control
   - Permission checking on every request

3. **Full-Stack**
   - Backend: Rails, PostgreSQL, S3, Sidekiq
   - Frontend: Vue 3, Pinia, Tailwind
   - DevOps: Docker, CI/CD ready

4. **Performance**
   - Optimized queries (indexes, includes)
   - Lazy-loading images
   - Presigned S3 URLs

5. **Security**
   - JWT tokens with refresh rotation
   - HTTPS/TLS
   - Input validation
   - Audit logging

6. **Code Quality**
   - 80%+ test coverage
   - Clean code patterns
   - Well-documented APIs

---

**Keep this handy as your reference while building! 🚀**
