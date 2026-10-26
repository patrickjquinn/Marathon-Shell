# UX playbook audit: Email, Messages, Phone, Notes, Calendar

Date: 2026-10-12 · Scope: `apps/{email,messages,phone,notes,calendar}/**` (all pages, dialogs, menus, covers) · Method: read the code against the UX playbook checklist, with Sailfish/Jolla conventions as the Jakob's-law baseline. Read-only; nothing ran on a device.

## Summary

These five apps are already close to Sailfish. Each primary "new" action sits at the bottom of the pulley and also appears as a cover action. Destructive actions go through `remorseDelete` or `RemorsePopup`. Empty states use `ViewPlaceholder` and say what to do next. Sizes all come from `Theme` (no hard-coded px anywhere in scope). Accessible names are set on almost every list row, and phone numbers are chunked by one shared formatter.

The real problems are at the edges the playbook cares about most:

- **Feedback when the network fails.** The test phone is offline and may have no SIM. Mail send never reports an outcome. IMAP setup blocks with no cancel. The dialer and SMS composer don't say up front that there is no service.
- **Resuming work.** Mail has one draft slot, and a reply overwrites it.
- **Dead ends.** No mail folders. Attachments can't be opened. Phone's "Send message" opens Messages but drops the number. Non-current mail accounts can't be selected.
- **Small cross-app inconsistencies.** The pin glyph, remorse wording, date formatting and cover placeholders differ between apps.

Counts: **P0 0 · P1 17 · P2 27** (44 findings).

Severity: P0 broken · P1 clearly violates playbook · P2 polish. Effort: S under 1 h · M about half a day · L a day or more.

---

## Email

Good:
- Unread mail is shown three ways (marker bar, bold, highlight colour) and the row's accessible name starts with "Unread", so it isn't colour-only.
- Delete and Archive use remorse, including from the message page, which hands off to the inbox's `RemorsePopup`.
- Compose autosaves every 2 s, saves again when the app goes to the background, and when sending fails it keeps the message as a draft.
- The IMAP email field validates on blur (`errorHighlight … && !activeFocus`) with copy that says how to fix it.
- Remote images and JS are off in the HTML body.

### InboxPage

**A2-01 · P1 · Doherty · `apps/email/pages/InboxPage.qml:59`**
Problem: when the inbox already has messages, a sync shows nothing at all. `BusyLabel` only runs when `count === 0` (`:14`). "Sync" from the pulley looks like a dead tap.
Fix: set `PullDownMenu { busy: page.syncState === "syncing" }`, which is the Jolla Email pattern. Keel's `PulleyMenuBase.busy` already exists.
Effort: S.

**A2-02 · P1 · Doherty (more than 10 s needs cancel) · `apps/email/pages/InboxPage.qml:14,88`**
Problem: `loading` is true for any state that isn't idle or error, and that includes the initial `""`. If messageserver never answers, "Checking for mail" spins forever with no timeout and no cancel. `MailService` exposes no cancel either.
Fix:
- Add a 15 s timeout that switches to the `syncFailed` placeholder.
- Expose `MailService.cancelSync()` (wrapping `m_retrieval->cancelOperation()`) as a "Stop" pulley item while syncing.
Effort: M.

**A2-03 · P1 · Jakob / dead end · `apps/email/pages/InboxPage.qml:43`, `AccountsPage.qml:49-55`**
Problem: there is no folder navigation. Sent, Drafts, Trash, Archive and Outbox can't be reached. Delete moves mail to Trash, so after the remorse runs out the user can't get the message back. Jolla Email lists folders for each account.
Fix: in AccountsPage, list each account's folders as `ListItem`s (a QMF folder model). On tap, set `mail.currentFolderId` and call `showInbox()`.
Effort: L.

**A2-04 · P2 · Jakob · `apps/email/pages/InboxPage.qml:59-79`**
Problem: mail can't be searched. Jolla Email has Search in the pulley.
Fix: add a "Search" pulley item that shows a `SearchField` header and filters by sender and subject, matching the Messages pattern.
Effort: M.

### AccountsPage

**A2-05 · P1 · Fake/dead control · `apps/email/pages/AccountsPage.qml:51-52`**
Problem: rows for accounts other than the current one are drawn dimmed with `enabled: false`. With two accounts, the second can never be opened. `setCurrentAccountId` exists but no UI calls it.
Fix: expose the account id role from the accounts model. On tap, set `mail.currentAccountId = id` and call `showInbox()`. Show the unread count only for the current account until the service exposes counts per account.
Effort: M.

