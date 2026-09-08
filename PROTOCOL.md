# leqra v4.33.0 — current game protocol (protocol 1)

Deploy the server and complete browser assets together. The JSON framing protocol remains **1**, and the application-version handshake now requires **4.33.0**:

```json
{"type":"server_hello","version":"4.33.0","protocol":1}
{"type":"client_hello","version":"4.33.0","protocol":1}
```

The sections below this release describe earlier protocol additions and are retained as history. Where their gameplay values differ, the current rules here and the current source take precedence.

## Home-screen mode selection

The home-screen icon selector and the battle-format/map-size selectors beneath it use the existing host-owned `rules` command with a complete validated rules object. They add no new protocol fields or commands. Guests and active-match controls remain read-only, normal server authorization applies, and online clients display accepted settings only after authoritative room state confirms them. The Rules dialog edits the remaining settings for that mode. New King of the Hill selections, its built-in preset and public Hill queue default to 30 points; explicit saved/custom targets remain valid.

## Survival rules and membership

`GET /api/config` includes `"survival"` in `objectiveModes`. Existing `rules`, `publish` and `preset` messages accept `rules.mode:"survival"`; no new input or damage command is added.

| Field or limit | Survival behavior |
| --- | --- |
| `rules.teamMode` | Must be `"teams"`; all room participants normalize to Team 1. |
| `rules.scoreTarget` | Integer 1–20, interpreted as waves to clear. The browser's Survival selection/preset defaults to 15. |
| `rules.timeLimit` | Integer 30–600 seconds per wave; browser default 75. |
| `rules.respawnSeconds` | Retained as a validated 1–10 setting for compatibility; Survival revives between waves instead. |
| Squad capacity | One to four available room participants, including friendly bots and local P2. All-bot squads are allowed. |
| Team assignments | All squad participants use Team 1; generated enemies use Team 2. Manual assignment to another team is rejected. |
| Existing rosters | Oversized `rules`, `publish` or `preset` requests fail with `survival_full` before changing the roster. |
| Live joins | New visitors join as spectators. Promotions and swaps during a run fail with `survival_active`; a full lobby squad fails with `survival_full`. |

The server checks readiness and available controllers independently of the browser. A spectating host can start an all-bot squad. A human disconnect loses the current tank life; if the run continues, a reconnect can restore that life at a later wave. Available bots can continue after human pilots leave or spectate. Empty or unavailable squads cannot start or continue. Generated enemies have no player, owner, token or room-member identity. Their tank IDs occupy unused combat slots **0–7**, distinct from spectator IDs **8 and above**. They never appear in `room.players` or consume a squad place. Public matchmaking queue modes remain unchanged.

## Survival state and lifecycle

The ordinary `state.objectives` object contains an empty `flags` array and the authoritative wave state:

```json
{"mode":"survival","flags":[],"survival":{
  "wave":5,"wavesCleared":4,"waveTarget":15,
  "enemiesRemaining":4,"boss":true,"breakTime":0,"status":"wave"
}}
```

`status` is `"wave"`, `"break"`, `"won"` or `"lost"`. `wave` is the current one-based wave; `wavesCleared` is the shared score. `enemiesRemaining` counts living generated enemies, `boss` indicates a living boss, and `breakTime` is the remaining break duration in seconds. `state.round` tracks the wave and `roundClock` is its remaining time.

Generated tank snapshots carry `survivalEnemy:true`; the boss also carries `survivalBoss:true`. False values can be omitted. The normal `bot`, `difficulty`, name, team, position, weapon, shield and movement fields still determine behavior. Clients must not infer room ownership from an enemy tank ID.

Enemy count is `min(4, 2 + floor((wave - 1) / 2))`, bounded by free combat slots. Regular enemies use `easy` on waves 1–5, `normal` on 6–10, `hard` on 11–15 and `godlike` from 16 onward. Every fifth wave replaces one enemy with a boss: `normal` on wave 5, `hard` on 10 and `godlike` on 15 and 20. Each higher difficulty appears as a boss before appearing in ordinary waves. When the respective pickup types are enabled, Normal bosses receive one Shield charge, Fierce two Shield charges and one Speed stack, and Godlike three Shield charges and one Speed stack. Their weapon starts at Homing, Cannon or Laser in successive boss waves, checking later entries cyclically for an enabled alternative. If none is enabled, no starting special weapon is granted. All starting gear uses ordinary effect durations, charges and damage rules. Clients derive the next-boss preview from this same schedule and enabled equipment.

A clear requires a surviving squad tank. It adds one point to every remaining squad participant, including downed tanks. The final target clear sets `phase:"matchOver"`, `status:"won"` and a squad winner ID. A wipe, expired wave timer or absence of available squad participants sets `phase:"matchOver"`, `status:"lost"` and `winner:-1`; this is a failed run, not a draw. Mutual destruction loses, while a final enemy killed on the last simulation tick clears the wave if a squad tank survives.

Nonfinal clears keep `phase:"playing"` with `status:"break"` for four seconds. The server clears projectiles, pickups and held input, and rejects firing/movement during the break. Defeated enemy snapshots remain present for the lineup until the next wave replaces them. At its end, available squad members receive fresh tanks, pickups reseed and the next wave starts with a fresh timer. The maze and generation remain unchanged throughout the run. The client uses the wave status and tank life serials to discard stale input and cosmetic shots.

Completed `matchStats` includes a frozen `survival` object of the same shape. Its player rows describe squad participants only, and its live duration excludes wave breaks. Generated enemies are not report participants, while destroying them still credits the attacking squad pilot's elimination count. The final wave state and report must be copied for snapshots rather than aliased to mutable simulation data.

## Survival wave retries

The host of a private Survival room can send `{"type":"restart_wave","generation":N,"wave":W}` for the current wave. The server validates the current generation and wave, available squad, room membership and host authority. The command is accepted during an active wave/countdown or after a lost run; lobbies, completed runs and between-wave breaks cannot retry. Existing version, action-rate, matchmaking and away-party restrictions apply. Rejections identify `action:"restart_wave"`.

A retry increments the simulation generation while retaining the same world and navigation data. It resends the reliable world state so clients discard stale predictions, effects, input and prior results. The current wave's enemies/boss and timer reset, available squad members receive fresh tanks, and the phase becomes a 2.6-second countdown. `wavesCleared` and prior-wave scores remain intact. A participant-keyed checkpoint restores statistics to the start of the wave, excluding the discarded attempt's elapsed time and combat totals. Removed or replacement participants cannot inherit each other's statistics. Rule changes, preset application and returning the room to its lobby invalidate its checkpoint. Room snapshots expose `canRestartWave` so the client can hide an invalid retry action; host authorization is still checked independently.

## Adding bots

An `add` command with `kind:"bot"` may omit `difficulty`. The server then copies the last bot's difficulty in active roster/seat order, defaulting to `normal` when no bot exists. It resolves this after earlier ordered roster edits, so the browser does not need to guess from a stale room snapshot. An explicitly supplied difficulty retains its existing validation and behavior. The Add Bot UI uses the omitted-field form; per-bot difficulty editing remains available.

## Map-dependent timers and machine-gun budget

Equipped weapon timers and Shield, Speed, Scope and Ghost durations refresh to **10 seconds** on Compact/Standard/Large or **15 seconds** on Huge/Giant/Ultra Wide. This corresponds to 15 seconds at maze area at least `14 * 12` cells. Projectile ranges/lifetimes and the 10-second grenade fuse remain separate.

