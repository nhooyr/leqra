# Account keys

On first launch, P1 and P2 receive different random callsigns such as
`pilot#BDF3XZ`, using the same six-character format and alphabet as random room
codes. When the server is
reachable, each name is claimed atomically using its independently saved account
key, without joining a game. Offline starts use local random names and confirm
them before entering online play. Existing saved names and imported accounts are
kept. Each account key owns
its pilot's reserved callsigns and public Infinity score. P1 and P2 each have
their own account key, aliases, and score. Either key can be used as either local
seat, or as the primary pilot on another device. Scores are calculated
by the server; importing a key cannot upload or alter them. The case-insensitive
`Bot ` prefix, and the bare name `Bot`, are reserved for bots in both online and
offline play. Ordinary names such as `RUST`, `Godlike Bot 7`, and `godlike-7`
remain available to players if no other account owns them. Custom bot identities
are shown in title case with a `Bot ` prefix, such as `Bot Rust`; public bots use
`Bot N` and `Bot N - Godlike` names.

When a name is used online, the editor reserves a stable three-line feedback
area with **Import account key** and **Generate random?** actions. Generating a
name keeps the same account key and score. A request ID is saved before sending,
so retrying the request does not reserve extra aliases. Offline repair remains
playable and waits for server confirmation before going online.

Open **Account** beside the pilot's callsign in the ready room to copy that
pilot's key, then open Account on another
device and import it. Check the account preview before using it. All platforms use
the same key format, scoped to the selected server. A local development key will
not authenticate against a different server or database.

An account key is the account's entire credential. Keep a private backup. Anyone
who obtains it can use its callsigns and public score. Keys belong in the Account
controls, never in an invite URL, public chat, issue, screenshot, or log. Native
iOS stores its key in the device-only Keychain; Android uses device-only Keystore
encryption outside backups; the web client stores it in that site's browser storage.

Opening the same public account on a new device takes over its existing tank.
The old device receives an explicit signed-out notice and stops reconnecting.
The tank keeps its authoritative identity and score; importing or previewing a
key alone does not take over a running game. Private room sessions keep their
separate temporary room credentials.

If the key might have been exposed, use **Reset account key** after returning to
the ready room. This preserves callsigns and public scores, invalidates the old
key and all of its public/private sessions, and requires the new key on other
devices. Clients save a pending replacement before requesting the reset so a
network interruption cannot discard the only valid key. Complete or recover
that pending operation before replacing the account again.

Resetting or taking over one seat can sign out its paired controller connection,
but the other pilot keeps its key, aliases, and score. A reset removes the affected
private local seat before the old room credential can reconnect. Updating from a
legacy shared P2 identity preserves its saved score under the new independent key;
clients save that P2 key before requesting the migration.

There is no password, email address, or automatic key recovery. If a key is lost,
another device that still has it can copy it. Otherwise use the application's
GitHub help link to request manual assistance; possession of a callsign alone
does not establish ownership, so recovery is not guaranteed. Never include an
account key in a public issue.
