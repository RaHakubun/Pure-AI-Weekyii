# Weekyii App Store Release Checklist (Project-Specific)

This doc is filled with repo-known details. Anything not found is marked as `UNKNOWN` and left blank for manual input.

## 1. App Identifiers (from project)
- App Name (Display): Weekyii
- Bundle ID (App): com.fluentdesign.Weekyii
- Bundle ID (Widget): com.fluentdesign.Weekyii.widget
- App Group ID: group.com.fluentdesign.Weekyii.shared
- Marketing Version (CFBundleShortVersionString): 1.0
- Build Number (CFBundleVersion): 1

Sources:
- /Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Weekyii.xcodeproj/project.pbxproj
- /Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Resources/Weekyii.entitlements

## 2. Capabilities & Permissions (from project)
- Photo Library (Read): "用于选择任务图片"
- Photo Library (Add): "用于将图片保存到相册"

Source:
- /Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/Resources/Info.plist

## 3. Feature Summary (from repo notes)
Use this to draft the App Store description.
- Core views: Today / Week / Pending / Past / Settings
- Data: SwiftData local persistence; iCloud is placeholder only
- Week/Day/Task/Step/Attachment models with state transitions
- Past week detail with stats and completed tasks list
- Task editor supports steps, attachments, and type
- Localized UI strings (CN/EN coverage)

Source:
- /Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/进度.md

## 4. App Store Connect Metadata (fill-in)
### Basic Info
- App Name: Weekyii
- Subtitle: UNKNOWN
- Primary Language: UNKNOWN
- Bundle ID: com.fluentdesign.Weekyii
- SKU: UNKNOWN
- Category (Primary/Secondary): UNKNOWN

### App Store Listing
- Description: UNKNOWN
- Keywords: UNKNOWN
- Promotional Text: UNKNOWN
- Support URL: UNKNOWN
- Marketing URL: UNKNOWN

### Review Information
- Contact Name: UNKNOWN
- Contact Email: UNKNOWN
- Contact Phone: UNKNOWN
- Demo Account Username: UNKNOWN
- Demo Account Password: UNKNOWN
- Review Notes: UNKNOWN

### Pricing & Availability
- Price Tier: UNKNOWN
- Territories: UNKNOWN
- Release Options (Manual / Automatic / Scheduled): UNKNOWN

### App Privacy
- Privacy Policy URL: UNKNOWN
- Data Collection Declaration: UNKNOWN
- Tracking (IDFA): UNKNOWN

### Age Rating
- Age Rating Questionnaire: UNKNOWN

### App Assets
- App Icon (1024): UNKNOWN
- Screenshots (iPhone sizes): UNKNOWN
- Optional: iPad screenshots: UNKNOWN
- Optional: App Preview Video: UNKNOWN

## 5. Xcode Build & Upload (project context)
- Scheme: Weekyii
- Archive in Xcode: Product -> Archive
- Distribute: App Store Connect -> Upload

Note: App target uses generated Info.plist (GENERATE_INFOPLIST_FILE=YES).

## 6. App Store Connect Submission Steps (high-level)
1. Create new app record in App Store Connect (My Apps -> + -> New App).
2. Fill App Information and App Store listing metadata.
3. Fill App Privacy details and provide Privacy Policy URL.
4. Set Pricing & Availability.
5. Upload build from Xcode and select the build for the version.
6. Provide App Review information (contact + demo account).
7. Submit for review.

## 7. Known Gaps (from repo)
These may impact review readiness.
- App icon final design missing (currently placeholder).
- Launch screen is placeholder (color + text).
- iCloud sync not implemented (placeholder).
- Pending view UX for future months may need improvement.

Source:
- /Users/luobowen/handwrittenfnn/weekyii/Weekyii/Weekyii/进度.md

## 8. Open Items (fill before submission)
- Confirm Bundle ID in App Store Connect matches `com.fluentdesign.Weekyii`.
- Provide Privacy Policy URL and complete App Privacy questionnaire.
- Prepare App Store metadata and assets.
- Provide review account and instructions.
- Decide pricing and release strategy.