Uncollected lifetime remains `floor(pickupCap * 8 / 3)` seconds, with a 30-second minimum for maze area at most `12 * 10` cells. The current six map values are **30, 30, 32, 45, 61 and 90 seconds**. These values are derived by the simulation; clients cannot supply expiry times.

Tank snapshots add server-owned `machineRounds`, an integer remaining budget from 0–180 for the equipped `rapid` weapon. A Machine gun pickup grants 180 rounds, equivalent to three seconds at the existing maximum of 60 successful emissions per second. Each successfully emitted round consumes one; dry or rejected attempts do not. Releasing Fire preserves the remaining budget while `powerTime` continues normally. A new Machine gun pickup refreshes the budget, and a weapon replacement, expiry or fresh life resets it as appropriate. The final budgeted round remains a valid projectile; the tank then returns to its standard weapon.

The browser subtracts outstanding predicted emissions from the server budget when deciding whether to preview another shot. Predictions never replenish authoritative rounds. The 96-projectile per-owner active cap, compact `machineBullets` stream, fire-rate ceiling and other server ownership checks remain intact. `machineRounds` cannot be set by input, and the existing `charges` field is not the Machine gun's firing budget.

---

# v4.23 connection compatibility and graceful shutdown (protocol 1)

The framing protocol remains version 1, but every real production WebSocket now has an application-version handshake before room or matchmaking actions. Immediately after upgrade the server sends:

```json
{"type":"server_hello","version":"4.23.2","protocol":1}
```

A compatible client replies before any normal command:

```json
{"type":"client_hello","version":"4.23.2","protocol":1}
```

A matching hello enables the connection and the server answers `client_ready`. Any other action before a successful hello, or a hello with a different app/protocol version, receives `type:error`, `code:"version_mismatch"`, `action:"version"`, the current `serverVersion` and `protocol`, plus reload guidance. This is deliberately stricter than protocol-number checking alone because releases can make coordinated client/server behavior changes while retaining the same JSON framing version.

On intentional process shutdown, before closing client sockets the server broadcasts:

```json
{"type":"server_shutdown","message":"The leqra server is shutting down. Returning to the Home Screen."}
```

The v4.23 browser treats this as terminal maintenance rather than a transport failure: it stops reconnecting, leaves online state and returns to local Home. Ordinary unexpected disconnect/reconnect behavior is unchanged.

---

# v4.2 combat presentation metadata (protocol 1)

Update the Go server and browser together. Clients still send logical controls,
not proposed projectiles, kills, cooldowns or damage. No new client fire/grant
command is added.

Tank snapshots add server-owned `shotSerial`: one increment per accepted volley.
A rejected cooldown/charge/ammunition request does not increment it. The existing
`spawnSerial` distinguishes separate lives of an occupant.

Projectile snapshots add `shotSerial`, `spawnSerial` and `pellet` (zero-based for
scatter). All pellets from one accepted trigger share the volley and life IDs.
Effect events add the server `tick`; shot/laser events include their volley/life
IDs, and shots include the actual firing `angle` so later tank rotation does not
change the old muzzle effect. IDs are cosmetic correlation metadata, not claims
the client can submit to gain shots. Existing Origin/ownership/rate validation is
unchanged. They add a small amount of snapshot metadata, not zero network overhead.

The browser predicts only eligible local visuals and sound. Go remains the source
of projectile existence, collision, ammunition, damage and scoring. Confirmed
volley IDs suppress duplicate sounds/effects and reconcile previews; bounded
unconfirmed previews expire. Remote shot effects and projectiles are rendered on
the buffered server-tick timeline. Gameplay simulation/snapshot rates remain
60/30 Hz, with client movement prediction still at fixed 60 Hz.

---

# v4.1 Cannon and Ghost additions (protocol 1)

Update both frontend and backend. Tank snapshots add server-owned `ghostTime`,
a remaining duration in seconds. The `ghost` identifier is accepted in the
host-validated enabled-pickup list and emitted as a pickup type. Default rooms
and matchmaking rules include all ten pickup types. No new client movement or
power-grant command exists: inputs remain logical controls, not coordinates or
trusted buff timers. Host permission, live-match locks and duplicate-weapon
validation apply as before.

Ghost bypasses internal tank/wall collisions, not the rim or tank collisions.
The timer is advanced before movement, in the same step order on Go and in local
prediction/replay. Expiry while embedded resolves to the nearest safe cell
interior, without a new life or invulnerability. The renderer avoids interpolating
across an expiry correction as if it were ordinary wall-crossing movement.
Speed and Ghost have independent timers. Bot, respawn and sudden-death paths
advance or reset Ghost consistently.

Cannon snapshots retain `kind:"cannon"` with radius **14** and speed **1128**.
Only the inner faces of the outer rim reflect them; interior walls remain
transparent to these shots. Reflection, muzzle handling and cosmetic extrapolation
must agree. Lifetime stays 5.3 seconds and does not reset on a bounce. No client
can submit a trusted collision, size, speed or damage report.

Bot removal uses the same existing host-authorized occupant-specific command;
only the client confirmation step is skipped for `kind:"bot"`. Human confirmations
and server permission checks are unchanged. Simulation/snapshot rates remain
60/30 Hz. The prediction module has changed for Ghost; do not deploy only the Go
files or only the browser assets.

---

# v4.0 matchmaking additions (protocol 1)

Update frontend and backend together. These are additive messages, but an old
client cannot consent to or process a matchmaking transfer correctly. The server
continues to validate all old game inputs, game ownership and Origin headers.

`GET /api/config` includes `matchmaking:true` and six queue definitions with
`key,name,mode,teamSize,players,map,cols,rows,target,seconds`. Keys:
`elimination-1`, `elimination-2`, `elimination-3`, `ctf-3`, `koth-3`, `ffa-8`.
Queue definitions are fixed by the server, not client-selected rule objects.

## Client commands

```json
{"type":"queue_info"}
{"type":"queue_join","queue":"ctf-3"}
{"type":"queue_accept","queueId":42,"ready":true}
{"type":"queue_accept","queueId":42,"ready":false}
{"type":"queue_cancel","queueId":42}
{"type":"return_party"}
```

`queue_join` is private-host only, in a lobby or completed match. It derives the
active real party from current room members; clients cannot supply a fake roster,
move bots into the queue, claim an accepted friend, or choose team assignments.
Remote controllers must accept the current ticket; a false acceptance cancels.
The host's request accepts only their own keyboard pilots. Queue IDs increase
within the process. Stale IDs, nonparticipants and foreign-room operations fail.
A party has 1–3 active real pilots and must fit a team; FFA requires exactly one.

A queue is cancelled by an involved disconnect, role change, removal or leave.
Setup/start operations are refused while queued or while source members are away.
Matched rooms reject private-host admin actions and new combat admissions. Their
host is `-1`. A spectator may watch/chat/rename but cannot promote into a vacant
match slot. The prior normal private-room role controls are otherwise retained.

Every new frontend `input` packet adds `room:<current room code>`. If supplied,
a different-room value is ignored, protecting against delayed pre-transfer
controls. Ownership still comes from the socket; the field cannot redirect input
into another room. Old input packets without it retain ordinary validation.

## Server messages

`queue_catalog` carries `queues`, an array of objects with `definition`,
`waitingPlayers` and `waitingParties`. Counts include only fully confirmed search
tickets, not pending invitations, bots or spectators. No other party identities,
credentials, skill ratings or wait-time promises appear in this catalog.