**A2-06 · P2 · Progressive disclosure · `apps/email/pages/AccountsPage.qml`**
Problem: there is no way to remove an account or change its settings. Account management is a dead end.
Fix: add a `ContextMenu` on the account `SectionHeader` row with "Remove account", behind `remorseDelete`.
Effort: M.

### AddAccountPage

**A2-07 · P1 · Fake control / offline · `apps/email/pages/AddAccountPage.qml:56-60`**
Problem: Google and Microsoft are always listed. In builds without OAuth they only fail after a tap ("isn't enabled in this build", `MailLogic.js:68`). Offline, they hand off to a browser that can't load and leave "Continue in your browser" on screen with no cancel or retry.
Fix:
- Hide OAuth providers when the service reports they aren't configured. That needs an `oauthAvailable` property on MailService.
- When there is no network, disable the row with the description "Needs an internet connection".
- Add a "Cancel" pulley item while waiting.
Effort: M.

### MailAccountSetupPage

**A2-08 · P1 · Doherty / Peak-end · `apps/email/pages/MailAccountSetupPage.qml:46-58,282-298`**
Problem: `addImapAccount` is a blocking call on the GUI thread. Offline, it can block until the connection times out, with no cancel. Every failure gets the same copy, "Check your email address and password…", which is wrong when the real cause is having no network.
Fix:
- Make `addImapAccount` asynchronous, using result signals like the OAuth flow.
- Show `BusyLabel` plus a Cancel action.
- Map the failure codes so that "no network" says "You're offline. Connect to the internet, then sign in." The password fields stay filled.
Effort: L.

**A2-09 · P2 · Jakob · `apps/email/pages/MailAccountSetupPage.qml:8,274-281`**
Problem: account setup is a `Page` with a centred `Button` at the end of a long form. Sailfish account creation is a `Dialog` whose accept is the forward swipe.
Fix: make it a `Dialog` with `DialogHeader { acceptText: qsTr("Sign in") }`, `canAccept: page.canSubmit`, and an `onAcceptBlocked` hint, then drop the Button.
Effort: M.

### MailComposePage

**A2-10 · P1 · Zeigarnik/Ovsiankina (data loss) · `apps/email/EmailApp.qml:15-18,66-68`, `MailComposePage.qml:29-31,51-58`**
Problem: there is one draft slot (`/apps/email/composeDraft`). A reply or forward that is edited and dismissed writes its fields into that slot (`persistDraft`). This silently overwrites an unsent new message. The next "New message" then opens the reply's To and "Re:" subject. Nothing in the inbox says a draft exists.
Fix:
- Keep drafts per message: either QMF Drafts-folder messages, or a key per reply in the form `composeDraft/<parentId|new>`.
- When a draft exists, add a pulley item "Continue draft" above "New message", or a "Draft" row at the top of the inbox.
Effort: M.

**A2-11 · P1 · Peak-end / Doherty · `apps/email/pages/MailComposePage.qml:41-49`, `marathon-services/src/mailservice.cpp:418-422`**
Problem: `send()` returns as soon as the message is queued. `m_transmit` activity is never connected, so a send that fails offline is never reported. The user sees "Sending message" and then nothing, while the message sits in an Outbox they can't see (A2-03).
Fix:
- Connect `m_transmit->activityChanged` to `sendSucceeded` and `sendFailed(reason)` signals.
- On success, show the Notice "Sent". On failure, show "Not sent — you're offline. It'll stay in Outbox; pull down in Inbox to retry."
- Show the Outbox count in the inbox header description.
Effort: M.

**A2-12 · P1 · Postel · `apps/email/pages/MailComposePage.qml:33,43`**
Problem: `canAccept` only checks that To isn't empty. Typing `bob`, or using `;` as a separator, goes straight to QMF and fails later with no message. Bcc is missing.
Fix:
- On accept, split on `[,;\s]+`, trim, accept `Name <addr>` forms, and normalise to `, `.
- If a token is invalid, block the accept and set `toField.errorHighlight` with the description "“bob” isn't an email address". Keep the text.
- Add a Bcc field behind a "Cc/Bcc" expander.
Effort: S.

### MailMessagePage

