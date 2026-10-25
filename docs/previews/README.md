# School operations redesign previews

These images are rendered from the actual Flutter widgets using isolated test fixtures. Names and counts are sample data; production screens continue to use the school APIs.

- `today-phone.png`: daily overview and attendance on a 390 × 844 phone.
- `school-phone.png`: searchable tools directory on the same phone.
- `today-tablet.png`: 1440 × 1000 workspace with navigation rail.

Regenerate from the repository root:

```sh
flutter test --no-pub test/operations_design_test.dart --dart-define=LG_DESIGN_PREVIEWS=true
```

Validation: Flutter 3.47.8, Dart 3.13.7. All 39 tests pass; `flutter analyze --no-pub` reports no issues. Layout tests cover 375px phone width, landscape, tablet, and desktop at 2× text size with reduced motion. Existing privacy, transport API, and offline materials queue tests remain green. The lockfile includes four test/SDK dependency changes required by this Flutter version.

This change updates the native app. Tools that open external MTT website pages retain their existing website UI. Light mode is the app's only exposed theme. Device-level GPS/background upload behavior and authenticated production data have not been exercised in these widget tests.
