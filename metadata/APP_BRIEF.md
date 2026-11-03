<!-- gf-brief source=f14f1c4a0d0bc2242627de468784458e41eebb3481276a351dffa3d30376a62f written=2026-11-03T22:05:22+03:00 -->
# KOTOROOM

## What it is

KOTOROOM helps people review their photo library a month at a time, set unwanted items aside for a final check, and find items that may be taking up storage. It also offers a PIN-protected photo collection, password and email-name tools, and breach checks.

## Launch and onboarding

1. A cold launch may briefly show a blank loading screen before the native desk appears. There is no separate onboarding walkthrough.
2. The desk is headed “Photo atelier”, “No. 01 / Desk” and “KOTOROOM”. Before Photos access is granted, its archive card says “Your photo archive” and “Review one month at a time. Keep the photographs that matter to you.” Its button is “Choose a month”.
3. Tapping “Choose a month”, “Roll the die”, “Storage cleanup”, “Month index”, or “Protected albums” requests Photos access if it has not already been decided. The selected destination opens after access is granted.
4. With access, the desk shows a featured month, its review progress and “Start reviewing”, “Continue reviewing”, or “View summary”. If there are no available photos, it says “No photos yet” and “Add photos to your library or change your photo selection.”
5. With limited Photos access, “Change photo selection” opens the system photo-selection picker. The desk says “Only the photos you selected are visible.”

## Screens

### Desk

The “KOTOROOM” desk shows the featured archive card and these controls:

- “Start reviewing”, “Continue reviewing”, or “View summary” opens the featured month. “Choose a month” opens the month index. When review is paused, “Check album protection” opens “Protected albums”.
- “Roll the die” picks an unfinished month. The “Your next sheet” panel shows “Photos left: [count]” and offers “Start reviewing” or “Continue”. If every month is finished, it opens the index and says “All caught up. Find your summaries in the month index.”
- “Storage cleanup” opens storage collections.
- “Month index” opens “Months”.
- “Review bin” opens the final review list.
- “Tools” opens the password, email-name and breach-check tools.
- “Secret Folder” opens the private collection.
- “Protected albums” opens album protection.
- “Quiet reminders” opens reminder preferences.

### Months and monthly review

“Months” lists available months with “Photos left: [count]”. “All” and “Unfinished” filter the list; tapping a month opens its review.

The review shows the month, progress, a photo and its date. Tap the photo to open “Photo preview”, or use “Done” there to close it. Swipe right or tap “Keep” to keep the photo; swipe left or tap “Bin” to put it in the review bin. “Undo last swipe” reverses the most recent choice for that month. The bin count opens “Review bin”.

When finished, “Month complete” shows “Kept: [count] · In bin: [count]”. “Open review bin” opens the bin, and “Back to months” returns to the index. “Undo last swipe” remains available when there is a choice to undo.

### Storage cleanup

“Storage cleanup” shows “Review by collection”, scan progress or the number of unique items, and four collections:

- “Exact duplicates” — “Verified copies, including Live Photo motion”.
- “Screenshots” — “Screen captures, arranged by month”.
- “Large videos” — “100 MB or larger, biggest first”.
- “Screen recordings” — “Recordings made on your screen”.

Each collection lists matching items. Tap a thumbnail to open “Photo preview” or “Video preview”; “Done” closes the preview. Selection circles select individual items. “Select extra copies” selects eligible duplicate extras, while “Select suggested items” selects suggested items in other collections; “Clear selection” clears the selection. “Add to bin ([count])” puts selected items in “Review bin”, and the bin count opens it.

Duplicate sets identify a “Suggested keeper” and require one matching copy to remain in Photos. Screen recordings can be sorted using “Size” or “Duration”. For originals that could not be checked locally, “Check original” attempts to include the individual item. “Review bin” on the storage screen also opens the bin.

### Review bin

“Review bin” contains items set aside from monthly review and storage cleanup. Tapping a thumbnail opens its preview; its selection circle selects or deselects it. “Select all” and “Deselect all” change the selection.

“Keep ([count])” returns selected items to Photos without deleting them. “Keep all in Photos” clears the whole bin. “Delete from Photos ([count])” starts deletion of selected items through Photos. The screen warns: “With iCloud Photos on, deletions sync across your devices. You can usually recover items in Recently Deleted for 30 days.”