**A2-13 · P1 · Fake control / dead end · `apps/email/pages/MailMessagePage.qml:111-156`**
Problem: attachments are listed with an icon, name and size in `highlightColor`, the colour Sailfish uses for things you can tap. The rows are a plain `Item` and do nothing.
Fix: make each one a `ListItem` that opens with `Qt.openUrlExternally` once it's saved, with a `ContextMenu` "Save to Downloads". Until there is a service API for that, draw the rows in `secondaryColor` so they don't look tappable.
Effort: M.

**A2-14 · P2 · Progressive disclosure · `apps/email/pages/MailHtmlBody.qml:10`**
Problem: remote images are always blocked, and there is no control to load them for a trusted message. Image-heavy mail looks broken.
Fix: add a pulley item "Show images" that sets `autoLoadImages: true` for this message only.
Effort: S.

**A2-15 · P2 · Hick / Pareto · `apps/email/pages/MailMessagePage.qml:33-54`**
Problem: "Mark as unread" is only in the inbox context menu, not on the message itself.
Fix: add a "Mark as unread" pulley item between Archive and Forward.
Effort: S.

### MailCover

Fine. The count and sender are clear, and the new-message action works. Nothing to report.

---

## Messages

Good:
- The draft for each conversation autosaves (1 s), comes back when the thread reopens, and appears as "Draft: …" in the list. This is a textbook Ovsiankina pattern.
- A failed send keeps the text in the field, and the copy names the fix ("check the SIM card and signal").
- The recipient field accepts `+`, spaces, dashes, dots and parentheses.
- Numbers are chunked for display. Unread conversations show a numeric count, not just colour.
- Delete uses `remorseDelete`.

### ConversationsPage

**A2-16 · P1 · Fake control (cross-app) · `apps/messages/MessagesApp.qml` (no route handling), `apps/phone/PhoneApp.qml:110-112`**
Problem: Phone's "Send message" (call log, People and contact page) calls `launchAppWithRoute("messages", "conversation", {number})`. MessagesApp never reads `MARATHON_APP_ROUTE` or its params, so the user lands on the conversation list and the number is lost.
Fix: in `MessagesApp.Component.onCompleted`, and on later activations, read the route and params and call `startConversation(number, contactName)`.
Effort: S.

**A2-17 · P2 · Consistency (similarity) · `apps/messages/pages/ConversationsPage.qml:125-133` vs `apps/notes/pages/NotesPage.qml:105-111`**
Problem: Messages marks pins with `icon-s-pin`. Notes marks pins with `icon-s-favorite`, the star that Phone uses for *favourite* contacts (`PeopleTab.qml:129`). One glyph means two different things.
Fix: use `icon-s-pin` for pins everywhere and keep the star for contact favourites only.
Effort: S.

### NewMessagePage

**A2-18 · P2 · Postel (validate on blur/submit) · `apps/messages/pages/NewMessagePage.qml:41-43`**
Problem: the description re-validates on every keystroke, so "Enter at least 3 digits" flashes after the first digit.
Fix: show the "at least 3 digits" copy only after the user presses Enter, or when the field loses focus with fewer than 3 digits.
Effort: S.

**A2-19 · P2 · Jakob · `apps/messages/pages/NewMessagePage.qml:34-48`**
Problem: there can only be one recipient. Jolla Messages allows several, as group or broadcast SMS.
Fix: keep this for now. Note it on the roadmap, and make sure the copy doesn't promise a group.
Effort: L.

### ConversationPage

**A2-20 · P1 · Offline / Peak-end · `apps/messages/pages/ConversationPage.qml:121-173`**
Problem: with no SIM or modem the composer looks fully working. The user finds out only after typing and sending, and on some paths only after the 30 s timeout (`:48-55`).
Fix: bind to `Telephony.hasModem` (already exposed by the platform). When there is no modem, show a `secondaryHighlightColor` line above the field: "No SIM — messages can't be sent". Typing stays enabled so the draft is kept, and Send is disabled with that reason as its accessible description.
Effort: S.

**A2-21 · P1 · Jakob / dead end · `apps/messages/pages/ConversationPage.qml:87-119`, `components/MessageBubble.qml`**
Problem:
- The thread has no pulley, so there is no "Call" and no "Add to contacts".
- Bubbles have no `ContextMenu`, so a message can't be copied or deleted.

