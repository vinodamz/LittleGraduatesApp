# Play Data Safety source inventory

Reviewed 2026-11-27. Scope: Little Graduates Android native screens and the 27 school modules delivered through its controlled workspace. This is a source inspection, not a production traffic capture or an assertion about deployed integration settings.

App branch: `codex/android-upload-demo`; inspected HEAD `008de715b361f0956e7bdfcaa39ffd9b44453e39`. Backend inspected HEAD `eac69d9feda847df25da2d9f397a41f68ce7dec9`. Shared working files were inspected; these hashes identify the checkout, not a verified APK/server match. No Console edits, production submissions, messages, test records, commits, or branch changes were made for this inventory.

## Immediate Console implications

The reported October 2 declaration is incomplete for these sources. Confirmed additions beyond location/name/user IDs/device IDs include **Email address, Address, Phone number, Other info, Health info, Purchase history, Other financial info, Other in-app messages, Photos, Videos, Voice or sound recordings, Files and docs, Other user-generated content, and In-app search history**. CRM also stores contacts/interaction history and appointments: see the specific Contacts and Calendar events rows before completing those categories. Retain App interactions for recorded usage and action events.

**Do not infer bank-account collection from payroll.** Current staff fields contain salary components, deductions and personal details, but no dedicated bank-account/IFSC/card-number input was found. User payment info remains conditional on actual payment-provider flows or intentional collection through configured forms/documents.

**Standalone audio is supported in source:** embedded Plans explicitly accepts a voice file and stores it, and Materials web has a separate voice-recorder/upload path. Native Materials itself exposes photo/video capture. Audio is not inferred from video soundtracks. Android WebView file selection/microphone behavior was not exercised in this review.

## Definitions and decision rules

