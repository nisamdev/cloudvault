# CloudVault Phase 1 - Implementation Guide
## Web App with Family Sharing (Files + Images)

---

## 🎯 Phase 1 Scope (8-10 Weeks)

### What You're Building
```
┌─────────────────────────────────────────┐
│        CloudVault Web App                │
│  (Responsive: Desktop, Tablet, Mobile)  │
├─────────────────────────────────────────┤
│  ▪ User Auth (email/password + OAuth2)  │
│  ▪ Files Section (PDFs, docs, etc)      │
│  ▪ Images Section (photos, gallery)     │
│  ▪ Family Sharing (invite family)       │
│  ▪ Shareable Public Links               │
│  ▪ File Versioning (keep last 3)        │
│  ▪ Search & Tagging                     │
│  ▪ Responsive Design                    │
│  ▪ Local dev via ngrok/localtunnel      │
└─────────────────────────────────────────┘
```

### What You're NOT Building (Phase 1)
- ❌ Mobile native apps (Phase 2: React Native)
- ❌ Real-time collaboration/editing
- ❌ Document editing
- ❌ Advanced OCR/AI
- ❌ Production deployment (use ngrok locally)

---

## 📁 Project Structure

```
cloudvault/
├── backend/                    # Rails API
│   ├── app/
│   │   ├── models/
│   │   │   ├── user.rb
│   │   │   ├── family.rb
│   │   │   ├── family_member.rb
│   │   │   ├── folder.rb
│   │   │   ├── file.rb
│   │   │   ├── shared_link.rb
│   │   │   └── audit_log.rb
│   │   ├── controllers/
│   │   │   └── api/v1/
│   │   │       ├── auth_controller.rb
│   │   │       ├── files_controller.rb
│   │   │       ├── images_controller.rb
│   │   │       ├── families_controller.rb
│   │   │       ├── folders_controller.rb
│   │   │       └── shares_controller.rb
│   │   ├── services/
│   │   │   ├── file_uploader.rb
│   │   │   ├── image_processor.rb
│   │   │   ├── permission_checker.rb
│   │   │   └── family_inviter.rb
│   │   └── jobs/
│   │       ├── process_image_job.rb
│   │       ├── generate_thumbnail_job.rb
│   │       └── clean_trash_job.rb
│   ├── config/
│   │   ├── database.yml
│   │   ├── storage.yml
│   │   └── initializers/
│   │       ├── cors.rb
│   │       ├── jwt.rb
│   │       └── sidekiq.rb
│   ├── db/
│   │   ├── migrate/
│   │   └── seeds.rb
│   ├── Gemfile
│   └── docker-compose.yml
│
├── frontend/                   # Vue 3 SPA
│   ├── src/
│   │   ├── components/
│   │   │   ├── FileSection.vue
│   │   │   ├── ImageGallery.vue
│   │   │   ├── FileUpload.vue
│   │   │   ├── FamilySharing.vue
│   │   │   ├── FamilyMembers.vue
│   │   │   └── SharedLink.vue
│   │   ├── views/
│   │   │   ├── LoginView.vue
│   │   │   ├── DashboardView.vue
│   │   │   ├── FilesView.vue
│   │   │   ├── ImagesView.vue
│   │   │   ├── SettingsView.vue
│   │   │   └── SharedView.vue (public share)
│   │   ├── stores/
│   │   │   ├── auth.js
│   │   │   ├── files.js
│   │   │   ├── family.js
│   │   │   └── ui.js
│   │   ├── api/
│   │   │   └── client.js
│   │   ├── utils/
│   │   │   ├── auth.js
│   │   │   ├── permissions.js
│   │   │   └── formatting.js
│   │   ├── App.vue
│   │   └── main.js
│   ├── public/
│   ├── package.json
│   ├── vite.config.js
│   └── tailwind.config.js
│
└── README.md
```

---

## 🚀 Week-by-Week Timeline