Jolla Messages has all of these.
Fix:
- Add a `PullDownMenu` with "Call" (Navigation to phone with the number) and, for unknown numbers, "Add to contacts".
- Make `MessageBubble` a `ListItem` with a menu holding "Copy" and "Delete" (`remorseDelete`).
Effort: M.

**A2-22 · P1 · User directive (no tinted fills) / Jakob · `apps/messages/components/MessageBubble.qml:29-37`**
Problem: bubbles are rounded `Rectangle`s filled with `highlightBackgroundColor` or `primaryColor @ 0.1`. The user has rejected tinted fills, and Sailfish Messages tells the sides apart mainly by alignment and text colour. The `0.1` is a raw opacity rather than a Theme token.
Fix: remove the fill and use alignment plus `highlightColor` text for outgoing messages and `primaryColor` for incoming. If some separation is still needed, use `Theme.opacityFaint`.
Effort: S.

**A2-23 · P2 · Postel / Jakob · `apps/messages/pages/ConversationPage.qml:144-157`**
Problem: the composer is a single-line `TextField`, so a long SMS scrolls out of view. There is no counter for characters or segments.
Fix: use a `TextArea` that grows up to about 5 lines, with an SMS segment counter label such as "160/1".
Effort: S.

### MessagesCover

**A2-24 · P2 · Consistency · `apps/messages/cover/MessagesCover.qml:15-19`, `apps/notes/cover/NotesCover.qml:13-17`**
Problem: the Messages and Notes cover placeholders have no icon. Mail and Phone placeholders do have one.
Fix: add `icon.source: "image://theme/icon-m-message"` and `"…icon-m-note"`.
Effort: S.

---

## Phone

Good:
- Keypad keys are `itemSizeLarge` high (Keel `Keypad.qml:65-66`), well over 44 pt.
- The dialled number is chunked and read digit by digit for screen readers.
- Call and End are full-size buttons in the bottom third. Holding 0 enters `+`.
- Missed calls use their own glyph and the "Missed call from" accessible name, not just `errorColor`.
- Call-log and contact delete go through remorse.
- `callFailed` shows fix-it copy for the no-modem case.

### DialerPanel

**A2-25 · P1 · Offline / Peak-end · `apps/phone/pages/DialerPanel.qml:62-77,132-146`**
Problem: with no SIM or modem the dialer looks normal. The user dials, the call page opens and then pops, and a Notice appears afterwards.
Fix: when `!Telephony.hasModem`, the "Enter number" placeholder line says "No SIM — emergency calls only". Call stays enabled for `Phone.isEmergency(number)` and is otherwise disabled with that reason.
Effort: S.

**A2-26 · P2 · Postel · `apps/phone/pages/DialerPanel.qml:31-41`**
Problem: a number copied from mail or the browser can't be pasted. Only key presses append.
Fix: on press-and-hold of the number label, offer "Paste". Strip the text to `[0-9+*#]` and keep the stored value raw.
Effort: S.

**A2-27 · P2 · Parkinson (one-tap repeat) · `apps/phone/pages/DialerPanel.qml:142`**
Problem: Call is disabled when the field is empty. Sailfish, and most dialers, fill in the last dialled number when Call is pressed on an empty field.
Fix: when the number is empty, Call puts the latest outgoing number from `callHistory` into the field. A second press dials.
Effort: S.

### MainPage / CallLogTab

**A2-28 · P2 · Von Restorff / colour-only · `apps/phone/pages/MainPage.qml:67-73`**
Problem: the cover shows missed calls, but the "Call log" tab has no count. Inside the app the only cue is red text.
Fix: pass `count: root.phone.missedCount` in the TabBar model (Marathon `TabBar` already reads `countRole`).
Effort: S.

**A2-29 · P2 · Jakob / Parkinson · `apps/phone/pages/CallLogTab.qml:65`**
Problem: tapping a call-log row only loads the number into the dialer, so calling back takes 2 taps and a tab switch. In Jolla Phone a tap on a history row calls.
Fix: make tap call (`root.phone.call(number)`). Keep "Edit before calling" in the context menu.
Effort: S.

**A2-30 · P2 · Progressive disclosure · `apps/phone/pages/CallLogTab.qml:17-28`**
Problem: there is no way to clear the call log, and repeated calls from the same number aren't grouped.
Fix: add a pulley item "Clear call log" (`RemorsePopup`), and group consecutive calls with the same number and type as "(3)".
Effort: M.

