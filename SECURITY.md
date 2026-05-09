# Security Notes

- Do not commit real API secrets, HealthKit exports, provisioning profiles, or certificates.
- The current app stores API configuration in `UserDefaults` for demo simplicity.
- A production version should store API secrets in Keychain.
- Simulator preview data is never synced.
- HealthSync is not a medical device and should not be used for diagnosis or emergency decisions.