### Week 1: Foundation & Auth
**Backend**
- [ ] Create Rails app: `rails new backend --api --database=postgresql`
- [ ] User model with bcrypt
- [ ] JWT authentication (gem: `jwt`)
- [ ] OAuth2 setup (Google/GitHub with gem: `omniauth-oauth2`)
- [ ] Database schema (users, sessions)
- [ ] Seed data (1 test user)

**Frontend**
- [ ] Create Vue 3 project: `npm create vite@latest frontend -- --template vue`
- [ ] Setup Pinia (state management)
- [ ] Setup Tailwind CSS
- [ ] Login/Register pages (no backend integration yet)
- [ ] Auth store (token management)

**Dev Setup**
- [ ] Docker Compose (PostgreSQL + Redis locally)
- [ ] Setup ngrok for local tunneling: `ngrok http 3000`
- [ ] CORS configuration

**Goals**: Can register user, login, get JWT token

---

### Week 2: Family Sharing Foundation
**Backend**
- [ ] Family model & schema
- [ ] FamilyMember model (roles: owner, admin, editor, viewer)
- [ ] FamilyInvitation model (email-based invites)
- [ ] Endpoints:
  - `POST /api/v1/families` - Create family
  - `GET /api/v1/families/:id` - Get family
  - `POST /api/v1/families/:id/invite` - Send invite
  - `POST /api/v1/families/invitations/:token/accept` - Accept invite

**Frontend**
- [ ] Family setup wizard (after first login)
- [ ] Invite family members form
- [ ] Family members list view
- [ ] Role badge/indicator

**Testing**
- [ ] Test invite flow (email capture)
- [ ] Test role assignment

**Goals**: User can create family, invite family members

---

### Week 3: File Upload & S3 Integration
**Backend**
- [ ] S3 configuration (AWS SDK gem)
- [ ] File model & schema
- [ ] Folder model (recursive structure)
- [ ] FileUploader service (chunked uploads)
- [ ] Endpoints:
  - `POST /api/v1/files/upload` - Upload file (multipart)
  - `GET /api/v1/files` - List files (paginated)
  - `GET /api/v1/files/:id` - File metadata
  - `GET /api/v1/files/:id/download` - Presigned S3 URL
  - `DELETE /api/v1/files/:id` - Soft delete

**Frontend**
- [ ] File upload UI (dropzone + progress)
- [ ] File list component
- [ ] Folder navigation
- [ ] Download link
- [ ] Permissions-based UI (show/hide based on role)

**Background Jobs**
- [ ] Sidekiq job for file indexing (metadata)

**Goals**: Can upload files, see in list, download them

---

### Week 4: Image Management + Gallery
**Backend**
- [ ] Image processing (gem: `image_processing`, `ruby-vips`)
- [ ] Generate thumbnails on upload
- [ ] Store image metadata (dimensions, EXIF)
- [ ] Endpoints:
  - `POST /api/v1/images/upload` - Upload image
  - `GET /api/v1/images` - Gallery list (sorted by date desc)
  - `GET /api/v1/images/:id/thumbnail` - Get thumbnail (S3 presigned)

**Frontend**
- [ ] Image gallery grid view
- [ ] Lightbox preview (click to zoom)
- [ ] Lazy-load thumbnails (Intersection Observer)
- [ ] Image upload dropzone (auto-detect image MIME type)
- [ ] Date-based grouping (Today, Yesterday, Last Week)

**Background Jobs**
- [ ] Thumbnail generation job (async, Sidekiq)
- [ ] EXIF metadata extraction

**Goals**: Can upload images, see gallery, preview with lightbox

---

### Week 5: File Versioning & Search
**Backend**
- [ ] FileVersion model & schema
- [ ] Store up to 3 versions per file
- [ ] Endpoints:
  - `GET /api/v1/files/:id/versions` - List versions
  - `GET /api/v1/files/:id/versions/:num/download` - Download version
  - `DELETE /api/v1/files/:id/versions/:num` - Delete old version
  - `POST /api/v1/files/:id/restore` - Restore version