### ContactPage

**A2-31 · P2 · Hick / Von Restorff / proximity · `apps/phone/pages/ContactPage.qml:47-90`**
Problem:
- Two `Button`s of equal weight, Call and Send message, sit stacked in mid-page, so neither is the clear primary action.
- `spacing: Theme.paddingLarge` is the same between the details and the buttons, so nothing is grouped.
- The phone `DetailItem` can't be tapped.

Fix: follow the Jolla contact card. Make the phone number a `ListItem` (tap calls) with an inline message `IconButton` at least `itemSizeSmall`, then remove the two buttons.
Effort: M.

### ActiveCallPage

**A2-32 · P1 · Colour-only signal / Hick (icon-only) · `apps/phone/pages/ActiveCallPage.qml:105-145`**
Problem:
- Speaker-on and keypad-open are shown only by `highlighted` colour. Mute at least swaps its glyph.
- The three toggles are icons with no visible label.

Fix:
- Put a `fontSizeExtraSmall` label under each `IconButton` ("Mute", "Keypad", "Speaker").
- Show the on state with the label's colour and a glyph swap (`icon-l-speaker` vs `icon-l-speaker-on`), as mute already does.
Effort: S.

**A2-33 · P2 · Peak-end · `apps/phone/pages/ActiveCallPage.qml:153-157`, `PhoneApp.qml:131-137`**
Problem: hanging up pops the page straight away. There is no "Call ended · 3:42" end state.
Fix: when the state goes to terminated, show "Call ended" and the final duration in `statusLabel` for about 1.5 s, then pop.
Effort: S.

### IncomingCallPage

**A2-34 · P2 · Fitts (mis-tap risk) · `apps/phone/pages/IncomingCallPage.qml:55-86`**
Problem: Answer and Decline are equal-size buttons stacked right next to each other, with Decline in the easiest thumb spot. There is no way to silence the ringer without declining.
Fix:
- Put Answer at the bottom and Decline above it, separated by `Theme.itemSizeMedium`.
- Add a "Silence" pulley item.
Effort: S.

---

## Notes

Good:
- Autosave runs 800 ms after typing stops, on page deactivation and when the app goes to the background. There is nothing to lose, and no Save button is needed, which is the Jolla model.
- Delete uses remorse from both the list and the editor.
- The empty states give the next action, including the tasks hint "- [ ] buy milk".

### NotesPage

**A2-35 · P2 · Consistency (output format) · `apps/notes/pages/NotesPage.qml:21-27`**
Problem: Notes formats dates by hand (`"d MMM"`, `toLocaleTimeString`). Messages, Phone and Calendar use `Format.formatDate(…, Formatter.*)`, so Notes shows a different format.
Fix: use `Format.formatDate(new Date(timestamp), Formatter.TimepointRelative)`.
Effort: S.

### NoteEditorPage

**A2-36 · P2 · Occam / Jakob · `apps/notes/pages/NoteEditorPage.qml:89-103`, `NotesStore.js:19,30`**
Problem:
- The title appears twice, once in the `PageHeader` and again in a large `TextField`.
- An empty title is stored as the literal English "Untitled", which isn't translated and is baked into the data.
- Jolla Notes is a single text body whose first line is the title.

Fix: drop the title field and take the title from the first line of the body. Fall back to the translated `qsTr("Untitled")` only when showing the title, never when storing it.
Effort: M.

### TasksPage

**A2-37 · P2 · Jakob · `apps/notes/pages/TasksPage.qml:36-45`**
Problem: a bare `Switch` with no icon is used as a checkbox, and a separate row tap opens the note. That gives two tap targets in one row, and the indicator is just a glass dot.
Fix: use `TextSwitch { text: task; description: noteTitle }` for the toggle. Move "Open note" to a `ContextMenu`.
Effort: S.

---

## Calendar

Good:
- It uses the real `DatePickerDialog` and `TimePickerDialog`, so there is no free-text date parsing to get wrong.
- A new event defaults to the next full hour on the selected day (Tesler).
- Delete uses remorse from the list and the event page.
- The cover shows the next event and the number left today.
- The day cell has an accessible name with the event count.

### EventEditorDialog

