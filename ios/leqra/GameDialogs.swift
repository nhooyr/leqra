import SpriteKit
import SwiftUI
import leqraCore

struct WebModal<Content: View>: View {
    let title: String
    var close: () -> Void
    var scrolls = true
    var scrollTrailingInset: CGFloat = 0
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
                            Button(action: close) { Image(systemName: "xmark").frame(width: 32, height: 32) }
                                .foregroundStyle(WebStyle.soft).accessibilityLabel("Close " + title)
                        }
                        WebStyle.border.frame(height: 1)
                        if scrolls {
                            ScrollView {
                                content().frame(maxWidth: .infinity, alignment: .leading).padding(
                                    .trailing, scrollTrailingInset)
                            }.scrollDismissesKeyboard(.interactively)
                                .accessibilityIdentifier("modalScroll")
                        } else {
                            content()
                        }
                    }
                }.frame(width: min(650, max(0, geometry.size.width - 24)))
                    .frame(maxHeight: min(760, max(200, geometry.size.height - 24))).padding(12)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PauseCard: View {
    @ObservedObject var session: GameSession
    let landscape: Bool
    @State private var originalCallsign = ""
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: "#091218").opacity(0.75).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        WebPanel(accent: true) {
                            if landscape {
                                HStack(alignment: .top, spacing: 24) {
                                    intro
                                    actions
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 18) {
                                    intro
                                    actions
                                }
                            }
                        }
                        if session.isInfinity {
                            WebPanel {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("LEADERBOARD").font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
                                    ForEach(
                                        Array(session.standings.prefix(10).enumerated()), id: \.element.id
                                    ) { index, entry in
                                        let seat = session.localPilotSeat(entry.id)
                                        HStack(alignment: .top) {
                                            Text(
                                                "\(index + 1). " + entry.displayName
                                                    + (seat.map { " (P\($0))" } ?? "")
                                            )
                                            .fontWeight(seat != nil ? .bold : .regular).fixedSize(
                                                horizontal: false, vertical: true)
                                            if let difficulty = entry.difficultyLabel {
                                                Text(difficulty).font(WebStyle.mono()).foregroundStyle(
                                                    WebStyle.muted)
                                            }
                                            Spacer()
                                            Text("\(entry.score)").bold()
                                        }.font(.system(size: 12)).foregroundStyle(
                                            WebStyle.paint(entry.colorIndex))
                                    }
                                    Text("+1 per kill, -1 per death").font(.system(size: 11)).foregroundStyle(
                                        WebStyle.soft)
                                }
                            }
                            WebPanel { FieldManualContent(session: session) }
                        }
                    }.frame(maxWidth: landscape ? 650 : 400).padding(12)
                }.frame(
                    width: geometry.size.width,
                    height: max(0, min(geometry.size.height - 24, landscape ? 320 : 620))
                )
                .accessibilityIdentifier("pauseMenuScroll")
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.onAppear { originalCallsign = session.callsign }
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.offline ? "TAKE A BREATHER" : "ONLINE MATCH").font(WebStyle.mono()).foregroundStyle(
                WebStyle.soft)
            (Text(session.offline ? (session.isInfinity ? "HOLD YOUR\n" : "TAKE A\n") : "STAY\n")
                .foregroundColor(WebStyle.text)
                + Text(session.offline ? (session.isInfinity ? "FIRE." : "BREATHER.") : "CONNECTED.")
                .foregroundColor(WebStyle.accent))
                .font(.system(size: landscape ? 26 : 34, weight: .black)).accessibilityIdentifier("Paused")
            Text(
                session.spectating
                    ? "The arena keeps running while you browse the menu."
                    : session.offline
                        ? "The battle is paused. Tanks are safe."
                        : "The match keeps running. Tanks remain vulnerable."
                            + (session.isInfinity ? " Respawning waits until the menu closes." : "")
            )
            .font(.system(size: 12)).lineSpacing(5).foregroundStyle(WebStyle.soft)
            if !session.canResume {
                Text(session.status).font(.system(size: 12)).foregroundStyle(WebStyle.danger)
            }
            if session.showFPS {
                Text("\(session.measuredFPS) FPS" + (session.latency.map { ", \($0) ms" } ?? ""))
                    .font(WebStyle.mono()).foregroundStyle(WebStyle.muted).accessibilityIdentifier(
                        "frameRateValue"
                    ).accessibilityValue(session.frameRateDetails)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !session.spectating {
                Text("CALLSIGN").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                HStack(spacing: 8) {
                    TextField("Callsign", text: $session.callsign).modifier(WebField())
                        .autocorrectionDisabled().onSubmit { session.saveCallsign() }
                        .task { session.scheduleCallsignAvailability() }
                    AccountKeyButton(
                        session: session, seat: 0, identity: session.identity, identifier: "pauseAccount")
                }
                CallsignFeedback(session: session)
            }
            Button(session.offline ? "← BACK TO THE BATTLE" : "← BACK TO THE ARENA") {
                if CallsignPolicy.clean(session.callsign) != CallsignPolicy.clean(originalCallsign) {
                    session.saveCallsign()
                }
                session.setPaused(false)
            }
            .buttonStyle(WebButtonStyle(kind: .primary)).disabled(!session.canResume).accessibilityIdentifier(
                "Resume")
            if !session.spectating || session.secondaryLocalID != nil {
                Button("Controls") { session.showControls = true }.buttonStyle(WebButtonStyle())
            }
            if session.room != nil, session.isHost {
                Button("End match") { session.returnToRoom() }.buttonStyle(WebButtonStyle())
                    .accessibilityIdentifier("Return to room")
            }
            if session.snapshot.objectives?.survival?.status == "lost", session.isHost {
                Button("Restart wave") { session.restartMatch(wave: true) }.buttonStyle(WebButtonStyle())
            }
            Button(session.isInfinity ? "Exit Infinity" : "Return to the room") {
                if session.isInfinity { session.exitArenaToRoom() } else { session.leave() }
            }
            .buttonStyle(WebButtonStyle()).accessibilityIdentifier("Leave game")
        }.frame(maxWidth: .infinity)
    }
}

