# Android CI/CD for Little Graduates

## Approved release flow

GitHub Actions checks pull requests and pushes to main using Flutter analysis,
the existing tests, and an Android debug build. These checks do not use secrets.

Pushing a version tag such as `v1.0.0` builds a release Android App Bundle for
`in.thelittlegraduates.app`, signs it with the existing upload key, retains the
bundle as a workflow artifact, and uploads it to Google Play internal testing.
Tags must point to commits on main. Release uploads run serially. A failed check,
missing credential, signing failure, or failed Play upload fails the workflow.

Production publishing uses a separate manual workflow and the GitHub environment
`google-play-production`. A required reviewer must be configured on that
environment before production publishing is enabled. It promotes a specified,
existing version code from internal testing rather than rebuilding the bundle.

## Build and signing

Pin the Flutter SDK to a stable version satisfying the project's Dart 3.12.2
requirement, and use JDK 21 as required by the existing Android tooling.
Version names come from version tags; version codes use a monotonically
increasing release workflow run number with a documented base offset to avoid
conflicting with the initial manual upload. Retries reuse the same version code.

Reconstruct the existing keystore and `android/key.properties` only in the
release job from GitHub secrets. Remove them after the build, including on
failure. Never print passwords, include keys in artifacts, or generate a
replacement signing key. Release builds must fail if signing configuration is
missing; remove the existing fallback to debug signing for release builds.

## Credentials and permissions

Use GitHub secrets for the base64 upload keystore, store password, key alias,
key password, and Google Play service-account JSON. Grant the service account
only the app permissions needed to upload testing releases and promote approved
production releases. Workflows use read-only repository permissions and pinned
action revisions. Secret-bearing jobs do not run on pull requests.

## First release and operational limits

Create the app in Play Console, enroll in Play App Signing, and upload the first
signed bundle manually if required by Google Play before API publishing.
Complete store listing, app-access instructions, content rating, data safety,
privacy policy, and location/foreground-service declarations before production.
The workflow does not fabricate these declarations or bypass Google review.

## Validation and delivery

Validate workflow syntax and expressions, run Flutter analysis and tests, and
attempt an Android build with available local tooling. Document any build
environment limitation. Deliver the change as a pull request with setup
instructions; validate secret-free CI on GitHub when access permits.
Live publishing remains unavailable until the existing signing key and Google
Play credentials are configured. Do not claim an app was published merely
because workflow files were created.
