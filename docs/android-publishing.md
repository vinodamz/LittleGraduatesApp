# Android publishing

Package: `in.thelittlegraduates.app`. Android CI and signed-release workflows pin Flutter 3.47.8 (Dart 3.13.7) and JDK 21. The `pubspec.yaml` Dart constraint remains `^3.12.2`; it is not the CI SDK version.

## Current release state — 27 November 2026

The next intended release is **v1.0.5** (`pubspec.yaml`: `1.0.5+1`). The publisher reports that v1.0.4 / code 1006 produced signed artifacts, but Play validation returned HTTP 403 requesting a foreground-service declaration. This documentation pass did not query remote release state. A successful signed build does not establish a committed, approved or available Play release, and changing the version alone does not resolve that declaration.

The source-backed release findings are in [Android release readiness](android-release-readiness-2026-11-27.md). Before the next Play submission:

- Complete the foreground-service declarations for the actual merged release manifest. Source uses `location` for driver-initiated trip tracking and `dataSync` for staff-initiated materials uploads. WorkManager contributes permissions through manifest merging; do not answer that the app has no foreground services. Supply real demonstrations of the user action, service notification and completion/stop behavior. [Google's foreground-service requirements](https://support.google.com/googleplay/android-developer/answer/13392821).
- Resolve background-location review, including the prominent disclosure, consent, declaration and real Android demonstration. The app declares `ACCESS_BACKGROUND_LOCATION`; an ongoing notification is not a substitute for this review. [Background-location requirements](https://support.google.com/googleplay/android-developer/answer/9799150).
- Update the public privacy policy for Materials, offline storage, embedded school tools and external recipients. The reviewed live policy is dated 2 October 2026 and still says other modules open externally. Its one-year driver-location/trip retention statement conflicts with a configurable 30-day raw-coordinate cleanup routine; the publisher must confirm deployed retention and deletion operations. The corrected [privacy draft](../publishing/app-privacy-policy-draft.md) keeps those business questions unresolved rather than inventing promises.
- Complete Data safety for the intended public release using the actual native and school-controlled WebView flows, SDKs and recipients. Assess identifiers, precise location, photos/video and possible audio, user-entered records and financial data in enabled fee forms; do not infer “no collection” or “no sharing.” Apps exclusively on internal testing are exempt from the Data safety section; this does not resolve the observed foreground-service 403. [Google's Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469).
- Confirm app-access reviewer credentials/instructions, target audience and content rating in Console. The app is intended for authorized adult staff/drivers; handling children's records is a separate privacy matter.

No Console declaration, new signed Android build, or real-device demonstration is established by these document edits. The parent release process owns CI, publication and remote verification.

## One-time setup

1. Merge these workflows to `main`. Pull requests and main pushes run analysis,
   existing tests, and a debug Android build without release secrets.
2. Create the Little Graduates app in Play Console with the package above.
   Enroll in Play App Signing. Use the existing keystore referenced by your local
   `android/key.properties`; do not create a replacement key.
3. Create a Google Cloud service account, enable the Google Play Android
   Developer API, and invite that service-account email in Play Console Users
   and permissions. Restrict access to this app, with app information access,
   testing release permission, and production release permission for promotion.
   Create its JSON key and keep it private.
4. In GitHub Settings → Environments, create `google-play-internal` and
   `google-play-production`. Restrict internal deployment to release tags and
   production to `main`. Require at least one reviewer on production, prevent
   self-review, and disable administrator bypass where available. If the GitHub
   plan does not support required reviewers, leave production publishing disabled.
5. Add these environment secrets to `google-play-internal`:

   | Secret | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | Base64 contents of the existing upload keystore |
   | `ANDROID_KEYSTORE_PASSWORD` | Existing store password |
   | `ANDROID_KEY_ALIAS` | Existing alias |
   | `ANDROID_KEY_PASSWORD` | Existing key password |
   | `PLAY_SERVICE_ACCOUNT_JSON` | Service-account JSON contents |

   Add `PLAY_SERVICE_ACCOUNT_JSON` to `google-play-production` as well. Prefer
   separate service accounts for testing and production permissions.
   The public repository allows production to verify environment protection using
   GitHub public metadata, without an additional GitHub access token.
   Never commit these values. Release jobs clean signing files even on failure.
6. Google Play API publishing needs an existing app and may require a first
   manual bundle upload. To bootstrap, run Android internal release manually
   **on a `vMAJOR.MINOR.PATCH` tag**. If the build and artifact-upload steps complete, the signed bundle is retained
   before the Play upload step. The workflow also checks Play status before building;
   a failure at that earlier check means this run has no new signed artifact. Download
   that artifact and upload it in Play Console. Do not retry an already committed
   version code; use a new tag for the next release.
7. Complete the Play listing, app-access instructions (staff name/PIN login),
   privacy policy, data safety, content rating, target audience, and required
   location/foreground-service declarations. The app uses driver location while
   trips run, so review its permissions carefully. CI does not supply these
   declarations or override Google review.

## Release to internal testing

Push a tag on a commit already merged into main:

```sh
git tag v1.0.5
git push origin v1.0.5
```

For that tag the version name is `1.0.5`. The signed build overrides the
`+1` development build number in `pubspec.yaml`. The version code is
`ANDROID_VERSION_CODE_BASE + github.run_number`, defaulting to `1000 + run_number`.
Set repository variable `ANDROID_VERSION_CODE_BASE` before the first release if
Play already contains larger version codes; keep the base stable afterward.
Every fresh run allocates a new code, while rerunning a failed job reuses its
code. Do not recreate tags or delete/recreate the workflow, which could reset
the run counter. Serialize releases and do not release an older run after a newer
one. If Play rejects an upload because the code is already used, create a new tag.

The workflow builds an AAB and split-per-ABI signed APKs, retains them as Actions
artifacts, and creates GitHub release downloads **before** attempting Play upload.
Those downloads can therefore exist even when Play validation fails. A rerun can
also encounter an already-created GitHub release; inspect the failed step and
existing artifacts before retrying.

Download the signed AAB from the workflow artifacts if needed. Configure internal
testers and share the Play opt-in link in Play Console. A successful API commit
does not guarantee immediate availability; Play may still review the release.

## Promote to production

Run **Promote Android to production** from Actions on `main`, entering the exact
version code already tested on internal. A configured reviewer approves the
environment deployment. The workflow fails closed if required-reviewer protection
cannot be confirmed. It promotes the existing bundle without rebuilding it.
Promotion creates a full production release, subject to Google review, and
replaces the production track release configuration. Finish any existing staged
rollout before promoting. Confirm the intended version and distribution in Play
Console before approving. Failed or ambiguous commits should be checked in Play
Console before rerunning.


## Read release status without publishing

The **Android Play release status** workflow uses the internal environment's
credentials; select a permitted release tag. Locally, with credentials already
provided by the publisher, the equivalent command is:

```sh
python3 scripts/play_release.py status --output /tmp/play-status.json
```

This code path reads the internal and production release lifecycle lists. It does
not open a Play edit, upload, change tracks or commit a release. Read the returned
review/publication state and version codes; a status-query failure leaves the
state unknown. The release lifecycle endpoint distinguishes releases awaiting
review, under review, approved and available. [Release lifecycle API](https://developers.google.com/android-publisher/api-ref/rest/v3/applications.tracks.releases/list).

Keep these milestones separate when reporting a release:

| Evidence | What it establishes |
| --- | --- |
| Signed AAB/APKs or GitHub downloads | A build is available; no Play acceptance is implied. |
| Play validation HTTP 403 | A declared release requirement blocked that attempt; preserve the response and resolve the stated requirement. |
| Successful edit commit | Play accepted the release edit; approval and distribution still need verification. |
| Track edit status `completed` | The script's selected rollout configuration; it is not proof that Google review has finished. |
| Lifecycle readback and Play Console/tester check | The current review/publication state and whether the intended audience can actually obtain the release. |

The promotion script requires the chosen version to be a `completed` internal
track entry. That check cannot establish that a human tested the installed app.
The publisher must confirm the tested version and inspect current lifecycle state
before promotion. Neither the status command nor a version bump completes App
content declarations or supplies demonstration videos.
