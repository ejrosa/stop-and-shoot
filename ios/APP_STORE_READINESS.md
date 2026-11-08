# App Store readiness checklist

This is a checklist for a later signed build. Nothing here has been submitted. No Apple Developer account is configured in this repository, and none was purchased or enrolled.

## Signing and identity

- [ ] Enroll in the Apple Developer Program with the account that will own the app.
- [ ] Replace `dev.provisional.stopandshoot` with a bundle id you control. Do it before the first TestFlight upload. The id is set in `ios/Config/Provisional.xcconfig`.
- [ ] Select the team in Xcode, or put `DEVELOPMENT_TEAM` only in gitignored `ios/Config/Local.xcconfig`.
- [ ] Confirm no certificate, `.p12`, `.p8`, provisioning profile, or App Store Connect API key is committed.
- [ ] Leave automatic signing on unless you have a reason to manage profiles by hand.

## Version

- [ ] Marketing version is `0.1.0` and build number is `1` for this foundation.
- [ ] Bump the build number for every upload. Bump the marketing version when the user-facing app changes.
- [ ] Keep `AppIdentity.marketingVersion` in sync so the Nominatim user agent matches the binary.

## Privacy

- [ ] Read [DATA_FLOW.md](DATA_FLOW.md) and match App Store Connect's nutrition labels to it.
- [ ] The privacy manifest already declares precise and coarse location for app functionality, not linked to an identity, and not used for tracking. UserDefaults is declared with reason `CA92.1` (flags such as the safety acknowledgement and the lookups switch). Confirm that reading before you submit.
- [ ] Location purpose string is While Using only. Do not add Always unless the product actually tracks in the background, and do not add a background mode for it in this design.
- [ ] Microphone and speech-recognition strings match the Speak button. Dictation is on-device only. Do not turn on server recognition without changing the purpose string, the manifest, and the in-app explanation.
- [ ] `ITSAppUsesNonExemptEncryption` is false because the app only uses the system HTTPS stack. Revisit it if custom cryptography is added.
- [ ] Host a privacy policy that matches DATA_FLOW.md, including the lookup hosts and the public demo fuel-station key. There is no policy URL in this repo.
- [ ] Host a support URL. There is no support URL in this repo.
- [ ] Replace `NREL_API_KEY` before a public TestFlight if demo-key limits or the provider's terms are a problem. Keep the real key in `Local.xcconfig` only.

## Device checks before TestFlight

- [ ] Mark a spot outdoors and compare the saved coordinates, accuracy, and GPS time with the Maps pin.
- [ ] Deny location and confirm the spoken failure. Then allow While Using and mark again.
- [ ] Mark from each Siri phrase. Confirm Siri opens the app and speaks the result, and that the app was not listening before you invoked Siri.
- [ ] Background the app during a slow fix and confirm it does not keep updating location.
- [ ] Toggle lookups off and confirm no new lookup traffic, then on and confirm sources are named on the spot.
- [ ] Dictate a note on a phone that supports on-device recognition, and type a note on one that does not.
- [ ] Import a JSON export from the website and confirm older spots are still there.
- [ ] Delete a spot, force-quit, and relaunch. Confirm the file survived and the deleted spot did not return.
- [ ] VoiceOver: confirm the mark button and the result text are announced.
- [ ] Silent switch on: confirm the mark button's spoken confirmation is still audible. This uses the playback audio session and was not verified on hardware.

## Metadata you still have to write

- [ ] Subtitle, description, and keywords. Do not say the app listens continuously or that coordinates never leave the phone.
- [ ] Category suggestion: Travel, or Photo & Video. Pick one in App Store Connect.
- [ ] Age rating: no restricted content is built in. Answer the questionnaire from the actual binary.
- [ ] Screenshots and a preview from a device or simulator. None are included here.
- [ ] Copyright and contact name in App Store Connect. Do not add a personal legal name to this public repo as part of that step unless you mean to publish it.
- [ ] Export compliance: the plist already answers that only exempt encryption is used. Confirm the upload questionnaire.
- [ ] Review notes: explain that marking is user initiated, location is While Using, and lookup calls send coordinates to the services in DATA_FLOW.md.

## Explicitly out of scope for the first binary

- [ ] CarPlay
- [ ] Always-on location or a lock-screen listener
- [ ] iCloud sync or a shared store with the website
- [ ] A custom wake word
