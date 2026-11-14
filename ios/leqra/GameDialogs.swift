import SwiftUI
import leqraCore

struct WebModal<Content: View>: View {
    let title: String
    var close: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: "#091218").opacity(0.8).ignoresSafeArea()
                WebPanel {
                    VStack(spacing: 14) {
                        HStack(alignment: .top) {
                            Text(title).font(.system(size: 23, weight: .black)).foregroundStyle(WebStyle.text)
                            Spacer()
                            Button(action: close) { Image(systemName: "xmark").frame(width: 32, height: 32) }.foregroundStyle(WebStyle.soft).accessibilityLabel("Close " + title)
                        }
                        WebStyle.border.frame(height: 1)
                        ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }.scrollDismissesKeyboard(.interactively)
                            .accessibilityIdentifier("modalScroll")
                    }
                }.frame(maxWidth: 650, maxHeight: min(760, max(200, geometry.size.height - 24))).padding(12)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PauseCard: View {
    @ObservedObject var session: GameSession
    let landscape: Bool
    var body: some View {
        GeometryReader { geometry in
          ZStack {
            Color(hex: "#091218").opacity(0.75).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    WebPanel(accent: true) {
                        if landscape { HStack(alignment: .top, spacing: 24) { intro; actions } }
                        else { VStack(alignment: .leading, spacing: 18) { intro; actions } }
                    }
                    if session.isInfinity {
                        WebPanel {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LEADERBOARD").font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
                                ForEach(Array(session.standings.prefix(10).enumerated()), id: \.element.id) { index, entry in
                                    HStack(alignment: .top) {
                                        Text("\(index + 1). " + (entry.id == session.localID ? session.identity : entry.name))
                                            .fontWeight(entry.id == session.localID ? .bold : .regular).fixedSize(horizontal: false, vertical: true)
                                        Spacer(); Text("\(entry.score)").bold()
                                    }.font(.system(size: 12)).foregroundStyle(WebStyle.paint(entry.colorIndex))
                                }
                                Text("+1 per kill, -1 per death").font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                            }
                        }
                        WebPanel { FieldManualContent(session: session) }
                    }
                }.frame(maxWidth: landscape ? 650 : 400).padding(12)
            }.frame(width: geometry.size.width, height: max(0, min(geometry.size.height - 24, landscape ? 320 : 620)))
                .accessibilityIdentifier("pauseMenuScroll")
          }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.offline ? "TAKE A BREATHER" : "ONLINE MATCH").font(WebStyle.mono()).foregroundStyle(WebStyle.soft)
            (Text(session.offline ? (session.isInfinity ? "HOLD YOUR\n" : "TAKE A\n") : "STAY\n").foregroundColor(WebStyle.text) + Text(session.offline ? (session.isInfinity ? "FIRE." : "BREATHER.") : "CONNECTED.").foregroundColor(WebStyle.accent))
                .font(.system(size: landscape ? 26 : 34, weight: .black)).accessibilityIdentifier("Paused")
            Text(session.offline ? "The battle is paused. Tanks are safe." : "The match keeps running. Tanks remain vulnerable." + (session.isInfinity ? " Respawning waits until the menu closes." : ""))
                .font(.system(size: 12)).lineSpacing(5).foregroundStyle(WebStyle.soft)
            if !session.canResume { Text(session.status).font(.system(size: 12)).foregroundStyle(WebStyle.danger) }
            if session.showFPS {
                Text("\(session.measuredFPS) FPS" + (session.latency.map { ", \($0) ms" } ?? ""))
                    .font(WebStyle.mono()).foregroundStyle(WebStyle.muted).accessibilityIdentifier("frameRateValue").accessibilityValue(session.frameRateDetails)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("CALLSIGN").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
            HStack(spacing: 8) {
                TextField("Callsign", text: $session.callsign).modifier(WebField()).autocorrectionDisabled().onSubmit { session.saveCallsign() }
                    .task { session.scheduleCallsignAvailability() }
                AccountKeyButton(session: session, seat: 0, identity: session.identity, identifier: "pauseAccount")
            }
            CallsignFeedback(message: session.callsignFeedback, checking: session.callsignChecking)
            Button(session.offline ? "← BACK TO THE BATTLE" : "← BACK TO THE ARENA") { session.saveCallsign(); session.setPaused(false) }
                .buttonStyle(WebButtonStyle(kind: .primary)).disabled(!session.canResume).accessibilityIdentifier("Resume")
            Button("Controls") { session.showControls = true }.buttonStyle(WebButtonStyle())
            Button("Settings") { session.showSettings = true }.buttonStyle(WebButtonStyle())
            if session.room != nil, session.isHost {
                Button("End match") { session.returnToRoom() }.buttonStyle(WebButtonStyle()).accessibilityIdentifier("Return to room")
            }
            if session.snapshot.objectives?.survival?.status == "lost", session.isHost {
                Button("Restart wave") { session.restartMatch(wave: true) }.buttonStyle(WebButtonStyle())
            }
            Button(session.isInfinity ? "Exit Infinity" : "Return to ready room") { if session.isInfinity { session.exitArenaToRoom() } else { session.leave() } }
                .buttonStyle(WebButtonStyle()).accessibilityIdentifier("Leave game")
        }.frame(maxWidth: .infinity)
    }
}

