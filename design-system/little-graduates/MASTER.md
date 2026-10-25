# Little Graduates — School operations design system

## Purpose
A staff workspace for daily school operations. Prioritize attendance, safe transport, and shelf checks. Keep existing role permissions, routes, API calls, and offline upload behavior intact.

## Visual direction
Use the Minimalism / Swiss Style recommendation from UI UX Pro Max's school operations dashboard search: clear hierarchy, low-cost effects, and functional spacing. Retain the existing berry brand rather than adopting the generic blue recommendation. Marketing sections and conversion CTAs do not apply to this authenticated workspace. Avoid glass, blur, and gratuitous animation.

## Tokens
The implementation source of truth is `lib/core/theme.dart`.
- Background: #F7F7FA; surface: #FFFFFF; border: #E5E3EC.
- Accent: #9D2453; accent surface: #F8EAF0.
- Primary text: #282638; secondary text: #646174.
- Success, warning, error, and information each have a foreground and pale background pair.
- Use the bundled Inter variable font (OFL license in `assets/fonts/OFL.txt`) with 30px page headings, 22px card headings, and 15–16px body text. Support system text scaling.
- 4/8px spacing rhythm; 16–24px card padding; 18px card corners; 24px feature panel corners.
- Material icons and native buttons with visible focus and pressed feedback; minimum 48px interactive targets.

## Information architecture
- Today: greeting and date, active trip and pending uploads, real daily summary, attendance action, shortcuts, upcoming trips, other permitted modules.
- Transport: retain role-specific tabs, trips, alerts, and live tracking.
- Staff: attendance, leave, duties, and roster.
- Materials: daily completion progress, upload state, search and shelf filter, shelf checks.
- School: searchable directory of every permitted module, user profile, privacy, and sign-out.
- Native tools open in their tab. Other school tools open in the shared authenticated workspace with Close, Previous page, loading feedback, and retry. Keep MTT module navigation and forms; hide the duplicate global header. External contact actions remain external.

## Responsive behavior
Bottom navigation on phones; navigation rail at 840px; expanded rail at 1200px. Bound main content to 1120px, login to 560px. Summary cards use three columns at standard text sizes and reflow for large text; shortcuts wrap; no fixed-height text cards. Preserve visited tabs so changing sections does not discard searches or scroll position. Load sections only when first visited.

## Data and states
Never fabricate totals or telemetry. Show loading/unavailable instead of zero when data is missing. Expose attendance/trip retries; retain pull-to-refresh. Keep pending material uploads visible. Keep permission-gated modules out of navigation and search. This release uses the existing light theme; no dark theme is exposed.
