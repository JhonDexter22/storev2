# BasePoint — real-device checklist

Everything below has passed tests and rendered frames, but none of it has run
on a phone. Use a cheap Android phone if you can (2–3 GB RAM, Android 10–12):
that is the phone a sari-sari store has, and the one that shows problems.

When something looks wrong, note what you were doing. The app records its
own errors: at the end of the day, open More → Settings → Help → **Error log**
and share it (it also rides along inside every backup).

Items marked **(new)** came in with the screen-by-screen review in early
October 2026 and have never run on a phone at all. Do those first if time is
short.

You will need: the owner's PIN, a second cashier, a Bluetooth thermal printer,
a few real products with barcodes, and some cash for a drawer count.

## 0. Install

Build one APK per CPU type (about 23–26 MB each) instead of one fat 70 MB APK:

```
flutter build apk --split-per-abi
```

Install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` on most phones
from 2017 on; use `app-armeabi-v7a-release.apk` on older or Android Go phones.

For the speed checks in section 13, use a **profile** build with the phone
plugged in (`flutter run --profile`). The demo-year loader is in debug and
profile builds only — never in a release.

- [ ] **(new)** Launcher shows **BasePoint** with the new icon: white "b" and amber dot on blue (uninstall first — launchers cache icons)
- [ ] On Android 13+, with themed icons on, the icon takes the theme colour
- [ ] **(new)** The welcome screen and cashier sign-in show the same "b" mark
- [ ] An old `storev2` install, if any, is a separate app (new app id) — remove it
- [ ] **(new)** Installing over an earlier BasePoint build keeps all data (the database upgrades to v13); old closed days show no "Utang paid in cash" line, and existing customers follow the store's credit limit

## 1. First run

- [ ] Opens on **Welcome**, not the till
- [ ] Switch to Filipino on the welcome screen; everything after is in Filipino
- [ ] Store name: keyboard opens by itself, capitalises words
- [ ] Owner: name, then PIN twice; a mismatch is caught
- [ ] Opening cash: keyboard opens by itself, numbers only
- [ ] "You're ready" shows the right store, name and amount
- [ ] **(new)** It says cashiers are added from **More → Staff**
- [ ] **Add my products** lands on Products with the "add your first product" prompt
- [ ] Kill the app on "You're ready", reopen: setup does **not** run again
- [ ] **(new)** Every later launch opens on **Sell**, not Products
- [ ] More → Staff: only the owner is on the roster (no May/Ronel/Nena)
- [ ] Owner PIN closes the day; `2468` does not

Restoring on a new phone (needs a backup file from section 14):

- [ ] **(new)** Welcome → Restore → finish setup: the last screen says "Your products and sales are back" and that cashiers need adding again from More → Staff
- [ ] **(new)** **Start selling** opens on Sell, with the restored products in the grid

## 2. Sell

- [ ] Tap, fly-to-cart animation, haptics feel right, not slow
- [ ] Popular chips appear after a few sales
- [ ] **(new)** Products without a photo show their **category colour** and initials (e.g. "SL" for "Sardines…, large"); same category, same colour
- [ ] **(new)** While most products have no photo, tiles are short — about 6 to a screen
- [ ] **(new)** A product with a photo shows it as a rounded square in the strip, recognisable
- [ ] **(new)** No "Low stock" badges on the till; "Out of stock" items are greyed, say "Out of stock" once, and sit last (in Popular too)
- [ ] **(new)** Stock counts are grey when healthy, amber when low
- [ ] **(new)** All and each category are A–Z
- [ ] **(new)** Search has a ✕, and is empty again after a sale is completed
- [ ] **(new)** Tap the blue quantity number on a card: the quantity picker opens
- [ ] Quantity keypad, hold a sale, recall it, repeat last sale
- [ ] **(new)** Cart panel → **Clear all** → **Undo** brings the whole sale back
- [ ] **(new)** Tap the amber **No backup** pill in the till header: a backup starts (share sheet)
- [ ] **(new)** Header: store icon is a grey square, scan button is blue
- [ ] **(new)** Bottom bar labels (Home, Products, Sell…) are in the same font as the rest of the app
- [ ] **(new)** Hold a sale, open **Held**, bring it back — you stay on Sell (the last held sale used to leave a blank screen)
- [ ] **(new)** Search "yelo": "No match for "yelo"", **Sell "yelo" as a quick item** and **Clear search**; Repeat last sale hides while searching
- [ ] **(new)** Quick item: price ₱5, qty 2 → cart shows "Yelo ₱10.00"; checkout, receipt and Returns show "Yelo"; no product's stock changed
- [ ] **(new)** **+ Quick item** chip (start of the category row) works with no search; a search with results ends with a Quick item tile
- [ ] **(new)** Hold a sale with a quick item, close the app, reopen, bring it back: name and price are kept

## 3. Scanning

- [ ] A scan beeps (high for a known product, low for an unknown one) and vibrates; with Settings → Scan sound off it only vibrates
- [ ] **(new)** Scan 3 different products back to back: each is **added on sight**, once, with a green flash
- [ ] **(new)** Hold one barcode in front of the camera for 5 seconds: added **once**
- [ ] **(new)** Scan the same product twice with a short pause: added twice
- [ ] **(new)** "Kopiko added · 2 in this sale" → **Edit** sets the count; 0 takes it out
- [ ] **(new)** A product with 2 in stock and 2 already in the cart: scanning it flashes amber, "Only 2 … in stock", nothing added
- [ ] Unknown code: "No product matches", **Add as new product** opens the product sheet with the code filled in
- [ ] **(new)** Turn off camera permission for the app, open the scanner: a translated message and **Type the code**, not an English error on black

## 4. Checkout

- [ ] Cash sale with change; GCash sale; Utang sale onto a customer
- [ ] Discount with a reason; it shows in Reports
- [ ] **(new)** Type `1,000` as cash received: it counts as a thousand
- [ ] **(new)** **Exact** on a sale with centavos (₱27.50) shows 27.50 in the box
- [ ] **(new)** Quick cash buttons follow the amount due (₱37 → ₱50 · ₱100 · ₱200)
- [ ] **(new)** Utang: **New customer** adds someone and selects them without leaving the sale
- [ ] **(new)** With more than 5 customers, search finds one by name or number
- [ ] **(new)** In Filipino, the line above the button reads "Nasa utang ni …"
- [ ] **(new)** Until it can be pressed, the button says what is missing: "Enter cash received", "Short by ₱…", "Pick a customer"
- [ ] **(new)** Tapped quick-cash amount turns blue; prices line up on the right; a long basket folds after 4 items
- [ ] **(new)** Done screen: big **Change to give** with the bills and coins (₱67 → ₱50 · ₱10 · ₱5 · ₱1 ×2) — readable at arm's length?
- [ ] **(new)** Done screen: exact cash says "No change"; GCash says "Paid with GCash"; utang shows the new balance against the limit
- [ ] **(new)** No printer set: the button says **Set up printer** and opens the printer screen; after picking one it becomes **Print receipt**

## 5. Products

- [ ] Add 5 products with the camera — photo, name, price, stock
- [ ] **(new)** The product sheet's **Save** is always on screen, above the keyboard too
- [ ] **(new)** The price field shows ₱ before anything is typed; ₱0 is refused
- [ ] **(new)** A barcode already used by another product is refused ("Already used by …")
- [ ] **(new)** Existing categories show as chips; tapping one fills the field
- [ ] **(new)** A new product form opens with no yellow restock warning
- [ ] **(new)** Type something, tap ✕ or outside: "Discard changes?" appears; swipe-down does not close the sheet
- [ ] **(new)** Lowering an existing product's stock asks for the **manager PIN**; raising it does not
- [ ] **(new)** Deleting a product that still has stock asks for the **manager PIN**; an empty one deletes with Undo
- [ ] **(new)** Header reads "… products · ₱… on hand"
- [ ] **(new)** Grid cards show only Low/Out badges and grey counts when healthy
- [ ] **(new)** "+ Stock" on a low product offers "💡 Suggested +N"

## 6. Restock

- [ ] **(new)** Out-of-stock and running-low items are compact rows; nearly-empty first
- [ ] **(new)** Tap a row: the add-stock sheet opens **empty** with "💡 Suggested +N"; **+12** gives 12, not 12 on top
- [ ] **(new)** After adding: "Added 24 · Kopiko now 24" with **Undo**, which takes it back
- [ ] **(new)** The third tile reads "Shopping list"; tap it and send the list to yourself — grouped by category, out-of-stock marked
- [ ] **(new)** Rows say **Buy 7** (not "+7"); the add-stock button reads "Enter an amount" until a number is in
- [ ] **(new)** **Stock in**: the restock list with empty boxes and the suggestion greyed inside; type a few, leave others empty → "Add 48 to 3 products" adds only those; **Undo** takes back all of it
- [ ] **(new)** Stock in: **Fill in suggested amounts**, search "sky" to add a healthy product, scan a barcode (adds the row with 1, scan again → 2)
- [ ] **(new)** Stock in: type an amount, press Back (and the phone's back gesture) → "Discard changes?"; keyboard does not cover the box being typed in

## 7. Home

- [ ] **(new)** Tiles: **Expected in drawer**, **Owed to you**, **Inventory** (in pesos), Stock alerts
- [ ] **(new)** Growth badge reads "+12% vs yesterday" — and is absent on a first day
- [ ] **(new)** **30 days** shows 30 thin bars dated at the ends; heading reads "SALES · LAST 30 DAYS"
- [ ] **(new)** "Transactions ›" in the sales card opens the list of sales
- [ ] **(new)** Needs attention follows Restock's order; "See all N ›" opens Restock
- [ ] **(new)** "+ Stock" there offers the suggested amount
- [ ] **(new)** Bell and avatar are both round; the avatar is the blue initials of whoever is signed in
- [ ] **(new)** Bell → overdue customers opens Credit already on **Overdue**
- [ ] **(new)** Close day card: "since 9:00 PM" today, "since Yesterday, 9:00 PM" otherwise
- [ ] **(new)** Header reads "Good evening, May" over your **store's name**; switch cashier and it follows
- [ ] **(new)** Phone: **Close day** sits right under the sales card; no "Start a new sale" card (the Sell button in the bar does it); tablet still has it
- [ ] **(new)** Phone: 3 recent sales, **See all ›** opens the sales list (tablet shows 5)

## 8. Printing (Bluetooth thermal printer)

- [ ] Pair the printer in Android settings first
- [ ] More → Settings → Receipt printer: the printer is listed
- [ ] **(new)** Likely printers are at the top; earbuds and speakers under "Other devices"
- [ ] **(new)** Choosing the printer prints a test receipt **at once**
- [ ] **(new)** Choose earbuds or a speaker by mistake: "Could not reach the printer" appears right there
- [ ] Android 12+: the Bluetooth permission prompt appears once, and printing works after
- [ ] Receipt prints; store name at the top; 58 mm lines do not wrap
- [ ] Printer off: a clear message, and the sale is still saved
- [ ] **(new)** Phone's Bluetooth off: the message has a **Refresh** button — switch Bluetooth on, tap it, the printers appear
- [ ] **(new)** With no printer chosen the grey button reads "Pick a printer above"; a device with no name shows as "Unnamed device"

## 9. Credit (utang)

- [ ] Customer with a phone number: Remind opens SMS with the message filled in
- [ ] Call opens the dialler
- [ ] Record a payment; balance and "last activity" update
- [ ] **(new)** Paying more than is owed is refused ("… only owes ₱…"); `1,000` with a comma works
- [ ] **(new)** Payment methods are the store's own (Cash, GCash, Card, any added), never Utang
- [ ] **(new)** After a payment: "Paid ₱200 · … now owes ₱300" with **Undo**
- [ ] **(new)** With more than 5 customers, a search box appears
- [ ] **(new)** A customer pays utang **in cash** → Cash count's expected amount includes it, as "Utang paid in cash"
- [ ] **(new)** Settings → **Credit limit** (₱500 to start; 0 = none). A customer over it shows a red line on their card, "Over the ₱500.00 limit by ₱…", and checkout warns
- [ ] **(new)** Edit a customer: give a regular their own higher limit — the red line goes; leave it empty to return to the store default
- [ ] **(new)** Each card's last charge or payment has its day under it ("Paid ₱100.00 / 24 Sep"); the three totals at the top are the same height
- [ ] **(new)** Customers who owe nothing sit under a folded **Settled · n** at the bottom; a search still finds them
- [ ] **(new)** Open a customer, **Record payment** there: "Paid ₱…" with **Undo** shows inside the panel

## 10. Returns

- [ ] Return one line of a sale; stock goes back up
- [ ] **(new)** Each sale is one tap (no red Void button on every card); fully returned sales say **Returned**
- [ ] **(new)** Search by receipt number or item; **Show older** reaches past the last 20
- [ ] **(new)** A GCash sale's refund defaults to GCash
- [ ] **(new)** A **cash** refund asks for the **manager PIN**
- [ ] **(new)** Return an **utang** sale: the only option is "Take off their tab"; no cash moves; the customer's balance drops; their ledger shows "Returned · …"
- [ ] **(new)** Sales sit under **Today / Yesterday / 29 Sep** headings, in date order; Show older keeps the headings going
- [ ] **(new)** Open a sale: under "Return items" it says "Today · 11:30 AM · GCash · #0090"; until something is picked ₱0.00 is grey and the button reads "Pick what came back"

## 11. Close day

- [ ] Home shows the Close day card with today's figures
- [ ] **(new)** There is no "Count exact" button
- [ ] **(new)** Tap a denomination's number and type the count (e.g. 37 ₱20 coins); Next moves to the next one
- [ ] **(new)** In Filipino, the labels read "papel" / "barya"
- [ ] Count the drawer; variance is right against the opening cash (**and** any utang paid in cash)
- [ ] **(new)** The button says **Close day**; the manager PIN prompt says "…to close the day"
- [ ] **(new)** After closing, Home's "Expected in drawer" drops back to the opening cash
- [ ] **(new)** Close twice in one day (morning and evening): the evening count does not expect the morning's cash
- [ ] Day-close report reads well, in both languages; printed slip lines add up to Expected
- [ ] **(new)** The screen is titled **Close day**, "Since 12:00 AM · May" under it; bills read "₱1,000"
- [ ] **(new)** After closing, the **Cash drawer** result is the first card; a short or over drawer shows "!" at the top, a balanced one a green tick
- [ ] **(new)** Close, then **Recount**, change the count, close again: **Closed days** shows the day **once**, with the second count

Closed days (More → Closed days):

- [ ] **(new)** Tiles read "LAST 30 DAYS" with Sales, **Short · n days** and **Over · n days** — short and over are not netted
- [ ] **(new)** All · Short · Over filters; with two people closing, cashier chips filter the list and tiles
- [ ] **(new)** A day whose window crosses midnight shows its opening date ("20 Sep 9:00 PM – 9:00 PM")
- [ ] **(new)** "Show older" appears after 20 closes
- [ ] **(new)** Day cards are one block (sales on the card, a › on the right, no "View count" row); tablet shows two columns

## 12. More and Settings

- [ ] More → **Lock till** (was Sign out): Back does not return to the till; close and reopen the app — still locked; the same person needs their code
- [ ] **(new)** More descriptions are never cut off with "…" — check in Filipino on the smallest phone, with a big utang figure showing
- [ ] **(new)** More has **Money** (Reports, Cash count, Closed days), **At the counter**, **Store** (Staff, Settings) — no language pill, no Products row
- [ ] **(new)** More → **Staff** opens straight onto Manage staff
- [ ] **(new)** Close the day or take a utang payment, return to More: the pills update without leaving the tab
- [ ] **(new)** Settings → **Opening cash** asks for the manager PIN
- [ ] **(new)** Settings → **Clear all data** and **Restore** ask for the manager PIN; Clear offers **Export a backup first**
- [ ] **(new)** Default minimum stock: digits only; "Also apply to every product" updates them all
- [ ] **(new)** A blank store name says "Enter a store name"
- [ ] **(new)** Help shows the app version, e.g. "1.0.0 (1)"

Reports:

- [ ] **(new)** **Share** sends a short text summary of the range (not the whole backup); send it to yourself and read it in the chat
- [ ] **(new)** Switching Today / 7 days / 30 days keeps the report on screen while it updates
- [ ] **(new)** A day with no sales says "No sales yet today" instead of a ₱0.00 headline
- [ ] **(new)** **Busiest hours** shows bars from opening to closing time and names the busiest hour; with the demo year, it matches when you'd expect the rush
- [ ] **(new)** On 7 days and 30 days, **Not selling** lists stocked products that sold nothing, most money first (hidden on Today)
- [ ] **(new)** Return an utang sale, then check Reports → Credit: a **Returned** bar, and "Book grew by" does not count the returned sale

- [ ] **(new)** More: the row is called **Close day** (as on Home); the cashier card reads "Store · 4 Oct", not cut off; tablet shows two columns with Lock till on screen

- [ ] **(new)** Settings: **Receipts** (printer, then the auto-print switch) and **At the till** (payment types, opening cash, credit limit, scan sound); Data starts with **Export a backup**, "Last export: never" in amber

- [ ] **(new)** Reports: By category right under Top products; Returns last, one line when there are none; tablet shows Transactions/Avg sale/Items once, Busiest hours beside the revenue card

- [ ] **(new)** Settings → Payment types → Add: the button reads "Enter a name" until you type; "gcash" says "already in the list" under the box and the sheet stays open; add Maya, remove it, **Undo** brings it back where it was

- [ ] **(new)** More → Staff: the starting-PIN warning has a **Change PINs** button; rows say "still on the starting PIN"; **Add staff**; open Ronel → **Make manager** (manager PIN) → he can now authorise a close; Nena alone can't be made a cashier

## 13. Speed with a year of data (profile build)

More → Settings → Developer → **Load a demo year** (replaces the store's data).
Note how long it takes to load — it shows the time when done.

- [ ] Home opens without a noticeable pause; switching Today / 7 days / 30 days is quick
- [ ] Sell: the product grid scrolls smoothly; search is instant
- [ ] Products: list and grid both scroll smoothly (add photos to ~20 products first)
- [ ] Home → Transactions for 30 days opens and scrolls smoothly (~2,000 sales)
- [ ] Reports: 7 days and 30 days switch without a long wait
- [ ] Credit opens quickly
- [ ] **(new)** Returns search and Closed days filters stay quick with a year of data
- [ ] Backup: "Exporting…" spinner keeps spinning (does not freeze) — note the time

## 14. Backup and restore

- [ ] With products or sales in the store, Home shows "Back up your store"; **Back up now** opens the share sheet
- [ ] Back out of the share sheet: "Backup cancelled", reminder stays
- [ ] Share to Google Drive or Messenger; reminder goes away; till pill says "Backed up"
- [ ] Check the file arrived and is named `basepoint-backup-…zip`
- [ ] Second phone (or after uninstall): Welcome → **Restore a backup** → pick the file
- [ ] Preview shows the row counts, photos, and "Store name and settings: Included"
- [ ] After restore: products with their photos, sales history, utang balances, store name, payment types
- [ ] Settings → Restore on a phone with data: asks for the manager PIN, warns, keeps a copy of the old data

## 15. Filipino

- [ ] Walk the main screens in Filipino; note any wording that sounds off at a counter
- [ ] Nothing cut off or overflowing on the smallest phone you have
- [ ] **(new)** Watch the longest new strings: the three-button Clear all data dialog, the Restock add-stock sheet, Closed days tiles ("Kulang · 2 araw"), and the setup screen after a restore

## 16. Everyday phone things

- [ ] Rotate the phone on Sell and Products
- [ ] Leave the app mid-sale for an hour, come back: note whether the cart and cashier survived
- [ ] Airplane mode from a fresh install: everything works, and text is in the app's own font (it is bundled now)
- [ ] Low battery saver on: animations still fine
- [ ] **(new)** Set the phone's text size to the largest: Sell tiles, Home tiles and Closed days tiles shrink rather than clip

## 17. End of the day

- [ ] More → Settings → Help → Error log: read what is there; tap an entry to see its detail
- [ ] Share the log to yourself with the **Share the log** button under the introduction; the file opens and reads sensibly
- [ ] **(new)** A repeated error reads "×4 · last 6:04 PM"
- [ ] **(new)** The report's second line names the screen size, text size and language
- [ ] **(new)** Clear → **Share first** shares without clearing
- [ ] Anything on the log you did not notice happening? Note it next to the entry