struct RulesEditor: View {
    @ObservedObject var session: GameSession
    @State private var rules = RoomRules()
    var body: some View {
        WebModal(title: "Room rules", close: { session.showRules = false }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(session.selectedMode.title.uppercased()).font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
                menu("FORMAT", value: $rules.teamMode, choices: [("ffa", "Free-for-all"), ("teams", "Teams")])
                    .disabled(!rules.infinity && ["ctf", "survival"].contains(rules.mode))
                menu("MAZE SIZE", value: $rules.mapSize, choices: [("compact", "Compact"), ("standard", "Standard"), ("large", "Large"), ("huge", "Huge"), ("giant", "Giant"), ("ultrawide", "Ultrawide")])
                Toggle("Portrait maze", isOn: $rules.portraitMaze).font(.system(size: 13))
                if rules.infinity {
                    Stepper("Score target: \(rules.infinityTarget == 0 ? "Endless" : String(rules.infinityTarget))", value: $rules.infinityTarget, in: 0...999)
                    Toggle("Random roaming bots", isOn: $rules.infinityRandomBots)
                    menu("ROAMING BOT DIFFICULTY", value: $rules.infinityBotDifficulty, choices: BotDifficulty.allCases.map { ($0.rawValue, $0.displayName) })
                    Toggle("Randomize roaming bot difficulty", isOn: $rules.infinityRandomDifficulty)
                } else {
                    Stepper("\(rules.mode == "survival" ? "Wave" : "Score") target: \(rules.scoreTarget)", value: $rules.scoreTarget, in: 1...(rules.mode == "koth" ? 300 : 20))
                    Stepper("Time limit: \(rules.timeLimit)s", value: $rules.timeLimit, in: 30...600, step: 15)
                    Stepper("Respawn: \(rules.respawnSeconds)s", value: $rules.respawnSeconds, in: 1...10)
                }
                Toggle("Friendly fire", isOn: $rules.friendlyFire)
                menu("POWER-UP FREQUENCY", value: $rules.pickupRate, choices: [("superfast", "Super fast"), ("fast", "Fast"), ("normal", "Normal"), ("slow", "Slow"), ("off", "Off")])
                Text("AVAILABLE POWER-UPS").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(powerEntries, id: \.0) { kind, name in
                        Button {
                            if rules.weapons.contains(kind) { rules.weapons.removeAll { $0 == kind } } else { rules.weapons.append(kind) }
                        } label: {
                            HStack { Image(systemName: rules.weapons.contains(kind) ? "checkmark.square.fill" : "square"); Text(name); Spacer() }.font(.system(size: 12)).frame(minHeight: 36)
                        }.foregroundStyle(rules.weapons.contains(kind) ? WebStyle.accent : WebStyle.muted)
                    }
                }
                if rules.teamMode == "teams" {
                    Text("TEAMS").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                    ForEach(0..<4) { index in
                        if rules.teamNames.indices.contains(index), rules.teamColors.indices.contains(index) {
                            VStack(spacing: 4) {
                                TextField("Team \(index + 1)", text: $rules.teamNames[index]).modifier(WebField())
                                PaintChoices(selected: rules.teamColors[index]) { rules.teamColors[index] = $0 }
                            }
                        }
                    }
                }
                Button("APPLY RULES") { session.updateRules(rules); session.showRules = false }.buttonStyle(WebButtonStyle(kind: .primary)).disabled(!session.isHost)
                Button("Restore defaults") {
                    rules = session.effectiveRules.restoringModeDefaults()
                }.buttonStyle(WebButtonStyle())
            }.font(.system(size: 13)).foregroundStyle(WebStyle.text).tint(WebStyle.accent)
        }.onAppear { rules = session.effectiveRules }
    }
    private func menu(_ label: String, value: Binding<String>, choices: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
            Picker(label, selection: value) { ForEach(choices, id: \.0) { key, title in Text(title).tag(key) } }.pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading).modifier(WebField())
        }
    }
}

