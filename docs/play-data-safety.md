# Google Play Data safety answers — BasePoint

Prepared 24 October 2026 for version 1.0.0 (1). Must agree with the privacy
policy at https://jhondexter22.github.io/basepoint-privacy/ (`docs/privacy-policy.html`).
Revisit both whenever a library or feature that sends data off the phone is
added (crash reporting, cloud sync, ads, analytics).

## Why only two data types are declared

- Google's definition: data processed only on the phone and never sent off it
  is not "collected". Products, sales, customers' names and phone numbers,
  photos, staff and settings all stay in BasePoint's private storage.
- Transfers the shopkeeper starts themselves, expecting them to happen, are
  not "sharing": backups and reports through the share menu, SMS reminders
  through their messaging app, calls, and Bluetooth printing.
- Data sent off the phone by a library counts as the app's. The barcode
  scanner's Google ML Kit (`com.google.mlkit:barcode-scanning:17.3.0`, bundled)
  sends Google device and app information, a per-installation identifier and
  performance figures, encrypted, for diagnostics and usage analytics; Google
  states it is not transferred to third parties. Source:
  https://developers.google.com/ml-kit/android-data-disclosure
- Android Auto Backup is off (`android:allowBackup="false"`).

## Data collection and security

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** |
| Do you provide a way for users to request that their data is deleted? | **No** |
| Account creation (if asked) | **My app does not allow users to create an account** |
| Independent security review / other badges | Leave unticked |

## Data types — tick only these two

| Category | Data type |
|---|---|
| App info and performance | **Diagnostics** |
| Device or other IDs | **Device or other IDs** |

Everything else unticked, including Crash logs (ML Kit sends error codes, not
crash reports; BasePoint's own error log never leaves the phone unless the
shopkeeper shares it), Personal info, Financial info, Messages, Photos and
videos, Files and docs, Contacts, App activity and Location.

## Data usage and handling — the same for both types

| Question | Answer |
|---|---|
| Collected / Shared | **Collected** only. Not shared. |
| Is this data processed ephemerally? | **No** |
| Is this data required or can users choose? | **Data collection is required** |
| Why is this user data collected? | **Analytics** only |

## What the store listing will then show

- Data collected: App info and performance, Device or other IDs
- No data shared with third parties
- Data is encrypted in transit
- You can't request that data be deleted