- [ ] Search endpoint:
  - `GET /api/v1/search?q=term` - Full-text search (files + images)

**Frontend**
- [ ] Search bar (top navigation)
- [ ] Search results (files + images mixed)
- [ ] File detail modal (show versions, restore options)
- [ ] Trash/restore UI

**Database**
- [ ] PostgreSQL FTS (full-text search) index

**Goals**: Can search files, see versions, restore old versions

---

### Week 6: Sharing Links & Permissions
**Backend**
- [ ] SharedLink model & schema
- [ ] Endpoints:
  - `POST /api/v1/files/:id/shares` - Create share link
  - `GET /api/v1/shares/:token` - Access shared file (public)
  - `PATCH /api/v1/shares/:id` - Update expiration/password
  - `DELETE /api/v1/shares/:id` - Revoke share
- [ ] Permission checker service (row-level security)

**Frontend**
- [ ] Share button on files/images
- [ ] Share link modal (copy, expiration, password)
- [ ] Public share view (no login needed)
- [ ] Family-visible toggle (all family members vs. just me)

**Goals**: Can create public share links, revoke shares, set expiration

---

### Week 7: Family Permissions & Access Control
**Backend**
- [ ] PermissionChecker service:
  - `can_view_file?(user, file)`
  - `can_edit_file?(user, file)`
  - `can_share_file?(user, file)`
- [ ] Visibility model for files (private, family, shared_link)
- [ ] Update file endpoints to check permissions
- [ ] Family-scoped queries

**Frontend**
- [ ] Role-based UI (editor/viewer distinction)
- [ ] Show/hide edit/delete buttons based on role
- [ ] Family privacy indicator ("Only you" vs "Shared with family")

**Database**
- [ ] Add `visibility` column to files
- [ ] Add `family_id` to files

**Goals**: Only family members can access family files, role-based permissions work

---

### Week 8: Polish & Responsive Design
**Frontend**
- [ ] Responsive design audit
  - Mobile: Stack layout, touch-friendly buttons
  - Tablet: 2-column layout
  - Desktop: Full 3-column (sidebar, main, detail)
- [ ] Mobile menu (hamburger)
- [ ] Touch-optimized file actions (swipe, long-press)
- [ ] Loading states & skeletons
- [ ] Error handling & retry logic

**Accessibility**
- [ ] ARIA labels
- [ ] Keyboard navigation
- [ ] Color contrast checks
- [ ] Screen reader testing

**Goals**: Works great on all devices, accessible

---

### Week 9: Testing & Security
**Backend**
- [ ] Unit tests (models, services)
- [ ] Integration tests (API endpoints)
- [ ] Permission tests (row-level security)
- [ ] Rate limiting (Rack::Attack)
- [ ] Audit logging (all file operations)
- [ ] HTTPS/TLS setup
- [ ] Input validation & sanitization

**Frontend**
- [ ] Component tests (Vue Test Utils)
- [ ] Pinia store tests
- [ ] API integration tests (mock backend)
- [ ] Security: CSP headers, XSS prevention

**Code Quality**
- [ ] RuboCop (Rails linting)
- [ ] ESLint (Vue linting)
- [ ] Test coverage: Target 80%+

**Goals**: >80% test coverage, security checklist complete

---

### Week 10: Documentation & Demo
**Documentation**
- [ ] README.md (features, tech stack, setup)
- [ ] API documentation (Swagger/OpenAPI)
- [ ] Security whitepaper (encryption, permissions model)
- [ ] Architecture diagram (improved)
- [ ] Setup instructions (local dev + ngrok)

**Demo**
- [ ] Record video walkthrough
- [ ] Create sample family (test users)
- [ ] Show file upload flow
- [ ] Show family sharing
- [ ] Show image gallery

**Portfolio Prep**
- [ ] GitHub repo (public, well-organized)
- [ ] Deploy frontend to Vercel (free, easy)
- [ ] Leave backend on local ngrok for now (mention this is Phase 2)
- [ ] Create GitHub Projects board showing progress

