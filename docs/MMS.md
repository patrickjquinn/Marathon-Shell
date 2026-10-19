# MMS

How Marathon sends and receives MMS through
[mmsd-tng](https://gitlab.com/kop316/mmsd), and the API apps and Settings use.
Status: being built (steps 1–7 and 9 below); group threads come after
one-to-one MMS works.

## Pieces

| Piece | Where | Does |
|---|---|---|
| mmsd-tng | session service `org.ofono.mms` | Fetches, stores and sends MMS over the modem's MMS bearer |
| `MmsManager` | `marathon-services/src/mmsmanager.*` | The shell's client of mmsd-tng |
| `SMSService` | `marathon-services/src/smsservice.*` | Messages, conversations and attachments in `messages.db`; routes a send to SMS (ModemManager) or MMS (mmsd-tng) |
| `Sms1` | `org.marathonos.Shell.Sms1` on `/org/marathonos/Shell/Sms` | The apps' API, behind the `sms` permission |
| `SmsClient` | `tools/marathon-app-runner/ipc/shellipcclients.*` | `Sms` in an app's QML |

## Rules

- Attachments cross the bus as file descriptors, never paths. A sandboxed
  app opens its own files and passes the descriptors; the shell copies them
  into its store. A path from an app is never opened by the shell.
- A message that needs MMS (an attachment, or more than one recipient) is
  never sent as SMS instead. Without mmsd-tng it is stored as failed and
  `SendFailed` says why.
- Pictures are scaled down in the shell to fit mmsd-tng's
  `TotalMaxAttachmentSize` (300 KB when mmsd-tng reports none).

## Storage

`messages.db` (SMSService), migrated in place:

- `messages`: adds `status` (`sending`, `sent`, `failed`, `received`),
  `participants` (JSON array of numbers, for group threads later) and
  `mmsPath` (mmsd-tng's message object).
- `attachments`: `id`, `messageId`, `contentType`, `name`, `size`, `path`.
  Files live in `$XDG_DATA_HOME/marathon/mms/<messageId>/`, copied out of
  mmsd-tng's store when a message arrives or is sent.

## Sms1 additions

| Member | |
|---|---|
| `SendMms(as recipients, s text, a(ssh) attachments) → i` | Each attachment is (content type, file name, fd). Returns the stored message id. |
| `OpenAttachment(i id) → h` | A read-only fd of a stored attachment. |
| `GetMessages(s conversationId)` | Each message gains `status` and `attachments` (`[{id, contentType, name, size}]`). |
| property `b MmsAvailable` | mmsd-tng is on the bus with a service. |
| signal `MessageStatusChanged(i id, s status)` | A sent message became `sent` or `failed`. |

### MMS settings (for Settings › Mobile network › MMS)

Settings reads and changes mmsd-tng's carrier settings through Sms1, not
mmsd-tng directly, so the `sms` gate and the shell's view of MMS stay in
one place. Callable only by the Settings app (system permission).

| Member | |
|---|---|
| `GetMmsSettings() → a{sv}` | mmsd-tng's `ViewSettings()` merged with its service's `GetProperties()`; empty when mmsd-tng is not running |
| `SetMmsSettings(a{sv})` | The modem keys go to `ChangeAllSettings()`, then `ProcessMessageQueue()` so queued messages retry; the service keys go to `SetProperty()` one by one |
| signal `MmsSettingsChanged(a{sv})` | After a change, or mmsd-tng's own `SettingsChanged(apn, mmsc, proxy)` from its auto-configuration |
| signal `MmsBearerError(u code)` | mmsd-tng's `BearerHandlerError`: 0 MMSC misconfigured, 1 no bearer active, 2 interface disconnected, 3 APN not connected |

Keys (mmsd-tng's names, to verify on a device with mmsd-tng running):

| Key | Type | From | Meaning |
|---|---|---|---|
| `CarrierMMSC` | s | `org.ofono.mms.ModemManager` | The MMSC URL |
| `MMS_APN` | s | ModemManager plugin | The APN that carries MMS (may be the internet APN) |
| `CarrierMMSProxy` | s | ModemManager plugin | The MMS proxy, `"NULL"` for none |
| `DefaultModemNumber` | s | ModemManager plugin | Own number when the SIM does not report it |
| `AutoProcessOnConnection` | b | ModemManager plugin | Send the queue when mobile data comes up |
| `UseDeliveryReports` | b | `org.ofono.mms.Service` | Ask for delivery reports |
| `TotalMaxAttachmentSize` | i | Service | Carrier limit in bytes (read-only in Settings) |
| `MaxAttachments` | i | Service | Carrier limit (read-only in Settings) |

## Steps

1. Storage migration and the attachment store.
2. Incoming MMS keeps its attachments.
3. Sends that need MMS never fall back to SMS; status from mmsd-tng.
4. Sms1: `SendMms`, `OpenAttachment`, `MmsAvailable`, statuses, settings.
5. `SmsClient`: `sendMms`, `openAttachment`, `mmsAvailable`.
6. Messages: attach in the composer, statuses in the thread.
7. Messages: picture bubbles.
8. Group threads (later).
9. Messages as a share target for pictures.