Room events add:
- `queue`: null or `{id,key,name,stage,players,required,members,since}`.
  `stage` is `confirming` or `searching`; `since` is server Unix milliseconds.
  Each member includes public `member,name,kind,controller,accepted` fields,
  where `controller` is the current room's public membership incarnation.
- `matchmaking`: null or `{queue,name,locked:true}` for a public battle.
- `awayMatch`: the battle code while this source lobby has reserved members.
- Participant rows add `away` (source reservation) and `hasParty` (return link).

Active searchers receive `queue_status` about once per second, with `queue`,
`queues` and `capacityBlocked`. Cancellation emits `queue_cancelled` with
`queueId,message`, followed by updated room metadata. Errors retain the normal
`type:error,code,message` structure with `action:queue_join|queue_accept|
queue_cancel|return_party` (or the disallowed action). Examples include
`party_too_large`, `ffa_solo`, `not_host`, `stale_queue`, `match_locked`,
`party_away`, `queue_locked`, `no_party`, `party_disconnected` and `queue_full`.

Transfer uses the existing private **welcome** response with an additional
`transfer:"match_found"` or `transfer:"party_return"`, current `room,id,member`,
the recipient's own `token`, and the usual role/protocol fields. No new socket is
required. Clients clear old input histories/buffer, stale UI/result state and
room-local chat, save the new room credential, and accept the forced new-world
state. The ordinary room/state/chat-history packets then describe the destination.
The lobby queue is consumed atomically only after all fallible match allocation
and whole-party/team validation succeeds. No state arrays or scores supplied by
a browser are imported into the public battle.

During transfer the original room identity is reserved. Its token can resume the
battle when a refresh races the match-found welcome. After a return, a bounded
20-second route maps that controller's old battle-code/token pair back to the
original room, where normal connected/expiry checks still apply. These private
routes never appear in broadcast data. Return restores only that socket's
controller and attached local seat; it cannot drag remote friends back early.
A public spectator without an origin receives `no_party`.

Queues run under the same hub mutex as membership changes, at most four scans per
second and four created matches per scan. Tickets are capped at 256 and source
plus destination rooms both count toward `MAX_ROOMS`. The server is one in-memory
process: a restart discards queue tickets and return reservations; replicas do
not share pools automatically. Gameplay/snapshots retain 60/30 Hz respectively.

---

## v3.8 map density and Scope

`rules.mapSize` also accepts `giant` (16×14). Existing sizes and the `large`
(12×10) default remain. The uncollected cap derives from actual world dimensions:
`round(cols * rows / 9.8)`. Starting stock is 2, 3, 4, 5, 6 for Compact through
Giant; caps are 5, 7, 12, 17, 23. Disabled pickups/weapon filters remain enforced.
`scope` is the eighth accepted value in `rules.weapons`, included in new defaults.
The entire settings object, including the new map/enum, is still host-validated.

Every tank snapshot adds server-owned `scopeTime` (seconds remaining; normally
0–10). Collecting Scope refreshes it to 10 without altering `power`, charges,
shield or speed. It expires in live simulation and resets for a new life. Clients
cannot set this timer through input messages. Pickup events use `text:"scope"`
with the established event format; no guide paths are sent in state packets.
The renderer computes guides for its owned tanks from the current world and
projects the timer for display without altering movement history/reconciliation.

Super fast remains the default: one live second before the first extra attempt,
then 1–2 seconds between attempts. Fast (2–3.5), Normal (4–6), Slow (7–10) and Off
are retained. This is an additive protocol-1 update, but frontend and backend
must both be updated: older rules validators do not understand `giant` or `scope`.

# leqra WebSocket protocol · version 1

The game page and the backend are served by the same Go process. Connect to `/ws` using WS on HTTP or WSS on HTTPS. The production upgrade requires an HTTP(S) Origin whose host matches the request Host, or an explicitly configured additional exact origin. Missing, opaque (`null`), and unrelated origins are rejected. No subprotocol, compression, or binary message format is negotiated.

All application messages are UTF-8 JSON objects with a `type`. Client messages are limited to 8,192 bytes, including the aggregate size of fragmented messages. The application allows up to 100 messages and 8 non-input/non-ping actions per connection per second. The transport separately bounds frame rates at 180 per second. These are abuse ceilings, not recommended sending rates.

## Client → server

### v3.6 team names and format constraints

The rules object accepts `teamNames:["Team 1","Team 2","Team 3","Team 4"]`.
Exactly four single-line strings are required when the array is supplied; each
normalizes outer whitespace and contains 1–24 Unicode code points with visible
content and no control/line-break characters. An omitted/null field is compatible
with old presets and receives the four default names. An explicit empty array is
invalid. Names are metadata: numeric identities and colors do not change.

Only the current host can apply rules in the lobby or after a completed match.
The accepted names appear in room rules and transfer through publish/preset and
reconnect. Clients must render names as text. Changing rules clears guest readiness.

New rules default to `teamMode:"ffa"` and `mapSize:"large"`. In FFA all active seats
have `team:0` internally, identifying an individual side by tank ID. In Teams mode,
configure/add requests may explicitly select only teams 1–4; `team:0` is rejected
with `bad_team`. There is no per-seat Independent option. Older published/saved
Teams setups with zero seats are migrated to numbered teams before use (host/owned
local on 1, others on 2), preserving valid numbered choices.

The normal create/join entry point admits actual network visitors; publishing a
local setup transfers its default host plus three Normal FFA bots, rather than
forcing those bots into every empty named room.

### v4.22 take a private room offline

A host in an ordinary private room may send `{"type":"unshare"}` while the room is in the lobby or post-match state and is not queued, transferred to matchmaking, or otherwise away. The server deletes the shared room, clears every member's server-room attachment, and sends the host `{"type":"unshared","room":"..."}`. Remote controllers receive `{"type":"room_offline","room":"..."}`. Shared primary/local-P2 controllers are notified once per WebSocket. The browser keeps the host's local roster, bots, local Player 2, room code and rules; reconnect credentials for the removed server room no longer restore it. Errors use `action:"unshare"` with the normal host/join/state validation.

### v3.5 chat, eight seats and map sizes

Combat IDs are **0–7** and spectator IDs begin at **8**. Arrays of scores and
server-side tank/control slots have eight positions. Membership incarnation
numbers, not reusable seat IDs alone, still authorize host/role operations.
`/api/config` and room messages advertise `maxPlayers:8`, `maxSpectators:16`.
`mapSize:"large"` (12×10) is the new default; `"huge"` selects 14×12.
Compact 7×7 and Standard 9×8 remain. Presets accept up to eight active seats.

Client chat: `{"type":"chat","text":"Hello room"}`. The connection supplies the
identity; sender name, member number, team and spectator role cannot be submitted
as trusted fields. A server room event is `{"type":"chat","room":"name",
"message":{"id":1,"member":42,"name":"PILOT","text":"Hello room",
"spectating":false,"team":1,"at":1750000000000}}`. The timestamp is Unix
milliseconds and the ID is monotonically increasing **within that room**.
Name/team/role are captured when sent, not rewritten when a member later changes.

Joining/resuming receives `{"type":"chat_history","room":"name","messages":[]}`
with up to the last 60 visible normal-channel messages. Clients replace/deduplicate
by message ID. Chat is not included in `state` snapshots. Ending/starting a match
preserves history; room deletion/restart clears it. Remote/local P2 sharing one
network controller uses that controller's chat identity, and server broadcasts are
deduplicated per WebSocket so that shared controller renders one copy.

