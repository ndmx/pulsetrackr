# PulseTrackr Mapbox Setup

PulseTrackr has a Mapbox-powered map view ready in `app/MapboxIncidentMapView.swift`.
It is wrapped in `#if canImport(MapboxMaps)`, so the app keeps building with the current MapKit fallback until the Mapbox SDK is added.

## Credentials

Mapbox iOS requires two tokens:

- Secret SDK download token with `Downloads:Read`, stored outside the repo in `~/.netrc`.
- Public runtime token, injected into the built app as `MBXAccessToken`.

Create `~/.netrc` like this:

```text
machine api.mapbox.com
login mapbox
password YOUR_SECRET_DOWNLOADS_READ_TOKEN
```

Then run:

```sh
chmod 0600 ~/.netrc
```

For the runtime token, keep a local file outside git named `~/.mapbox` containing only the public token. Do not commit either token.

```sh
printf "YOUR_PUBLIC_MAPBOX_TOKEN" > ~/.mapbox
chmod 0600 ~/.mapbox
```

The Xcode target includes an `Inject Mapbox Token` build phase. During builds it reads `~/.mapbox` and writes the token into the generated app `Info.plist` as `MBXAccessToken`.

## SDK

Add this Swift Package in Xcode:

```text
https://github.com/mapbox/mapbox-maps-ios.git
```

Use the `MapboxMaps` product for the `pulsetrackr` target.

Once `MapboxMaps` is available, `PulseMapView` automatically switches from the MapKit fallback to `MapboxIncidentMapView`.