When empty, it says “Your bin is empty” and “Add items from Storage cleanup or swipe left during monthly review. It stays in Photos until you confirm deletion.” “Done” returns to the previous screen.

### Protected albums

“Protected albums” says “Choose an album to keep its photos out of review and the bin. New additions are protected too.” With full Photos access, each album has a toggle. “Remove protection from unavailable album” removes protection for an album that is no longer available.

With limited access, “Manage full Photos access” opens iPhone Settings. If there are no albums, the screen says “Create an album in Photos to protect it here.”

### Secret Folder

On first opening “Secret Folder”, the app displays: “This folder has no backup. Losing this iPhone or deleting KOTOROOM can permanently erase your photos. Keep your PIN safe. Restore photos before changing devices.”

Enter a six-digit PIN in “Create a six-digit PIN”, tap “Continue”, repeat it in “Confirm your PIN”, and tap “Create folder”. On later visits, enter “Vault PIN” and tap “Unlock folder”. On supported devices, an enabled “Unlock with Face ID” control can also unlock it.

“My collection” contains:

- “Enable Face ID” or “Turn off Face ID”, when available after unlocking with a PIN.
- “Add from Photos”, which opens “Add to vault”. Select photos or Live Photos and tap “Add ([count])”; “Cancel” closes the picker. “Manage photo access” changes the limited selection when applicable.
- After an import, “Verified copies · [count]” shows a receipt. “Remove originals from Photos ([count])” removes eligible originals through Photos; “Keep originals” dismisses the receipt.
- Photo and Live Photo tiles open their details. “All photos” returns to the collection. “Restore to Photos” adds a copy to Photos while retaining the private copy. “Remove original from Photos” is offered when the original is eligible. “Delete vault copy” opens “Delete this private copy?”, with “Delete vault copy” and “Cancel”.
- “Lock folder” locks the collection. It also locks when leaving the screen or sending the app to the background.

### Tools

“Tools” groups “Password generator” and “Email name ideas” under “Create offline”, and “Check a password” and “Check an email” under “Check online”.

**“Password generator”** immediately generates a password. “Roll password” generates another; “Copy password” copies it and changes to “Copied”. “Length: [number]”, “Include numbers”, “Include symbols”, and “Exclude similar characters” adjust the recipe and generate a new password. “Check this password” checks it against known leaks. The screen says: “Checking sends the first five characters of the password hash to Have I Been Pwned.”

**“Email name ideas”** offers “Base name (optional)” and the styles “Business”, “Short”, and “Random”. Tap an idea to select it; “Roll names” produces more. “Preview domain” offers “Name only”, “gmail.com”, “outlook.com”, and “Custom”; the latter shows “Domain, e.g. example.com”. “Copy name” copies the selected name, and “Copy address” appears when a valid domain is selected. The screen explains that the email provider checks availability during registration.

**“Check a password”** accepts “Password to check” and uses “Check password”. It says: “Only the first five characters of the password hash are sent to Pwned Passwords. The match is checked on this iPhone.”

**“Check an email”** may offer “Open HIBP email search”, which opens the official Have I Been Pwned search. When the in-app check is available, it accepts “Your email address”, offers “Check email” and “Use the official HIBP website”, and says: “Only the first six characters of the email hash are sent through KOTOROOM’s relay. Your iPhone finds the matching breaches.”

Checks can show “Password found in leaks”, a count and replacement advice; “Known breaches: [count]” with breach details; or “No matches found in the available data.” “Data from Have I Been Pwned” links to the source.

### Quiet reminders

“Quiet reminders” has the “Remind me to continue” toggle. The screen explains: “One silent reminder at 6 PM, three days after your last swipe. Finishing the month cancels it.”

If notification access is off, “Open notification settings” opens iPhone Settings. If enabled without a scheduled reminder, the screen says “A reminder will be set when you leave a month unfinished.” Tapping a delivered reminder returns to the relevant month when available.

### Widget and Apple Watch

The “Monthly contact sheet” widget displays a month and “[reviewed] of [total] reviewed”. Tapping it returns to that month. Without a month it shows “Photo desk” and “Open to choose a month”.

The companion watch screen displays “PIPROOM”, month progress and “In bin: [count]”. “Roll a month” picks a month when available. Without synced information, it says “Open Piproom on your paired iPhone to sync.”; without a selected month it says “Choose a month on your iPhone.”

