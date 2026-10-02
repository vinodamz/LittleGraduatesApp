# Android publishing

Package: `in.thelittlegraduates.app`. CI uses Flutter 3.44.8 (Dart 3.12.2) and JDK 21.

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
   Production also needs `ENVIRONMENT_READ_TOKEN`: a fine-grained GitHub token
   restricted to this repository with Actions read permission (environment
   inspection). It is used only to check that production has required reviewers.
   Never commit these values. Release jobs clean signing files even on failure.
6. Google Play API publishing needs an existing app and may require a first
   manual bundle upload. To bootstrap, run Android internal release manually
   **on a `vMAJOR.MINOR.PATCH` tag**. Its signed bundle is retained as an artifact
   before the upload step, even if Play rejects the first API upload. Download
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
git tag v1.0.0
git push origin v1.0.0
```

The version name is `1.0.0`. The version code is
`ANDROID_VERSION_CODE_BASE + github.run_number`, defaulting to `1000 + run_number`.
Set repository variable `ANDROID_VERSION_CODE_BASE` before the first release if
Play already contains larger version codes; keep the base stable afterward.
Every fresh run allocates a new code, while rerunning a failed job reuses its
code. Do not recreate tags or delete/recreate the workflow, which could reset
the run counter. Serialize releases and do not release an older run after a newer
one. If Play rejects an upload because the code is already used, create a new tag.

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
