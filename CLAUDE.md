# CLAUDE.md

Guidance for Claude Code when working with the Quote Me codebase.

## Project Overview

"Quote Me" is an enterprise-grade quote management system:
- **AWS Backend**: Serverless API with dual authentication (API Key for public, JWT for admin)
- **Flutter Apps**: Cross-platform mobile/web with professional indigo theme
- **Admin System**: Full CRUD, search, import/export, and tag management
- **Web Infrastructure**: Automated CloudFront/S3 deployment with SSL

## Development Commands

### AWS Deployment
```bash
cd aws
./deploy.sh    # ALWAYS use this for consistent deployments
```
✅ Uses `aws/template-quote-me.yaml` as single source of truth
✅ Handles OpenAI API key injection securely
✅ **Identity Providers**: Google and Apple Sign In configured via `configure_identity_providers.sh` script
✅ **Push Notifications**: Automatically detects and deploys FCM service account JSON
✅ **One-Click Deployment**: Single script handles all scenarios (FCM optional)
✅ **"Scorched Earth" Ready**: Complete rebuild from scratch with consistent configuration

#### Identity Provider Configuration
```bash
# Configure identity providers (runs automatically during deployment)
./configure_identity_providers.sh 4    # Configure all (Google + Apple + OAuth flows)

# Individual configuration options:
./configure_identity_providers.sh 1    # Google only
./configure_identity_providers.sh 2    # Apple only
./configure_identity_providers.sh 3    # Update OAuth flows
./configure_identity_providers.sh 5    # Show current config
```
✅ **Avoids CloudFormation Issues**: Identity providers configured outside CFN (resolves multi-line private key problems)
✅ **OAuth Flows**: Automatically configures callback URLs, scopes, and flows
✅ **Environment Integration**: Uses `.env.deployment` for credentials

#### Standalone Apple Sign In Deployment
```bash
# For new apps - deploy only Apple Sign In infrastructure
./deploy_apple_signin.sh
```
✅ Minimal template (`template_sign_in_with_apple.yaml`)  
✅ One-click deployment with `.env.apple` configuration  
✅ Outputs ready-to-use Amplify configuration

**✅ DEPLOYMENT STATUS**
- Database: `quote-me-quotes` with 2,330+ quotes, 367 tags
- Performance: Fast DynamoDB queries with pagination support
- Domain: `https://quote-me.anystupididea.com` (web app) / `https://dcc.anystupididea.com` (API)
- **Federated Auth**: Google and Apple Sign In fully operational
- **OAuth Configuration**: All callback URLs, flows, and scopes properly configured
- All endpoints operational with JWT auth for admin

### API Testing
```bash
# Public API tests (API Key required)
./tests/test_api.sh

# Admin API tests (auto-creates temp admin user)
./tests/test_admin_api.sh
python3 tests/test_tag_cleanup.py
python3 tests/test_tag_editor.py

# Duplicate Detection Tests
./tests/test_duplicate_detection.sh

# Subscription & Daily Nuggets Tests
python3 tests/test_subscription_sync.py
python3 tests/test_rob_subscription.py
python3 tests/test_daily_nuggets_tags.py   # Per-subscriber tag filter (live)
```

### Flutter Development
```bash
cd dcc_mobile
flutter pub get
flutter run       # iOS/Android
flutter build web --release  # Web
```

### Web Deployment
```bash
./deploy-web.sh [domain]  # Full deployment with SSL/CDN
```

## Architecture

### Backend (`aws/`)
- **Infrastructure**: SAM template with API Gateway, Lambda, DynamoDB, Cognito
- **Authentication**: Dual-layer (API Key for public, JWT for admin) + Federated (Google, Apple Sign In)
- **Lambda Functions**:
  - `quote_handler.py`: Public API with tag filtering via DynamoDB scan, limit up to 1000
  - `admin_handler.py`: CRUD with tag management and data integrity, limit up to 1000
  - `auth_handler.py`: User registration/verification
  - `options_handler.py`: CORS support
  - `openai_handler.py`: Secure GPT-4o-mini proxy for tag generation
  - `candidate_quotes_handler.py`: Admin-only AI quote finding by author (configurable 1-20 limit)
  - `candidate_quotes_by_topic_handler.py`: Admin-only AI quote finding by topic (configurable 1-20 limit)
  - `favorites_handler.py`: User favorites management with JWT authentication
  - `daily_nuggets_handler.py`: Subscription management, scheduled email delivery, and push notifications
- **Performance**: Fast DynamoDB queries with filter expressions and pagination
- **Security**: Rate limiting (public only), email verification, role-based access
- **Email Delivery**: AWS SES for Daily Nuggets, EventBridge for scheduling
- **Push Notifications**: Firebase Cloud Messaging (FCM) v1 API with JWT authentication