v4.22 and later clients may also send `channel:"opponent"`. Outside matchmaking,
the ordinary/default channel is room-wide. Inside a matchmaking battle, the
default channel is party-scoped: it reaches only travellers whose return reservation
points to the same private source room. `channel:"opponent"` reaches the sender and
the opposing matchmaking side, not the sender's teammates. History is filtered by
those same server-authoritative scopes; a client cannot select an arbitrary member
or destination room. Side-less matchmaking spectators do not get party/opponent
chat.

Text is valid single-line UTF-8, trimmed, 1–280 Unicode code points; empty,
invisible-only and control-character text is rejected. The member-owned bucket
allows four initial messages and replenishes one per second. Errors use
`type:"error", action:"chat"` and `bad_chat`, `chat_rate` or `not_joined`.
Existing generic action/frame limits and kicked-session rejection also apply.
8 KiB is the incoming aggregate transport-message bound, not the chat character
limit; it also accommodates JSON escaping and full eight-seat presets.

Snapshot encoding is shared across recipients, but message fields and authority
are unchanged. New-maze variants remain reliable; routine updates keep only the
latest pending snapshot per socket. The 60 Hz simulation/30 Hz snapshots and
client replay/interpolation contracts are retained. Update browser and Go code
together: earlier clients assume four tank indices.


### v3.4 friendly fire and objective sudden death

`MatchRules` adds `friendlyFire: boolean` (default false). It is included in
room/state messages, publish requests and saved preset configuration. The existing
host-only `rules` action validates/applies it between matches and clears readiness.
Omitting it in an older rules object uses false; a non-boolean JSON value fails
validation. Clients still cannot directly request damage or alter target locks.

All tank owners can hurt themselves with shells, missiles and grenade explosions,
regardless of this rule. Other same-team damage is filtered only while the rule
is false. Laser shooter immunity is retained. Bot/seeker enemy selection is
independent of friendly fire and never intentionally targets allies.

Objective snapshots add `suddenDeath: boolean` and `showdown: integer`. A tied
objective timer stays `phase: "playing"`, sets `roundClock`/`phaseTime` to zero,
freezes objective scoring and gives eligible active tanks one fresh final life.
A `suddenDeath` cosmetic event announces it, with a text explanation. New
`spawnSerial` values reset each tank's old-life rendering/prediction normally.
The map generation does not change. No large GO banner is triggered by that event.

Subsequent deaths do not schedule respawns. The final living side wins via the
normal `matchOver` snapshot and winner field, without adding objective points.
Mutual elimination repeats the showdown for still-available original contestants.
Eligibility is private server state, not a client-editable/snapshot role flag.
Late joins/promotions/swaps wait for a new match and cannot acquire another final
life. Spectator identities remain separate. A new game resets sudden death.


### v3.3 spectator membership

`/api/config` adds `spectators:true`, `watchLinks:true`, `maxSpectators:16`.
The tank slots are IDs 0–7 as of v3.5; spectator IDs are >=8 and not tank indices.
`member` is an immutable public incarnation number. IDs can change on role swaps;
private reconnect tokens remain attached to the same member and are never broadcast.

- `join` accepts `spectating:true`. This explicitly requires an accepted nonempty
  `name`. Regular joins automatically fall back to a spectator when no joinable
  tank seat exists. A normal token resume preserves its role; a confirmed watch
  link with an active session may demote that same resumed member. Expired/revoked
  tokens retain the existing strict reconnect/kick behavior.
- `welcome` adds `spectating`, `member`, and `full` (automatic overflow fallback).
- `room` contains `players` (combat slots only), `spectators` (separate members),
  and `maxSpectators`. Both arrays use safe member summaries with `id`, `member`,
  `name`, `connected`, `kind`, `owner`, `team`, `spectating`, and public score data.
  Spectators do not enter the game tank array, ready requirement or side count.
- `{type:"spectate",spectating:true|false}` changes the sender's own role.
  Optional `target` plus `member` may identify its owned local P2. Other member
  roles cannot be altered through this command. A full promotion returns `no_seat`;
  a full gallery on demotion returns `spectators_full`; both use action `spectate`.
- Host-only `{type:"swap",target:activeID,member:activeIncarnation,
  spectator:spectatorID,spectatorMember:spectatorIncarnation}` exchanges two current human
  roles atomically. It takes no coordinates/weapon state. The incoming member gets
  the selected slot's side and score, no additional active life. Bots cannot watch.
  Stale, disconnected incoming, cross-room and non-host requests are rejected.
- A reliable `identity` message (`id`, `member`, `spectating`, `localId`,
  `localMember`) goes to controllers on role changes before the updated `room`
  and forced map/state. Reset prediction/held controls only when that browser’s
  own primary or secondary membership changes. Keep command sequence numbers
  monotonic on the live socket so queued controls cannot outrank new inputs.
  Unrelated controllers retain held controls and acknowledgement history. The
  server uses a new life identity for a new seat occupant. Normal snapshot buffering is
  unchanged. `swapped` acknowledges a successful exchange to the host.
- Existing `kick` accepts spectator IDs and checks the same immutable member
  reference. Host powers follow the member across its own swap. Connected
  spectators can receive host handoff. Dependent local players retain controller
  ownership, including while their controller spectates.
- `publish` accepts a `spectating` field on the primary or local-P2 `SeatSpec`.
  At most four active seats and two local human spectators can be imported; bots
  cannot have this role. Saved preset replacement is refused while spectators
  are present (`spectator_preset`, or `guests_present` for remote spectators).

Spectator gameplay input is ignored, and supplying another pilot's `player` ID
returns `not_owned`. Controllers with an active secondary local seat can still
send that seat's independent inputs while spectating themselves. Member capacity,
message limits, origin validation, reconnect grace, and bounded queues remain.
At most 16 spectators (including disconnected reserves) may be members of a room.
The authoritative game and roster are sent to all connected spectators.

The spectator-link callsign prompt is a browser flow before any WebSocket is opened:
`?room=<URL-encoded name>&spectate=1`. Normal links retain direct join. Spectator
roles are retained across rounds, games and valid reconnects, not server restarts.

### v3.2 rules, presets and objectives

`/api/config` adds `matchRules`, `presets`, and `objectiveModes`. The transport
protocol stays version 1. Update both server and client together.

A complete rules object has this shape (these are the defaults):

```json
{"mode":"elimination","teamMode":"teams","mapSize":"standard","scoreTarget":5,"timeLimit":75,"respawnSeconds":3,"pickupRate":"fast","friendlyFire":false,"weapons":["rapid","scatter","shield","homing","grenade","speed","laser"]}
```

Host-only `{type:"rules",rules:...}` applies in lobby/matchOver. Validation occurs
before mutation. It clears readiness and publishes a room update containing
`rules` and `startError`. Guest attempts return `not_host`; live edits return
`match_active`; malformed values return `bad_rules`, each with `action:"rules"`.
Free-for-all sets every seat team to zero. Nonzero team assignments via `configure`
or `add` return `teams_locked` until the host disables that format.

`publish` accepts an optional complete `rules` object alongside the roster.
`{type:"preset",rules:...,roster:[...]}` atomically replaces virtual seats and
rules, but only when the host is the sole network controller. Reserved remote
seats count as guests; `guests_present` refuses their replacement. The host's
credential is retained, virtual member IDs are refreshed, and scores are reset.
Preset names, localStorage data, key bindings and warning preferences never need
to be transmitted; the server only receives the validated lineup/rules.

