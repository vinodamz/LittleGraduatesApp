# Isolated Android upload demonstration backend

This runs **real MTT PHP API code and real MariaDB**, with synthetic data. It is not a substitute implementation of the API. It does not access a production database, send school messages, or call an external integration. Only login/session and Materials API routes are exposed. Do not use it as a production server.

Stable UI values for the recording:

- School: **Little Graduates Demo**
- Staff name: **Demo Materials Teacher**
- PIN: **654321** (public, synthetic test credential)
- Materials: **Demo Pink Tower**, **Demo Number Rods**
- Location: **Demo shelf**
- Generated gallery image: `<runtime>/demo-material.png`
- Generated machine-readable identifiers: `<runtime>/fixture.json`

## Runner interface

The workflow owns checkout and dependencies. On an Ubuntu runner, install `mariadb-server mariadb-client php-cli php-mysql php-mbstring php-gd`, plus Git and Python 3. Check out `vinodamz/MontessoriTraineeTeacher` **at commit `19c07a772cf12e4d9c36ca4cd8712f31c83b494c`** into a separate source directory. Setup records the exact source HEAD. The scripts in this directory belong to the app checkout, not the MTT checkout. No GitHub or production secrets are needed by this backend.

```sh
bash tools/demo_backend/setup.sh "$MTT_SOURCE_DIR" "$RUNNER_TEMP/lg-demo"
bash tools/demo_backend/serve.sh "$RUNNER_TEMP/lg-demo" 8765 > "$RUNNER_TEMP/lg-demo/http.log" 2>&1 &
# Wait for http://127.0.0.1:8765/demo/health before building/recording.
python3 tools/demo_backend/smoke.py "$RUNNER_TEMP/lg-demo"
# Planck owns the build and UI recording:
# flutter build apk --debug --dart-define=LG_BASE_URL=http://10.0.2.2:8765
```

Setup requires at least 256 MiB free disk space and a **new** runtime directory and creates its own MariaDB data directory and Unix socket, with TCP networking disabled. It does not use any runner-wide database or credentials. Only committed `api/`, `includes/`, `sql/`, and `migrate.php` are archived from MTT. Existing configuration, uploads and dumps are excluded. Configuration is generated for the new local socket, then MTT's schema and migrations run before synthetic seeding. Seed refuses an existing user population. Never point the setup at a production data directory.

The debug manifest permits HTTP. Both the regular API client and Materials background worker use `AppConfig.baseUrl`. For the Android emulator use `http://10.0.2.2:8765`, the host loopback alias, without `adb reverse` when testing radio-off behavior. The seed leaves `site_base_url` empty so MTT derives media URLs from each request's Host header: device requests return `10.0.2.2` URLs, while host smoke requests return `127.0.0.1` URLs. Alternatively, for a connected device use `adb reverse tcp:8765 tcp:8765` and build with `http://127.0.0.1:8765`; an adb tunnel may remain reachable when the device radios are disabled. This does not change the release app's HTTPS endpoint or network policy. The backend rejects all non-demo routes rather than redirecting them elsewhere.

The archive is the committed checkout HEAD, not any uncommitted source changes. `mtt-commit.txt`, `fixture.json` and `/demo/health` identify it. If upstream migrations or authentication change, setup/smoke must fail visibly; do not quietly replace the backend with fake responses.

## Deliberately slow upload acknowledgement

The demo router sleeps **20 seconds** before invoking the real `api/v1/materials/media.php`. PHP has already received the multipart request at that point. This delays server processing/acknowledgement, not the network bandwidth itself. Login, material lists, checks and media downloads have no artificial delay. Four PHP workers allow those requests while an upload is waiting.

Set `DEMO_UPLOAD_DELAY_SECONDS=2` for a quick smoke setup, or write an integer from 0 to 120 into `<runtime>/upload-delay-seconds` between runs. The value is read for each upload. The application's five-minute multipart timeout accommodates this delay. Do not invent a foreground-service notification: the app must actually schedule/run WorkManager and display its own notification. Planck must verify the running service and the notification in the recording. A delayed response alone does not prove that the background worker, rather than a foreground UI upload, performed the transfer.

Use synthetic gallery media, mark a condition, attach the image, and exercise the actual user upload path. The smoke test uploads to Demo Number Rods so Demo Pink Tower remains clear for the UI recording; it does not replace the UI demonstration. It uses a fresh client key, retries it, and verifies authenticated media bytes. It writes `smoke-report.json` without storing the login token. Reset the emulator/app data for a clean take; for a clean database, create another new runtime rather than reusing one.

Label the recording/evidence honestly: **debug Android build, synthetic school account/media, real MTT API, isolated MariaDB, intentionally delayed upload acknowledgement**. Record the app/backend commit IDs, emulator/API version and observed service type. Do not claim that this demonstrates the deployed backend, a release-signed build, production performance, or Google approval.

## Evidence and shutdown

Keep `fixture.json`, `mtt-commit.txt`, `smoke-report.json`, `requests.jsonl`, migration logs, and the workflow's recording/service evidence. Request logs contain method, route, response status and elapsed/delay times, not PINs, bearer tokens or request bodies. Keep the fake-data label with any shared evidence.

Stop the PHP server process/group started by the workflow, then:

```sh
bash tools/demo_backend/stop.sh "$RUNNER_TEMP/lg-demo"
```

Shutdown leaves generated runtime data and logs intact for diagnosis. Delete that disposable runtime only after evidence is retained. For alternate local binary locations, setup accepts `MARIADB_BIN`, `MARIADBD_BIN`, `MARIADB_INSTALL_DB_BIN`, `MARIADB_ADMIN_BIN`, and optional `DEMO_MARIADB_BASEDIR`; these select binaries only, never a remote database.

## Verification performed

The setup imported the real schema and completed migrations on local MariaDB 10.11.20. The pinned revision above has the identical `sql/` Git tree (`5927b47bce7a037ecb6a9c9c2111e0cc6679ee14`) to that fresh bootstrap; its migrations were also rerun. Against the pinned PHP API, the real HTTP smoke passed login, condition write, delayed multipart upload, duplicate-client-key retry with a single persisted row, SHA-256 byte readback, unauthenticated file denial, emulator Host URL generation, and denial of non-demo routes. PHP 8.5.12 was used locally; the Ubuntu PHP 8.3 runner and actual Android foreground service/video remain workflow checks. These are HTTP/database tests, not native UI or foreground-service proof.