**Goals**: Portfolio-ready, can be demoed in interviews

---

## 💻 Development Setup (Week 1)

### Backend Setup
```bash
# Create Rails app
rails new cloudvault-backend --api --database=postgresql --skip-bundle

cd cloudvault-backend

# Add gems
bundle add devise jwt omniauth-oauth2 google-oauth2 active_storage-s3
bundle add sidekiq redis rack-cors rack-attack
bundle add rspec-rails factory_bot faker --group development, test

# Create database
rails db:create

# Generate models
rails generate model User email:string password_digest:string oauth_provider:string oauth_id:string
rails generate model Family name:string owner:references
rails generate model FamilyMember family:references user:references role:string

# Run migrations
rails db:migrate

# Start server
bundle exec rails server -b 0.0.0.0

# In another terminal, start ngrok
ngrok http 3000

# Note the ngrok URL, add to CORS config
```

### Frontend Setup
```bash
# Create Vue 3 project
npm create vite@latest cloudvault-frontend -- --template vue
cd cloudvault-frontend

# Install dependencies
npm install
npm install -D tailwindcss postcss autoprefixer
npm install pinia axios

# Initialize Tailwind
npx tailwindcss init -p

# Create .env for API URL
echo "VITE_API_URL=http://localhost:3000" > .env.local
echo "VITE_API_URL=https://{ngrok_url}" > .env.production

# Start dev server
npm run dev

# Access at http://localhost:5173
```

### Docker Compose
```yaml
# docker-compose.yml (place in backend directory)
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: cloudvault_dev
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
```

**Start local DB:**
```bash
docker-compose up -d
```

---

## 🔑 Key Implementation Details

### JWT Token Flow
```ruby
# User logs in
POST /api/v1/auth/login
  email: "user@example.com"
  password: "password123"

# Response
{
  access_token: "eyJhbGc...",  # Valid 15 min, store in memory
  refresh_token: "eyJhbGc...", # Valid 7 days, httpOnly cookie
  user: { id, email, name }
}

# For API calls, send:
Authorization: Bearer {access_token}

# When expired, refresh:
POST /api/v1/auth/refresh
  refresh_token: "{refresh_token}"
```

### Family Sharing Flow
```
1. User creates family "Smith Family"
   Family.create(name: "Smith Family", owner_id: current_user.id)

2. User invites family members (email: wife@example.com, role: editor)
   FamilyInvitation.create(family_id: family.id, email: "wife@example.com", role: "editor")
   → Send email with accept link: /families/invitations/{token}/accept

3. Family member clicks link, creates account (or logs in)
   FamilyInvitation.accept → FamilyMember.create(user_id: ..., family_id: ..., role: "editor")

4. When user uploads file, can choose:
   - Private (only me)
   - Family (all family members with their roles)
   - Shared Link (public, anyone with link)

5. When family member accesses, permission checker validates:
   - Is user in family? → can view
   - Is user editor/owner? → can edit/delete
   - Is user viewer? → read-only
```

### Image Upload & Thumbnail Generation
```ruby
# File Upload (app/services/file_uploader.rb)
class FileUploader
  def upload(params)
    file = params[:file]
    
    # Validate
    validate_file_size(file)
    validate_mime_type(file)
    
    # Upload to S3
    s3_key = "files/#{SecureRandom.uuid}/#{file.original_filename}"
    s3_client.put_object(bucket: ENV['S3_BUCKET'], key: s3_key, body: file.read)
    
    # Create DB record
    db_file = File.create!(
      user_id: current_user.id,
      family_id: current_family.id,
      name: file.original_filename,
      mime_type: file.content_type,
      size: file.size,
      s3_key: s3_key,
      file_type: 'file'
    )
    
    # If image, queue thumbnail generation
    ProcessImageJob.perform_later(db_file.id) if file.content_type.start_with?('image/')
    
    db_file
  end
end

# Image Processing (app/jobs/process_image_job.rb)
class ProcessImageJob
  include Sidekiq::Job
  
  def perform(file_id)
    file = File.find(file_id)
    image = ImageProcessing::Vips.source(file.s3_key)
    
    # Generate thumbnail (300x300)
    thumb = image.resize_to_limit(300, 300)
    thumb_key = "thumbnails/#{file.id}.jpg"
    s3_client.put_object(bucket: ENV['S3_BUCKET'], key: thumb_key, body: thumb)
    
    # Extract dimensions & EXIF
    metadata = image.metadata
    file.update!(
      image_width: metadata[:width],
      image_height: metadata[:height],
      image_orientation: metadata[:orientation],
      thumbnail_s3_key: thumb_key
    )
  end
end
```

