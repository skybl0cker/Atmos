# Atmos – radar-first weather app

A Flutter weather app for people who actually watch the sky. Live radar with
measured storm motion and model "future radar", a 14-day forecast, and a
severe-weather situation room that follows the closest threat — hurricanes,
tornado outbreaks, earthquakes, and the news around them.

- **Web app:** https://skybl0cker.github.io/Atmos/ (installable via Safari → Add to Home Screen)
- **Android:** every push to `main` builds a signed release APK + Play Store app bundle, published to the rolling "Latest build" GitHub release. Package: `com.skybl0cker.atmos`, current version 1.2.0.
- **Play Store:** in progress — see `play-store/` for the privacy policy, feature graphic, and listing copy.

## What it does
- **Radar timeline** — RainViewer observed frames → RainViewer nowcast → SkyCast-measured +30/+60 min echo-motion extrapolation (cross-correlation of the two latest tiles, falling back to layer-mean steering wind) → HRRR simulated reflectivity from +90 min to +6 h (badged MODEL).
- **Situation room (4th tab)** — active NWS warnings nationwide drive a dynamic tab (hurricane, tornado emergency, quake…). Inside: live tropical cyclones from NHC best-track data (name, category, wind, pressure, movement, track map with warning polygons), significant USGS earthquakes ranked by distance from you, and related news headlines.
- **Forecasts** — 14-day daily (Open-Meteo), hourly details, rain-start notifications, NWS alerts with official safety instructions.

## Setup
```bash
flutter pub get
flutter run
```

## Platform permissions
**Android** – `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```
(Web/desktop: GPS works on web over HTTPS; city search works everywhere.)

## Data sources (all free, no keys)
- Forecast + air quality: Open-Meteo. Air quality is US AQI; pollen isn't included because Open-Meteo only covers Europe.
- Radar: NEXRAD base reflectivity mosaic from the Iowa Environmental Mesonet (Iowa State) — continental US only; the radar screen explains coverage outside that area. Short-term frames: RainViewer. Future radar: HRRR via IEM.
- Alerts: US National Weather Service active alerts (US only).
- Tropical cyclones: NHC homepage (active storm names) + ATCF best-track b-deck files (position/intensity/track).
- Earthquakes: USGS (M5.5+, last 7 days).
- News: Google News RSS.
- Map tiles: OpenStreetMap (fine for a small app; use a tile provider account if usage grows).

## Accuracy notes
Model output is always badged as model output. Echo-motion extrapolation can't guarantee individual storm placement or predict new convective development — growth/decay modelling is the known next frontier.

## Notifications, haptics & radio
- **Notifications**: local only, no server. A check runs when the app opens or you pull to refresh — unseen NWS alerts fire a notification then. Not background push; a true instant-warning system needs WorkManager/BGTaskScheduler, not set up here.
- **Haptics**: short vibration once per refresh when it's raining or storming. Toggle in the drawer.
- **Weather radio**: NOAA doesn't stream NWR itself; the station list is volunteer SDR relays via weatherusa.net — coverage is patchy and streams can vanish without warning.

## Privacy
No accounts, no ads, no analytics. Location is sent to weather data providers only to fetch your forecast/radar and is never stored on any server. See `play-store/privacy-policy.html`.