let powerEntries = [("cannon", "Cannon"), ("ghost", "Ghost"), ("laser", "Laser"), ("homing", "Homing missile"), ("grenade", "Grenade"), ("speed", "Super speed"), ("rapid", "Machine gun"), ("scatter", "Shotgun"), ("shield", "Shield"), ("starman", "Starman")]

struct NativeSettings: View {
    @ObservedObject var session: GameSession
    var body: some View {
        WebModal(title: "Settings", close: { session.showSettings = false }) {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("Request 120 FPS", isOn: $session.highFrameRate)
                Toggle("Show FPS and ping", isOn: $session.showFPS)
                Toggle("Sound and haptics", isOn: $session.soundEnabled).onChange(of: session.soundEnabled) { _ in session.applyAudioSetting(preview: .unmute) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Sound volume"); Spacer(); Text("\(Int(session.soundVolume))%").font(WebStyle.mono()).accessibilityIdentifier("soundVolumeValue") }
                    Slider(value: Binding(get: { session.soundVolume }, set: session.setSoundVolume), in: 0...100, step: 1) { editing in
                        if !editing { session.applyAudioSetting(preview: .volumePreview) }
                    }.accessibilityLabel("Sound volume")
                }
                Text("Display rate adapts to the screen, power, temperature, and iOS settings.").font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                if !session.frameRateDetails.isEmpty { Text(session.frameRateDetails).font(WebStyle.mono()).foregroundStyle(WebStyle.muted) }
                Text("ONLINE SERVER").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                TextField("https://leqra.com", text: $session.serverAddress).modifier(WebField()).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Native protocol \(NetworkClient.supportedVersion)").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                Button("ACCOUNT KEY") { session.openAccount() }.buttonStyle(WebButtonStyle()).accessibilityIdentifier("settingsAccount")
                Button("P2 ACCOUNT KEY") { session.openAccount(seat: 1) }.buttonStyle(WebButtonStyle()).accessibilityIdentifier("settingsLocalAccount")
                Button("DONE") { session.showSettings = false }.buttonStyle(WebButtonStyle(kind: .primary)).accessibilityIdentifier("Done")
            }.font(.system(size: 13)).tint(WebStyle.accent)
        }
    }
}