### Flutter App (`dcc_mobile/`)
- **Platforms**: iOS, Android, Web (https://quote-me.anystupididea.com)
- **Key Screens**:
  - `quote_screen.dart`: Main app with About dialog, unified auth menu, heart favorites
  - `settings_screen.dart`: Theme selector, voice controls, tag preferences
  - `admin_dashboard_screen.dart`: Full CRUD, search, import/export, AI tag recommendations, AI quote finding
  - `tags_editor_screen.dart`: Individual tag management
  - `user_profile_screen.dart`: Profile management, Daily Nuggets subscription
  - `favorites_screen.dart`: Personal favorites collection with native share icons
  - `daily_nuggets_admin_screen.dart`: Admin view for managing subscribers
- **Authentication**: AWS Amplify Cognito with JWT management + Federated (Google, Apple Sign In)
- **Theme System**: Light/Dark/System modes with persistent preferences
- **Audio**: TTS with 20-50+ voices, rate/pitch controls (default: OFF)
### Key Features
- **About Dialog**: Responsive dialog with app info, accessible to all users
- **Quote Retrieval Limit**: User-configurable limit (50-1000) for quote fetching
- **AI Tag Generation**: GPT-4o-mini via secure Lambda proxy with "Recommend Tags" feature
- **Favorites System**: Heart icons throughout app, personal favorites collection
- **Daily Nuggets**: Email subscriptions with timezone-aware delivery at 8 AM daily + deep link management
- **Push Notifications**: Cross-platform FCM integration with user permission management and test notifications
- **Import/Export**: TSV import, multi-format export (JSON/CSV)
- **Duplicate Detection**: Server-side prevention at quote creation with fuzzy matching
- **Search**: Universal search across quotes, authors, tags
- **Sorting**: 4-field sorting with persistent preferences
- **Progress Tracking**: Real-time status for batch operations
- **Cross-Device Sync**: Profile data stored on server as single source of truth
- **Desktop UX**: Enter key login support for web users
- **Security**: Authentication guards on all protected routes
- **Native UX**: Platform-specific icons (Cupertino on iOS/macOS, Material elsewhere)

### Web Infrastructure
- **CloudFormation**: S3, CloudFront, Route53, ACM for SSL
- **Deployment**: `./deploy-web.sh` handles everything automatically
- **Features**: Custom domains, HTTPS enforcement, SPA routing, CDN caching

### Import/Export
**Import**: Copy/paste TSV from Google Sheets with real-time progress
**Export**: JSON/CSV to Download, Clipboard, or S3 with shareable URLs
**Access**: Admin Dashboard → Menu

### Identity Provider Configuration
The system uses a hybrid approach for federated authentication:
- **CloudFormation**: Manages core Cognito User Pool and Client infrastructure
- **Shell Script**: Configures identity providers outside CloudFormation to avoid multi-line private key issues

**Configuration Files:**
- `configure_identity_providers.sh`: Automated identity provider setup
- `.env.deployment`: Contains Google and Apple credentials
- `template-quote-me.yaml`: Core infrastructure (identity providers removed)

**Required Apple Developer Portal Setup:**
- **Service ID**: `com.anystupididea.quoteme.signin`
- **Domains and Subdomains**: `quote-me-auth-1757704767.auth.us-east-1.amazoncognito.com`
- **Return URLs**: `https://quote-me-auth-1757704767.auth.us-east-1.amazoncognito.com/oauth2/idpresponse`

**Required Google Cloud Console Setup:**
- **Client ID**: `445066027204-f4qcm9jdlborgg9koks4lce2uju7u1lt.apps.googleusercontent.com`
- **Authorized JavaScript Origins**: `https://quote-me.anystupididea.com`
- **Authorized Redirect URIs**: `https://quote-me-auth-1757704767.auth.us-east-1.amazoncognito.com/oauth2/idpresponse`







## Key Integration Points
- **Environment**: `./update_env.sh` syncs AWS outputs to `.env`
- **Auth Model**: API Key (public/rate-limited), JWT (admin/unlimited)
- **Data Flow**: DynamoDB → Lambda → API Gateway → Flutter
- **Domains**:
  - API: https://dcc.anystupididea.com (AWS API Gateway with CloudFront/SSL)
  - Web App: https://quote-me.anystupididea.com (Flutter web app)
- **Identity Providers**: Configured via shell script outside CloudFormation

## API Endpoints

### Public (API Key, Rate Limited)
- `GET /quote` - Random quote with optional tag filtering
- `GET /quote/{id}` - Specific quote by ID
- `GET /tags` - All available tags (367 tags from TagsTable)
- `POST /auth/register` - User registration (no auth required)
- `POST /auth/confirm` - Email verification (no auth required)

### Admin (JWT + Admin Group)
- **Quotes**: GET/POST/PUT/DELETE `/admin/quotes[/{id}]`
- **Tags**: GET/POST/PUT/DELETE `/admin/tags[/{tag}]`
- `DELETE /admin/tags/unused` - Remove orphaned tags
- `POST /admin/generate-tags` - GPT-4o-mini tag generation
- `GET /admin/candidate-quotes` - AI quote finding by author (1-20 configurable limit)
- `GET /admin/candidate-quotes-by-topic` - AI quote finding by topic (1-20 configurable limit)  
- `GET /admin/subscriptions` - View all Daily Nuggets subscribers

### User Features (JWT Authentication)
- `GET /favorites` - Get user's favorite quotes
- `POST /favorites/{id}` - Add quote to favorites
- `DELETE /favorites/{id}` - Remove quote from favorites
- `GET /favorites/{id}/check` - Check if quote is favorited
- `GET /subscriptions` - Get Daily Nuggets subscription status
- `PUT /subscriptions` - Update Daily Nuggets subscription
- `DELETE /subscriptions` - Cancel Daily Nuggets subscription
- `POST /subscriptions/test` - Send test Daily Nuggets email

## User Management
- **Registration**: Self-service with email verification
- **Groups**: "Users" (auto), "Admins" (manual)
- **Admin**: `admin@dcc.com` / `AdminPass123!`
- **Cognito**: Pool `us-east-1_WCJMgcwll`, Client `308apko2vm7tphi0c74ec209cc`
- **Federated Auth**: Google (`445066027204-f4qcm9jdlborgg9koks4lce2uju7u1lt.apps.googleusercontent.com`) and Apple (`com.anystupididea.quoteme.signin`)

## Production Status
- **Database**: 2,330 quotes, 367 tags across dedicated tables
- **Auth**: Cognito with self-registration, role-based access, Google/Apple Sign In
- **Performance**: Fast DynamoDB queries, CloudFront CDN
- **Platforms**: iOS, Android, Web (https://quote-me.anystupididea.com)

## Key Capabilities
- **About Dialog**: App info accessible to all users
- **Quote Retrieval Limit**: Configurable 50-1000 quotes per fetch (Settings screen)
- **Audio**: TTS with 50+ voices, rate/pitch controls (default: OFF)
- **Admin**: Full CRUD, search, sort, import/export with AI tag recommendations and AI quote finding
- **Daily Nuggets**: Email subscriptions with admin management and timezone-aware delivery
- **AI Tags**: GPT-4o-mini via secure Lambda proxy
- **Favorites**: Personal quote collections with heart icons and native sharing
- **Resilience**: Auto-retry, graceful error handling
- **Standards**: Clean architecture, automated testing

## Recent Improvements

### November 2025 (v1.1) - Tags & Filtering Fixes
- **✅ Tags Endpoint Fixed**: Resolved 500 errors preventing tags from loading
  - **Root Cause**: Duplicate Lambda functions configured for /tags endpoint
  - **Fix**: Removed legacy TagsHandlerFunction, consolidated to QuoteHandlerFunction
  - **Result**: All 367 tags now display correctly in Settings screen
- **✅ Quote Filtering Fixed**: Multi-tag quote retrieval now works correctly
  - **Root Cause**: Code expected non-existent TagQuoteIndex GSI and mapping table
  - **Fix**: Rewrote filtering to use DynamoDB scan with contains() expressions
  - **Result**: Selecting multiple tags returns relevant quotes without 404 errors
- **✅ Data Model Clarified**: Tags stored in separate TagsTable, quotes have tags as array attribute
- **✅ Documentation Updated**: Removed incorrect "O(1)" and "zero-scan" performance claims

### September 2025
- **✅ Federated Authentication Overhaul**: Complete Google and Apple Sign In implementation
  - **Google Sign In**: Fully operational with proper OAuth flows and callback URLs
  - **Apple Sign In**: Complete implementation with Apple Developer Portal integration
  - **Cross-Platform Support**: Works on iOS, Android, and web browsers
  - **AWS Cognito Integration**: Identity providers with proper attribute mapping
  - **Profile Screen Support**: Graceful handling of Apple's privacy-focused data sharing
  - **"Scorched Earth" Deployment**: Identity providers configured via shell script outside CloudFormation
  - **OAuth Configuration**: Automatic setup of callback URLs, flows, and scopes
- **✅ AI Quote Finding Features**: Admin-only quote discovery tools
  - **Find New Quotes by Author**: GPT-4o-mini powered author-specific quote finding
  - **Find New Quotes by Topic**: Topic-based quote discovery across multiple authors
  - **Configurable Limits**: Admin settings for 1-20 quotes per search (default: 5)
  - **Same OpenAI Integration**: Uses existing environment variables and CORS patterns
- **✅ Duplicate Detection Restored**: Server-side fuzzy matching prevents duplicates at quote creation
- **✅ Daily Nuggets Deep Links**: "Manage subscription" emails link directly to Profile screen
- **✅ Profile Data Sync**: Removed local storage, server is single source of truth across devices
- **✅ CORS Issues Fixed**: Web app can now access all subscription APIs properly
- **✅ Authentication Security**: Profile routes protected, unauthenticated users redirected to login
- **✅ Desktop UX Enhancement**: Enter key submits login form for better web experience
- **✅ Test Organization**: All test files moved to `tests/` directory for better project structure
- **✅ Enhanced Federated User Support**: Complete Google OAuth user experience improvements
- **✅ Platform Compatibility**: Resolved iOS/Android build issues with conditional web imports
- **✅ UI/UX Polish**: Fixed disabled controls and removed debug artifacts

## Development Guidelines
- Keep file sizes manageable with proper separation of concerns
- Always use themes.dart for styling (never inline styles)
- Edit existing files rather than creating new ones
- Only create documentation when explicitly requested