### Permission Checking
```ruby
# app/services/permission_checker.rb
class PermissionChecker
  def self.can_view?(user, file)
    return true if file.user_id == user.id  # Owner
    
    if file.visibility == 'private'
      false
    elsif file.visibility == 'family'
      family_member?(user, file.family_id)
    elsif file.visibility == 'shared_link'
      true  # Anyone with link
    else
      false
    end
  end
  
  def self.can_edit?(user, file)
    return true if file.user_id == user.id
    
    return false unless file.visibility == 'family'
    
    family_member_with_role?(user, file.family_id, ['editor', 'admin', 'owner'])
  end
  
  private
  
  def self.family_member?(user, family_id)
    FamilyMember.exists?(family_id: family_id, user_id: user.id)
  end
  
  def self.family_member_with_role?(user, family_id, roles)
    FamilyMember.exists?(
      family_id: family_id, 
      user_id: user.id, 
      role: roles
    )
  end
end

# Usage in controller
class FilesController
  before_action :authorize_file_access
  
  def authorize_file_access
    @file = File.find(params[:id])
    unless PermissionChecker.can_view?(current_user, @file)
      render json: { error: "Unauthorized" }, status: :forbidden
    end
  end
end
```

---

## 🎨 Frontend Structure (Vue 3 + Pinia)

### Auth Store (src/stores/auth.js)
```javascript
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '@/api/client'

export const useAuthStore = defineStore('auth', () => {
  const user = ref(null)
  const accessToken = ref(localStorage.getItem('accessToken'))
  const isAuthenticated = computed(() => !!user.value)
  
  async function login(email, password) {
    const response = await api.post('/auth/login', { email, password })
    accessToken.value = response.data.access_token
    user.value = response.data.user
    localStorage.setItem('accessToken', response.data.access_token)
  }
  
  async function logout() {
    await api.post('/auth/logout')
    user.value = null
    accessToken.value = null
    localStorage.removeItem('accessToken')
  }
  
  return { user, accessToken, isAuthenticated, login, logout }
})
```

### Files Store (src/stores/files.js)
```javascript
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '@/api/client'

export const useFilesStore = defineStore('files', () => {
  const files = ref([])
  const currentFolderId = ref(null)
  const loading = ref(false)
  
  async function fetchFiles(folderId = null) {
    loading.value = true
    try {
      const response = await api.get('/files', {
        params: { folder_id: folderId, file_type: 'file' }
      })
      files.value = response.data.files
    } finally {
      loading.value = false
    }
  }
  
  async function uploadFile(file, folderId = null) {
    const formData = new FormData()
    formData.append('file', file)
    if (folderId) formData.append('folder_id', folderId)
    
    return api.post('/files/upload', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      onUploadProgress: (event) => {
        const progress = Math.round((event.loaded * 100) / event.total)
        // Emit progress event
      }
    })
  }
  
  return { files, loading, fetchFiles, uploadFile }
})
```