Bounds and objective details are in GAMEPLAY-v3.2.md and rules.go. CTF requires
exactly two numbered sides; KOTH supports Teams or FFA. Online rule authority is
independent of frontend disabled fields.

Snapshots add `rules` and nullable `objectives`. Objective state carries
`mode`, `flags` (team/homeX/homeY/x/y/carrier/home/returnIn),
`hillX`, `hillY`, `radius`, `owner`, `contested`, and fractional `hold`. Flag carrier
−1 means none. Hill owner zero is neutral; positive values are numbered teams;
negative `−id−1` values are individual FFA seats.

Tanks add `respawnTime`, `spawnSerial`, and `cooldownTotal`. Reconciliation and
render interpolation reset across spawnSerial changes. Objective modes bypass
elimination's last-survivor round scoring; captures/holding award server points
and end at the target or an untied time limit. Tied clocks enter the v3.4
final-life sudden-death state described above. Disconnects do not respawn unattended tanks;
resume restores participation. A fresh entrant in an unused seat gets the current
team score and waits the configured objective respawn delay. Retired occupied
combat identities still are not reused mid-match.

No client objective score, flag-position, damage or respawn messages are accepted.
Normal logical input remains the sole control path; physical remappings do not
change wire ownership or its independently acknowledged secondary-player stream.


### v3.1 secondary names and gameplay

`rename_local` accepts `{type:"rename_local",target:<seat ID>,member:<occupant member>,name:<text>}`.
The authenticated controller must own that `kind:"local"` seat. A name-only change
is allowed during a round, preserves readiness/scores/input acknowledgements, and
returns a private `renamed` acknowledgement with `id`, `member`, `name`, followed
by a room broadcast. Errors include `action:"rename_local"`. It cannot rename
remote humans, bots, a different controller's secondary, or a stale occupant.
Primary `rename` retains its existing socket-derived identity behavior.

The client binds primary Fire to F, or F/Space when no secondary local pilot exists;
secondary Fire defaults to Space. Both pilots can remap their local keys. Wire input is still the existing logical `fire` flag.
Grenades now detonate on first living-tank contact (0.2s owner grace), using one
normal blast with team/shield/cover filtering, in addition to manual trigger and
5s fuse. No client damage/impact reports are accepted.

### v3.0 unified-room extensions

The framing protocol remains version 1; `/api/config` advertises `unifiedRooms`,
`localPlayers: 2`, `serverBots`, and `teams`, with app version 3.3.0.

Publish a configured local room (host first, 1–4 entries):

```json
{"type":"publish","code":"Friday team battle","roster":[{"kind":"human","name":"HOST","team":1},{"kind":"local","name":"PLAYER 2","team":1},{"kind":"bot","name":"RUST","team":2,"difficulty":"hard"}]}
```

Unlike named `create`, **publish is create-only**: `room_exists` refuses to
merge or overwrite an existing room. Blank code generates a random one. All
kinds/teams/difficulties/capacity are validated before allocating the room.
Only one primary human and at most one secondary local participant may be
imported; other entries are bots. No combat state or scores are accepted.

Host-only lobby/match-over controls:

```json
{"type":"add","kind":"bot","difficulty":"easy","team":2,"name":"RUST"}
{"type":"add","kind":"local","team":1,"name":"PLAYER 2"}
{"type":"configure","target":2,"member":3,"difficulty":"hard","team":3,"name":"VAPOR"}
{"type":"configure","target":0,"member":1,"team":1}
{"type":"lobby"}
```

`team: 0` means that seat's own free-for-all side; 1–4 are numbered shared sides.
Difficulty is `easy`, `normal`, `hard`, or `godlike`. The host may edit human teams, but
humans rename themselves using `rename`. Bots/local names are host-editable.
`configure` and `kick` require the current occupant's public `member` value.
Roster edits clear online guest readiness. The host's Start action is sufficient
consent; bots and the dependent local tank need no ready handshake. Two opposing
available sides are required, not two WebSocket clients.

`lobby` is host-only in any phase: it ends the match, clears combat state/scores,
and keeps the roster. It is not a pause. Mid-match add/team edits return
`match_active`; kicking remains allowed. Existing four-seat limits include
bots, local participants and remote humans.

A primary socket's input remains unchanged. Its secondary local seat uses an
independent `seq` with an explicit `player`:

```json
{"type":"input","player":1,"seq":47,"forward":true,"fire":false}
```

The socket may only control its own primary ID or a `kind: local` seat whose
`owner` matches it. Bots and other humans reject forged inputs with `not_owned`.
Each tank snapshot has its own `ack`/`ackSteps`. New-map prediction resets must
not rewind input sequence numbers within a live connection. Frame/input budgets
are per socket, not per seat.

Room entries add `kind`, `owner`, `team`, and `difficulty`. Bots/local seats
have no separate token or Client. Tank snapshots add `team`, `bot`, and
`difficulty`; internal bot navigation state is not serialized. Team points are
mirrored across teammates' score slots. Same-team damage is filtered in
collision/prediction/damage while friendlyFire is false. All owners take their
own shell/missile/grenade damage; lasers still ignore their owner.

A disconnected primary releases its local dependent's input as well. Resume
restores ownership. Leave/kick/expiry removes the dependent local participant;
bots remain for other humans. Only real connected humans can inherit host.
Bot-only abandoned rooms are not retained after the last human's grace expires.

### Existing connection and room commands

Create a room:

```json
{"type":"create","name":"PILOT"}
```

Join a room, or create it if missing:

```json
{"type":"join","code":"ABC234","name":"RIVAL"}
```

A tokenless `join` is **join-or-create**. Since v2.6, `code` is arbitrary
single-line Unicode text, not just a six-character identifier. The server trims
outer whitespace/BOM, requires visible content, validates UTF-8, and rejects
control characters, U+2028/U+2029, and more than 128 Unicode code points. Names
preserve spelling and case. The exception is an ASCII six-character name that
matches the old `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` alphabet after uppercasing;
those retain case-insensitive uppercase matching. No Unicode composition
normalization is performed. Internal spaces, punctuation and emoji are retained.

Lookup, capacity checks, allocation, and host assignment run under the hub mutex.
An existing room is joined without replacing its host, world, readiness, or
scores. A missing room is created under exactly the accepted name and its first
successful joiner becomes host. Rooms are published only after pilot credential
allocation succeeds. Full combat rosters fall back to spectators; a full spectator gallery returns
`room_capacity`. The server room cap returns
`server_full` when creation is needed; invalid names return `bad_code`.

`create` with no `code` or an outer-whitespace-only `code` chooses a random unused
short code. A nonempty `code` opts into the same atomic named join-or-create:

```json
{"type":"create","code":"Friday tanks 💥 / room #1","name":"PILOT"}
```

An existing named room still keeps its host. Names are not permanent ownership
reservations. The browser updates its share URL only after receiving `welcome`,
using the server's accepted `room`. URL encoding does not alter the string sent
in JSON. Never place the private reconnect token in the share URL.

Resume a disconnected seat, within 20 seconds:

```json
{"type":"join","code":"ABC234","token":"TOKEN_FROM_YOUR_WELCOME_MESSAGE"}
```

