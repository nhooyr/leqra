# Public Infinity scores and recovery

The server stores public Infinity standings and resume credentials in SQLite.
`LEQRA_DATA` selects the database; the default for `./dev.sh` and `go run ./src`
is `data.sqlite` in the current directory. Production uses
`LEQRA_DATA=/opt/leqra/data.sqlite` from `deploy/leqra.env`. The database and its
`-wal`/`-shm` sidecars must be writable by the server account. The service allows
those files while keeping the server executable read-only.

Scores change only in the authoritative server simulation. Neither a join nor an
input packet can supply a score, ranking ID, or leaderboard. Online callsigns
are permanent case-insensitive claims belonging to a durable
owner credential. Another owner must choose a different callsign; knowing a name
cannot recover its score. Offline practice may use any callsign.
Private-room reconnect behavior is unchanged.

Every first online join receives a private `publicToken` in its welcome. It
contains 256 random bits generated with `crypto/rand`; SQLite stores only its
SHA-256 hash. The same credential owns the controller's primary and local
co-pilot callsign claims, if present.

Public Infinity also saves that owner's score profile. Public-arena welcomes
include `public:true`; resume joins send the credential as `publicToken` and
recover the server's saved IDs, names, tank colors, and scores across restarts.
Private Infinity welcomes retain room generation/credentials; receiving owner
proof does not change their route or make private matches durable.

Recovery never looks up a player by callsign. Unknown or malformed owner
credentials produce `public_resume_invalid`; the client may then deliberately
create a fresh identity with an available callsign. An owner whose old score
profile was reset or pruned retains its callsign claims and may create a new
zero-score public profile using the same credential. Do not print tokens, put
them in URLs, or share them. Use HTTPS/WSS in production.

A standalone public pilot whose transport closes releases its arena seats.
Room parties retain their existing short room reconnect reservation. Standings
and credentials remain saved; archived rows do not count toward public capacity.
A credential replacing its own still-live transport keeps the existing tank and
equipment. A retired tank returns at a fresh spawn with its saved score.
Recovery ignores draft names and colors.
An explicit manual Play sends `updateNames:true`, atomically validates the requested
P1/P2 names, and preserves the authorized score IDs. Omitting a co-pilot during
manual Play disables P2 for future recovery while retaining its saved score;
selecting P2 again restores that owned slot. A superseded transport receives
`session_replaced` and stops automatic retries, retaining its owner proof for
a later manual Play. Explicit Exit stops automatic rejoining on the client
while retaining the credential for a
later deliberate Play. Native iOS stores it in the app's Keychain. Roaming bots'
ranked identities and scores are saved too, and their bodies return as players
repopulate the arena.

Meaningful nonzero scores never expire automatically. To bound anonymous
zero-score churn, the server periodically prunes inactive zero-score credential
groups above 8,192, oldest first. When that limit is exceeded it also reclaims
zero-score credentials unused for 30 days. An active credential is retained.

## Online callsign ownership

The same private `publicToken` identifies an owner in public Infinity and private
rooms. SQLite stores all claimed online callsigns, including unused aliases,
zero-score pilots, and offline owners, independently from leaderboard rows.
Names are cleaned and Unicode case folded before comparison. Renaming keeps the
old alias reserved to its owner. Leaderboard resets, removals, and zero-score
profile pruning do not release names.

`POST /api/callsigns` accepts `application/json` with `{publicToken?, names:[]}`
and returns `{names:[{seat,name,available}]}`. The endpoint is read-only and never
allocates an owner or claims a name. It checks the browser Origin, limits the
body, and rejects unknown fields or trailing JSON. Availability is advisory:
joining or renaming claims the entire local-seat batch atomically. Conflicts
return `callsign_taken` with `conflicts:[{seat,name}]`, identifying which local
seat needs a new name. No public response includes bearer hashes.

## Durability and failure behavior

The pinned `modernc.org/sqlite` driver runs entirely in Go; the existing
`CGO_ENABLED=0` cross-build does not need a system SQLite library. Storage uses
SQLite WAL mode and `synchronous=FULL`. Changed score rows commit in a transaction
before the server sends the public state containing them. Idle simulation ticks
do not write to disk. Database work never holds the arena mutex, so transport
input can still be accepted while a score commits. SQLite commits serialize with
joins, server simulation steps, and administration.

A clean shutdown performs a final flush. A hard kill recovers already committed
scores from the WAL on startup. Hardware/filesystem durability still depends on
honoring SQLite's synchronization requests. A missing database starts a new
leaderboard. An unreadable, corrupt, incompatible, or already locked database
fails startup instead of silently discarding saved scores. A runtime write
failure retains pending changes and withholds public state broadcasts until a
commit succeeds; new joins receive `server_busy` if their credentials cannot be
saved. Restore disk access and space before restarting.

Treat the database as private: it is created with mode `0600`, and never served
as a public asset. Only one leqra process may own a database. For a backup, stop
the server and copy the
database and any remaining sidecars together. Copying only the main file while
the server runs can omit committed WAL transactions. Do not remove sidecars
from a running server.

## Local administration

The separate admin UI starts at `http://127.0.0.1:8081` by default, including with
`./dev.sh`. `LEQRA_ADMIN_ADDR` can select another loopback address/port, or `off`.
It does not expose routes on the public game listener. To use the production UI,
forward that loopback port through SSH and open the local forwarded address.
See [the admin UI guide](leaderboard-admin.md) for the forwarding command.

Reset removes archived identities and resets connected public tanks to zero in
one SQLite transaction, preserving their credentials and connections. Remove by
callsign regex resets matching connected tanks to zero and hides matching offline
standings. Offline paired identities retain their proof so deleting one callsign
does not destroy an unmatched co-pilot's score. A later deliberate resume can
relist a hidden pilot at zero. Connected public clients receive a
`leaderboard_reset` notice and the revised standings. Administrative reset/removal
accepts no arbitrary score values.