### FileUpload Component (src/components/FileUpload.vue)
```vue
<template>
  <div class="file-upload">
    <div 
      @drop="handleDrop"
      @dragover.prevent="isDragging = true"
      @dragleave="isDragging = false"
      :class="['dropzone', { dragging: isDragging }]"
    >
      <input
        type="file"
        ref="fileInput"
        @change="handleFileSelect"
        multiple
        style="display: none"
      />
      <button @click="$refs.fileInput.click()">
        Click to upload or drag files
      </button>
    </div>
    
    <div v-if="uploadProgress" class="progress">
      <div class="progress-bar" :style="{ width: uploadProgress + '%' }"></div>
      <span>{{ uploadProgress }}%</span>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useFilesStore } from '@/stores/files'

const filesStore = useFilesStore()
const isDragging = ref(false)
const uploadProgress = ref(null)
const fileInput = ref(null)

async function handleFileSelect(event) {
  const files = event.target.files
  for (let file of files) {
    await filesStore.uploadFile(file)
  }
}

function handleDrop(event) {
  event.preventDefault()
  isDragging.value = false
  const files = event.dataTransfer.files
  fileInput.value.files = files
  handleFileSelect({ target: fileInput.value })
}
</script>

<style scoped>
.dropzone {
  border: 2px dashed #cbd5e0;
  border-radius: 8px;
  padding: 40px;
  text-align: center;
  transition: all 0.3s;
}

.dropzone.dragging {
  border-color: #4f46e5;
  background-color: #eef2ff;
}
</style>
```

### ImageGallery Component (src/components/ImageGallery.vue)
```vue
<template>
  <div class="gallery">
    <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-2">
      <div 
        v-for="image in images"
        :key="image.id"
        class="image-tile"
        @click="selectedImage = image"
      >
        <img :src="image.thumbnailUrl" :alt="image.name" />
        <div class="overlay">
          <span>{{ image.name }}</span>
        </div>
      </div>
    </div>
    
    <!-- Lightbox Modal -->
    <Transition name="fade">
      <div v-if="selectedImage" class="lightbox" @click="selectedImage = null">
        <div class="lightbox-content" @click.stop>
          <button @click="selectedImage = null" class="close">×</button>
          <img :src="selectedImage.imageUrl" :alt="selectedImage.name" />
          <div class="lightbox-info">
            <h3>{{ selectedImage.name }}</h3>
            <p>{{ formatFileSize(selectedImage.size) }}</p>
            <p>{{ formatDate(selectedImage.createdAt) }}</p>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useImagesStore } from '@/stores/images'

const imagesStore = useImagesStore()
const selectedImage = ref(null)

onMounted(() => {
  imagesStore.fetchImages()
})

const images = computed(() => imagesStore.images)
</script>

<style scoped>
.gallery {
  padding: 20px;
}

.image-tile {
  position: relative;
  overflow: hidden;
  border-radius: 8px;
  cursor: pointer;
}

.image-tile img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  transition: transform 0.3s;
}

.image-tile:hover img {
  transform: scale(1.1);
}

.overlay {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: flex-end;
  padding: 10px;
  color: white;
  font-size: 12px;
  opacity: 0;
  transition: opacity 0.3s;
}

.image-tile:hover .overlay {
  opacity: 1;
}

.lightbox {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.8);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.lightbox-content {
  position: relative;
  max-width: 80vw;
  max-height: 90vh;
}

.lightbox-content img {
  max-width: 100%;
  max-height: 100%;
}

.close {
  position: absolute;
  top: 10px;
  right: 10px;
  background: none;
  border: none;
  color: white;
  font-size: 32px;
  cursor: pointer;
}

.fade-enter-active, .fade-leave-active {
  transition: opacity 0.3s;
}

.fade-enter-from, .fade-leave-to {
  opacity: 0;
}
</style>
```

---

## 📊 Database Migrations Reference