struct AccountPanel: View {
    @ObservedObject var session: GameSession
    @State private var draft = ""
    @State private var checked: GameSession.CheckedAccount?
    @State private var checking = false
    @State private var message = ""
    @State private var confirmReset = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        WebModal(title: "Account key", close: session.closeAccount) {
            VStack(alignment: .leading, spacing: 14) {
                Text(session.accountContextIdentity).font(WebStyle.mono(12, weight: .bold))
                    .foregroundStyle(session.accountSeatContext == 1 ? WebStyle.mapped(session.accountLocalPlayer?.color ?? GamePalette.colors[1]) : WebStyle.paint(session.colorIndex))
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("accountPlayerIdentity")
                Text("Each local player has a separate account key. Copying, importing, or resetting this key affects only this player's account.")
                    .font(.system(size: 12)).foregroundStyle(WebStyle.soft).fixedSize(horizontal: false, vertical: true)
                Text(session.accountOrigin).font(WebStyle.mono()).foregroundStyle(WebStyle.muted).fixedSize(horizontal: false, vertical: true)
                Text("Your key controls your reserved callsigns and public Infinity score. Copy it to another trusted device to use the same account. Keep it private.")
                    .font(.system(size: 12)).foregroundStyle(WebStyle.soft).fixedSize(horizontal: false, vertical: true)
                Text(session.accountHasKey ? "••••••••••••••••" : "No account key saved on this device.")
                    .font(WebStyle.mono()).accessibilityIdentifier("maskedAccountKey")
                Button(session.accountPendingKeyVerified ? "COPY NEW ACCOUNT KEY" : "COPY ACCOUNT KEY") { session.copyAccountKey() }.buttonStyle(WebButtonStyle())
                    .disabled(!session.accountCanCopyKey || session.accountBusy).accessibilityIdentifier("copyAccountKey")
                if let info = session.accountInfo { accountPreview(info) }
                Text(session.accountStatus).font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                    .frame(minHeight: 30, alignment: .topLeading).accessibilityIdentifier("accountStatus")
                if session.accountSavedActivationCount > 0 {
                    Text("A previous activation may have completed after its connection closed. Its key is saved separately and will not replace your selected account without review.")
                        .font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                    ForEach(0..<session.accountSavedActivationCount, id: \.self) { index in
                        Button("REVIEW SAVED ACTIVATION \(index + 1)") {
                            checkTask?.cancel(); checking = true; checked = nil; message = ""
                            checkTask = Task { @MainActor in
                                do {
                                    let result = try await session.checkSavedActivation(index)
                                    guard !Task.isCancelled else { return }
                                    checked = result; checking = false
                                } catch {
                                    guard !Task.isCancelled else { return }
                                    checking = false; message = "That activation is not confirmed yet. Its key remains saved; try again later."
                                }
                            }
                        }.buttonStyle(WebButtonStyle()).disabled(!session.canImportAccount || checking || session.accountBusy)
                    }
                }
                WebStyle.border.frame(height: 1)
                Text("IMPORT ACCOUNT KEY").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                SecureField("Paste account key", text: $draft).modifier(WebField())
                    .textContentType(.oneTimeCode).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    .disabled(!session.canImportAccount || session.accountBusy || session.accountRecoveryKeyPending)
                    .accessibilityIdentifier("importAccountKey")
                    .onChange(of: draft) { _ in checked = nil; message = ""; checkTask?.cancel(); checking = false }
                if !session.canImportAccount {
                    Text("Return to the offline ready room to import or reset a key.").font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                } else {
                    Button("CHECK KEY") { checkKey() }.buttonStyle(WebButtonStyle())
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking || session.accountBusy || session.accountRecoveryKeyPending)
                        .accessibilityIdentifier("checkAccountKey")
                    if let checked {
                        accountPreview(checked.info)
                        Text("This replaces the account key saved on this device for this server. Copy your current key first if you want to keep it.")
                            .font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                        Button("USE THIS ACCOUNT") {
                            checking = true
                            checkTask = Task { @MainActor in
                                let accepted = await session.useAccount(checked)
                                guard !Task.isCancelled else { return }
                                checking = false
                                if accepted { self.checked = nil; draft = "" }
                            }
                        }.buttonStyle(WebButtonStyle(kind: .primary)).accessibilityIdentifier("useAccountKey")
                            .disabled(checking || session.accountBusy)
                    }
                }
                Text(checking ? "Checking key…" : message).font(.system(size: 11)).foregroundStyle(WebStyle.danger)
                    .frame(minHeight: 30, alignment: .topLeading).accessibilityIdentifier("accountImportStatus")
                WebStyle.border.frame(height: 1)
                Button(session.accountRecoveryKeyPending ? "RETRY KEY RESET" : "RESET ACCOUNT KEY") {
                    checkTask?.cancel(); checked = nil; draft = ""; message = ""
                    confirmReset = true
                }
                    .buttonStyle(WebButtonStyle(kind: .danger))
                    .disabled(!session.canImportAccount || !session.accountCanResetKey || session.accountBusy || checking)
                    .accessibilityIdentifier("resetAccountKey")
                Text("Reset signs out every other device and invalidates the old key. Your names and scores stay with the new key.")
                    .font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                Text("Lost your key? Copy it from a signed-in device. If none remain, there is no automatic recovery and your callsigns stay reserved. You can ask for manual help on GitHub.")
                    .font(.system(size: 11)).foregroundStyle(WebStyle.soft).fixedSize(horizontal: false, vertical: true)
                Link("Open a GitHub issue", destination: URL(string: "https://github.com/nhooyr/leqra/issues/new")!)
                    .font(.system(size: 12)).foregroundStyle(WebStyle.accent)
                Button("DONE") { session.closeAccount() }.buttonStyle(WebButtonStyle(kind: .primary))
            }.font(.system(size: 13))
        }
        .confirmationDialog("Reset account key?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset key and sign out other devices", role: .destructive) { Task { await session.resetAccountKey() } }
        } message: { Text("Every other device will need the new key to sign in again. Callsigns and scores are preserved.") }
        .onDisappear { checkTask?.cancel(); draft = ""; checked = nil }
    }

    @ViewBuilder private func accountPreview(_ info: AccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let profile = info.publicProfile {
                Text("\(profile.name), score: \(profile.score)").fontWeight(.semibold)
                if let local = profile.localName { Text("\(local), score: \(profile.localScore ?? 0)") }
            }
            if !info.names.isEmpty {
                Text("Reserved callsigns: " + info.names.joined(separator: ", "))
                if info.totalNames > info.names.count { Text("Showing \(info.names.count) of \(info.totalNames) reserved callsigns.") }
            }
        }.font(.system(size: 12)).foregroundStyle(WebStyle.soft).fixedSize(horizontal: false, vertical: true)
    }

    private func checkKey() {
        checkTask?.cancel(); checked = nil; checking = true; message = ""
        let input = draft
        checkTask = Task { @MainActor in
            do {
                let result = try await session.checkAccountKey(input)
                guard !Task.isCancelled, draft == input else { return }
                checked = result; checking = false
            } catch {
                guard !Task.isCancelled, draft == input else { return }
                message = error.localizedDescription; checking = false
            }
        }
    }
}

