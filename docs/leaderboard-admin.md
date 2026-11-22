# Local leaderboard administration

The server starts a separate admin page at <http://localhost:8081>, including
when started with `./dev.sh`. The default `LEQRA_ADMIN_ADDR=localhost:8081`
binds both `127.0.0.1` and `::1` on the same port, and startup logs list both
actual addresses. Both binds must succeed; an occupied port fails startup.
It is never served on the public game port. Set `LEQRA_ADMIN_ADDR` to another
`localhost:PORT` for both families, an explicit loopback IP and port for one
family, or `off` to disable the page. Wildcard and public bind addresses are rejected.

For a remote server, forward its loopback port through SSH:

```sh
ssh -N -L 8081:127.0.0.1:8081 leqra
```

Then open <http://127.0.0.1:8081> on the local computer. Substitute the SSH host
normally used for deployment. If local port 8081 is occupied, use
`-L 8082:127.0.0.1:8081` and open local port 8082.

The page previews callsigns, scores, and connection status. Its regex field
uses Go regular expressions, with case-sensitive matching by default. For
example, `(?i)^test` matches names beginning with “test” regardless of case.
Previewing and refreshing do not change any scores.

The table includes current registered accounts even if they have no public
leaderboard entry; those rows show no score. Choose **Recover key** in the
Account key column, confirm the replacement, then use **Copy key** and import
it through the client's Account settings. Recovery preserves the account's
callsigns and scores, revokes its old key, and signs out clients using that key.
Released or expired accounts are no longer available for recovery.

The server stores hashes of account keys, so recovery creates a replacement
rather than displaying the original. The replacement is generated in the admin
browser and remains visible until the recovery panel is closed. If clipboard
access is unavailable, select and copy the key from its field.

“Clear matches” clears only matching standings. “Reset all” clears the public
Infinity leaderboard. Both ask for confirmation. Affected connected players
stay in the arena with score zero, and connected public clients receive an
informational reset notice. Offline entries disappear from the standings;
an offline co-pilot can retain a hidden zero-score identity when its paired
credential still owns an unaffected seat. Neither operation releases reserved
online callsigns or lets another device take over their ownership.

Mutations are serialized with the authoritative server and committed to the
SQLite database selected by `LEQRA_DATA` before broadcasting. The page cannot
upload scores or change a player's ownership token. It accepts only loopback
connections and loopback Host headers, rejects cross-origin requests, and
requires a per-process cryptographic CSRF token for every mutation. Treat
access to the machine or its forwarded admin port as administrative access.

Use the page rather than deleting or editing a running server's SQLite files.
SQLite's WAL and shared-memory sidecars belong to the database and may contain
committed state.
