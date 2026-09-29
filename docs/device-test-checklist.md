# BasePoint — real-device checklist

Everything below has passed tests and rendered frames, but none of it has run
on a phone. Use a cheap Android phone if you can (2–3 GB RAM, Android 10–12):
that is the phone a sari-sari store has, and the one that shows problems.

When something looks wrong, note what you were doing. The app records its
own errors: at the end of the day, open More → Settings → **Error log** and
share it (it also rides along inside every backup).

## 0. Install

Build one APK per CPU type (about 23–26 MB each) instead of one fat 70 MB APK:

```
flutter build apk --split-per-abi
```

Install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` on most phones
from 2017 on; use `app-armeabi-v7a-release.apk` on older or Android Go phones.

For the speed checks in section 6, use a **profile** build with the phone
plugged in (`flutter run --profile`). The demo-year loader is in debug and
profile builds only — never in a release.

- [ ] Launcher shows **BasePoint** with the storefront icon
- [ ] On Android 13+, with themed icons on, the icon takes the theme colour
- [ ] An old `storev2` install, if any, is a separate app (new app id) — remove it

## 1. First run

- [ ] Opens on **Welcome**, not the till
- [ ] Switch to Filipino on the welcome screen; everything after is in Filipino
- [ ] Store name: keyboard opens by itself, capitalises words
- [ ] Owner: name, then PIN twice; a mismatch is caught
- [ ] Opening cash: keyboard opens by itself, numbers only
- [ ] "You're ready" shows the right store, name and amount
- [ ] Lands on Products with the "add your first product" prompt
- [ ] Kill the app on "You're ready", reopen: setup does **not** run again
- [ ] More → switch cashier: only the owner is on the roster (no May/Ronel/Nena)
- [ ] Owner PIN closes the day; `2468` does not

## 2. A morning at the counter

- [ ] Add 5 products with the camera — photo, name, price, stock
- [ ] Scan a real barcode to find a product; scan an unknown one to add it
- [ ] A scan beeps (high for a known product, low for an unknown one) and vibrates; with Settings → Scan sound off it only vibrates
- [ ] More → Sign out: Back does not return to the till; close and reopen the app — still locked; the same person needs their code
- [ ] Sell: tap, fly-to-cart animation, haptics feel right, not slow
- [ ] Popular chips appear after a few sales
- [ ] Quantity keypad, hold a sale, recall it, repeat last sale
- [ ] Cash sale with change; GCash sale; Utang sale onto a customer
- [ ] Discount with a reason; it shows in Reports
- [ ] Return one line of a sale; stock goes back up

## 3. Printing (Bluetooth thermal printer)

- [ ] Pair the printer in Android settings first
- [ ] More → Settings → Receipt printer: the printer is listed
- [ ] Android 12+: the Bluetooth permission prompt appears once, and printing works after
- [ ] Receipt prints; store name at the top; 58 mm lines do not wrap
- [ ] Printer off: a clear message, and the sale is still saved

## 4. Utang

- [ ] Customer with a phone number: Remind opens SMS with the message filled in
- [ ] Call opens the dialler
- [ ] Record a payment; balance and "last activity" update

## 5. Close day

- [ ] Home shows the Close day card with today's figures
- [ ] Count the drawer; variance is right against the opening cash
- [ ] Day-close report reads well, in both languages

## 6. Speed with a year of data (profile build)

More → Settings → Developer → **Load a demo year** (replaces the store's data).
Note how long it takes to load — it shows the time when done.

- [ ] Home opens without a noticeable pause; switching Today/Week/Month is quick
- [ ] Sell: the product grid scrolls smoothly; search is instant
- [ ] Products: list and grid both scroll smoothly (add photos to ~20 products first)
- [ ] Home → sales for Month opens and scrolls smoothly (~2,000 sales)
- [ ] Reports: Week and Month switch without a long wait
- [ ] Utang screen opens quickly
- [ ] Backup: "Exporting…" spinner keeps spinning (does not freeze) — note the time

## 7. Backup and restore

- [ ] With products or sales in the store, Home shows "Back up your store"; **Back up now** opens the share sheet
- [ ] Back out of the share sheet: "Backup cancelled", reminder stays
- [ ] Share to Google Drive or Messenger; reminder goes away; till pill says "Backed up"
- [ ] Check the file arrived and is named `basepoint-backup-…zip`
- [ ] Second phone (or after uninstall): Welcome → **Restore a backup** → pick the file
- [ ] Preview shows the row counts, photos, and "Store name and settings: Included"
- [ ] After restore: products with their photos, sales history, utang balances, store name, payment types
- [ ] Settings → Restore on a phone with data: warns, keeps a copy of the old data

## 8. Filipino

- [ ] Walk the main screens in Filipino; note any wording that sounds off at a counter
- [ ] Nothing cut off or overflowing on the smallest phone you have

## 9. Everyday phone things

- [ ] Rotate the phone on Sell and Products
- [ ] Leave the app mid-sale for an hour, come back: note whether the cart and cashier survived
- [ ] Airplane mode from a fresh install: everything works, and text is in the app's own font (it is bundled now)
- [ ] Low battery saver on: animations still fine

## 10. End of the day

- [ ] More → Settings → Error log: read what is there; tap an entry to see its detail
- [ ] Share the log to yourself; the file opens and reads sensibly
- [ ] Anything on the log you did not notice happening? Note it next to the entry
