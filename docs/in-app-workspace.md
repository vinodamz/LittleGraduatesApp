# School tools inside the app

Transport, Staff and Materials keep their Flutter screens. Students, Assessment,
Tasks, Admissions, Fees, Expenses, Logbook, Inventory, Weekly Plans, Daycare and
Recruitment open inside one authenticated workspace. Staff links, Materials
reports and Transport management use the same route. No second PIN is required.

This deliberately reuses the complete MTT workflows instead of maintaining a
second implementation of every business form. These screens remain web content:
MTT is the backend and still enforces module access, record scopes, validation
and CSRF. The workspace needs an internet connection; native Materials offline
checks and the browser outbox retain their existing behavior.

The Flutter web app embeds a sandboxed MTT iframe; Android/iOS use the official
Flutter WebView plugin. Both bootstrap with an HTTPS form POST to `/app/open.php`.
The bearer token is never included in a URL or handed to external destinations.
The bootstrap and iframe use `strict-origin`: `no-referrer` would make form POSTs
send `Origin: null`, causing MTT to reject the handoff.
The bridge regenerates the PHP session and CSRF state, stores only the token ID,
and redirects to a validated local school page. Each request checks token
revocation and user activation. No new database table is required.

MTT's CSP permits framing only by itself and `https://app.thelittlegraduates.in`.
Messages are accepted only from the expected frame and exact MTT origin. The app
checks the displayed user identity. Close returns to the Flutter screen; Previous
page traverses the tool's own history. Loading has a timeout and a retry screen.
MTT hides its duplicate global bar but retains each module's navigation and forms.
The web iframe delegates microphone access only to MTT for Materials voice notes;
the browser still requires the user to grant recording permission.

The browser workspace uses MTT's existing session cookie on the MTT host. Opening
a tool synchronizes that website session to the app's selected account; older
forms cannot submit with their old CSRF secret. App logout revokes the token and
therefore ends the linked workspace session. Browser privacy settings must permit
same-site cookies between the two HTTPS school subdomains.

WhatsApp, telephone, email and public privacy-policy links use their normal apps.
File attachments and printing use the browser/platform facilities. Android/iOS
WebView file-download and printing behavior still needs physical-device QA before
a mobile store release. Web publication does not create a mobile release.

## Checks

- `flutter analyze`, `flutter test`, `flutter build web --release`
- MTT: `php tests/app_workspace_test.php`, `php tests/api_cors_test.php`
- `node scripts/workspace_browser_smoke.cjs` (requires Playwright and Chrome).
  Set `LG_TEST_ORIGIN`, `CHROME_BIN` and optionally `LG_WORKSPACE_JS` to the checked
  out MTT `assets/js/app-workspace.js`. Without the latter, the test fetches the
  deployed bridge script. Test records and endpoint responses are fixtures; it
  never signs into a real staff account or writes a school record.

Set `LG_VERIFY_REAL_BRIDGE=1` for the browser smoke test to also send the invalid
fixture token to the live MTT bridge. It must receive 401 (invalid login), never
403 `origin_denied`. No real staff login or record is used.