struct ControlsPanel: View {
    @ObservedObject var session: GameSession
    var body: some View {
        WebModal(title: "Controls", close: { session.showControls = false }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(session.identity).font(.system(size: 13, weight: .bold)).foregroundStyle(WebStyle.paint(session.colorIndex))
                Text("WASD/arrow keys to drive, Q/C/Space to fire.").font(.system(size: 12)).foregroundStyle(WebStyle.soft)
                Text("Drag the left stick to drive and aim. Hold the right Fire button to shoot. Pickups equip automatically.").font(.system(size: 13)).lineSpacing(5)
                Text("Grenades: tap to throw. Release, then tap again to detonate. Projectiles pass through the tank that fired them.").font(.system(size: 12)).lineSpacing(5).foregroundStyle(WebStyle.soft)
                Text("Ricochet around corners. Collect Shield, Ghost, Super speed, or Starman to stay in the battle.").font(.system(size: 12)).lineSpacing(5).foregroundStyle(WebStyle.soft)
                Button("BACK") { session.showControls = false }.buttonStyle(WebButtonStyle(kind: .primary))
            }
        }
    }
}

struct SidebarPanel: View {
    @ObservedObject var session: GameSession
    var body: some View {
        WebModal(title: "Sidebar", close: { session.showSidebar = false }) {
            VStack(alignment: .leading, spacing: 18) {
                if let report = session.snapshot.matchStats {
                    Text("MATCH REPORT").font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
                    Text("\(report.rounds) rounds, \(Int(report.duration)) seconds").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                    ForEach(report.players) { player in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(player.name + ((player.member == session.roomMemberID || player.controllerMember == session.roomMemberID) ? " (P1)" : "")).fontWeight(player.member == session.roomMemberID || player.controllerMember == session.roomMemberID ? .bold : .regular)
                                Spacer(); Text("\(player.score)").bold()
                            }.foregroundStyle(WebStyle.mapped(player.color))
                            Text("\(player.eliminations) eliminations, \(player.deaths) deaths, \(player.selfDestructs) self-destructs").foregroundStyle(WebStyle.soft)
                            if report.mode == "ctf" { Text("\(player.captures) captures, \(player.flagReturns) returns").foregroundStyle(WebStyle.muted) }
                            if report.mode == "koth" { Text("\(Int(player.hillSeconds))s on hill").foregroundStyle(WebStyle.muted) }
                        }.font(.system(size: 11)).padding(.vertical, 5)
                    }
                    WebStyle.border.frame(height: 1)
                }
                Text("LEADERBOARD").font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
                ForEach(session.standings) { entry in
                    HStack { Text(entry.id == session.localID ? session.identity : entry.name).fontWeight(entry.id == session.localID ? .bold : .regular); Spacer(); Text("\(entry.score)").font(WebStyle.mono(22)) }.font(.system(size: 12)).foregroundStyle(WebStyle.paint(entry.colorIndex))
                }
                WebStyle.border.frame(height: 1)
                FieldManualContent(session: session)
                Button("SETTINGS") { session.showSidebar = false; session.showSettings = true }.buttonStyle(WebButtonStyle())
            }
        }
    }
}