A resume token is a bearer credential. Keep it private, never put it in a shared URL, and send it only over the original server's connection. The included client stores it in the current tab's session storage. A live session cannot be replaced by a second socket presenting its token. An expired or unknown credential does not silently become a fresh join on the server. A token-bearing request for a missing room returns `room_missing` without creating anything. When an explicit invite fails to resume (`resume_expired` or `room_missing`), the client may send a separate `join` without a token to request a fresh seat, creating the room if absent. This fallback does not run for background-only reconnection, and it never bypasses capacity, live-session, or kick protection. Copied active-session invite handling remains bounded as in v2.2.

Change your own callsign (v2.2 application extension; wire protocol remains 1):

```json
{"type":"rename","name":"SNOW FOX"}
```

Accepted in the lobby, during a match, and after a match. The server derives the
player from the socket, ignores supplied player IDs/tokens for this action, and
applies the same Unicode whitelist and 16-rune limit used at join. Empty or
unsupported-only names receive `bad_name`; a socket without current room
membership receives `not_joined`. The existing action-rate limit applies.
A rename changes only player/tank name and room activity time, not readiness,
score, input sequence/acknowledgements, spawn state, or reconnect credentials.

Kick another player (v2.3 extension; host only, any room/match phase):

```json
{"type":"kick","target":2,"member":3}
```

`target` is the integer seat ID (0–3), and `member` is that occupant's public,
monotonically increasing room-local incarnation ID from the latest `room` message.
It is not a reconnect credential. Rejoining a vacated slot assigns a new member;
renaming or resuming the existing seat does not. Both fields are required. The
server derives the sender and room from the live socket and checks current host
membership. Supplied room codes, credentials or claims of host status cannot
choose a different room or authorize the action. Hosts cannot kick themselves.
Errors carry `action:"kick"` with codes `not_joined`, `not_host`, `bad_target`,
`kick_self`, or `player_missing`; malformed field types are invalid JSON messages.
The normal per-client action-rate limit applies.

The target socket receives a terminal notice:

```json
{"type":"kicked","room":"ABC234","message":"You were removed from the room by the host. Automatic reconnection has stopped."}
```

The requesting host receives a private acknowledgement:

```json
{"type":"player_kicked","id":2,"member":3,"name":"RIVAL"}
```

The room roster and state are then updated for the remaining clients. The target
is detached, its held inputs cleared, its tank eliminated and its owned projectiles
removed. Removed sockets cannot rejoin or control a player. Room rules resolve the
next simulation step normally. The client treats `kicked` as terminal, closes its
socket, clears reconnect state/retry timers and the invite URL, and displays the
notice; **never** run an invite/new-seat fallback for this message.

To handle a lost terminal notification, the room retains hashes (not raw secrets)
of kicked reconnect tokens for two minutes, capped at 1,024 records with expired
records pruned. A reconnect presenting a retained kicked token receives the same
terminal notice. This exceeds the client's 18-second retry period and the server's
20-second reconnect grace. Even after that notice expires, the removed token cannot
restore its seat; it becomes an ordinary unknown/expired credential. This is not
an account/IP ban: a fresh socket with no credential may deliberately request a
new seat under normal capacity rules. The tab additionally suppresses stale-invite
auto-joining after receiving a kick when session storage is available.

Lobby actions:

```json
{"type":"ready","ready":true}
{"type":"start"}
{"type":"leave"}
```

`start` is accepted only from the host in lobby/match-over state, with at least two available opposing sides and all other connected active humans ready. Each room has four numbered seats (0–3), including bots and a secondary local player. The host may choose numbered teams or individual free-for-all sides.

Controls (about 30 Hz while held and up to 60 Hz on movement changes, plus immediate Fire press/release messages):

```json
{
  "type":"input",
  "seq":123,
  "forward":true,
  "reverse":false,
  "left":false,
  "right":false,
  "fire":true,
  "stickX":0,
  "stickY":0
}
```

`seq` is an unsigned, monotonically increasing integer for the current connection. Duplicate/older sequence values are ignored. A reconnect resets the input sequence. Analog components are clamped to −1…1 and normalized to unit length. The server determines acceleration-free movement, turn rate, collisions, firing, cooldown, and available ammunition; coordinates, kills, power-ups, and scores submitted by a client are not authoritative. Controls expire to neutral after 350 ms without an accepted input. Menu/background input release does not make the tank invulnerable or pause the game.

Latency check:

```json
{"type":"ping","t":1234.5}
```

The server echoes `t` in an application `pong`. This is separate from WebSocket ping/pong control frames. The server also sends a WebSocket ping every ten seconds and uses read/write deadlines to remove stale peers.

## Server → client

Successful join:

```json
{
  "type":"welcome",
  "protocol":1,
  "room":"ABC234",
  "id":0,
  "token":"PRIVATE_RECONNECT_CREDENTIAL",
  "resumed":false,
  "created":true
}
```

`created` is an additive v2.4 field: `true` only for the client that created the
room, whether through `create` or a tokenless `join`. Normal joins and resumes
receive `false`. `resumed` still identifies restoration of a prior seat. A fresh
room gets fresh credentials and scores; expired credentials never become host
credentials. The following `room` message remains the authority for current host.

Successful rename (private acknowledgement to the requesting socket):

```json
{"type":"renamed","id":1,"name":"SNOW FOX"}
```

A `room` message with the updated name is then broadcast to that room. Subsequent
state snapshots carry the updated tank name. Server-accepted names, rather than
unconfirmed text edits, are saved by the browser. Other rooms receive no update.

Lobby membership:

```json
{
  "type":"room",
  "code":"ABC234",
  "host":0,
  "phase":"lobby",
  "players":[
    {"id":0,"member":1,"name":"PILOT","color":"#d2f65a","connected":true,"ready":false,"score":0}
  ],
  "canStart":false,
  "maxPlayers":4
}
```

The `host` can change after a disconnect. A disconnected but reserved player remains in the list with `connected:false` until the reconnect grace expires. An unused seat can join mid-match but waits until the next round to spawn. A previously occupied combat identity is not reassigned during an active match.

Authoritative state (30 snapshots per second):

```text
{
  type: "state",
  tick: integer,
  generation: integer,
  phase: "lobby" | "countdown" | "playing" | "roundOver" | "matchOver",
  phaseTime: seconds remaining in phase,
  round: integer,
  roundClock: seconds remaining in round,
  winner: seat ID or -1,
  scores: [seat0, seat1, seat2, seat3],
  tanks: [...],
  bullets: [...],
  pickups: [...],
  events: [...],
  world?: {cols, rows, width, height, walls: [{x,y,w,h,axis,line}, ...]}
}
```

The server includes `world` with the first snapshot of each maze generation sent to a connection. A reconnect receives it again. Do not regenerate the maze from device dimensions. Positions use server-world units, not CSS pixels. Each online cell is 84 units, each tank's collision radius is 17, and the shared world is 9×8 cells.

Tank data includes ID, name, color, x/y, angle in radians, radius, vx/vy, alive state, cooldown, invulnerability, shield duration, power, power duration, special-weapon charges, boost time (`speedTime`), recoil, track travel, and last processed input sequence (`ack`) plus `ackSteps`. `ackSteps` is the number of **server simulation ticks** performed with that sequence, resetting to 1 on its first applied tick. A held input can span several ticks: treating `ack` alone as a single simulated step is incorrect. Stale input becomes neutral without resetting its sequence chronology; a resumed connection resets the acknowledgement state. These fields are generated by the server, never accepted as client movement/timing authority. Bullet data includes ID, owner seat, x/y, vx/vy, radius, age, remaining life, color, bounce count, optional projectile `kind`, and `target` (locked target seat or -1). Pickups include x/y, type, age, and remaining life.