Primary reference: [Google Play — Provide information for your app's Data safety section (10787469)](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en), especially data collection, sharing, handling, and data types/purposes.

Off-device transmission counts, including controlled WebViews and transient requests. On-device-only processing does not. Optional means users can choose collection; required behavior in any distributed version prevents an optional declaration. Service-provider and user-initiated-transfer exceptions need factual support. Permission declarations alone do not prove collection. The mappings below are findings from this repository, applying those rules.

**Collection status:** Confirmed means an implemented submit/upload/query sends this type off-device when used; it does not mean every user provides it. Conditional means configuration, deployed behavior, or interpretation of a specific payload still needs verification. Not evidenced means this review found no supporting collection path, not a universal guarantee.

**Choice:** R = required for authenticated app use; O = manually supplied/feature opt-in in inspected code. O does not mean every field in that feature can be left blank. If a school or another distributed version makes that collection unavoidable for any user, resolve that before selecting Optional. Access restrictions alone are not proof of optional collection.

**Purposes:** AF = App functionality; AM = Account management; SEC = Fraud prevention, security, and compliance. These are exact Console purpose names. School recordkeeping is AF; do not automatically mark Analytics, Personalization, or Developer communications merely because there are reports, role restrictions, or school messages. Admissions marketing and configured automation purposes need actual-use confirmation.

## Data-type matrix

All persisted submissions below are **not ephemeral**. The search row has a separate retention limitation. A sharing answer is not established by a collection answer; consult the destination table.

| Google category / exact data type | Collection finding and source | Choice / purpose |
|---|---|---|
| Location / Approximate location | Confirmed coarse-location path: Android coarse permission and accepted geolocation fixes; transport sends coordinates. Do not infer location from an IP address unless it is actually used that way. [A4], [B4] | O: driver chooses location sharing/OS permission; AF. |
| Location / Precise location | Confirmed GPS coordinates, saved pickup pins, trip points, speed/heading/accuracy/time. [A4], [B4] | O: location feature; AF. |
| Personal info / Name | Confirmed account names; children, guardians, emergency contacts, staff, applicants, leads, visitors. [B1], [B2], [B3], [B7], [B8], [B10] | R for named school accounts; additional records manual. AF; AM for account identity. |
| Personal info / User IDs | Confirmed login user ID and person-linked student/staff/account identifiers in API/forms. [B1], [B2] | R for account/auth requests; AF, AM; SEC for failed-login controls. |
| Personal info / Email address | Confirmed parent/guardian, relative, applicant and lead fields; configured notification recipient. [B2], [B3], [B8], [B15] | O in inspected forms; AF. AM only if used for managing an account, not merely a school contact. |
| Personal info / Address | Confirmed home/permanent/emergency/parent and staff home-address fields. [B2], [B3] | O fields; AF. |
| Personal info / Phone number | Confirmed guardian, pickup/emergency, staff relative, applicant, visitor and CRM contacts. [B2], [B3], [B7], [B8], [B10] | O to provide/use feature; required for some contact/booking submissions; AF. |
| Personal info / Other info | Confirmed DOB, gender, nationality, occupation/qualification and educational records. Nationality alone does not establish ethnicity. [B2], [B3], [B8], [B18] | O manual records; AF. |
| Financial info / Purchase history | Confirmed fee payments/reference numbers and expense amount/date/merchant/payment method/receipt records. [B5], [B6] | O manual financial workflows; amount/payment fields required for a submitted record; AF. |
| Financial info / Other financial info | Confirmed staff salary/allowances/tax/deductions, expected salary, fee debts/invoices. [B3], [B5], [B8] | O manual payroll/fee workflows; AF. |
| Financial info / User payment info | **Conditional, not proved by local payroll/payment-method labels.** No dedicated bank-account/IFSC/card-number fields found in staff profile/pay sources. Check actual CoFee/payment forms and any intentionally requested banking attachments. [B3], [B14] | Do not select solely because “bank transfer” exists. If collected, AF and feature-specific choice. |
| Health and fitness / Health info | Confirmed blood group, allergies, medical notes; symptoms, temperature, injury, medication/dose/first aid; staff blood group. [B2], [B3], [B10] | O manual health records; some selected health-log fields are needed for that entry; AF. |
| Messages / Other in-app messages | Confirmed transport messages/broadcasts/SOS, staff messages and replies; WhatsApp content submitted through CRM integration. [B4], [B11], [B13] | O compose/send; message body needed to send; AF. |
| Photos and videos / Photos | Confirmed native material photo upload, child/staff images, receipts, logbook/survey photos, plans. [A3], [B2], [B6], [B9], [B10], [B16] | O capture/choose/upload; some configured forms or replacement-evidence workflows may require a photo to finish; AF. |
| Photos and videos / Videos | Confirmed native Materials video capture/selection/upload and web material video upload. [A3], [B9] | O capture/choose/upload; AF. |
| Audio files / Voice or sound recordings | Confirmed standalone Plans voice file input, POST handler, allowed MIME types and file storage. Materials web also records voice separately. [B9] | O upload/record; AF. Native microphone/audio-picker execution not tested here. |
| Files and docs / Files and docs | Confirmed student documents, birth/identity certificates, staff qualifications/ID proofs, recruitment CVs, task attachments, expense PDFs; original filenames/metadata retained. [B2], [B3], [B8], [B6], [B12] | O choose/upload; requiredness varies by selected form; AF. |
| Contacts / Contacts | Confirmed app-managed family/relative/guardian relationships and CRM contact interaction history. This is the mapping for those contact records, **not** a claim of Android address-book or device-call-log access. [B2], [B3], [B7] | O manual/imported contacts and contact actions; AF. Include when declaring the CRM/contact-management feature. |
| Calendar / Calendar events | Confirmed CRM appointment date/slot and associated family/notes, displayed in CRM calendar. This is an app-managed appointment calendar, **not** device-calendar import. [B7] | O appointment booking; date/slot needed to book; AF. Mere task due dates or calendar-shaped UI alone do not add this type. |
| App activity / App interactions | Confirmed token last-used time, notification read markers, CRM call/WhatsApp click audit and workflow actions. [B1], [B7], [B15] | R for automatic authenticated last-use tracking; optional actions add events. AF; SEC where used for security audit. |
| App activity / In-app search history | Confirmed search text leaves device as `q` in Students, CRM, Materials; CoFee member-name search also goes off-device. [B17], [B14] | O user search; AF. Dedicated retained search-history table not established; web/access logs and external-provider retention not verified, so do not assert ephemeral processing. |
| App activity / Other user-generated content | Confirmed notes, duty comments, plan text, observations, feedback, surveys and task descriptions where no more specific type applies. [B9], [B10], [B12], [B16], [B18] | O manual content; content necessary when submitting that record; AF. |
| Device or other IDs / Device or other IDs | Confirmed unique per-device/app bearer token, stored token hash/device label, resent for API/workspace authentication. No evidence here of advertising ID/IMEI collection. [A2], [B1] | R for authenticated use; AF, AM; SEC for credential/audit controls. |

### Types not established by the inspected implementation

| Exact type | Decision and boundary |
|---|---|
| Race and ethnicity; Political or religious beliefs; Sexual orientation | No dedicated collection field found. Do not infer from nationality, gender, a photograph, or arbitrary free text. Configurable surveys/external apps still need their actual question sets checked. |
| Credit score | No score collection/integration found. Fees owed are Other financial info. |
| Fitness info | No exercise/fitness tracking found. Classroom gross/fine motor observations are educational observations; medical observations are Health info. |
| Emails | No mailbox/email-content import found. Configured outgoing notification email exists; verify whether any deployed external tool handles users' email content before adding this category. Email address is already confirmed. |
| SMS or MMS | No SMS/MMS inbox reading or SMS transport found. WhatsApp messages belong under Other in-app messages. |
| Music files; Other audio files | No music-specific or additional audio-content workflow established. Explicit voice memos justify Voice or sound recordings; an accepted MP3 extension alone does not establish music collection. |
| Installed apps | No installed-app inventory collection found. Opening WhatsApp/browser is not such an inventory. |
| Other actions | No additional distinct type established beyond the recorded App interactions and more specific school records above; do not duplicate the same taps here without a separate payload rationale. |
| Web browsing history | School workspace navigation is not evidence of collecting general browsing history. Arbitrary browser-history harvesting not found; external tools and server logs remain unverified. |
| Crash logs; Diagnostics; Other app performance data | No native telemetry/crash-upload SDK found in pubspec. Backend error logs and optional MCP debug/audit logging exist, but this review did not establish exported native crash/performance telemetry. Check deployed logging/monitoring before a blanket “not collected” claim. |

## Coverage of all 27 module destinations

The authoritative catalog is [B1]; the native registry is [A1]. All authenticated modules inherit User IDs, app/device tokens and last-use events. Rows list additional records beyond that common layer. Unless stated otherwise, purpose is AF and manually submitted feature data is O subject to the matrix's requiredness caveat. A displayed server record is not itself a new upload; the cited create/edit paths establish collection.

| # | Module key / delivery | Records and exact types beyond common auth; evidence |
|---|---|---|
| 1 | `my_day` / embedded | Dashboard for attendance, plans and logbook shortcuts. Reuses linked workflows; no separate new datatype from dashboard rendering. `today.php:1`, [B10], [B18]. |
| 2 | `duties` / embedded | Completion/status/reasons, comments/extra work: App interactions; Other user-generated content. `duties/index.php:32`. |
| 3 | `tasks` / embedded | Assignees, descriptions, due dates, attachment uploads: Name; Other user-generated content; Files and docs; Photos when an image is uploaded. `tasks/tasks.php:80`, `:311`; [B12]. |
| 4 | `materials` / native + linked web | Condition notes/marks, photos/videos; separate web voice memos: Other user-generated content; Photos; Videos; Voice or sound recordings. Shelf “location” is not geolocation. [A3], [B9]. |
| 5 | `plans` / embedded | Weekly activities/notes and photos/voice files: Other user-generated content; Photos; Voice or sound recordings. [B9]. |
| 6 | `staff` / native + linked school forms | Native attendance/leave; school profile, health, payroll, files and messages: Name; Email address; Address; Phone number; Other info; Contacts; Health info; Other financial info; Photos; Files and docs; Other in-app messages; Other user-generated content. Native attendance does not upload GPS. [A5], [B3], [B11]. |
| 7 | `my_leave` / embedded | Leave dates/type/reason/decision: Other user-generated content; Other info; Health info when medical reasons are supplied. `staff/leave.php:38`; same staff workflow. |
| 8 | `notifications` / embedded | Read markers/preferences: App interactions. Notification content reuses source workflow; configured email channel described below. [B15]. |
| 9 | `students` / embedded | Child/guardian/emergency records, medical/allergy details, photos/docs, fees: Name; Email address; Address; Phone number; Other info; Contacts; Health info; Photos; Files and docs; Purchase history; Other financial info. [B2], [B5]. |
| 10 | `montessori` / embedded `/assessment/` | Educational baseline/observations/progress: Other info; Other user-generated content, linked child/teacher identity. [B18]. Do not automatically label every learning observation Health/Fitness. |
| 11 | `daycare` / embedded | Staff/child check-in/out, comments: App interactions; Other info; Other user-generated content. `daycare/index.php:32`. |
| 12 | `logbook` / embedded | Visitors/pickup/incident/health/medication/observation and photos: Name; Phone number; Other info; Health info; Photos; Other user-generated content. [B10]. |
| 13 | `transport` / native + school desk | Trip/roster/pickup coordinates, driver contacts, passenger status, messages: Approximate location; Precise location; Name; Phone number; Other info; Other in-app messages; App interactions. [A4], [B4]. |
| 14 | `crm` / embedded | Leads/families/contact timeline, searches, appointments, outgoing WhatsApp actions: Name; Phone number; Email address where entered; Other info; Contacts; Calendar events; In-app search history; Other in-app messages; Other user-generated content; App interactions. [B7], [B13], [B17]. Confirm actual admissions marketing use separately. |
| 15 | `recruitment` / embedded | Candidate name/contact/qualifications/salary expectation/CV/evaluation: Name; Phone number; Email address; Other info; Other financial info; Files and docs; Photos for image CV; Other user-generated content. [B8]. |
| 16 | `fees` / embedded | Fee calculation/enrolment and linked student invoice/payment records: Name; Phone number; Email address; Purchase history; Other financial info; Other user-generated content. User payment info remains conditional. [B5], [B14]. |
| 17 | `expenses` / embedded | Amount, merchant/date/payment method, descriptions, receipt files/photos and OCR text: Purchase history; Other financial info where reimbursement/debt applies; Files and docs; Photos; Other user-generated content. [B6]. |
| 18 | `money` / embedded | Aggregates fee/invoice/expense/child financial records; no separate new upload from viewing totals. Financial types inherited from Students/Fees/Expenses. `money.php`, [B5], [B6]. |
| 19 | `inventory` / embedded | Assigned person, supplier/purchase details, stock/condition notes: Name when person-assigned; Purchase history for recorded purchases; Other user-generated content. `inventory/edit.php:39`. Shelf/location label is not GPS. |
| 20 | `wacrm` / configured external embed | SSO identity and configured CRM messages/contacts/files: Name; User IDs; Other info (role); Phone number; Other in-app messages; Files and docs for document sends. Full remote app schema not inspected; verify extra types/configuration. [B13]. |
| 21 | `duties_admin` / embedded | Assignees, recurring templates, notes: Other user-generated content; App interactions; linked account identity. `duties/admin.php:29`. |
| 22 | `feedback` / embedded | Parent/child association, comments/discussion/resolution: Name; Other user-generated content. `feedback/edit.php:25`. Specific health/financial information remains classified by its specific type if explicitly solicited. |
| 23 | `surveys` / embedded | Configurable questions/responses/photo uploads: Other user-generated content; Photos; identity/contact/health types only where actually requested by current questions. Source definitions and server collection are [B16]; production custom definitions not read. |
| 24 | `grades` / embedded | Grade labels/promotion configuration: Other user-generated content; App interactions. No new sensitive type from grade configuration alone. `grades.php:27`. |
| 25 | `admin` / embedded | User names/PINs/roles/access and integration settings: Name; User IDs; Other info; App interactions; AM in addition to AF. `admin.php:36`. Credentials/settings are not advertising IDs or bank accounts. |
| 26 | `mcp_admin` / embedded | Token labels, OAuth clients, revocation/debug/audit controls: User IDs; App interactions; Other user-generated content; AF/AM/SEC. External clients may retrieve school records through authorized tools; enabled clients/scopes/use must be audited. `mcp_admin.php:24`, `includes/mcp.php:163`. |
| 27 | `n8n` / configured external embed | Configured automation UI/workflows: local code proves the external launch/frame, not remote workflow payloads, recipients, retention or all datatypes. Do not declare this destination data-free. [B13]. |

## Destinations and sharing: what source proves, what remains open

| Destination/path | Data transfer supported by source | Remaining decision |
|---|---|---|
| MTT API and controlled workspace | Auth token and all submitted school records go to configured MTT backend; SQL/files persist records. [A2], [B1–B18] | Establish actual operator/first party and processors. An own backend does not itself prove onward sharing is absent. |
| OpenStreetMap tiles | Native live map calls `tile.openstreetmap.org` with map tile coordinates; endpoint receives network metadata and requested map area. [A4] | Location-related third-party network path is real in code; verify service terms/handling and any applicable sharing exception. No student names/phones found in the tile URL. |
| WACRM / WhatsApp | Configured WACRM SSO contains user ID/name/role; server sends recipient phone, text/template variables and document links/filenames/captions. [B13] | Confirm active URL/operator, forwarding to Meta/other processors, attachments, automation triggers, recipients and actual purposes. Do not assume every send is exempt merely because one UI action can initiate it. |
| n8n | Configured external URL/frame; workflow code and live credentials/settings are outside this inspected repository. [B13] | Need enabled workflows, integrations, data inputs/outputs and ownership. No honest exhaustive sharing/type answer is possible from the frame wrapper alone. |
| CoFee | Member name/mobile/email/guardian name/admission date sent to `api.cofee.life`; member-name searches and enrolment/billing actions. [B14] | Verify enabled integration and downstream payment data. Financial account/card collection was not demonstrated by local forms. |
| Google Drive | Materials audit ZIP can be uploaded to configured Drive service-account folder. [B19] | Confirm feature enabled, actual archive contents, folder access and processor relationship. Photos/videos/audio/documents/notes can be involved depending on archive contents. |
| Email delivery | Configured notification recipient email, title/body/link sent using PHP mail. [B15] | Confirm settings, mail provider and payloads. No send was performed. |
| Fonts / OCR dependency CDN | Embedded header loads Google Fonts; Expenses loads Tesseract.js via jsDelivr. OCR executes in browser; resulting text is submitted to MTT. [B6], [B20] | External asset requests expose normal network metadata; source does not show receipts uploaded to a cloud OCR service. Provider logging/identification use unverified. |
| MCP/OAuth clients | Admin can create/revoke clients/tokens; API audit/debug mechanisms exist. | Confirm actual enabled clients/tool permissions and school records supplied to them; do not infer a particular AI vendor or remote recipient. |

No production configuration, provider agreement, remote WACRM/n8n implementation, custom survey definitions, web-server logs, or deployed SDK telemetry was inspected. Consequently this inventory does **not** certify “no sharing,” universal encryption, deletion/retention policy, or any marketing/analytics practice. Those are concrete release-owner checks, not inferred business policy.

## Evidence index

Paths below point to the inspected shared checkout. Additional `path:line` references in the module table are relative to `/Users/vinodamz/LGApps/MontessoriTraineeTeacher`.

- **A1:** [native registry](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/core/module_registry.dart:13); [27-module grouping](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/features/home/school_catalog.dart:1).
- **A2:** [workspace token/path POST](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/features/workspace/workspace_view_native.dart:95); [API client](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/core/api_client.dart); [dependencies](/Users/vinodamz/LGApps/LittleGraduatesApp/pubspec.yaml).
- **A3:** [native image/video picker](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/features/materials/materials_screen_native.dart:321); [material mark/upload API](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/features/materials/materials_api.dart:272).
- **A4:** [location permissions](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/features/transport/location_tracker.dart:40); [point upload](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/features/transport/location_tracker.dart:106); [OSM tiles](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/features/transport/live_screen.dart:172); [consent](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/features/transport/trip_screen.dart:78).
- **A5:** [native staff API payloads](/Users/vinodamz/LGApps/LittleGraduatesApp/lib/features/staff/staff_api.dart:157).
- **B1:** [login/device tokens/last-use and 27-module catalog](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/api.php:76); [login request](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/api/v1/login.php:2); catalog starts at line 170.
- **B2:** [student health/contact persistence](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/students/edit.php:43); [guardian fields](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/students/parent_form.php:133); [documents](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/students/documents.php:167).
- **B3:** [staff profile fields and storage](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/staff.php:1203); [pay components](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/staff/pay.php:31); [staff photo/ID/certificates](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/staff/apply.php:175).
- **B4:** [transport location payload](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/api/v1/transport/location.php:3); [message persistence](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/transport_ops.php:168); [cab contact persistence](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/transport.php:310).
- **B5:** [invoice/payment storage](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/students/fees.php:56); payment storage at line 105.
- **B6:** [expense fields and storage](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/expenses/edit.php:125); [browser OCR](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/assets/js/expenses-ocr.js:1).
- **B7:** [CRM contact/appointment entry](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/crm/book_visit.php:62); [CRM calendar](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/crm/calendar.php); [contact-action audit](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/crm/log_action.php:3); [lead editor](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/crm/edit.php).
- **B8:** [candidate fields/salary](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/recruitment/edit.php:43); CV file input at line 240.
- **B9:** [Plans voice upload handler](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/plans/edit.php:72); [standalone voice file input](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/plans/edit.php:233); [audio MIME allowlist](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/plans.php:26); [voice file persistence](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/plans.php:638); [Materials web voice recorder](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/materials/index.php:1029).
- **B10:** [logbook field definitions](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/logbook.php:27); [entry storage](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/logbook/add.php:71).
- **B11:** [staff messages/replies](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/staff/messages.php:24).
- **B12:** [task fields](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/tasks/tasks.php:80); [attachment handler](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/tasks/tasks.php:311).
- **B13:** [external integration registry](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/functions.php:154); [SSO payload](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/functions.php:205); [WhatsApp payload/send](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/functions.php:267); [external frame](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/external_app_view.php:21); [native workspace external handoff](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/app/external.php:46).
- **B14:** [CoFee member payload](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/fees/cofee_exec.php:47); [CoFee host/client](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/cofee_api.php:17).
- **B15:** [notification preferences/email/records](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/notify.php:1); [read markers](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/notify.php:143).
- **B16:** [survey answer/photo submission](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/survey.php:81); [configurable question types](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/surveys.php:1597).
- **B17:** [student server search](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/students/index.php:22); [CRM server search](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/crm/leads.php:23); [material server search](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/materials/daily.php:139).
- **B18:** [assessment baseline fields/storage](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/assessment/baseline.php:27); [My Day entry points](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/today.php:1).
- **B19:** [Drive export action](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/materials/gdrive_push.php:22); [Drive upload client](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/gdrive.php:104).
- **B20:** [Google Fonts requests](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/includes/header.php:19); [OCR dependency CDN](/Users/vinodamz/LGApps/MontessoriTraineeTeacher/expenses/edit.php:435).

Validation performed: inspected native registry/catalog and API/embedded source paths; traced representative fields to POST handlers, SQL/file persistence and outgoing integrations; checked Google's official definitions; checked document module count and evidence targets. No runtime UI/network test, build, production write, third-party send, or exhaustive external-service review was performed for this document.
