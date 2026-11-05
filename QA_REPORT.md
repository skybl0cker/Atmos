# Atmos QA pass — Nov 5, 2026

Local only, nothing committed. Verified with `dart analyze` (0 issues in
`lib/` and `test/`), `flutter test` (36/36 passing), and a web release build
driven in a phone-sized browser.

## Bugs fixed

| # | Area | Problem | Fix |
|---|------|---------|-----|
| 1 | Background severe alerts (Android) | `plugin.show()` was called without `initialize()` in the background isolate, so it threw (silently) and closed-app severe alerts never fired. | Initialize the plugin first (`services/background_alerts.dart`). |
| 2 | Background alerts | The worker marked *every* alert seen, including advisories it deliberately doesn't announce, so the app never notified about them either. | Only severe/extreme alerts are marked seen in the background. |
| 3 | In-app alerts | Each refresh *replaced* the seen-alert list with the current place's ids, erasing the background worker's record for other places, so they were announced again. | Merge + cap at 300 (`services/seen_alerts.dart`). |
| 4 | Hurricane motion | NHC b-decks repeat each fix per wind radius, so motion was measured between two copies of one fix ("moving N at 0 mph"). | One fix per timestamp (`TropicalService.stormFromBdeck`). |
| 5 | Hurricane position | Label assumed °N/°W (wrong east of the dateline). | Hemisphere-aware label. |
| 6 | Hourly icons | Day/night used a fixed 6 AM–8 PM window. | Uses the forecast's real sunrise/sunset (`WeatherData.isDaylight`). |
| 7 | Errors with data on screen | A failed refresh (offline, location denied) was invisible once any data was showing. | "Offline · updated 3:03 PM · retry" notice in the header. |
| 8 | Home-screen widget | Switching °F/°C didn't redraw the Android widget. | Redraw on unit toggle. |
| 9 | Air quality | Fetched but no longer shown after the redesign. | Back in Details. |
| 10 | Background rain | First place's forecast was downloaded twice per run. | Reused. |
| 11 | Layout | Rain chip, rain-outlook header and offline notice overflowed on narrow screens; header + hero overflowed on 320×568 phones. | Flexible text + temperature scales with screen height. Covered by a small-phone widget test. |
| 12 | Tests | The only test was Flutter's template counter test (referenced `MyApp`, didn't compile). | Replaced with 36 real tests. |

## New features

- **Instant start / offline**: the last forecast is saved and painted on launch
  before the network refresh; works with no connection.
- **Swipe between saved places** on the home hero, with page dots.
- **Rain heads-up chip** ("Rain likely in ~20 min") under the summary.
- **Rain, next 2 hours** bar chart in the sheet when rain is on the way.
- **Today's tips**: umbrella / jacket / sunscreen / hydrate / wind / air-quality chips.
- **More details**: rain chance today, air quality (AQI), moon phase with a drawn phase icon.

## Cleanup

- Ten unused widget files from earlier designs removed (archived in
  `unused_widgets_archive.zip`).
- All analyzer warnings and infos resolved.

## Not verified

- Android/iOS builds: no Android SDK or Xcode on this PC, so background
  workers, notifications, haptics and the home-screen widget were reviewed in
  code only.
- Radio playback (no audio played during testing).
- Swipe-between-places in the browser (covered by unit test only).

## Running the checks

With Flutter on PATH:

    flutter analyze
    flutter test
    flutter build web --release