struct RulesEditor: View {
    @ObservedObject var session: GameSession
    @State private var rules = RoomRules()
    private var powerHelp: PowerupHelp { PowerupHelp(rules: rules) }
    var body: some View {
        WebModal(title: "Room rules", close: { session.showRules = false }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(session.selectedMode.title.uppercased()).font(WebStyle.mono()).foregroundStyle(
                    WebStyle.accent)
                if !rules.infinity && (session.room?.infinityPublic ?? session.publicInfinitySelected) {
                    Text(
                        "Public Infinity uses all ten power-ups with 15-second effects, 8-second Starman, and 30-second ground expiry. The room settings below apply when Public Infinity is off."
                    )
                    .font(.system(size: 12)).foregroundStyle(WebStyle.soft).fixedSize(
                        horizontal: false, vertical: true
                    )
                    .accessibilityIdentifier("publicInfinityRulesNote")
                }
                menu(
                    "FORMAT", value: $rules.teamMode, choices: [("ffa", "Free-for-all"), ("teams", "Teams")]
                )
                .disabled(!rules.infinity && ["ctf", "survival"].contains(rules.mode))
                menu(
                    "MAZE SIZE", value: $rules.mapSize,
                    choices: [
                        ("compact", "Compact"), ("standard", "Standard"), ("large", "Large"),
                        ("huge", "Huge"), ("giant", "Giant"), ("ultrawide", "Ultrawide"),
                    ]
                ).disabled(rules.infinity)
                Toggle("Portrait maze", isOn: $rules.portraitMaze).font(.system(size: 13)).disabled(
                    rules.infinity)
                if rules.infinity {
                    Stepper(
                        "Score target: \(rules.infinityTarget == 0 ? "Endless" : String(rules.infinityTarget))",
                        value: $rules.infinityTarget, in: 0...999)
                    Toggle("Random roaming bots", isOn: $rules.infinityRandomBots).accessibilityIdentifier(
                        "randomRoamingBots")
                    if rules.infinityRandomBots {
                        ForEach(BotDifficulty.allCases, id: \.self) { difficulty in roamingRate(difficulty) }
                        Text(
                            "1× averages 1 bot every 1.5 seconds per living human while the shared budget has space."
                        )
                        .font(.system(size: 11)).foregroundStyle(WebStyle.muted).fixedSize(
                            horizontal: false, vertical: true)
                        Text(
                            "16 roaming bots per player, up to 128 in a room. Bots spread around players and retire when nobody is nearby."
                        )
                        .font(.system(size: 11)).foregroundStyle(WebStyle.muted).fixedSize(
                            horizontal: false, vertical: true)
                    }
                } else {
                    Stepper(
                        "\(rules.mode == "survival" ? "Wave" : "Score") target: \(rules.scoreTarget)",
                        value: $rules.scoreTarget, in: 1...(rules.mode == "koth" ? 300 : 20))
                    Stepper(
                        "Time limit: \(rules.timeLimit)s", value: $rules.timeLimit, in: 30...600, step: 15)
                    Stepper("Respawn: \(rules.respawnSeconds)s", value: $rules.respawnSeconds, in: 1...10)
                }
                Toggle("Friendly fire", isOn: $rules.friendlyFire)
                if !rules.infinity {
                    menu(
                        "POWER-UP FREQUENCY", value: $rules.pickupRate,
                        choices: [
                            ("superfast", "Super fast"), ("fast", "Fast"), ("normal", "Normal"),
                            ("slow", "Slow"), ("off", "Off"),
                        ])
                }
                Text(rules.infinity ? "INFINITY POWER-UPS" : "AVAILABLE POWER-UPS").font(WebStyle.mono())
                    .foregroundStyle(WebStyle.muted)
                Text(powerHelp.summary).font(.system(size: 12)).foregroundStyle(WebStyle.soft).fixedSize(
                    horizontal: false, vertical: true
                )
                .accessibilityIdentifier("rulesPowerupSummary")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(powerEntries, id: \.0) { kind, name in
                        if rules.infinity {
                            powerRow(kind: kind, name: name)
                        } else {
                            Button {
                                if rules.weapons.contains(kind) {
                                    rules.weapons.removeAll { $0 == kind }
                                } else {
                                    rules.weapons.append(kind)
                                }
                            } label: {
                                powerRow(kind: kind, name: name)
                            }
                            .accessibilityIdentifier("rulePowerup_" + kind)
                        }
                    }
                }
                if rules.teamMode == "teams" {
                    Text("TEAMS").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                    ForEach(0..<4) { index in
                        if rules.teamNames.indices.contains(index), rules.teamColors.indices.contains(index) {
                            VStack(spacing: 4) {
                                TextField("Team \(index + 1)", text: $rules.teamNames[index]).modifier(
                                    WebField())
                                PaintChoices(selected: rules.teamColors[index]) {
                                    rules.teamColors[index] = $0
                                }
                            }
                        }
                    }
                }
                if !session.roomSetupError.isEmpty {
                    Text(session.roomSetupError).font(.system(size: 11)).foregroundStyle(WebStyle.danger)
                }
                Button("APPLY RULES") { if session.updateRules(rules) { session.showRules = false } }
                    .buttonStyle(WebButtonStyle(kind: .primary)).disabled(!session.isHost)
                Button("Restore defaults") {
                    rules = session.effectiveRules.restoringModeDefaults()
                }.buttonStyle(WebButtonStyle())
            }.font(.system(size: 13)).foregroundStyle(WebStyle.text).tint(WebStyle.accent)
        }.onAppear { rules = session.effectiveRules }
    }
    private func powerRow(kind: String, name: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                if !rules.infinity {
                    Image(systemName: rules.weapons.contains(kind) ? "checkmark.square.fill" : "square")
                }
                Text(name).fontWeight(.semibold)
                Spacer(minLength: 0)
            }.font(.system(size: 12)).foregroundStyle(
                rules.infinity || rules.weapons.contains(kind) ? WebStyle.accent : WebStyle.muted)
            Text(powerHelp.description(for: kind)).font(.system(size: 12)).foregroundStyle(WebStyle.soft)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func roamingRate(_ difficulty: BotDifficulty) -> some View {
        let value = Binding<Double>(
            get: { rules.effectiveInfinityBotSpawnRates[difficulty.rawValue] ?? 0 },
            set: { rules.setInfinityBotSpawnRate($0, for: difficulty.rawValue) })
        return VStack(alignment: .leading, spacing: 5) {
            Text("\(difficulty.displayName.uppercased()) BOT SPAWN RATE").font(WebStyle.mono())
                .foregroundStyle(WebStyle.muted)
            Picker("\(difficulty.displayName) bot spawn rate", selection: value) {
                ForEach(rules.infinityBotSpawnRateChoices(for: difficulty.rawValue), id: \.self) { rate in
                    Text(
                        rate == 0 ? "Off" : "\(rate.formatted(.number.precision(.significantDigits(1...3))))×"
                    ).tag(rate)
                }
            }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).modifier(WebField())
                .accessibilityIdentifier("roamingSpawnRate_\(difficulty.rawValue)")
        }
    }
    private func menu(_ label: String, value: Binding<String>, choices: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
            Picker(label, selection: value) {
                ForEach(choices, id: \.0) { key, title in Text(title).tag(key) }
            }.pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading).modifier(WebField())
        }
    }
}