The short event history contains increasing IDs and event types such as `shot`, `hit`, `shield`, `pickup`, `roundStart`, `roundEnd`, `matchEnd`, `blast`, `impact`, and `laser`. Every event includes its maze `generation`; ignore effects from another generation and deduplicate IDs. The client treats old events in its first snapshot as history rather than replaying every sound after a reconnect. Events are for effects; authoritative state determines the result.

Other responses:

```json
{"type":"pong","t":1234.5}
{"type":"left"}
{"type":"error","code":"not_ready","message":"Add at least two opposing sides and ask connected guests to ready up."}
```

Room/action errors include `already_joined`, `server_full`, `server_error`, `bad_code`, `room_missing`, `room_full`, `session_active`, `resume_expired`, `not_host`, and `not_ready`.

Protocol violations close the socket: malformed framing uses 1002; binary data 1003; invalid JSON/UTF-8 1007; invalid commands/rate limits 1008; oversized messages 1009. The server may close overloaded connections with 1013. Clients should never assume every disconnect has a clean close frame.

## Client reconciliation and buffered playback (v2.1)

Protocol 1 remains wire-compatible with the original controls. `ackSteps` is an additive server field; the matching v2.1 client and server should be upgraded together to get correct reconciliation.

The browser records the prediction step at which it sends a sequence. If a snapshot reports `(ack, ackSteps)`, its authoritative pose includes movement through `startStep(ack) + ackSteps - 1`. Reset prediction to that pose, then replay the newer locally simulated inputs once at 1/60 s. Client positions, client durations, and claimed acknowledgements have no authority. Input history and replay work are bounded. Small corrections are hidden using a decaying **render-only** offset, not by pushing the physics state toward stale coordinates. Death, respawn, new maze, and reconnect clear stale prediction history.

Remote snapshots are timestamped with `tick / 60`, not their browser arrival time. A monotonic playback clock samples the stored timeline; it does not restart at zero when another packet arrives. The buffer target adapts between 70 and 180 ms. Playback speed is gently adjusted instead of jumping backward to grow the buffer. Extrapolation is capped at 75 ms and constrained by walls. This buffers **remote** visuals; it does not delay local input. Severe stalls cannot be hidden indefinitely.

Normal state snapshots may be superseded before transport writes if a connection is slow. Room/control messages and maze-bearing snapshots are not superseded. Event histories remain bounded and IDs must still be deduplicated. Bytes already written into TCP cannot be recalled. The browser does not apply a new maze generation without its world data.

`GET /api/config` now advertises `snapshotRate: 30` and `inputAckSteps: true`. Simulation remains 60 Hz. The hub uses bounded catch-up steps for short scheduler delays, rather than losing a game tick every time a timer wakeup is missed.

## Ownership and limits

The server simulation runs at 60 Hz. It alone awards points and chooses round/match transitions. The frontend may predict movement and interpolate snapshots, but never decides whether a projectile killed a tank. The in-memory room model has no persistence or multi-instance discovery. Room codes are invitations, not user accounts or passwords. Use TLS and edge abuse controls when running publicly.

## Power-up extensions, v2.5–v2.6 (wire protocol remains 1)

No new client commands are required or accepted. Pickups have type `rapid`,
`scatter`, `shield`, `homing`, `grenade`, `speed` or `laser`. The server chooses all
projectile kinds, targets, timers, boosts and damage. Supplied client power
fields have no authority. Deploy the matching v2.6 client and backend together.

Tank `power` holds only the weapon slot (empty, `rapid`, `scatter`, `homing`,
`grenade`, `laser`). `speedTime` and `shield` are independent remaining durations.
`charges` is the remaining shot count for scatter, missile, grenade and laser
pickups; homing/grenade/laser start with three and a ten-second equip timer.

The Go control step and client Net.move both decrement `speedTime` before
movement. While positive, movement is multiplied by 1.65 and turning by 1.25.
Snapshots retain the full timer precision so input replay crosses expiration on
the same simulation tick. A speed pickup refreshes the timer to six seconds.

Normal projectile `kind` is omitted/empty. `homing` has radius 5, speed 235,
maximum turn rate **4.8 radians/second**, and a ten-cell acquisition range. Its
wide seeker requires `dot(direction, directionToTarget) >= -0.75`
(about 139 degrees either side of the nose). It starts steering after 0.1 seconds,
cannot lock its owner, and requires visible, alive, non-invulnerable targets.
A valid lock persists; leaving the cone or losing visibility sets `target=-1`
and a **0.06-second** reacquisition delay. Wall/corner impacts reflect velocity,
clear the lock, and apply **0.04 seconds** of steering inhibition.

Homing snapshots add **`rangeLeft`** and **`seekDelay`**, both server-owned floats.
Initial range is world width + height (half perimeter), minus the actual barrel
segment and any collision separation. Every travelled segment and separation
nudge consumes it. Range is never renewed by guidance or a ricochet; motion and
damage are clamped to the remaining budget even partway through a tick. Reaching
zero removes the projectile and emits one cosmetic `impact` event. The lifetime
fallback is `(world.width + world.height) / 235 + 0.5` seconds, with a defensive
128-bounce ceiling instead of the ordinary shell's 22-bounce cap. A wall hit by
itself does not destroy a missile. The weapon still has three charges, a
0.72-second shot cooldown, and a ten-second equip timer.

The client cannot supply a missile's target, range, turn rate or hit result.
Local and server-controlled bots apply the same projectile geometry and guidance,
ignoring same-numbered teammates for missile targeting and damage. Grenade
physical-contact triggers are separate, as described below. Bots on opposing
sides can engage one another.

`grenade` has radius 6, initial speed 205, exponential drag 0.45/second and a
5-second fuse. It reflects off walls and detonates on first swept contact with a
living tank (stationary overlap also counts). Teammates and invulnerable tanks
can trigger contact, but existing damage immunity is retained. Its owner has
a 0.2-second launch grace. A contact produces only a blast, not an additional
contact hit; shields therefore absorb one hit. At detonation
it damages eligible tank circles within radius 110 only where a ray to the
tank center is unobstructed. Shield/invulnerability rules still apply. All
victims are resolved before round scoring. The complete blast is one event.

`blast` and `impact` events carry world `x`, `y`, owner, color and visual `radius`;
`player` is -1. `shot.text` identifies `homing` or `grenade` for sound selection
(empty for ordinary rounds). Event history stays bounded and deduplicated.
Clients must never use an effect event to award damage, replenish charges or
change scores. Projectile visuals interpolate velocity and fuse as well as
position; capped extrapolation respects missile ricochets, remaining range and grenade drag.

### Ricocheting laser (v2.7) and spawn cadence

`laser` remains hitscan, **not a projectile-list entry**. The server traces at
radius 3 from the tank centre, reflecting on wall normals (both axes on corner
hits), with one total path budget of `2 * (world.width + world.height)`. Each
segment consumes the remaining range. A tiny post-bounce step is deducted from
the same budget; the trace has a defensive 128-segment cap. The first vulnerable
opponent/shield stops it; the shooter is skipped throughout. Damage occurs once.
Cooldown remains 0.85 seconds and charges remain three, independent of active
projectile slots. The first up-to-28 units of barrel travel are hidden visually
but count toward range, preventing barrel-overlap wall bypasses.