struct FieldManualContent: View {
    @ObservedObject var session: GameSession
    private var infinity: Bool { session.isInfinity || session.effectiveRules.infinity || session.readyRoom && (session.room?.infinityPublic ?? session.publicInfinitySelected) }
    private let descriptions = [
        "cannon": "Pierces walls. Four times the size and speed.",
        "ghost": "Drive through walls. Stacks with Super speed.",
        "laser": "Instant ricochets with a long dotted aim guide.",
        "homing": "Guided missiles that ricochet.",
        "grenade": "Homes in on opponents. Explodes on tank impact, another Fire press, or its 10-second fuse. Walls stop blasts.",
        "speed": "Stacks to five, adding 65% speed each time.",
        "rapid": "Three seconds of firing with tiny, fast rounds.",
        "scatter": "Fast, ricocheting spread.",
        "shield": "Stack up to five protective rings.",
        "starman": "Invincibility, lethal contact, movement through walls, unlimited ammunition and no cooldown."
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FIELD MANUAL").font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
            Text("Touch").font(.system(size: 13, weight: .semibold))
            Text("Drag the joystick to drive and aim. Tap or hold Fire to shoot.").font(.system(size: 12)).foregroundStyle(WebStyle.soft)
            Text(infinity ? "INFINITY" : session.selectedMode.title.uppercased()).font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
            Text(infinity ? "Gain a point for each kill and lose a point each time the tank is destroyed. Respawn after one second. Keep growing the score without a time limit." : session.selectedMode.help)
                .font(.system(size: 12)).foregroundStyle(WebStyle.soft)
            Button("CONTROLS") { session.showSidebar = false; session.showControls = true }.buttonStyle(WebButtonStyle())
            Text("GRAB AN ADVANTAGE, 10 POWER-UPS").font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
            ForEach(powerEntries, id: \.0) { kind, name in
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 12, weight: .bold)).foregroundStyle(WebStyle.text)
                    Text(descriptions[kind] ?? "").font(.system(size: 12)).foregroundStyle(WebStyle.soft)
                }
            }
        }
    }
}

struct JoinRoomPanel: View {
    @ObservedObject var session: GameSession
    @State private var code = ""
    var body: some View {
        WebModal(title: "Find a room.", close: { session.showJoin = false }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("CALLSIGN").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                HStack(spacing: 8) {
                    TextField("Callsign", text: $session.callsign).modifier(WebField())
                        .task { session.scheduleCallsignAvailability() }
                    AccountKeyButton(session: session, seat: 0, identity: session.identity, identifier: "joinAccount")
                }
                CallsignFeedback(message: session.callsignFeedback, checking: session.callsignChecking)
                Text("ROOM NAME OR CODE").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                TextField("Friday tanks 💥", text: $code).modifier(WebField()).autocorrectionDisabled()
                Button("JOIN →") { session.showJoin = false; session.connect(code: code) }.buttonStyle(WebButtonStyle(kind: .primary)).disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Missing rooms are created with the joining pilot as host.").font(.system(size: 11)).foregroundStyle(WebStyle.soft)
            }
        }
    }
}