let powerEntries = [
    ("cannon", "Cannon"), ("ghost", "Ghost"), ("laser", "Laser"), ("homing", "Homing missile"),
    ("grenade", "Grenade"), ("speed", "Super speed"), ("rapid", "Machine gun"), ("scatter", "Shotgun"),
    ("shield", "Shield"), ("starman", "Starman"),
]

struct NativePreferencesPanel: View {
    @ObservedObject var session: GameSession
    @State private var confirmReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            NativeSettingToggle(
                "Request 120 FPS", isOn: $session.highFrameRate, identifier: "settingHighFrameRate")
            NativeSettingToggle("Show FPS and ping", isOn: $session.showFPS, identifier: "settingShowFPS")
            NativeSettingToggle(
                "Game controller support", isOn: $session.gamepadSupport, identifier: "settingGamepadSupport")
            NativeSettingToggle("Sound and haptics", isOn: $session.soundEnabled, identifier: "settingSound")
                .onChange(of: session.soundEnabled) { _ in session.applyAudioSetting(preview: .unmute) }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sound volume")
                    Spacer()
                    Text("\(Int(session.soundVolume))%").font(WebStyle.mono(13)).accessibilityIdentifier(
                        "soundVolumeValue")
                }
                Slider(
                    value: Binding(get: { session.soundVolume }, set: session.setSoundVolume), in: 0...100,
                    step: 1
                ) { editing in
                    if !editing { session.applyAudioSetting(preview: .volumePreview) }
                }.accessibilityLabel("Sound volume")
            }
            if !session.frameRateDetails.isEmpty {
                Text(session.frameRateDetails).font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
            }
            Text("ONLINE SERVER").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
            TextField("https://leqra.com", text: $session.serverAddress).modifier(WebField()).keyboardType(
                .URL
            ).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("RESET ALL SETTINGS") { confirmReset = true }.buttonStyle(WebButtonStyle(kind: .danger))
                .accessibilityIdentifier("resetAllSettings")
        }.font(.system(size: 13)).tint(WebStyle.accent)
            .confirmationDialog(
                "Restore defaults and return to the room? Room, server, display, audio, and control settings will reset. Saved account keys and callsigns stay on this device.",
                isPresented: $confirmReset, titleVisibility: .visible
            ) {
                Button("Reset all settings", role: .destructive) { session.resetAllSettings() }
                Button("Cancel", role: .cancel) {}
            }
    }
}

struct NativeSettingToggle: View {
    let title: String
    @Binding var isOn: Bool
    let identifier: String
    init(_ title: String, isOn: Binding<Bool>, identifier: String) {
        self.title = title
        _isOn = isOn
        self.identifier = identifier
    }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            Toggle(title, isOn: $isOn).labelsHidden().frame(width: 70, height: 44)
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
        }.frame(maxWidth: .infinity, minHeight: 44)
    }
}