**A2-38 · P1 · Jakob (core model gap) · `apps/calendar/pages/EventEditorDialog.qml:13-31,89-101`**
Problem: an event has only a start time. There is no end time, duration or location. Jolla Calendar's editor has Starts, Ends and Location. Without an end time, conflicts and "busy until" can't be shown.
Fix: add an "Ends" `ValueButton` that defaults to start + 1 h and moves with the start, plus a Location `TextField`. Extend the model with `endTime` and `location`.
Effort: M.

**A2-39 · P2 · Zeigarnik / consistency · `apps/calendar/pages/EventEditorDialog.qml:34-35`**
Problem:
- Swiping back loses a half-filled event without warning.
- Nothing explains why accept is disabled. Mail does explain this, via `onAcceptBlocked`.

Fix: add `onAcceptBlocked: Notices.show(qsTr("Add a title first"))`. Save edits that haven't been accepted to a single `ConfigurationValue` and offer them again the next time "New event" is opened.
Effort: S.

**A2-40 · P2 · Tesler · `apps/calendar/CalendarApp.qml:77-85`**
Problem: a new event created between 23:00 and 23:59 rolls `hour` over to 0 but keeps today's date, so the event lands in the past.
Fix: base both date and hour on the same `start` Date object.
Effort: S.

### MonthPage

**A2-41 · P2 · Empty state with next action · `apps/calendar/pages/MonthPage.qml:106-115`**
Problem: the day's "No events" label doesn't suggest a next action. Every other empty state in these apps does ("Pull down to add one").
Fix: use hint text such as "Pull down to add one". Even better, make the empty row a `ListItem` that opens `newEvent(page.date)`.
Effort: S.

### AgendaPage

**A2-42 · P2 · Serial position / next action near attention · `apps/calendar/pages/AgendaPage.qml:12-19`**
Problem: "All events" starts with the oldest event ever. Recurring events appear only once, on their start date, so the list doesn't match the month view.
Fix: list from today onward, or use `positionViewAtIndex` to jump to the first event today or later. Expand recurring events over a window such as 90 days, or label them "Repeats weekly from …".
Effort: M.

---

## Cross-app consistency (same function, same look)

| Pattern | Email | Messages | Phone | Notes | Calendar | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| Primary "new" action at the bottom of the pulley, plus a cover action | ✓ | ✓ | n/a (dialer) | ✓ | ✓ | Consistent; good |
| Delete through remorse | ✓ | ✓ | ✓ | ✓ | ✓ | Consistent |
| Remorse wording | "Deleted" | (default) | "Deleted %1" | "Deleting" | "Deleting event" | Inconsistent tense (see A2-43) |
| Pin glyph | — | icon-s-pin | star = favourite | star = pin | — | Inconsistent (A2-17) |
| Date output | model string | Format | Format | hand-rolled | Format | A2-35 |
| Cover placeholder icon | ✓ | ✗ | ✓ | ✗ | n/a | A2-24 |
| Accept-blocked feedback | ✓ | n/a | ✗ (contact editor) | n/a | ✗ | A2-39 |

**A2-43 · P2 · Similarity · `apps/notes/pages/NoteEditorPage.qml:33`, `apps/calendar/pages/EventPage.qml:25`, `apps/phone/pages/ContactPage.qml:15`, `apps/email/pages/InboxPage.qml:18`**
Problem: `RemorsePopup` text uses the present participle in some apps and the past tense in others.
Fix: use the Sailfish form everywhere, "Deleting", and keep "Archiving" for archive.
Effort: S.

**A2-44 · P2 · Occam (code) · `apps/messages/MessagesLogic.js:3-53` and `apps/phone/Phone.js:3-47`**
Problem: the number chunking and `sameNumber` logic is copied into both apps. The output is the same today, but the copies will drift.
Fix: move it into one shared JS module in marathon-silica, or into a `Marathon.Platform` helper.
Effort: S.

## Checked and found acceptable

- Type scale: each screen uses 4 sizes or fewer from `Theme.fontSize*` and 2 weights. Phone's `ExtraLight` is the Sailfish dialer convention.
- Spacing: everything uses Theme padding tokens, with no raw px.
- Toggles: only Sailfish `TextSwitch` and `Switch` (glass indicator), never pill switches.
- Touch targets: list rows are `itemSizeSmall` to `itemSizeExtraLarge`, `IconButton` is `itemSizeSmall`, and keypad keys are `itemSizeLarge`. All are at least 44 pt.