## Features

- Monthly contact-sheet review with “Keep”, “Bin” and “Undo last swipe”.
- “Roll the die” for an unfinished month.
- “Storage cleanup” for “Exact duplicates”, “Screenshots”, “Large videos” and “Screen recordings”.
- A “Review bin” for checking, keeping and deleting selected items.
- “Protected albums” that exclude their photos from review and the bin.
- “Secret Folder” for PIN-protected photos and Live Photos, with optional Face ID.
- “Password generator”, “Email name ideas”, “Check a password” and “Check an email”.
- “Quiet reminders”, a “Monthly contact sheet” widget and a companion watch view.

## Behaviours that can look like bugs

- “Reading your library…” temporarily disables entry to some review controls. Wait for the library to load.
- If Photos access is denied, the desk says “Allow Photos access in iPhone Settings to start reviewing.” Open Settings and allow access. Limited access includes only selected items; use “Change photo selection” or “Manage photo access” to change them.
- If protected albums are unavailable, review can pause with “Check access to protected albums to continue.” Open “Protected albums”, restore full access or remove protection from an unavailable album.
- “Unfinished” can show “All caught up.” Select “All” to see completed months. An empty library shows “There are no available photos to review.”
- “Keep” and “Bin” wait until the current photo loads. “Undo last swipe” is disabled until there is a previous choice. If a preview cannot load, “Try again” retries it.
- “No matching items” means the current cleanup collection has no matches. A scan may still show “Checking local originals…”. Use “Check original” for an available individual original that needs checking.
- Duplicate selection can say “Keep one matching copy in Photos.” Leave one matching copy unselected. “Add to bin ([count])”, “Keep ([count])” and “Delete from Photos ([count])” require a selection.
- “Your bin is empty” is expected before items are set aside. Add items from cleanup or monthly review.
- PIN buttons require six digits. If confirmation differs, “The PINs didn’t match. Choose your PIN again.” appears; enter and confirm the PIN again. “Add ([count])” requires at least one photo.
- The empty private collection says “Add your first photos. After verification, you can remove their originals from Photos.” Use “Add from Photos”.
- Password and email checks require input and are disabled while checking. A custom email domain can show “Enter a valid domain.”; enter a valid domain to use “Copy address”.
- If notifications are denied, enable them through “Open notification settings”.

## Starter content and resume

There are no seeded photos or review items in the app. Passwords and email-name ideas are generated when their tools open. The widget preview contains an example month.

Unfinished month reviews can be resumed from the desk, “Months”, the widget or a reminder. Review choices and the bin persist between visits. The private collection persists on the device, subject to the no-backup warning shown in “Secret Folder”.

## Permissions

- **Photos access:** Requested when opening a photo-review, cleanup or protection flow for the first time, or when adding to “Secret Folder”. Usage description: “Choose photos for monthly review or import verified originals into your Secret Folder.”
- **Add to Photos:** Used when restoring a private photo to Photos. Usage description: “Restore a selected Secret Folder photo to your Photos library.”
- **Face ID:** Requested when enabling or using Face ID for “Secret Folder”, where supported. Usage description: “Use Face ID to unlock your Secret Folder on this iPhone.”
- **Notifications:** Requested when enabling “Remind me to continue”. The app does not supply a separate usage-description string for this prompt.

## Absent

The native UI has no login or accounts, in-app purchase, ads, account deletion flow, or App Tracking Transparency prompt. It does not offer a general user-generated content or publishing feature; users do select and manage their own photos and enter text in the tools.

Analytics absence cannot be established from the native screens alone.

## Data and support

Review progress, preferences and the private collection are kept on the device. Photos remain in Photos until the user confirms a deletion; iCloud Photos may sync those deletions. “Secret Folder” has no backup, as its on-screen warning states.

Breach checks send partial hashes as described on their screens, and the official email-search option opens an external service. No on-screen Contact or Support control was found.

## Scanning and health

None. The app does not provide barcode or QR-code scanning, or health, medical or product-health information.

## Platform

The native interface uses English and U.S. formatting for displayed dates and related values. The iPhone app is configured for portrait orientation and iPhone only, with a minimum iOS version of 17.0. A companion Apple Watch app is included.

## Category

Utilities.
