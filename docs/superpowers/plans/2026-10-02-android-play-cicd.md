# Android Play CI/CD Implementation Plan

Goal: Check Flutter changes and publish signed version tags to internal testing; promote an existing tested version through a protected production environment.

- [ ] Add isolated secret-free CI and serial release workflows pinned to action revisions, Flutter 3.44.8, and JDK 21.
- [ ] Reconstruct signing files from secrets, require release signing, retain only the AAB, and clean signing files on every exit.
- [ ] Implement Play API upload and promotion with explicit package, version validation, and a production-environment protection check.
- [ ] Document secrets, first-upload bootstrap, Play service-account permissions, and version-code allocation.
- [ ] Run existing Flutter tests and analysis, build Android, validate workflow YAML and Python, and open a PR.
