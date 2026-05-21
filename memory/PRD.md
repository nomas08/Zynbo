# Zynbo — Product Requirements (Living Doc)

## Problem statement
Build **Zynbo**, a Flutter mobile chat application similar to WhatsApp. Uses Firebase Authentication (Google Sign-In) and Firestore as the backend. The user will provide `google-services.json` from their own Firebase project.

Initial dependencies pinned by user:
```yaml
firebase_core: ^latest
firebase_auth: ^latest
google_sign_in: ^latest
```

## User personas
- **Everyday chatter** — wants a fast, clean, secure 1:1 chat app
- **Group organiser** — wants group chats for friends/teams (P2)
- **Privacy-first user** — values minimal data and clear security rules

## Tech stack
- Flutter 3.19+ / Dart 3.3+
- Firebase: Auth (Google Sign-In), Cloud Firestore, Storage (future)
- google_fonts (Space Grotesk), cached_network_image, image_picker

## What's implemented (Jan 2026 — Iteration 1)
- ✅ Flutter project scaffold (`/app/zynbo/`)
- ✅ Firebase initialization in `main.dart` with `firebase_options.dart` placeholder
- ✅ **Login screen** with Google Sign-In flow (branded teal/lime aesthetic, animated)
- ✅ **AuthGate** routing: Login → Profile Setup → Home (reacts to `authStateChanges`)
- ✅ **AuthService** singleton: `signInWithGoogle`, `signOut`, `_ensureUserDocument` (Firestore /users/{uid}), `saveProfile`, `hasCompletedProfile`
- ✅ **Profile Setup screen**: display name, about, optional phone; writes `profileCompleted: true` to Firestore
- ✅ **Home screen**: profile card (live stream from `/users/{uid}`), empty chats placeholder, sign-out
- ✅ `ZynboUser` model with `toMap`/`fromMap`
- ✅ Firestore security rules (`firestore.rules`) — users own their doc; chats locked
- ✅ Comprehensive setup README with Firebase wiring + SHA-1 instructions

## Prioritized backlog
### P0 (next session — once user provides google-services.json)
- Verify Google Sign-In end-to-end on a physical/emulated device
- Confirm Firestore writes hit `/users/{uid}` on first login

### P1 (chat MVP)
- 1:1 direct messages — `/chats/{chatId}/messages/{messageId}` real-time stream
- Chat list with last-message preview + unread badge
- Online/last-seen presence (Firestore heartbeats or Realtime DB)
- Search users by email/phone to start a chat

### P2
- Group chats + admin controls
- Media attachments (images/audio/files) via Firebase Storage
- Push notifications (FCM)
- Read receipts, typing indicators
- Profile photo upload (camera/gallery via `image_picker` already in pubspec)

### P3
- End-to-end encryption layer
- Voice/video calls (Agora or WebRTC)
- iOS-specific polish + App Store assets

## File map
```
/app/zynbo/
├── pubspec.yaml
├── README.md          # full setup guide
├── firestore.rules
├── analysis_options.yaml
├── .gitignore
└── lib/
    ├── main.dart
    ├── firebase_options.dart        (placeholder — user runs flutterfire configure)
    ├── models/user_model.dart
    ├── services/auth_service.dart
    └── screens/
        ├── login_screen.dart
        ├── profile_setup_screen.dart
        └── home_screen.dart
```

## Known limitations
- This Kubernetes environment has no Flutter SDK; project cannot be `flutter run`-tested here. User must run on a local machine with the Flutter SDK.
- `firebase_options.dart` contains placeholder values; user must run `flutterfire configure` OR manually edit the file before launching.
- No automated test suite yet (Flutter unit/widget tests would be a P2 add).
