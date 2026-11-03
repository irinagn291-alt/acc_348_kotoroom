# Piproom

Open `Piproom.xcodeproj` and run the Piproom scheme on an iPhone running iOS 17 or later. The watch companion supports watchOS 10 and later. For a device build, select a signing team for all three products and enable the `group.app.piproom.iphone` App Group on the iPhone and widget targets.

Choose a month or roll the die. Swipe right to keep a photo or left to set it aside in the review bin. Photos asks for confirmation before deleting a selection. Protect albums from the photo desk to exclude their contents from review.

## Tools

Open **Tools** on the desk, including before granting Photos access. **Password generator** uses the system random generator on the device. Start with 20 characters and adjust the length, numbers, symbols and similar-looking characters. **Email name ideas** generates five local suggestions in Business, Short or Random style. Add a domain to preview or copy an address. The provider checks availability when you register. Both tools work offline. Copied values use the local pasteboard and expire after two minutes.

**Check a password** contacts Pwned Passwords only on submission, sends a five-character hash prefix with response padding, and matches the suffix locally. **Check an email** opens HIBP’s official website in the default build. Enter the address there. A configured private relay enables native email results with breach names, dates and affected data classes when available. See [email relay setup](EmailRelay/README.md).

## Storage cleanup

Open **Storage cleanup** from the desk. Exact duplicates match the bytes and roles of every PhotoKit resource, including paired Live Photo motion and available edit resources. Screenshots are grouped by month. Large videos start at 100,000,000 bytes. Screen recordings can be sorted by size or duration. Tap a thumbnail to inspect a photo or play a video.

Scanning uses local resources. When an original is unavailable, **Check original** allows iCloud access for that item. All four collections feed the same persistent review bin as monthly swipes. Bulk suggestions skip favorites, previous Keep decisions and recognized shared items. Protected albums are excluded throughout. Before deleting a queued duplicate, Piproom verifies that the selected item and its retained copy still match.

## Reminders, widget and watch

Enable **Quiet reminders** on the desk to get one silent local reminder at 6 PM local time three days after your last swipe in an unfinished month. The next swipe replaces it. Finishing the month or turning off reminders cancels it.

Add **Piproom → Monthly contact sheet** from the iPhone widget gallery. Tap the small widget to open the displayed month. Install Piproom on a paired Apple Watch and open the iPhone app to sync. The watch shows the last synced counts and can roll an unfinished month. Use Handoff on iPhone to open the month displayed on the watch. Only calendar labels and counts are shared.

## Integration tests

Use a dedicated iPhone simulator named `Piproom Review`. Install the test runner and grant it Photos access. Tests create their own album and check the surviving assets by identifier. Run without simulator cloning.

```sh
xcrun simctl privacy "$PIPROOM_UDID" grant photos app.piproom.iphone.uitests.xctrunner
xcodebuild -project Piproom.xcodeproj -scheme Piproom -destination "id=$PIPROOM_UDID" -parallel-testing-enabled NO test
```

## Secret Folder

Open **Secret Folder** from the desk and confirm a separate six-digit PIN. After unlocking with the PIN, you can enable Face ID. The private collection locks when you leave it or background Piproom. There is no backup or PIN reset.

Import unedited JPEG, HEIC, PNG or Live Photos. Each completed item is encrypted, read back, checked against its source digest and committed to the encrypted index. A Live Photo includes its still and paired movie. Unsupported or incomplete items remain in Photos. After import you can keep every original or remove verified, unprotected originals using the Photos confirmation dialog. Open a private item and choose **Restore to Photos** to export it while retaining the vault copy.

The vault uses its own app-private, backup-excluded directory. Original resources, previews and the catalog are encrypted with AES-GCM. Temporary files needed by PhotoKit have device file protection and are cleaned up after use and on restart. The device-only Keychain holds a PIN-wrapped random key and, if enabled, an independent copy gated by the current Face ID enrollment. The widget and Apple Watch do not receive vault contents.

The vault integration tests run on a separate simulator named `Piproom Vault QA`. Grant the app and its UI test runner Photos access and enroll a simulated face before running `VaultTests`. The test creates its own still and Live Photo, exercises original removal and verifies that restored resource hashes match.
