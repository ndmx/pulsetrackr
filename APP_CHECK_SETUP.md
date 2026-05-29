# PulseTrackr Firebase App Check Setup

App Check is configured for the Firebase iOS app:

```text
1:689000999730:ios:e77409e6700264ae59c52b
```

## iOS client

- `FirebaseAppCheck` is linked into the app target.
- `FirebaseBootstrap.configureIfAvailable()` installs the App Check provider before `FirebaseApp.configure()`.
- Debug builds use `AppCheckDebugProviderFactory`.
- Release builds use App Attest on iOS 14+ and fall back to DeviceCheck on older supported systems.
- `app/pulsetrackr.entitlements` enables the App Attest production environment.

## Firebase project

The Firebase project `pulsetracker-0000` has:

- Firebase App Check API enabled.
- Apple Team ID `4ZSXLWH9W2` attached to the Firebase iOS app.
- App Attest config patched with a 1-hour token TTL.
- A local development debug token registered for this workstation.

## Local debug testing

The local Xcode user scheme contains `FIRAAppCheckDebugToken` for Debug runs. It lives under `pulsetrackr.xcodeproj/xcuserdata/` and is ignored by git.

Do not commit App Check debug tokens. If a debug token is exposed, revoke it in Firebase Console > App Check > app overflow menu > Manage debug tokens.

## Production notes

- App Store/TestFlight/Release builds should use App Attest.
- Keep App Check enforcement enabled for callable SOS functions.
- Before enforcing App Check on Firestore, watch Firebase App Check request metrics to avoid blocking legitimate users unexpectedly.
