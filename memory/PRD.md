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

### Iteration 6 (Jan 2026) — Groups + Media (Phase A) ✅

**Group chats**
- Chat doc now has `type: 'direct' | 'group'` discriminator; groups also carry `groupName`, `groupPhoto`, `createdBy`, `admins`, N-person `participants`
- `ChatService.createGroup({createdBy, participants, groupName, groupPhoto})` returns a Firestore auto-id
- `ChatService.sendMessage` now accepts `recipientIds: List<String>` and increments unread for ALL non-sender participants — works for both 1:1 and groups
- New `CreateGroupScreen` (2-step: pick members → name+photo)
- `NewChatScreen` adds a prominent "New group" entry at the top
- `ChatScreen` group-aware: header shows group photo + name + `N members`, plus multi-user typing roll-up ("Alice +2 are typing…")
- Group bubbles for non-self messages show sender name in lime above the text (`_SenderName` stream)
- Read receipts in groups: ✓✓ only when ALL other participants have read

**Media — images**
- `image_picker` integration (gallery + camera) via composer's `+` button → bottom-sheet picker
- Upload to Firebase Storage at `/chats/{chatId}/img_<ts>.jpg` (1600px max, 82% quality)
- Image messages render with rounded corners, in-bubble loading shimmer, cached via `cached_network_image`
- Chat list preview shows a camera icon + "Photo" label

**Media — voice notes**
- New `MediaService.uploadChatMedia` for Storage I/O
- Composer mic button → records via `record` package (AAC, 96kbps M4A), displays live timer + cancel button
- Stops & uploads on send tap; sends as `type: 'voice'` with `mediaUrl` + `durationMs`
- Voice bubbles render with play/pause button, linear progress, current/total time via `just_audio`
- Chat list preview shows a mic icon + "Voice message" label
- Microphone permission requested at record-time via `permission_handler`

**Security**
- `firestore.rules` updated: group chats need `participants.size() >= 2` instead of `== 2`
- New `storage.rules` published: chat media readable/writable only by participants (20 MB cap); user-owned files (5 MB cap)

**Pubspec additions:** `record ^5.1.0`, `just_audio ^0.9.36`, `permission_handler ^11.2.0`, `path_provider ^2.1.2`

**Native config (called out in README):** Android `RECORD_AUDIO` + media perms in `AndroidManifest.xml`; iOS `NSCameraUsageDescription` / `NSMicrophoneUsageDescription` / `NSPhotoLibraryUsageDescription` in `Info.plist`



**Lifecycle-aware presence**
- New `lib/services/presence_service.dart` with `goOnline` / `goOffline`
- `ZynboApp` converted to `StatefulWidget` with `WidgetsBindingObserver`
- On `AppLifecycleState.resumed` → presence: online; on paused/inactive/detached/hidden → offline
- Also flips to online on `authStateChanges` user emission (handles cold-start race)

**Read receipts (WhatsApp-style ✓/✓✓)**
- Messages now include `readBy: [senderId, …]`; sender is implicitly read
- `ChatScreen` keeps a local `_markedRead` cache; on every message stream tick, batch-updates `readBy: arrayUnion([currentUid])` for incoming unread messages (idempotent, no duplicate writes)
- `buildMessage(..., readByOther: bool)` renders inside-bubble ticks: single faded check = sent; double lime check = read by other
- Firestore rules tightened: messages allow update **only when `affectedKeys()` is exactly `['readBy']`** — no message tampering

**Typing indicators**
- `typing: {uid: bool}` map seeded in `ensureChat`
- `ChatService.setTyping` toggles `typing.{uid}` on the chat doc
- `ChatScreen` debounces: keystroke → typing=true; idle 3 s → typing=false; on send → immediate false; on dispose → cleanup
- **Chat header** subtitle reactively shows `typing…` (italic, teal) when the other user is typing, else `Online` / `Offline`
- **Chat list tile** shows `typing…` in place of the last-message preview while the other user is typing

- **Renamed** `home_screen.dart` → `chats_list_screen.dart`; class `HomeScreen` → `ChatsListScreen`. `AuthGate` updated.
- **WhatsApp-style list** with Zynbo aesthetic:
  - Branded header (Zynbo wordmark + current-user avatar that opens a profile bottom-sheet with sign-out)
  - **Search bar** filters tiles by other-user name OR last message
  - Tiles: 56px avatar (initials fallback in lime-on-teal), green online dot, name, smart timestamp, last-message preview, italic placeholder when empty, "online" lime pill
  - Smart timestamps: HH:mm (today), "Yesterday", weekday (within 7d), else "d MMM"
- **Unread badge** (P1 → done):
  - `unreadCount: {uid: int}` map added to chat docs in `ensureChat`
  - `sendMessage(recipientId:)` now does `FieldValue.increment(1)` on `unreadCount.{recipientId}`
  - `ChatScreen.initState` calls `ChatService.markChatRead(chatId, uid)` to zero the counter
  - Tile shows pill badge (teal bg, lime text, "99+" cap), name + preview + timestamp bold/teal when unread


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

### P1 (mostly done)
- ✅ **Lifecycle-aware presence** — iteration 5 (RTDB `onDisconnect()` upgrade for true network-drop detection remains a P2 nice-to-have)
- ✅ **Unread counts** — iteration 4
- ✅ **Read receipts** — iteration 5
- ✅ **Typing indicators** — iteration 5
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
    │   ├── chat_service.dart
    │   └── presence_service.dart     ← new in iteration 5
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