struct AccountPanel: View {
    @ObservedObject var session: GameSession
    @State private var draft = ""
    @State private var checked: GameSession.CheckedAccount?
    @State private var checking = false
    @State private var message = ""
    @State private var confirmReset = false
    @State private var confirmRelease = false
    @State private var releaseName: String?
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        WebModal(title: "Account key", close: session.closeAccount) {
            VStack(alignment: .leading, spacing: 14) {
                Text(session.accountContextIdentity).font(WebStyle.mono(12, weight: .bold))
                    .foregroundStyle(
                        session.accountSeatContext == 1
                            ? WebStyle.mapped(session.accountLocalMember?.color ?? GamePalette.colors[1])
                            : WebStyle.paint(session.colorIndex)
                    )
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(
                        "accountPlayerIdentity")
                Text(
                    "Each local player has a separate account key. Copying, importing, or resetting this key affects only this player's account."
                )
                .font(.system(size: 12)).foregroundStyle(WebStyle.soft).fixedSize(
                    horizontal: false, vertical: true)
                Text(session.accountOrigin).font(WebStyle.mono()).foregroundStyle(WebStyle.muted).fixedSize(
                    horizontal: false, vertical: true)
                Text(
                    "Your key controls your callsign and public Infinity score. Copy it to another trusted device to use the same account. Keep it private."
                )
                .font(.system(size: 12)).foregroundStyle(WebStyle.soft).fixedSize(
                    horizontal: false, vertical: true)
                Text(
                    "Each callsign has its own account and score. New callsigns start at zero. Saved callsigns let you switch back without pasting a key. Accounts expire after one month without signing in."
                )
                .font(.system(size: 12)).foregroundStyle(WebStyle.soft).fixedSize(
                    horizontal: false, vertical: true)
                Text(session.accountHasKey ? "••••••••••••••••" : "No account key saved on this device.")
                    .font(WebStyle.mono()).accessibilityIdentifier("maskedAccountKey")
                Button(session.accountPendingKeyVerified ? "COPY NEW ACCOUNT KEY" : "COPY ACCOUNT KEY") {
                    session.copyAccountKey()
                }.buttonStyle(WebButtonStyle())
                    .disabled(!session.accountCanCopyKey || session.accountBusy).accessibilityIdentifier(
                        "copyAccountKey")
                if let info = session.accountInfo { accountPreview(info) }
                ForEach(session.savedCallsignNames, id: \.self) { name in
                    let useDisabled =
                        !session.canImportAccount || session.accountBusy || session.switchingCallsign
                        || session.isCurrentSavedCallsign(name)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button("USE " + name) { session.useSavedCallsign(name) }
                                .buttonStyle(WebButtonStyle()).disabled(useDisabled)
                                .saturation(useDisabled ? 0 : 1).opacity(useDisabled ? 0.45 : 1)
                            Button("RELEASE") {
                                releaseName = name
                                confirmRelease = true
                            }
                            .buttonStyle(WebButtonStyle(kind: .danger)).disabled(
                                !session.canImportAccount || session.accountBusy || session.switchingCallsign)
                        }
                        Text(session.savedCallsignScoreText(name)).font(.system(size: 12)).foregroundStyle(
                            WebStyle.soft
                        )
                        .accessibilityIdentifier("savedCallsignScore-" + name)
                    }
                }
                Text(session.accountStatus).font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                    .frame(minHeight: 30, alignment: .topLeading).accessibilityIdentifier("accountStatus")
                if session.accountSavedActivationCount > 0 {
                    Text(
                        "A previous activation may have completed after its connection closed. Its key is saved separately and will not replace your selected account without review."
                    )
                    .font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                    ForEach(0..<session.accountSavedActivationCount, id: \.self) { index in
                        Button("REVIEW SAVED ACTIVATION \(index + 1)") {
                            checkTask?.cancel()
                            checking = true
                            checked = nil
                            message = ""
                            checkTask = Task { @MainActor in
                                do {
                                    let result = try await session.checkSavedActivation(index)
                                    guard !Task.isCancelled else { return }
                                    checked = result
                                    checking = false
                                } catch {
                                    guard !Task.isCancelled else { return }
                                    checking = false
                                    message =
                                        "That activation is not confirmed yet. Its key remains saved; try again later."
                                }
                            }
                        }.buttonStyle(WebButtonStyle()).disabled(
                            !session.canImportAccount || checking || session.accountBusy)
                    }
                }
                WebStyle.border.frame(height: 1)
                Text("IMPORT ACCOUNT KEY").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                SecureField("Paste account key", text: $draft).modifier(WebField())
                    .textContentType(.oneTimeCode).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().privacySensitive()
                    .disabled(
                        !session.canImportAccount || session.accountBusy || session.accountRecoveryKeyPending
                    )
                    .accessibilityIdentifier("importAccountKey")
                    .onChange(of: draft) { _ in
                        checked = nil
                        message = ""
                        checkTask?.cancel()
                        checking = false
                    }
                if !session.canImportAccount {
                    Text("Return to the offline room to import or reset a key.").font(.system(size: 11))
                        .foregroundStyle(WebStyle.soft)
                } else {
                    Button("CHECK KEY") { checkKey() }.buttonStyle(WebButtonStyle())
                        .disabled(
                            draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking
                                || session.accountBusy || session.accountRecoveryKeyPending
                        )
                        .accessibilityIdentifier("checkAccountKey")
                    if let checked {
                        accountPreview(checked.info)
                        Text(
                            "This selects the imported account. Your current callsign and key stay saved on this device for switching back."
                        )
                        .font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                        Button("USE THIS ACCOUNT") {
                            checking = true
                            checkTask = Task { @MainActor in
                                let accepted = await session.useAccount(checked)
                                guard !Task.isCancelled else { return }
                                checking = false
                                if accepted {
                                    self.checked = nil
                                    draft = ""
                                }
                            }
                        }.buttonStyle(WebButtonStyle(kind: .primary)).accessibilityIdentifier("useAccountKey")
                            .disabled(checking || session.accountBusy)
                    }
                }
                Text(checking ? "Checking key…" : message).font(.system(size: 11)).foregroundStyle(
                    WebStyle.danger
                )
                .frame(minHeight: 30, alignment: .topLeading).accessibilityIdentifier("accountImportStatus")
                WebStyle.border.frame(height: 1)
                Button(session.accountRecoveryKeyPending ? "RETRY KEY RESET" : "RESET ACCOUNT KEY") {
                    checkTask?.cancel()
                    checked = nil
                    draft = ""
                    message = ""
                    confirmReset = true
                }
                .buttonStyle(WebButtonStyle(kind: .danger))
                .disabled(
                    !session.canImportAccount || !session.accountCanResetKey || session.accountBusy
                        || checking
                )
                .accessibilityIdentifier("resetAccountKey")
                Button("RELEASE CURRENT CALLSIGN") {
                    releaseName = nil
                    confirmRelease = true
                }
                .buttonStyle(WebButtonStyle(kind: .danger))
                .disabled(
                    !session.canImportAccount || !session.accountHasKey || session.accountBusy
                        || session.switchingCallsign
                )
                .accessibilityIdentifier("releaseAccount")
                Text(
                    "Reset signs out every other device and invalidates the old key. Your callsign and score stay with the new key."
                )
                .font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                Text(
                    "Lost your key? Copy it from a signed-in device. If none remain, there is no automatic recovery; an inactive account expires after one month. You can ask for manual help on GitHub."
                )
                .font(.system(size: 11)).foregroundStyle(WebStyle.soft).fixedSize(
                    horizontal: false, vertical: true)
                Link(
                    "Open a GitHub issue",
                    destination: URL(string: "https://github.com/nhooyr/leqra/issues/new")!
                )
                .font(.system(size: 12)).foregroundStyle(WebStyle.accent)
                Button("DONE") { session.closeAccount() }.buttonStyle(WebButtonStyle(kind: .primary))
            }.font(.system(size: 13))
        }
        .confirmationDialog("Release callsign?", isPresented: $confirmRelease, titleVisibility: .visible) {
            Button("Release callsign and delete score", role: .destructive) {
                Task { await session.releaseCallsign(releaseName) }
            }
        } message: {
            Text(
                "This permanently deletes this account's score, makes the callsign available to others, and signs out its devices. Other saved accounts are kept."
            )
        }
        .confirmationDialog("Reset account key?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset key and sign out other devices", role: .destructive) {
                Task { await session.resetAccountKey() }
            }
        } message: {
            Text(
                "Every other device will need the new key to sign in again. Your callsign and score are preserved."
            )
        }
        .onDisappear {
            checkTask?.cancel()
            draft = ""
            checked = nil
        }
    }

    @ViewBuilder private func accountPreview(_ info: AccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let name = info.preferredCallsign { Text("Callsign: " + name) }
            if let profile = info.publicProfile {
                Text("Public Infinity score: \(profile.score)").fontWeight(.semibold)
            }
        }.font(.system(size: 12)).foregroundStyle(WebStyle.soft).fixedSize(horizontal: false, vertical: true)
    }

    private func checkKey() {
        checkTask?.cancel()
        checked = nil
        checking = true
        message = ""
        let input = draft
        checkTask = Task { @MainActor in
            do {
                let result = try await session.checkAccountKey(input)
                guard !Task.isCancelled, draft == input else { return }
                checked = result
                checking = false
            } catch {
                guard !Task.isCancelled, draft == input else { return }
                message = error.localizedDescription
                checking = false
            }
        }
    }
}