struct PresetsPanel: View {
    @ObservedObject var session: GameSession
    @State private var name = ""
    var body: some View {
        WebModal(title: "Room presets", close: { session.showPresets = false }) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Save this room's rules and bots for another battle.").font(.system(size: 12)).foregroundStyle(WebStyle.soft)
                TextField("Preset name", text: $name).modifier(WebField())
                Button("SAVE ROOM") { session.savePreset(name: name); name = "" }.buttonStyle(WebButtonStyle(kind: .primary)).disabled(!session.isHost || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(session.savedPresets) { preset in
                    HStack { Text(preset.id).font(.system(size: 13)); Spacer(); Button("LOAD") { session.loadPreset(preset); session.showPresets = false }.buttonStyle(WebButtonStyle(compact: true)).frame(width: 70).disabled(!session.canLoadPreset) }
                }
            }
        }
    }
}

struct ChatPanel: View {
    @ObservedObject var session: GameSession
    @State private var channel: ChatChannel = .room
    var body: some View {
        VStack(spacing: 8) {
            HStack { Text("CHAT").font(WebStyle.mono()); Spacer(); Picker("Channel", selection: $channel) { if session.roomChatAvailable { Text("Room").tag(ChatChannel.room) }; if session.opponentChatAvailable { Text("Opponent").tag(ChatChannel.opponent) } }.font(.system(size: 11)); Button { session.showChat = false } label: { Image(systemName: "xmark").frame(width: 32, height: 32) } }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(channel == .room ? session.chatMessages : session.opponentMessages) { message in
                            VStack(alignment: .leading, spacing: 3) { Text(message.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(WebStyle.accent); Text(message.text).font(.system(size: 12)).foregroundStyle(WebStyle.text) }.id(message.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.onChange(of: session.chatMessages.count) { _ in if let last = session.chatMessages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            HStack {
                TextField("Message", text: $session.chatDraft).modifier(WebField()).onSubmit(submit)
                Button(action: submit) { Image(systemName: "paperplane.fill").frame(width: 36, height: 40) }.foregroundStyle(WebStyle.accent).disabled(session.chatPending || session.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = session.chatError { Text(error).font(.system(size: 11)).foregroundStyle(WebStyle.danger) }
            Text("\(session.chatDraft.unicodeScalars.count) / 280").font(WebStyle.mono()).foregroundStyle(WebStyle.muted).frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(12).frame(maxWidth: 345).frame(height: 360).background(WebStyle.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(WebStyle.edge, lineWidth: 1).allowsHitTesting(false)).padding(10)
            .onAppear { if !session.roomChatAvailable && session.opponentChatAvailable { channel = .opponent } }
    }
    private func submit() { session.sendChat(session.chatDraft, channel: channel) }
}

struct QueuePanel: View {
    @ObservedObject var session: GameSession
    var body: some View {
        WebModal(title: "Find a match", close: { session.showQueues = false }) {
            VStack(alignment: .leading, spacing: 14) {
                if let queue = session.queueState {
                    Text(queue.name).font(.system(size: 18, weight: .bold)).foregroundStyle(WebStyle.accent)
                    Text("\(queue.players) / \(queue.required) players, \(queue.stage)").font(.system(size: 12)).foregroundStyle(WebStyle.soft)
                    ForEach(queue.members) { member in HStack { Text(member.name); Spacer(); Text(member.accepted ? "READY" : "WAITING") }.font(.system(size: 12)) }
                    if session.canConfirmQueue { Button("READY") { session.send(.queueAccept(queue.id)) }.buttonStyle(WebButtonStyle(kind: .play)) }
                    if session.canCancelQueue { Button("CANCEL SEARCH") { session.send(.queueCancel(queue.id)) }.buttonStyle(WebButtonStyle()) }
                } else {
                    ForEach(session.queueListings) { listing in
                        Button { session.send(.queueJoin(listing.definition.key)) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(listing.definition.name).font(.system(size: 17, weight: .bold))
                                Text("\(listing.waitingPlayers) waiting, \(listing.definition.cols) × \(listing.definition.rows) maze").font(WebStyle.mono())
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(WebStyle.sunken, in: RoundedRectangle(cornerRadius: 7))
                        }.foregroundStyle(WebStyle.text).disabled(!session.canQueue)
                    }
                    if session.queueListings.isEmpty { ProgressView().tint(WebStyle.accent).frame(maxWidth: .infinity) }
                }
            }
        }
    }
}