```ruby
# db/migrate/[timestamp]_create_users.rb
class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :email, null: false, index: { unique: true }
      t.string :password_digest
      t.string :full_name
      t.string :avatar_url
      t.bigint :storage_quota, default: 268435456  # 256MB
      t.bigint :storage_used, default: 0
      t.string :oauth_provider
      t.string :oauth_id
      t.boolean :two_factor_enabled, default: false
      t.string :two_factor_secret
      t.string :timezone, default: 'UTC'
      t.timestamps
    end
  end
end

# db/migrate/[timestamp]_create_families.rb
class CreateFamilies < ActiveRecord::Migration[7.1]
  def change
    create_table :families do |t|
      t.string :name, null: false
      t.text :description
      t.references :user, foreign_key: { to_table: :users }, null: false
      t.bigint :family_storage_quota, default: 2147483648  # 2GB
      t.bigint :family_storage_used, default: 0
      t.timestamps
    end
    add_index :families, [:user_id, :created_at]
  end
end

# db/migrate/[timestamp]_create_family_members.rb
class CreateFamilyMembers < ActiveRecord::Migration[7.1]
  def change
    create_table :family_members do |t|
      t.references :family, foreign_key: true, null: false
      t.references :user, foreign_key: true, null: false
      t.string :role, null: false  # owner, admin, editor, viewer
      t.datetime :joined_at
      t.timestamps
    end
    add_index :family_members, [:family_id, :user_id], unique: true
  end
end

# db/migrate/[timestamp]_create_files.rb
class CreateFiles < ActiveRecord::Migration[7.1]
  def change
    create_table :files do |t|
      t.references :user, foreign_key: true, null: false
      t.references :family, foreign_key: true
      t.references :folder, foreign_key: true
      t.string :name, null: false
      t.string :mime_type, null: false
      t.bigint :size, null: false
      t.string :s3_key, null: false
      t.string :file_type, null: false  # 'file' or 'image'
      t.string :file_hash
      
      # Image-specific
      t.integer :image_width
      t.integer :image_height
      t.integer :image_orientation
      t.string :thumbnail_s3_key
      
      # Access control
      t.string :visibility, default: 'private'
      t.datetime :trashed_at
      
      t.timestamps
    end
    add_index :files, [:user_id, :created_at]
    add_index :files, [:user_id, :trashed_at]
    add_index :files, [:family_id, :created_at]
    add_index :files, [:file_type, :created_at]
  end
end
```

---

## 🚢 Local Dev Setup with ngrok

### Start Everything
```bash
# Terminal 1: PostgreSQL + Redis
cd backend
docker-compose up

# Terminal 2: Rails API
cd backend
bundle install
rails db:create db:migrate db:seed
bundle exec rails server -b 0.0.0.0 -p 3000

# Terminal 3: ngrok tunnel
ngrok http 3000
# Note the URL: https://abc123.ngrok.io

# Terminal 4: Vue frontend
cd frontend
echo "VITE_API_URL=https://abc123.ngrok.io" > .env.local
npm run dev
# Access at http://localhost:5173
```

### Update CORS for ngrok
```ruby
# backend/config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'localhost:5173', 'abc123.ngrok.io'  # Add ngrok URL
    resource '*', headers: :any, methods: [:get, :post, :patch, :delete, :put]
  end
end
```

---

## 📈 MVP Success Criteria

- [ ] ✅ Users can register/login
- [ ] ✅ Family creation & member invites work
- [ ] ✅ File upload/download works
- [ ] ✅ Image gallery displays with thumbnails
- [ ] ✅ Sharing links can be created & revoked
- [ ] ✅ File permissions respected (only family can see)
- [ ] ✅ Search finds files + images
- [ ] ✅ Responsive design (mobile-friendly)
- [ ] ✅ >80% test coverage
- [ ] ✅ GitHub repo with documentation
- [ ] ✅ Can demo locally with ngrok

**Estimated Timeline**: 8-10 weeks (working 20-30 hrs/week)

---

## Phase 2: React Native Mobile App

Once Phase 1 is complete, build React Native Expo app with:
- Offline-first architecture (local DB sync)
- Native camera integration
- Push notifications
- Same family sharing model
- Shared code patterns

---

**Ready to start? Begin with Week 1: Foundation & Auth** 🚀
