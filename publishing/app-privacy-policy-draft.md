# Little Graduates app privacy policy — publication draft

Draft reviewed: 27 November 2026. **This file is a publication draft aligned with the updated November school policy; publisher follow-up items are listed at the end.**

The Little Graduates Android app (`in.thelittlegraduates.app`) is operated by PARENT PETAL LITTLE STEPS LLP for authorized adult school staff and transport drivers. The operator name and contact below match the currently published school policy.

## Information and purposes

The app uses staff names, account identifiers, roles, device labels and sign-in credentials, including the school-issued PIN, to authenticate users and show their permitted tools. A sign-in token and cached profile are kept on the device. Materials background uploads also keep session credentials in app-private storage while signed in.

Transport tools display school-provided schedules, vehicles, routes, child pickup/drop details, stops and parent contact information. Staff record pickup, drop-off and absence status. During a driver-started active trip, the app collects precise location, timestamps, accuracy, speed and heading and sends them to the school transport system for cab tracking, arrival estimates and pickup/drop operations. Collection continues when the app is in the background or the screen is off. Tracking stops when the trip finishes, is cancelled or is stopped locally; signing out also stops local tracking. Android displays an ongoing tracking notification. The app explains location sharing before the driver agrees to continue.

Materials checks include condition marks, notes and staff-selected photos or videos. Videos may contain sound. The app keeps an account-specific offline queue so pending work can be retried when connectivity returns. Android background uploads use an upload notification; some video preparation requires reopening the app.

Plans accepts standalone voice-file attachments, and Materials school pages support voice notes. These recordings are stored as part of the relevant school record. Available upload and recording controls depend on the page, device and app version.

Staff tools also handle attendance and leave information. Authenticated school pages open inside the app for permitted student/parent records, admissions, assessments, tasks, fees and payment records, expenses, stock, plans and other enabled school workflows. Their form submissions are part of the school app's information processing. The app exchanges its login token with the school backend to establish the embedded session; it does not put that API token in external links.

Depending on account permissions and the records entered, school tools process student and staff health information, including blood group, allergies and medical, incident or medication notes; staff salary components, allowances and deductions; and school fees, invoices, payments and expenses. Family, guardian and CRM contact records include contact details, interaction history, appointment dates and related notes. These records support school care, administration, payroll, billing and admissions communications.

## Access and external services

Authorized staff access school information according to their account permissions. Families can view their child's cab through the school's private tracking link. User-selected WhatsApp alerts open WhatsApp with the information being shared. The school uses its connected services only to deliver school services.

The native live map requests tiles from OpenStreetMap. That service receives network request metadata and tile requests identifying the map area being viewed.

When enabled, WACRM and n8n open in a separate browser after the user chooses to open them. WACRM's configured single sign-on sends the staff account ID, name and role in a short-lived signed integration token; it does not send the school API bearer token. Without configured single sign-on, WACRM uses its own login. n8n may require its own login. Public fee-calculator and receipt links also open separately. A receipt link contains the token used to access that receipt and should be shared only with its intended recipients.

## Device storage and deletion

Successful materials uploads remove the app-managed outbox media copies after server confirmation. This does not delete a user's original gallery/camera files, all cached notes or checks, or the school server's records. Failed or waiting uploads remain available for retry. Account-specific materials caches and pending work can survive app restarts and sign-out.

Signing out removes the app's stored login token and cached sign-in profile; this is not an account-deletion or server-record-deletion operation. It attempts server token revocation, which requires connectivity. The Android application disables its backup and device-transfer stores; pending uploads should finish on the original device before it is erased or replaced.

Retention of raw driver-location coordinates depends on the school's configured cleanup settings and can differ from retention of trip records and other school information. Contact the school at **info@thelittlegraduates.in** for the applicable retention periods, including for staff, child and parent records. To request deletion of an app account or associated information, use the same address and identify the account or records concerned. The school handles deletion requests manually after verifying the request.

## Permissions and communications

Location permissions support active driver-trip tracking. Notification permission supports trip and materials-upload notifications. Photos and videos are attached using device capture/picker controls. School-page attachments, including existing voice files and documents, use file-selection controls where available. Selecting an existing voice file does not itself activate the microphone. Available features and permission prompts depend on Android, the device, the page and the capture app. The manifest declares camera and microphone access, but this draft does not promise a separate in-app microphone prompt or unrestricted photo-library access. Permission changes in device settings may prevent the associated feature from working.

The default native school API endpoint uses HTTPS. This is not a claim that every external service or stored record is encrypted at rest. No advertising SDK or Android advertising-ID use was identified in the reviewed native app; the publisher must also verify the final SDK and enabled-service inventory.

## Contact

PARENT PETAL LITTLE STEPS LLP / The Little Graduates

Email: info@thelittlegraduates.in

This is the contact already published by the school for privacy questions and account/record deletion requests. The working inbox, request-verification process, response times, retention exceptions and server-side deletion coverage require operational confirmation; no new processing-time promise is made in this draft.

## Publisher confirmation — do not publish this section as policy text

- Retain the published November wording: coordinate retention depends on configured cleanup, and the school supplies applicable retention periods on request. Confirm those operational periods for coordinates, trips, other school records, backups and logs; do not replace them with a duration inferred from code defaults.
- Confirm the existing privacy/deletion contact is monitored and document the actual process, scope and exceptions. Do not carry forward an unverified promise of prompt deletion.
- The operator confirmed that connected services are used only for school services. Keep the enabled-provider, workflow and recipient inventory consistent with that purpose; this confirmation does not establish each provider's independent data handling or a blanket Play sharing exemption.
- Reconcile Data safety, background-location and foreground-service answers with the final merged Android manifest and real device evidence. A permissions list alone does not determine collection or sharing declarations.
- The public policy was updated on 27 November 2026 through website merge `2b1f788`, including Materials, authenticated in-app pages and configurable-retention/contact-school wording. Publish this follow-up's school-record and standalone-voice additions, then verify them at https://thelittlegraduates.in/privacy-policy/. Editing these source files does not itself deploy the follow-up.
- Verify the pending Android school-page file-selector fix in the final build for Plans voice files and other attachments. File-selection support does not establish in-page microphone recording support; do not describe the pending fix as already released or device-tested.
