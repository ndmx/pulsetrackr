PulseTrack owns Firebase Hosting for `pulsetracker.org` and `pulsetracker-0000.web.app`.
Its `frontend/public/.well-known/apple-app-site-association` and `/i/**` rewrite serve
PulseTrackr iPhone universal links. This directory keeps a source copy of the AASA
file; do not deploy Hosting from this repository, because that would replace the
PulseTrack website.

Deploy the `pulsetrackr-sos` functions codebase from this repository, and deploy
the merged Firestore rules and Hosting from `/Users/ndmx0/Codehub/PROD/PulseTrack`.
The Python `submit_incident` draft in that repository must not be deployed under
the same callable name as the TypeScript PulseTrackr function.

After the AASA file is deployed, reinstall the iPhone app to refresh its
associated-domain cache when testing universal links.