struct ControlsPanel: View {
    @ObservedObject var session: GameSession
    @ObservedObject private var hardware = NativeHardwarePresence.shared
    @State private var capture: BindingCapture?
    @State private var bindingError = ""
    private var keyboardConnected: Bool { hardwareProbe ?? hardware.keyboardConnected }
    private var mouseConnected: Bool { hardwareProbe ?? hardware.mouseConnected }
    private var hardwareProbe: Bool? {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--probe-touch-only-controls") { return false }
            if arguments.contains("--probe-hardware-controls") { return true }
        #endif
        return nil
    }
    private struct BindingCapture: Identifiable {
        let layout: Int
        let action: NativeControlAction
        var id: String { "\(layout)-\(action.rawValue)" }
    }
    var body: some View {
        let controlsCovered = capture != nil || session.showQuickTour || session.showAccount
        ZStack {
            WebModal(title: "Controls", close: { session.showControls = false }, scrollTrailingInset: 10) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(session.identity).font(.system(size: 13, weight: .bold)).foregroundStyle(
                        WebStyle.paint(session.colorIndex))
                    if session.hasLocalP2 {
                        Text("Touch controls P1.").font(.system(size: 12)).foregroundStyle(WebStyle.soft)
                    }
                    Text(
                        "Drag the left stick to drive and aim. Touch near your tank to rotate exactly toward that point without moving. Tap Fire to shoot, or hold it to fire continuously. Drag Fire to aim while firing, even while driving with the joystick. Pickups equip automatically."
                    ).font(.system(size: 13)).lineSpacing(5)
                    HardwareControlsPanel(
                        session: session, keyboardConnected: keyboardConnected, mouseConnected: mouseConnected
                    ) { layout, action in
                        bindingError = ""
                        capture = BindingCapture(layout: layout, action: action)
                    }
                    Button("QUICK TOUR") { session.showQuickTour = true }.buttonStyle(WebButtonStyle())
                        .accessibilityIdentifier("quickTour")
                    Button("SHOWCASE") { session.presentShowcase() }.buttonStyle(WebButtonStyle())
                        .accessibilityIdentifier("openShowcase")
                    Text(
                        keyboardConnected
                            ? "Exit Showcase with Escape, or switch away from the app and return."
                            : "Switch away from the app and return to exit Showcase."
                    )
                    .font(.system(size: 11)).foregroundStyle(WebStyle.soft)
                    Button(session.hasAttachedLocalP2 ? "P1 ACCOUNT KEY" : "ACCOUNT KEY") {
                        session.openAccount()
                    }
                    .buttonStyle(WebButtonStyle()).accessibilityIdentifier("settingsAccount")
                    if session.hasAttachedLocalP2 {
                        Button("P2 ACCOUNT KEY") { session.openAccount(seat: 1) }
                            .buttonStyle(WebButtonStyle()).accessibilityIdentifier("settingsLocalAccount")
                    }
                    Divider().overlay(WebStyle.border)
                    NativePreferencesPanel(session: session)
                    Button("BACK") { session.showControls = false }.buttonStyle(
                        WebButtonStyle(kind: .primary))
                    Text(session.settingsVersionText).font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                        .accessibilityIdentifier("settingsVersion")
                }
            }
            .opacity(session.showAccount ? 0 : 1)
            .allowsHitTesting(!controlsCovered)
            .accessibilityHidden(controlsCovered)
            if let capture {
                WebModal(title: "Press a key", close: { closeCapture() }) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Layout \(capture.layout + 1), \(capture.action.label)").font(
                            .system(size: 14, weight: .bold))
                        Text("Press a keyboard key. Escape cancels.").font(.system(size: 13))
                        if !bindingError.isEmpty {
                            Text(bindingError).font(.system(size: 12)).foregroundStyle(WebStyle.danger)
                                .accessibilityIdentifier("bindingError")
                        }
                        NativeKeyCaptureView(
                            onKey: { code in
                                do {
                                    try NativeInputSettings.shared.assign(
                                        keyCode: code, layout: capture.layout, action: capture.action)
                                    self.capture = nil
                                } catch { bindingError = error.localizedDescription }
                            }, onCancel: { closeCapture() }, onError: { bindingError = $0 }
                        )
                        .frame(height: 1).accessibilityIdentifier("keyCapture")
                        Button("CANCEL") { closeCapture() }.buttonStyle(WebButtonStyle())
                    }
                }
            }
            if session.showQuickTour {
                QuickTourPanel(
                    highFrameRate: session.highFrameRate, gamepads: session.gamepads,
                    playSound: { session.applyAudioSetting(preview: $0) },
                    close: { session.showQuickTour = false })
            }
        }
        .onChange(of: keyboardConnected) { connected in
            if !connected { closeCapture() }
        }
    }
    private func closeCapture() {
        capture = nil
    }
}

private struct QuickTourPanel: View {
    let highFrameRate: Bool
    let gamepads: NativeGamepads
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var practice: QuickTourPractice
    @State private var page = 0
    private static let lessons: [(title: String, instruction: String)] = [
        ("Drive and aim", "Drag the left stick to drive. Touch near your tank to aim without moving."),
        (
            "Fire",
            "Tap Fire to shoot, or hold it to fire continuously. Drag Fire to aim while firing, even while driving with the joystick."
        ),
        ("Score a point", "Destroy the stationary tank to score a point."),
    ]

    init(
        highFrameRate: Bool, gamepads: NativeGamepads, playSound: @escaping (AudioCue) -> Void,
        close: @escaping () -> Void
    ) {
        self.highFrameRate = highFrameRate
        self.gamepads = gamepads
        self.close = close
        _practice = StateObject(wrappedValue: QuickTourPractice(playSound: playSound))
    }

    private var canAdvance: Bool {
        page == 0 ? practice.moved : page == 1 ? practice.fired : practice.score > 0
    }

