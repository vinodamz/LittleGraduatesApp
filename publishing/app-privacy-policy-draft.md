# Little Graduates app privacy policy — publication draft

Draft reviewed: 27 November 2026. **The business-confirmation items at the end remain unresolved; this file is not the published policy.**

The Little Graduates Android app (`in.thelittlegraduates.app`) is operated by PARENT PETAL LITTLE STEPS LLP for authorized adult school staff and transport drivers. The operator name and contact below match the currently published school policy.

## Information and purposes

The app uses staff names, account identifiers, roles, device labels and sign-in credentials, including the school-issued PIN, to authenticate users and show their permitted tools. A sign-in token and cached profile are kept on the device. Materials background uploads also keep session credentials in app-private storage while signed in.

Transport tools display school-provided schedules, vehicles, routes, child pickup/drop details, stops and parent contact information. Staff record pickup, drop-off and absence status. During a driver-started active trip, the app collects precise location, timestamps, accuracy, speed and heading and sends them to the school transport system for cab tracking, arrival estimates and pickup/drop operations. Collection continues when the app is in the background or the screen is off. Tracking stops when the trip finishes, is cancelled or is stopped locally; signing out also stops local tracking. Android displays an ongoing tracking notification. The app explains location sharing before the driver agrees to continue.

Materials checks include condition marks, notes and staff-selected photos or videos. Videos may contain sound. The app keeps an account-specific offline queue so pending work can be retried when connectivity returns. Android background uploads use an upload notification; some video preparation requires reopening the app.

Staff tools also handle attendance and leave information. Authenticated school pages open inside the app for permitted student/parent records, admissions, assessments, tasks, fees and payment records, expenses, stock, plans and other enabled school workflows. Their form submissions are part of the school app's information processing. The app exchanges its login token with the school backend to establish the embedded session; it does not put that API token in external links.

## Access and external services

Authorized staff access school information according to their account permissions. Families can view their child's cab through the school's private tracking link. User-selected WhatsApp alerts open WhatsApp with the information being shared.

The native live map requests tiles from OpenStreetMap. That service receives network request metadata and tile requests identifying the map area being viewed.

When enabled, WACRM and n8n open in a separate browser after the user chooses to open them. WACRM's configured single sign-on sends the staff account ID, name and role in a short-lived signed integration token; it does not send the school API bearer token. Without configured single sign-on, WACRM uses its own login. n8n may require its own login. Public fee-calculator and receipt links also open separately. A receipt link contains the token used to access that receipt and should be shared only with its intended recipients.

## Device storage and deletion

Successful materials uploads remove the app-managed outbox media copies after server confirmation. This does not delete a user's original gallery/camera files, all cached notes or checks, or the school server's records. Failed or waiting uploads remain available for retry. Account-specific materials caches and pending work can survive app restarts and sign-out.

Signing out removes the app's stored login token and cached sign-in profile; this is not an account-deletion or server-record-deletion operation. It attempts server token revocation, which requires connectivity. The Android application disables its backup and device-transfer stores; pending uploads should finish on the original device before it is erased or replaced.

**Server retention wording remains to be confirmed before publication.** The currently published policy states one year for driver location and trip records. Source code separately has a configurable routine that attempts to delete raw coordinates older than 30 days after location uploads, enabled by default. This does not establish the deployed setting, a guaranteed deletion schedule, trip-record retention, or backup/log retention. Neither duration is adopted here as a new verified business commitment.

## Permissions and communications

Location permissions support active driver-trip tracking. Notification permission supports trip and materials-upload notifications. Photos and videos are attached using device capture/picker controls; available features and permission prompts depend on Android, the device and the capture app. The manifest declares camera and microphone access, but this draft does not promise a separate in-app microphone prompt or unrestricted photo-library access. Permission changes in device settings may prevent the associated feature from working.

The default native school API endpoint uses HTTPS. This is not a claim that every external service or stored record is encrypted at rest. No advertising SDK or Android advertising-ID use was identified in the reviewed native app; the publisher must also verify the final SDK and enabled-service inventory.

## Contact

PARENT PETAL LITTLE STEPS LLP / The Little Graduates

Email: info@thelittlegraduates.in

This is the contact already published by the school for privacy questions and account/record deletion requests. The working inbox, request-verification process, response times, retention exceptions and server-side deletion coverage require operational confirmation; no new processing-time promise is made in this draft.

## Publisher confirmation — do not publish this section as policy text

- Resolve the published one-year statement against deployed coordinate cleanup, trip retention, other school records, backups and logs. Obtain approved retention wording; code defaults are not a retention policy.
- Confirm the existing privacy/deletion contact is monitored and document the actual process, scope and exceptions. Do not carry forward an unverified promise of prompt deletion.
- Confirm hosting providers, enabled external integrations, SDK behavior and recipients; assess the actual records collected through school-controlled WebViews as well as native screens.
- Reconcile Data safety, background-location and foreground-service answers with the final merged Android manifest and real device evidence. A permissions list alone does not determine collection or sharing declarations.
- Update and verify the public policy at https://thelittlegraduates.in/privacy-policy/ before publication. The reviewed live HTML, dated 2 October 2026, lacks Materials and still describes other modules as external-browser pages. This repository edit does not update that website.
