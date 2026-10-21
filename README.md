# Little Graduates app

Android and iOS app (Flutter) for the Little Graduates MTT system. Staff sign in with the same name + PIN as the website. A bottom bar keeps Today, Transport, Staff and Materials one tap apart. Other modules open the website.

- **Transport** is the driver trip screen, with live location.
- **Staff** is check-in, leave and today's roster. Payroll, documents and messages stay on the website.
- **Materials** is the daily shelf check. Marks, photos and videos are saved on the phone first, then uploaded in the background. Audit history, trends, the monthly board and duties stay on the website.
- **Every other module** opens its MTT web page until it is rebuilt here.

The server side lives in the MTT repo (`api/v1/`, `includes/api.php`, migration 072).

## Transport (drivers)

1. Sign in, open **Transport**, pick today's pickup or drop, then tap **Start trip**.
2. The phone shares its location every 15 seconds as an Android foreground service (the ongoing "Trip running" notification). This keeps working with the screen off or while WhatsApp is open.
3. Near a stop that has a location (within 80 m), the stop is marked **reached** automatically and the driver gets a notification to WhatsApp the family. A highlighted button and notification also appear when a family is about 5 minutes away.
4. Mark each child picked up / dropped / absent. Tracking stops when the trip is finished or cancelled, on the phone or on the website.

Parents follow their private link: approximate time plus the cab on a map while their child is waiting.

For screen-off reliability, set Location to **Allow all the time** (the trip screen has a shortcut), and turn off battery optimisation for the app on phones that kill background apps aggressively.

## Project layout

```
lib/
  main.dart                    app start, providers, signed-in/out switch
  core/
    config.dart                server URL (LG_BASE_URL), upload intervals
    api_client.dart            /api/v1 JSON client, bearer token
    session.dart               sign-in state, user, modules (token in secure storage)
    module_registry.dart       module key → native screen; others open the web
    notifications.dart         driver prompts
    theme.dart                 colours, type, controls
    nav.dart                   bottom-bar tab switch
  features/
    auth/login_screen.dart     pick name, PIN pad
    shell/app_shell.dart       Today, Transport, Staff, Materials, More
    home/home_screen.dart      Today and More
    transport/                 today's runs, trip screen, location tracker
    staff/                     check-in, leave, roster
    materials/                 daily shelf check, local outbox, background upload
```

## Materials (daily check)

1. Open **Materials**. Today's active materials are grouped by shelf. Pick a condition, add an optional note, and attach a camera photo, a camera video, or a gallery file. "Rest are Good" marks the unmarked materials on that shelf only.
2. The check and the original file are written to this phone immediately (sqlite plus `materials_outbox/`). Closing the app, losing the network, or leaving the screen does not drop them.
3. Photos are scaled to 1600px and re-encoded as JPEG (quality 75). Videos wider than 720p, or larger than 12 MB, are transcoded to 720p. Originals stay until the school server confirms the upload, then they are deleted.
4. Android uploads with WorkManager (a data-sync foreground notification, plus an hourly refresh). iOS uploads the file bytes with a background URL session, and uses a background processing task for the queue. Each item has an idempotency key so a retry does not create a second photo.
5. The Materials tab and the Today screen show how many items are still on the phone. A failed item has a Retry button.

Apply MTT migration `076` before shipping the app build. Until that column exists, media uploads get a retryable server error instead of a duplicate file.

### Adding another MTT module to the app

1. Build the screens under `lib/features/<module>/`.
2. Register the screen in `nativeModuleScreens` in `lib/core/module_registry.dart`.
3. On the server, add any endpoints under `api/v1/<module>/`, then set the module's `native` flag to `true` in `api_app_modules()` (`includes/api.php`).

Until step 3 ships, the tile keeps opening the website, so old app versions keep working.

## Build

Requires Flutter, JDK 21 and the Android SDK (`flutter doctor`).

```bash
flutter test
flutter build apk --release --split-per-abi   # → build/app/outputs/flutter-apk/
```

Use `app-arm64-v8a-release.apk` for almost all current phones.

To run against a local MTT server from the emulator (debug builds allow http):

```bash
flutter run --dart-define=LG_BASE_URL=http://10.0.2.2:8765
```

## Release signing

Release builds are signed with the key referenced by `android/key.properties` (gitignored). The keystore and its password live outside the repo in `~/.lg-android-keys/`.

**Back up that folder somewhere safe.** Every future update must be signed with the same key; if it is lost, phones have to uninstall and reinstall the app.

## Google Play CI/CD

GitHub Actions checks PRs and main pushes. Version tags build a signed App Bundle
and publish to internal testing; a protected manual workflow promotes tested
versions to production. Release builds require the existing signing key.
See [Android publishing setup](docs/android-publishing.md) for secrets, Play API
permissions, first-upload setup, and release instructions.