    var body: some View {
        WebModal(title: "Quick tour", close: close, scrolls: false) {
            GeometryReader { geometry in
                if geometry.size.width >= 440 && geometry.size.height < 330 {
                    HStack(spacing: 16) {
                        stage.frame(width: geometry.size.width * 0.57, height: geometry.size.height)
                        VStack(alignment: .leading, spacing: 10) {
                            ScrollView { instructions }
                            navigation
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        instructions
                        stage.frame(minHeight: 170, maxHeight: 320)
                        navigation
                    }
                }
            }
        }
        .onAppear { if scenePhase == .active { gamepads.setPractice(practice.scene) } }
        .onChange(of: scenePhase) { phase in
            if phase != .active { practice.scene.resetControls() }
            gamepads.setPractice(phase == .active ? practice.scene : nil)
            practice.scene.resetFrameClock()
        }
        .onDisappear {
            gamepads.setPractice(nil)
            practice.scene.resetControls()
        }
    }

    private var instructions: some View {
        // Reserve the tallest lesson at the current width.
        ZStack(alignment: .topLeading) {
            ForEach(Self.lessons.indices, id: \.self) { index in
                if index == page {
                    lesson(index, accessible: true)
                } else {
                    lesson(index, accessible: false).hidden().accessibilityHidden(true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lesson(_ index: Int, accessible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.lessons[index].title).font(.system(size: 20, weight: .bold))
            Text(Self.lessons[index].instruction).font(.system(size: 14)).fixedSize(
                horizontal: false, vertical: true
            )
            .accessibilityIdentifier(accessible ? "tourInstructions" : "")
        }
    }

    private var stage: some View {
        VStack(spacing: 0) {
            // Leave room for the score without resizing the practice renderer.
            Color.clear.frame(height: 30).overlay {
                if page == 2 {
                    Text("score: \(practice.score)").font(WebStyle.mono()).foregroundStyle(WebStyle.paint(0))
                        .accessibilityIdentifier("tourScore")
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(WebStyle.surface)
                }
            }
            SpriteView(
                scene: practice.scene, isPaused: scenePhase != .active,
                preferredFramesPerSecond: min(highFrameRate ? 120 : 60, UIScreen.main.maximumFramesPerSecond),
                options: [.ignoresSiblingOrder, .shouldCullNonVisibleNodes]
            )
            .accessibilityElement(children: .ignore).accessibilityLabel("Practice arena")
            .accessibilityIdentifier("tourPracticeArena")
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(WebStyle.edge, lineWidth: 1).allowsHitTesting(false))
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(page + 1) / 3").font(WebStyle.mono()).foregroundStyle(WebStyle.soft)
            Button(page == 2 ? "DONE" : "NEXT") {
                if page == 2 {
                    close()
                } else {
                    if page == 0 { practice.enableFiring() } else { practice.startScoring() }
                    gamepads.rearmPractice()
                    page += 1
                }
            }.buttonStyle(WebButtonStyle(kind: .primary)).disabled(!canAdvance)
                .opacity(canAdvance ? 1 : 0.45)
                .accessibilityIdentifier("tourNext")
        }
    }

}

@MainActor private final class QuickTourPractice: ObservableObject {
    @Published private(set) var moved = false
    @Published private(set) var fired = false
    @Published private(set) var score = 0
    let scene = GameScene(size: CGSize(width: 320, height: 240))
    private let start = CGPoint(x: 126, y: 84)
    private var arena: PracticeArena
    private let world: ArenaWorld
    private let playSound: (AudioCue) -> Void
    // Demo events never enter the match's audio history.
    private var audioRouter = AudioEventRouter()
    private var elapsed = 0.0
    private var lastFireProgress: Double?

    init(playSound: @escaping (AudioCue) -> Void) {
        self.playSound = playSound
        world = ArenaWorld(
            width: 336, height: 168, cols: 4, rows: 2,
            walls: [
                MazeWall(x: 0, y: 0, w: 336, h: 8, axis: "h"),
                MazeWall(x: 0, y: 160, w: 336, h: 8, axis: "h"),
                MazeWall(x: 0, y: 8, w: 8, h: 152), MazeWall(x: 328, y: 8, w: 8, h: 152),
                MazeWall(x: 80, y: 8, w: 8, h: 38), MazeWall(x: 248, y: 122, w: 8, h: 38),
            ])
        arena = Self.makeArena(world: world, start: start)
        scene.scaleMode = .resizeFill
        scene.showsTankIdentities = false
        scene.showsFireControl = false
        scene.configureLayout(infinity: false, landscape: false, loadoutHeight: 0)
        scene.onFrame = { [weak self] dt in self?.advance(dt) }
        scene.onFireChanged = { [weak self] down in
            guard let self, self.scene.showsFireControl else { return }
            self.arena.captureFire(down, player: self.arena.localID)
        }
        scene.onControlsReset = { [weak self] in
            guard let self else { return }
            self.arena.resetFireInput(player: self.arena.localID)
        }
        display(arena.snapshot, now: ProcessInfo.processInfo.systemUptime)
    }

    private static func makeArena(world: ArenaWorld, start: CGPoint, scoring: Bool = false) -> PracticeArena {
        var tanks = [ArenaTank(id: 1, x: start.x, y: start.y, colorIndex: 0)]
        if scoring { tanks.append(ArenaTank(id: 2, x: 266, y: start.y, angle: .pi, colorIndex: 1)) }
        let arena = PracticeArena(
            name: "", colorIndex: 0, botCount: 0, world: world, initialTanks: tanks,
            respawnsEnabled: false, stationaryTankID: scoring ? 2 : nil)
        var rules = RoomRules()
        rules.pickupRate = "off"
        arena.configure(rules: rules)
        return arena
    }

    func enableFiring() {
        scene.resetControls()
        scene.showsFireControl = true
    }

    func startScoring() {
        scene.resetWorld()
        arena = Self.makeArena(world: world, start: start, scoring: true)
        audioRouter = AudioEventRouter()
        elapsed = 0
        lastFireProgress = nil
        display(arena.snapshot, now: ProcessInfo.processInfo.systemUptime)
    }

    private func advance(_ dt: Double) {
        var input = scene.input
        input.fire = scene.showsFireControl && input.fire
        let step = 1.0 / 60
        elapsed += min(dt, 0.08)
        while elapsed + 1e-9 >= step {
            arena.step(input: input, dt: step)
            elapsed = max(0, elapsed - step)
            if let tank = arena.snapshot.tanks.first {
                if !moved && hypot(tank.x - start.x, tank.y - start.y) >= 12 { moved = true }
                if score != tank.score { score = tank.score }
            }
            if scene.showsFireControl, !fired,
                arena.snapshot.bullets.contains(where: { $0.owner == arena.localID })
            {
                fired = true
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        display(arena.presentationSnapshot(fraction: elapsed / step, localInput: input, now: now), now: now)
    }

    private func display(_ snapshot: ArenaSnapshot, now: Double) {
        var snapshot = snapshot
        snapshot.world = world
        scene.display(snapshot: snapshot, localID: arena.localID, maze: arena.maze, fixedWalls: world.walls)
        let sounds = audioRouter.consume(
            snapshot: snapshot, localID: arena.localID, infinity: false, online: false,
            now: now)
        for sound in sounds where [.regular, .ricochet, .impact, .explosion].contains(sound.cue) {
            playSound(sound.cue)
        }
        if scene.showsFireControl, let tank = snapshot.tanks.first {
            let readout = PilotReadout(tank: tank, snapshot: snapshot, infinity: false, online: false)
            if lastFireProgress != readout.progress {
                lastFireProgress = readout.progress
                scene.configureReadiness(
                    label: readout.fireLabel, progress: readout.progress, locked: readout.locked)
            }
        }
    }
}

struct HardwareControlsPanel: View {
    @ObservedObject var session: GameSession
    @ObservedObject private var settings = NativeInputSettings.shared
    @State private var bindsOpen = false
    let keyboardConnected: Bool
    let mouseConnected: Bool
    var capture: (Int, NativeControlAction) -> Void
    var body: some View {
        if keyboardConnected || mouseConnected {
            WebDisclosure(isExpanded: $bindsOpen, title: "Binds") {
                VStack(alignment: .leading, spacing: 12) {
                    let devices =
                        keyboardConnected ? (mouseConnected ? "KEYBOARD/MOUSE" : "KEYBOARD") : "MOUSE"
                    Text(devices + ", " + (session.hasLocalP2 ? session.secondaryIdentity : session.identity))
                        .font(WebStyle.mono(11, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(
                            WebStyle.paint(session.hasLocalP2 ? session.secondaryPaint : session.colorIndex))
                    if !session.hasLocalP2 {
                        Text("Add local P2 in Players and bots to assign them these controls.")
                            .font(.system(size: 12)).foregroundStyle(WebStyle.soft)
                    }
                    if keyboardConnected {
                        Text("Keyboard defaults: WASD/arrow keys to drive, Q/C/Space/Enter to fire.")
                            .font(.system(size: 12)).foregroundStyle(WebStyle.soft)
                        ForEach(0..<2, id: \.self) { index in
                            Text("KEYBOARD LAYOUT \(index + 1)").font(WebStyle.mono()).foregroundStyle(
                                WebStyle.soft)
                            ForEach(NativeControlAction.allCases, id: \.self) { action in
                                HStack(spacing: 12) {
                                    Text(action.label).font(.system(size: 13)).fixedSize(
                                        horizontal: false, vertical: true
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Button(
                                        NativeControlBindings.keyLabel(
                                            settings.bindings.layouts[index][action])
                                    ) { capture(index, action) }
                                    .buttonStyle(WebButtonStyle(compact: true)).frame(width: 115)
                                    .accessibilityIdentifier("bind\(index)_\(action.rawValue)")
                                }
                            }
                        }
                        Button("RESET DEFAULT KEYS") { settings.resetBindings() }.buttonStyle(
                            WebButtonStyle()
                        )
                        .accessibilityIdentifier("resetBindings")
                    }
                    if mouseConnected {
                        NativeSettingToggle(
                            "Mouse aim", isOn: $settings.mouseAim, identifier: "settingMouseAim")
                        NativeSettingToggle(
                            "Mouse fire", isOn: $settings.mouseFire, identifier: "settingMouseFire")
                    }
                }
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
                    Text("\(report.rounds) rounds, \(Int(report.duration)) seconds").font(WebStyle.mono())
                        .foregroundStyle(WebStyle.muted)
                    ForEach(report.players) { player in
                        let seat = player.localSeat(controllerMember: session.roomMemberID)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(
                                    CallsignPolicy.displayName(player.name, bot: player.kind == "bot")
                                        + (seat.map { " (P\($0))" } ?? "")
                                ).fontWeight(seat != nil ? .bold : .regular)
                                Text(player.kind == "bot" ? "BOT" : "HUMAN PILOT").font(WebStyle.mono())
                                    .foregroundStyle(WebStyle.muted)
                                Spacer()
                                Text("\(player.score)").bold()
                            }.foregroundStyle(WebStyle.mapped(player.color))
                            Text(
                                "\(player.eliminations) eliminations, \(player.deaths) deaths, \(player.selfDestructs) self-destructs"
                            ).foregroundStyle(WebStyle.soft)
                            if report.mode == "ctf" {
                                Text("\(player.captures) captures, \(player.flagReturns) returns")
                                    .foregroundStyle(WebStyle.muted)
                            }
                            if report.mode == "koth" {
                                Text("\(Int(player.hillSeconds))s on hill").foregroundStyle(WebStyle.muted)
                            }
                        }.font(.system(size: 11)).padding(.vertical, 5)
                    }
                    WebStyle.border.frame(height: 1)
                }
                Text("LEADERBOARD").font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
                ForEach(session.standings) { entry in
                    let seat = session.localPilotSeat(entry.id)
                    HStack(alignment: .top) {
                        Text(
                            CallsignPolicy.displayName(entry.name, bot: entry.bot)
                                + (seat.map { " (P\($0))" } ?? "")
                        )
                        .fontWeight(seat != nil ? .bold : .regular).fixedSize(
                            horizontal: false, vertical: true)
                        if entry.bot || !session.isInfinity {
                            Text(entry.bot ? "BOT" : "HUMAN PILOT").font(WebStyle.mono()).foregroundStyle(
                                WebStyle.muted)
                        }
                        Spacer()
                        Text("\(entry.score)").font(WebStyle.mono(22))
                    }.font(.system(size: 12)).foregroundStyle(WebStyle.paint(entry.colorIndex))
                }
                WebStyle.border.frame(height: 1)
                FieldManualContent(session: session, includeSidebarControls: true)
                Button("CONTROLS") {
                    session.showSidebar = false
                    session.showControls = true
                }.buttonStyle(WebButtonStyle())
            }
        }
    }
}

struct FieldManualContent: View {
    @ObservedObject var session: GameSession
    var includeSidebarControls = false
    private var infinity: Bool {
        session.isInfinity || session.effectiveRules.infinity
            || session.readyRoom && (session.room?.infinityPublic ?? session.publicInfinitySelected)
    }
    private var powerHelp: PowerupHelp {
        PowerupHelp(
            rules: session.effectiveRules, world: session.readyRoom ? nil : session.snapshot.world,
            infinity: infinity)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FIELD MANUAL").font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
            Text("Touch").font(.system(size: 13, weight: .semibold))
            Text(
                "Drag the joystick to drive and aim. Touch near the tank to aim in place. Tap Fire to shoot, or hold it to fire continuously. Drag Fire to aim while firing, even while driving with the joystick."
            ).font(.system(size: 12)).foregroundStyle(WebStyle.soft)
            if includeSidebarControls {
                Text("Connect a game controller to play.")
                    .font(.system(size: 12)).foregroundStyle(WebStyle.soft).accessibilityIdentifier(
                        "manualGamepadHint")
            }
            Text(infinity ? "INFINITY" : session.selectedMode.title.uppercased()).font(WebStyle.mono())
                .foregroundStyle(WebStyle.accent)
            Text(
                infinity
                    ? "Gain a point for each kill and lose a point each time the tank is destroyed. Respawn after one second. Keep growing the score without a time limit."
                    : session.selectedMode.help
            )
            .font(.system(size: 12)).foregroundStyle(WebStyle.soft)
            Button("CONTROLS") {
                session.showSidebar = false
                session.showControls = true
            }.buttonStyle(WebButtonStyle())
            Text("POWER-UPS").font(WebStyle.mono()).foregroundStyle(WebStyle.accent)
            Text(powerHelp.summary).font(.system(size: 12)).foregroundStyle(WebStyle.soft).fixedSize(
                horizontal: false, vertical: true
            ).accessibilityIdentifier("manualPowerupSummary")
            ForEach(powerEntries, id: \.0) { kind, name in
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 12, weight: .bold)).foregroundStyle(WebStyle.text)
                    Text(powerHelp.description(for: kind, includeGrenadeControls: includeSidebarControls))
                        .font(.system(size: 12)).foregroundStyle(WebStyle.soft)
                }
            }
        }
    }
}

struct JoinRoomPanel: View {
    @ObservedObject var session: GameSession
    @State private var code = ""
    @State private var spectating = false
    @FocusState private var codeFocused: Bool
    var body: some View {
        WebModal(title: "Find a room.", close: { session.showJoin = false }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("CALLSIGN").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                HStack(spacing: 8) {
                    TextField("Callsign", text: $session.callsign).modifier(WebField())
                        .disabled(session.releasingCallsign)
                        .task { session.scheduleCallsignAvailability() }
                    AccountKeyButton(
                        session: session, seat: 0, identity: session.identity, identifier: "joinAccount")
                }
                CallsignFeedback(session: session)
                Text("ROOM NAME OR CODE").font(WebStyle.mono()).foregroundStyle(WebStyle.muted)
                TextField("Friday tanks 💥", text: $code).modifier(WebField()).autocorrectionDisabled()
                    .focused($codeFocused)
                    .submitLabel(.done).onSubmit { codeFocused = false }.accessibilityIdentifier(
                        "joinRoomCode")
                Toggle("Spectate", isOn: $spectating).font(.system(size: 12, weight: .bold))
                    .accessibilityIdentifier("joinSpectatingToggle")
                Button(spectating ? "WATCH →" : "JOIN →") {
                    session.showJoin = false
                    session.connect(code: code, spectating: spectating)
                }.buttonStyle(WebButtonStyle(kind: .primary)).disabled(
                    session.releasingCallsign || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ).accessibilityIdentifier("joinRoomButton")
                Text(
                    spectating
                        ? "Join as a spectator without a tank."
                        : "Missing rooms are created with the joining pilot as host."
                ).font(.system(size: 11)).foregroundStyle(WebStyle.soft)
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
                Text("Save this room's rules and bots for another battle.").font(.system(size: 12))
                    .foregroundStyle(WebStyle.soft)
                TextField("Preset name", text: $name).modifier(WebField())
                Button("SAVE ROOM") {
                    session.savePreset(name: name)
                    name = ""
                }.buttonStyle(WebButtonStyle(kind: .primary)).disabled(
                    !session.isHost || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(session.savedPresets) { preset in
                    HStack {
                        Text(preset.id).font(.system(size: 13))
                        Spacer()
                        Button("LOAD") {
                            session.loadPreset(preset)
                            session.showPresets = false
                        }.buttonStyle(WebButtonStyle(compact: true)).frame(width: 70).disabled(
                            !session.canLoadPreset)
                    }
                }
            }
        }
    }
}

struct QueuePanel: View {
    @ObservedObject var session: GameSession
    var body: some View {
        WebModal(title: "Find a match", close: { session.showQueues = false }) {
            VStack(alignment: .leading, spacing: 14) {
                if let queue = session.queueState {
                    Text(queue.name).font(.system(size: 18, weight: .bold)).foregroundStyle(WebStyle.accent)
                    Text("\(queue.players) / \(queue.required) players, \(queue.stage)").font(
                        .system(size: 12)
                    ).foregroundStyle(WebStyle.soft)
                    ForEach(queue.members) { member in
                        HStack {
                            Text(CallsignPolicy.displayName(member.name, bot: member.kind == "bot"))
                            Spacer()
                            Text(member.accepted ? "READY" : "WAITING")
                        }.font(.system(size: 12))
                    }
                    if session.canConfirmQueue {
                        Button("READY") { session.send(.queueAccept(queue.id)) }.buttonStyle(
                            WebButtonStyle(kind: .play))
                    }
                    if session.canCancelQueue {
                        Button("CANCEL SEARCH") { session.send(.queueCancel(queue.id)) }.buttonStyle(
                            WebButtonStyle())
                    }
                } else {
                    ForEach(session.queueListings) { listing in
                        Button {
                            session.send(.queueJoin(listing.definition.key))
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(listing.definition.name).font(.system(size: 17, weight: .bold))
                                Text(
                                    "\(listing.waitingPlayers) waiting, \(listing.definition.cols) × \(listing.definition.rows) maze"
                                ).font(WebStyle.mono())
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(
                                WebStyle.sunken, in: RoundedRectangle(cornerRadius: 7))
                        }.foregroundStyle(WebStyle.text).disabled(!session.canQueue)
                    }
                    if session.queueListings.isEmpty {
                        ProgressView().tint(WebStyle.accent).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