One `laser` event includes the complete `points: [{x,y}, ...]` polyline, bounded
to 129 points. `x`, `y`, `endX` and `endY` remain its first/last visible positions
for compatibility. The client draws the connected segments, never a straight
chord across cover. The event includes the normal `id`, `generation`, `owner`,
`player` and `color`; an accompanying `shot` event has `text:"laser"`. Normal tank
state, not cosmetic events, determines hits. History bounds and generation/ID
deduplication remain unchanged. Use the current client for the correct visuals.

### Remote grenade button semantics (v2.7)

No new client damage/detonation command is accepted. The hub derives a rising
Fire edge from accepted, sequence-ordered `input.fire` changes, and latches it
until one simulation tick. This retains even a down/up pair arriving between
ticks. A bounded boolean coalesces multiple faster-than-tick taps rather than
replaying an input backlog. The internal `Input.FirePressed` field is excluded
from JSON; clients cannot supply it. Pending presses are dropped on input timeout,
disconnect, and round reset. Repeated held packets do not create new presses.

On a fresh press, a living tank detonates all its owned live `grenade` projectiles
first. This does not consume a weapon charge and bypasses throw cooldowns. It
works regardless of current power/expiry/remaining charges. If no grenade is
active, a grenade-equipped tank launches one subject to normal charges/cooldowns.
These actions consume the whole hold, preventing same-press follow-up shots and
preventing repeats when the five-second fuse or the final weapon charge expires.
Other weapon types retain hold-to-fire. The next explicit release/press permits
another throw. Only the authenticated socket's own tank can trigger this action;
a supplied owner, target, or forged damage field has no authority.

Fuses continue after weapon changes and owner death (dead owners cannot manually
detonate). Blast damage, wall visibility, shields, multi-victim resolution and
one-event cosmetic explosions are the same for timed and manually triggered blasts.

Rounds begin with the map-tier stock (2–6 pickups); the default first additional
attempt is after one live second and subsequent attempts are at randomized
1–2-second intervals. The uncollected cap is round(cols × rows / 9.8). Failed placement/full-cap attempts still wait for
the next interval. The pickup lifetime remains 19 seconds.


## Post-match report (v3.7)

`GET /api/config` advertises `postMatchStats: true`. A `state` with
`phase: "matchOver"` includes `matchStats` for a normally completed match:

```json
{"mode":"ctf","duration":123.45,"rounds":1,"limited":false,"players":[
  {"id":1,"member":7,"seat":0,"name":"PILOT","team":1,"kind":"human",
   "eliminations":4,"deaths":2,"selfDestructs":1,"teamKills":0,
   "captures":3,"flagReturns":1,"hillSeconds":0,
   "active":true,"winner":true,"mixedTeams":false}
]}
```

`id` is a report-local row identity; `member` is the existing public room-member
incarnation, **not a token**. `seat` is the last combat seat. `active` means the
participant still belonged to the combat lineup at completion, not that their
tank survived. `winner` marks members of the winning side still in that lineup,
including eliminated teammates. Personal totals follow membership across seat
changes. `mixedTeams` marks participants who played on different teams; their
last team is shown. Entries with `active:false` retain earlier participants.
Pure spectators are omitted, but receive the report normally.

`duration` is live simulation seconds, excluding countdowns, round breaks and
local pauses, including sudden death. `hillSeconds` counts each eligible pilot's
uncontested occupation, not a duplicated team score. `limited` reports the
256-participant ledger bound in unusually high-turnover matches.

No client message can submit these counters. Playing snapshots omit this field;
only the server's frozen, once-encoded report is sent at completion. A late join
or reconnect to the finished match receives the same data. A new match clears
it. Renaming/leaving/swapping after completion cannot mutate it. Old clients
ignore this additive field but need updating to display the popup's new section.


## v4.5: dark-only paint authority and stacked speed

`Tank.speedStacks` is an integer 0–5. While `speedTime > 0`, one stack means the
legacy +65% movement / +25% turn effect; each additional stack adds the same
amount. A Speed pickup increments the stack to five and refreshes `speedTime` to
six seconds. Expiry or a fresh life clears both fields. Speed and Shield each use
spawn-selection weight 3; every other enabled pickup uses weight 1. Clients cannot
submit either speed field through input.

Numbered Teams always use `MatchRules.teamColors[team-1]`. Per-member `colorIndex`
is ignored and cleared when entering Teams. In Free-for-all, a member can request
a cosmetic paint change with the owner-scoped action:

```json
{"type":"paint","target":2,"member":17,"colorIndex":5}
```

The authenticated online human may paint their own FFA tank. A controller may also
paint its dependent local keyboard seat. The room host may paint bots, but **may
not paint another online human**. The server rejects `paint` during a match and in
Teams. `configure.colorIndex` is no longer an authorized paint path. Paint is
cosmetic and does not reset readiness. Public team matchmaking copies clear any
private FFA paint while preserving the original member's preference back home.

The browser appearance is dark-only; color identity remains canonical protocol
metadata and does not depend on CSS or a client theme setting.

## v4.4: shield charges, palette identities, and automatic weapons

An accepted `Tank` snapshot has `shield` (remaining shared duration) and
`shieldCharges` (0–5). A pickup adds one charge up to five and refreshes duration
to ten. Damage consumes a charge then grants the ordinary .35-second protection.
A fresh life resets both. Clients cannot set either field through input.

`MatchRules.teamColors` is an array of exactly four palette indices 0–7. Omitted
legacy values normalize to `[0,1,2,3]`; malformed explicit values are rejected.
`SeatSpec.colorIndex` and room-player `colorIndex` use -1 or omitted/null for
inheritance and 0–7 for a tank override in the v4.4 format. v4.5 supersedes the
old host `configure.colorIndex` mutation with the owner-aware `paint` action above.
Rule edits apply team palettes through the existing `rules` command. `color` in
public state is still a canonical stable identity; clients map it to the active
skin. It never changes numeric teams, targeting or damage. A frozen player-stat
row additionally records canonical `color` to retain the played appearance.

Weapon IDs remain `rapid` and `scatter` for compatibility with saved selections;
UI labels are Machine gun and Shotgun. Their projectile `kind` is now explicit.
`rapid`: radius 3.5/3, speed 846, 1.5-second life, no cooldown, at most one shot per
60 Hz simulation tick, 96 active slots. `scatter`: radius 3.5, speed 846, three
pellets per volley, .54 cooldown, 3.9-second life; its owner is excluded from hits
and shield consumption even after a weapon swap. Other damage rules are unchanged.

To bound bandwidth for continuous fire, regular `state.bullets` excludes rapid
rounds. Optional `state.machineBullets` carries those rounds as numeric tuples:

```
[id, owner, shotSerial, spawnSerial, x, y, vx, vy, age, life, bounces, colorIndex]
```

Geometry/time samples use the same rounding as conventional bullet objects.
The decoder reconstructs `kind:"rapid"`, `r:3.5/3`, `pellet:0`, `target:-1` and
canonical color. It accepts at most 768 well-formed records, combines them with
normal bullets before buffering, and preserves volley/life reconciliation.
Machine gun `shot` cosmetic events are emitted once per four volleys; actual
rounds and shotSerial always advance at the allowed rate. Client sound, trail
and preview limits are cosmetic, not authority for ammunition or hits.

Deploy both client and server together: earlier browsers do not decode the
compact stream. No client-provided size, damage, charge, color or fire-rate
claim is accepted by the simulation. Protocol commands, authentication and the
strict same-origin asset/transport policy are otherwise retained.
