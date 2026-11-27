# Real Android DataSync recording

Workflow: **Android upload demonstration** (`android-demo.yml`). Pull requests
changing the recording workflow or fixture run it automatically. Manual dispatch
is also available after merging to the default branch. Keep existing required
CI/status checks; this workflow is additional evidence, not a replacement gate.
Select the app revision to record and the full MTT source commit SHA. The default
MTT revision is `19c07a772cf12e4d9c36ca4cd8712f31c83b494c`.

The workflow uses Ubuntu 24.04, Java 21, Flutter 3.47.8 and an API 35 x86_64
Google APIs emulator with KVM. The emulator action is pinned to upstream commit
`a421e43855164a8197daf9d8d40fe71c6996bb0d`. Runner tool/SDK inventory and both
source revisions are captured in `runner.txt`; Gradle installs the app's required
SDK/NDK components. No local emulator, signing keys or production credentials are
needed. The app's source/features are not patched for recording.

## Fixture integration

The **app repository's** `tools/demo_backend/{setup,serve,stop}.sh` prepare the
checked-out MTT source, an isolated socket-only MariaDB database and generated
synthetic PNG. The integration uses this existing fixture contract:

```sh
DEMO_UPLOAD_DELAY_SECONDS=30 bash tools/demo_backend/setup.sh .demo-mtt /tmp/lg-android-demo
bash tools/demo_backend/serve.sh /tmp/lg-android-demo 8765
bash tools/demo_backend/stop.sh /tmp/lg-android-demo
```

The fixture manifest is `/tmp/lg-android-demo/fixture.json` with `demo_only`,
`mtt_commit`, `user.id/name/pin`, `materials[].id/name` and `media_file`.
`GET /demo/health` must report `demo_only: true`. Its real MTT APIs handle login,
condition save, multipart upload and authenticated media readback. All records
are synthetic. The server delays the real media request by 30 seconds to leave
the notification visible; this transport condition is disclosed in the summary.
`requests.jsonl` contains safe request audit metadata, not credentials/bodies.

The APK is built with `LG_BASE_URL=http://10.0.2.2:8765`. Do not add `adb reverse`:
it would allow requests to bypass the emulator's offline network condition.

## Recorded sequence and success gates

1. Install the actual debug APK; import the synthetic PNG into Android's gallery.
2. Sign in with the fixture teacher through the app, open Materials, mark the
   first synthetic material Good, and accept Android's real notification prompt.
3. Start continuous Android `screenrecord`. Disable radios and verify that the
   route to `10.0.2.2` is unreachable. Choose the photo using the system picker.
4. Read the app's outbox without modifying it. Require a prepared photo in a
   retryable state after an actual failed foreground upload attempt; hash its bytes.
5. Keep Materials visible and restore Wi-Fi with cellular data left disabled.
   Wait for the already-scheduled WorkManager task's actual DataSync foreground
   service and notification 71041, with the app Activity still resumed. Save
   service and Activity evidence. Do not kill the process, force a job, post a
   notification, inject queue records, or change Android's restrictions.
6. Press Home only after that service starts, then expand the real notification
   shade. Require the visible app notification,
   ID 71041, and WorkManager's `SystemForegroundService` with DataSync type bit
   and `isForeground=true`, while the app Activity is not resumed.
   Wait up to 75 seconds, still subject to the continuous recording's 170-second
   guard. Retain the latest service/notification dumps even when this gate fails.
7. Verify real MTT media readback matches the queued photo's SHA-256; reopen
   Materials, wait for the queue to drain and record the reloaded screen.

The earlier cold-process attempts remain failed diagnostic evidence: Android
denied the foreground-service start. This demonstration covers a service started
while the user is in the app and continuing after Home; it makes no claim of
successful cold-restart foreground-service behavior.

All taps use fresh accessibility labels/resource IDs and observed bounds.
Different picker/semantics behavior fails with screenshots/XML diagnostics;
there are no coordinate-only fallbacks or made-up success results.

The artifact contains `demo.mp4` (unedited, silent screenrecord output),
`summary.md`, event timestamps, screenshots/UI trees, service/notification/job
dumps, queue metadata, upload readback hash, safe backend logs and logcat.
No database, config, token store or signing material is uploaded. Failure
artifacts are explicitly marked diagnostic-only, even if a partial MP4 exists.

Local checks: `python3 -m unittest discover -s scripts/android_demo -p 'test_*.py' -v`
and `bash -n scripts/android_demo/{setup,run,finish}.sh`. They validate the driver,
not the Android app or video. The first real hosted run remains necessary.

Watch the complete successful video before hosting it for Play review. This
demonstrates DataSync with synthetic data; it does not demonstrate the separate
location foreground service or establish Play approval/release-device parity.

References: [official emulator action](https://github.com/ReactiveCircus/android-emulator-runner/tree/a421e43855164a8197daf9d8d40fe71c6996bb0d),
[Ubuntu 24.04 runner inventory](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md).
