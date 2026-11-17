# Account keys

On first launch, P1 and P2 receive different random callsigns such as
`pilot#BDF3XZ`, using the same six-character format and alphabet as random room
codes. When the server is
reachable, each name is claimed atomically using its independently saved account
key, without joining a game. Offline starts use local random names and confirm
them before entering online play. Existing saved names and imported accounts are
kept. Each account key owns one callsign and one public Infinity score.
Entering a new callsign or generating a new one creates a fresh account with
zero score. It does not rename the old account or transfer its score. The client
saves the new key before registering it and switches only after the server
accepts the name. A rejected name leaves the current account and game unchanged.
A successful account switch returns to the ready room.

Previously used callsigns and their account keys are saved on the device.
Entering a saved callsign again, or selecting it under **Saved callsigns** in
Account, signs into that account without asking for its key again. Its own score
is restored. Saved accounts can be used by either P1 or P2, but both seats cannot
use the same account simultaneously. Import a key to use it on another device.

Accounts and their callsigns expire after **one calendar month without signing in**.
The deadline is the same UTC day and time in the next month, clamped to that
month's last day when needed. For example, a January 31 sign-in expires on
February 28, or February 29 in a leap year, at the same UTC time. Gameplay and
explicit account selection renew this period; merely viewing account details
does not. After expiry, the name can be claimed by a fresh account, starting from
zero. A saved expired key cannot recover its former score. Clients check a saved
key before switching and preserve the current account if the old name is now
owned by someone else.

The case-insensitive `Bot ` prefix and bare name `Bot` are reserved for bots.
Ordinary names such as `RUST`, `Godlike Bot 7`, and `godlike-7` are available when
unclaimed. Bot labels remain separate from account identities.

When a name is used online, the editor reserves a stable three-line feedback
area with **Import account key** and **Generate random?** actions. Generation
saves a request ID and fresh key before sending so retries can recover the same
new account. Offline changes save a fresh local account and confirm its name
before entering online play.

Clients automatically replace historical default names when that seat has no
saved account key: `PILOT`, `Player 1`, `Player 2`, `CO-PILOT`, `YOU`, `SNOW FOX`,
and the old Android `Pilot 100` through `Pilot 999` pattern. Matching ignores
case and repeated spaces. Saved custom names and names with an existing key are
kept. This migration runs at startup, never in response to a revoked-key error.

Open **Account** beside the pilot's callsign in the ready room to copy that
pilot's key, then open Account on another
device and import it. Check the account preview before using it. All platforms use
the same key format, scoped to the selected server. A local development key will
not authenticate against a different server or database.

An account key is the account's entire credential. Keep a private backup. Anyone
who obtains it can use its callsign and public score. Keys belong in the Account
controls, never in an invite URL, public chat, issue, screenshot, or log. Native
iOS stores its key in the device-only Keychain; Android uses device-only Keystore
encryption outside backups; the web client stores it in that site's browser storage.

Opening the same public account on a new device takes over its existing tank.
The old device receives an explicit signed-out notice and stops reconnecting.
The tank keeps its authoritative identity and score; importing or previewing a
key alone does not take over a running game. Private room sessions keep their
separate temporary room credentials.

Use **Release callsign** in Account to delete the current account, or **Release**
beside a saved callsign to release an older one. The confirmation names the
callsign and explains that its score is permanently deleted, its key stops
working on every device, and anyone can claim the name. Cancelling changes
nothing. The device removes the saved key only after the server confirms the
release; a network failure keeps it so the release can be retried safely. Releasing
the selected account gives that seat a fresh, unregistered local callsign.

If the key might have been exposed, use **Reset account key** after returning to
the ready room. This preserves the callsign and public score, invalidates the old
key and all of its public/private sessions, and requires the new key on other
devices. Clients save a pending replacement before requesting the reset so a
network interruption cannot discard the only valid key. Complete or recover
that pending operation before replacing the account again.

Resetting or taking over one seat can sign out its paired controller connection,
but the other pilot keeps its key, callsign, and score. A reset removes the affected
private local seat before the old room credential can reconnect. Updating from a
legacy shared P2 identity preserves its saved score under the new independent key;
clients save that P2 key before requesting the migration.

There is no password, email address, or automatic key recovery. If a key is lost,
another device that still has it can copy it. Otherwise use the application's
GitHub help link to request manual assistance; possession of a callsign alone
does not establish ownership, so recovery is not guaranteed. Never include an
account key in a public issue.

Historical aliases are removed on upgrade, keeping the current scored callsign.
A legacy shared P2 name and score are retained only for the existing independent-key
migration. This compatibility exception does not create additional aliases; the
P2 score is never added to or duplicated as the primary score.
