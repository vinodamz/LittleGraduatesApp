# Coordinated mobile and web release

MTT remains the PHP backend and database at https://mtt.thelittlegraduates.in.
The Flutter frontend is served at https://app.thelittlegraduates.in.

## Hosting and CI/CD

The app subdomain has a separate document root:
`$HOME/thelittlegraduates.in/app`. MTT remains at its existing document root.
AutoSSL provides the app's certificate; no certificate-verification bypass is used.

`Web release build` checks Flutter code and builds the web app on pull requests.
After a main push or a manual run on main, it publishes the tested output to the
`web-release` branch. cPanel's `LittleGraduatesAppWeb` Git repository pulls that
branch and runs its `.cpanel.yml`, mirroring the existing MTT deployment model.
The job verifies the HTTPS `build-id.txt` against the source SHA.

The app repository uses the same cPanel deployment account as MTT. Its
`CPANEL_HOST`, `CPANEL_USER`, and `CPANEL_TOKEN` secrets were transferred as
GitHub sealed ciphertext encrypted for the target repository; plaintext was
not exported to the workstation or workflow artifacts.

MTT's API allows only the exact HTTPS app and MTT origins. Mobile clients
continue to authenticate with the existing bearer tokens. No data migration
or backend move is part of this release.

## Browser behavior

Browser material checks and media are saved to IndexedDB, scoped to the signed-in
MTT user. Failed uploads retry every 30 seconds while the page is open and on
refresh. Browser storage failures are surfaced before claiming a change was
saved. Exclusive Web Locks prevent competing tabs from overwriting an outbox.
The native mobile queue, sqlite storage, and background jobs remain in the
native implementation behind conditional exports.

Browser location sharing requires an open page. Use the Android/iOS app for
screen-off/background driver tracking. Browser videos upload as selected,
subject to the existing server limit; native video transcoding remains mobile-only.

## Validation and release order

1. Flutter analysis, widget/API/privacy/outbox tests, and Python release tests.
2. Compile the web app and test in Chrome using isolated API fixtures.
3. Merge the additive MTT origin change and verify the live OPTIONS response.
4. Merge the app release, wait for Android CI and the web deployment, and verify
   both the HTTPS build marker and live unauthenticated login loading.
5. Tag the matching mobile version and run the existing signed Android internal
   release. Production promotion retains its existing protected environment.

The browser smoke test is `scripts/browser_smoke.cjs`. It requires Playwright,
a running server for `build/web` (default `http://127.0.0.1:8766`), and optional
`CHROME_BIN`. It intercepts API calls with test data and verifies sign-in, an
offline condition, persistence after reload, retrying once, and tab exclusion.
