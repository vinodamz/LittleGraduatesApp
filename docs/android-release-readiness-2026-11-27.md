# Android release readiness — 27 November 2026

## Release state and scope

The parent reports that Android CI passed and v1.0.4 / code 1006 built signed
artifacts, but Play validation returned HTTP 403 asking whether the app uses
foreground-service permissions. These remote results were not independently
queried by this sidecar. The intended next release is v1.0.5.

The 403 is not resolved by another version number alone. Complete the applicable
Play Console App content foreground-service declarations using the actual merged
release manifest and evidence. Do not declare that foreground services are absent.
[Google's foreground-service declaration guidance](https://support.google.com/googleplay/android-developer/answer/13392821).

This sidecar did not change workflows, release scripts/tests, signing material,
version numbers, or remote state. It did not commit, push, or publish.

## Applied Android changes

- `MaterialsBridge.kt` explicitly imports `androidx.annotation.OptIn`. Without
  that import, Kotlin resolves the annotation to `kotlin.OptIn`, which is not the
  Media3 lint opt-in. The bridge's existing Media3 usage is unchanged.
  [Media3's documented annotation](https://developer.android.com/media/media3/exoplayer/troubleshooting).
- The application disables Android backup and references explicit cloud-backup
  and device-transfer exclusion rules for all nine standard storage domains.
  The installed `flutter_secure_storage` 11.2.0 documentation warns that restoring
  encrypted preferences without their device-bound keys can fail key unwrapping.
  Account caches and materials queues also contain sensitive school data and
  background-worker tokens. The exclusions prevent transferring these stores;
  they do not delete any existing local records or files. Pending uploads must
  finish on the original device before it is erased or replaced.
  [Android backup and device-transfer behavior](https://developer.android.com/identity/data/autobackup).

## Foreground-service declaration facts

These are source-backed facts for the publisher, not a claim that Console answers
have been submitted or that Android video evidence exists.

| Service / permission | Actual trigger and purpose | Source evidence |
| --- | --- | --- |
| `location` / `FOREGROUND_SERVICE_LOCATION` | A driver explicitly starts/resumes a trip after an in-app location disclosure. GPS fixes track the cab and support arrival estimates and pickup/drop operations while the screen is off or another app is open. There is an ongoing trip notification. Tracking stops when the trip ends, is cancelled, is stopped locally, or the server reports it no longer running. | `lib/core/privacy.dart`; `lib/features/transport/trip_screen.dart`; `lib/features/transport/location_tracker.dart`; geolocator Android manifest |
| `dataSync` / `FOREGROUND_SERVICE_DATA_SYNC` | Staff attach materials photos/videos or save checks. A local outbox survives offline periods. WorkManager schedules pending uploads with a connected-network requirement and an upload notification. | `lib/features/materials/materials_background.dart`; `materials_queue.dart`; `android/gradle.properties` |

`workmanager.enableDataSyncForegroundService=true` selects the locked
workmanager_android 0.10.9 plugin's `AndroidManifest.dataSync.xml`. Thus the data-sync
permission is present through manifest merging even though the main app manifest
does not list it directly. That plugin declares `SystemForegroundService` with
`dataSync|shortService` and also emits `FOREGROUND_SERVICE_SHORT_SERVICE`; inspect
the compiled manifest rather than inferring Play questions solely from the app XML.
The Dart code requests the **dataSync** service type, not a standalone short-service
use case. Android documents no type-specific permission for `shortService`.
[Android foreground-service types](https://developer.android.com/develop/background-work/services/fgs/service-types).

The app also declares `ACCESS_BACKGROUND_LOCATION`. Keep the corresponding
background-location declaration, prominent disclosure and store-policy coverage
consistent. An ongoing notification does not by itself remove the need for policy
review. The required demonstration must show the Android app's real behavior;
no Android device/emulator was available for this sidecar to record it.
[Background-location submission requirements](https://support.google.com/googleplay/android-developer/answer/9799150).

Suggested evidence to capture: user starts a driver trip, sees the disclosure and
permission prompt, leaves the app, sees the ongoing location notification, and
finishes/stops the trip; separately, a user attaches material media and the upload
notification shows the pending transfer completing. Record actual behavior and
durations; do not invent a video URL or claim tests that were not performed.

## Privacy draft corrections needed before publication

Reviewed `publishing/app-privacy-policy-draft.md` against current source.

1. **Retention contradicts code.** The draft says driver locations and trips are
   retained for one year. `MontessoriTraineeTeacher/includes/transport_ops.php`
   defines `transport_purge_old_coordinates()`, deleting raw coordinates older
   than 30 days when `transport_delete_coordinates` is enabled (default on).
   Cleanup runs after location uploads and errors are caught. This neither proves
   a guaranteed 30-day deletion schedule nor establishes trip-record retention.
   Confirm the deployed setting, trip retention, backups and logs before stating
   a duration. Do not publish the unverified one-year promise.
2. **Offline retention needs precision.** Account-specific cached materials sheets,
   checks and pending media can survive logout/restart. Logout removes the secure
   sign-in token and cached session profile. Successful media uploads
   remove app-managed outbox copies, not the original gallery/camera files owned
   by the user. Failed/waiting uploads remain for retry. Notes and server records
   are not all deleted when a media upload completes.
3. **Include actual information flows.** Native code sends staff account IDs/PINs
   for authentication; precise GPS coordinates with time, accuracy, speed and
   heading; materials photos/videos and condition notes; and school operational
   form submissions. It displays child/parent contact and pickup/drop records.
   Native attendance/leave forms also handle employment-related information.
4. **Cover the embedded school tools.** The native WebView exchanges a bearer
   token for an authenticated MTT session and loads school-controlled pages. A
   statement that those modules 'must also be covered' is an unfinished draft,
   not a description of their data practices. Inventory actual student, parent,
   staff, fees and other enabled forms with the parent agent's module evidence.
   Google includes collection through developer-controlled WebViews in Data
   safety. [Data safety definitions](https://support.google.com/googleplay/android-developer/answer/10787469).
5. **Disclose recipients based on facts.** Cab information reaches authorized
   school staff and families through private tracking links. WhatsApp alerts are
   user initiated. `live_screen.dart` requests OpenStreetMap tiles directly from
   `tile.openstreetmap.org`, exposing request metadata and the viewed map area to
   that service. Confirm hosting providers and other server-side recipients.
   Data safety 'sharing' exceptions require the publisher's assessment; do not
   automatically select 'no sharing' or 'no collection'.
6. **Permission wording must match implementation.** The manifest declares camera
   and microphone permissions, but the inspected Android image-picker path uses
   external capture/picker activities; no direct app-level microphone runtime
   request was found. Do not promise a microphone prompt or blanket photo-library
   access. No broad `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` permission appears in
   the inspected app/image-picker manifests. Verify the final merged manifest.
7. **Do not invent operational promises.** The deletion inbox, 'prompt' manual
   processing, legal entity identity, server retention exceptions, encryption at
   rest, and all hosting/SDK practices need owner confirmation. Default native
   API traffic is HTTPS; that does not prove every embedded third-party flow or
   backend storage guarantee. The public privacy URL could not be fetched by the
   web tool during this review, so its live content/reachability is unverified.

Code-backed Data safety categories to assess include personal/account identifiers,
precise location, photos/videos (potentially recorded audio), and user-provided
notes/operational records. Financial or other sensitive categories depend on the
actual enabled school forms. The app is described as for authorized adult staff
and drivers; handling children's records is distinct from claiming children are
the app's target audience. Final Console responses remain the publisher's task.

## Build compatibility and verification

- Local Flutter is `/tmp/lg-flutter-sdk` version 3.47.8. The concatenated path
  `/tmp/lg-flutter-sdk3.47.8` does not exist.
- SDK source specifies compile/target API 36, min API 24 and NDK 28.2.13676358.
  Android settings specify AGP 9.0.1 and Gradle 9.1.0; workflows use JDK 21.
  This agrees with AGP's Gradle/NDK requirements. No speculative Gradle migration
  was applied. Flutter's own plugin supplies the legacy Kotlin plugin when its
  `android.builtInKotlin=false` compatibility path is active.
  [AGP 9.0.1 compatibility](https://developer.android.com/build/releases/agp-9-0-0-release-notes).
- All main Android XML files parse. The manifest resource reference resolves;
  cloud and device-transfer rules each exclude nine storage domains. Owned
  Android `git diff --check` passed.
- No local JDK/Android SDK build, AAPT resource validation, Android lint run,
  signed-bundle inspection, physical-device test, or publishing was performed.
  Parent CI must validate the changed Kotlin/XML and inspect the resulting merged
  manifest/AAB. The full Flutter suite was not repeated for these Android-only
  edits. The previously successful signed artifact is useful evidence but does
  not verify this new build or satisfy Play declarations.

Secondary non-blocking observation: `prepare_signing.py` currently writes
non-ASCII property values as UTF-8, while Gradle loads them through Java
`Properties.load(InputStream)` (ISO-8859-1). The existing successful key was not
inspected and no signing script was changed in this narrowed task. If the owner
uses non-ASCII passwords/aliases, Unicode escaping or a matching Reader is needed.
[Java Properties encoding](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/Properties.html).
