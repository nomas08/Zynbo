# Zynbo — Product Requirements (Living Doc)

## Problem statement
Build **Zynbo**, a Flutter mobile chat application similar to WhatsApp. Uses Firebase Authentication (Google Sign-In) and Firestore as the backend. User provides `google-services.json` from their own Firebase project.

## User personas
- **Everyday chatter** — wants a fast, clean, secure 1:1 chat app
- **Group organiser** — wants group chats for friends/teams (P2)
- **Privacy-first user** — values minimal data and clear security rules

## Tech stack
- Flutter 3.19+ / Dart 3.3+
- Firebase: Auth (Google Sign-In), Cloud Firestore, Storage (future)
- google_fonts (Space Grotesk), cached_network_image, image_picker, intl

## What's implemented

### Iteration 1 (Jan 2026)
- Flutter scaffold, Firebase init, branded theme (teal/lime, Space Grotesk)
- Login screen (Google Sign-In, animated)
- `AuthGate` routing Login → Profile Setup → Home
- `AuthService` with Google Sign-In, sign-out, `_ensureUserDocument`
- Profile setup screen + Home screen with profile card

### Iteration 2 (Jan 2026) — Schema refresh
- `AuthService.createUserIfNotExists(User)` matching user-supplied snippet (fields: `name`, `email`, `photo`, `status`, `lastSeen`)
- Sign-out now flips `status: 'offline'` + bumps `lastSeen` before tearing down auth
- `ZynboUser` model + all screens migrated to `name` / `photo` schema
- Home profile card chip reactively flips Online ↔ Offline via Firestore stream

### Iteration 3 (Jan 2026) — 1:1 Chat MVP ✅
- **`ChatService`** singleton with deterministic `chatIdFor(uidA, uidB)`, `ensureChat`, `sendMessage` (exact user snippet), `getMessages`, `getUserChats`
- **`Message`** model with `Timestamp` ↔ `DateTime` mapping
- **`ChatScreen`** — full conversation UI:
  - Real-time message stream via `getMessages(chatId)`
  - Asymmetric chat bubbles (teal for mine, white for theirs)
  - Day dividers (Today / Yesterday / d MMM yyyy)
  - Composer with multi-line input, send button, "sending…" indicator
  - Header with avatar, name, live online/offline status
- **`NewChatScreen`** — search all users by name or email; tapping opens a chat (creates `/chats/{chatId}` doc if missing)
- **Home screen rewritten** — real chat list from `getUserChats` stream:
  - Tiles show other user's avatar (with green online dot), name, last message, smart timestamp
  - Empty state when no chats exist
  - FAB → New chat
- **Firestore rules updated** — participants-only read/update on `/chats/{chatId}`; messages immutable; users readable by all authed (needed for search)

## Prioritized backlog

### P0 (user-side)
- Drop in `google-services.json` + run `flutterfire configure`
- Register SHA-1/SHA-256 in Firebase Console
- Publish `firestore.rules` and enable Firestore + Google sign-in provider

### P1
- **Lifecycle-aware presence** — `WidgetsBindingObserver` to flip status on app background/resume + Firestore heartbeat (or migrate to Realtime DB `onDisconnect()` for true offline detection)
- **Unread counts** — per-chat `unreadCount` map keyed by uid, decremented on screen entry
- **Read receipts** — `readBy` array on messages
- **Typing indicators** — ephemeral `typing` field on chat doc

### P2
- Group chats + admin controls
- Media attachments (images/audio/files) via Firebase Storage
- Push notifications (FCM) for offline message delivery
- Profile photo upload (camera/gallery via `image_picker` already in pubspec)

### P3
- End-to-end encryption layer
- Voice/video calls (Agora or WebRTC)
- iOS-specific polish + App Store assets

## File map
```
/app/zynbo/
├── pubspec.yaml
├── README.md
├── firestore.rules                 # users + chats + messages rules
├── analysis_options.yaml
├── .gitignore
└── lib/
    ├── main.dart                   # theme + AuthGate
    ├── firebase_options.dart       (placeholder — user runs flutterfire configure)
    ├── models/
    │   ├── user_model.dart
    │   └── message_model.dart      ← new in iteration 3
    ├── services/
    │   ├── auth_service.dart
    │   └── chat_service.dart       ← new in iteration 3
    └── screens/
        ├── login_screen.dart
        ├── profile_setup_screen.dart
        ├── home_screen.dart        ← rewritten with real chat list
        ├── chat_screen.dart        ← new in iteration 3
        └── new_chat_screen.dart    ← new in iteration 3
```

## Required Firestore indexes
The `getUserChats` query (`where participants array-contains uid` + `orderBy updatedAt desc`) requires a composite index. Firestore will print a deeplink to auto-create it on the first run — accept it.

## Known limitations
- Kubernetes pod has no Flutter SDK; `flutter pub get` / `flutter analyze` must run on the user's local machine
- Presence is one-shot (flips on login/logout) — true real-time presence is a P1 follow-up
- `firebase_options.dart` ships with `REPLACE_ME_*` placeholders
