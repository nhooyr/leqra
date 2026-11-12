import SwiftUI
import SpriteKit
import leqraCore

struct NativeGameView: UIViewRepresentable {
    let scene: GameScene
    let highFrameRate: Bool
    let paused: Bool
    var infinity: Bool = true
    var landscape: Bool = false
    var loadoutHeight: CGFloat = 97

    func makeUIView(context: Context) -> UIView {
        let container = KeyboardGameContainer(scene: scene)
        scene.configureLayout(infinity: infinity, landscape: landscape, loadoutHeight: loadoutHeight)
        container.configure(scene: scene, highFrameRate: highFrameRate, paused: paused)
        return container
    }

    func updateUIView(_ view: UIView, context: Context) {
        scene.configureLayout(infinity: infinity, landscape: landscape, loadoutHeight: loadoutHeight)
        (view as? KeyboardGameContainer)?.configure(scene: scene, highFrameRate: highFrameRate, paused: paused)
    }
}

/// SKView does not support subclassing. Its ordinary UIView parent owns the
/// hardware-keyboard responder while SpriteKit owns rendering and touch input.
private final class KeyboardGameContainer: UIView {
    private let gameView = SKView()
    private var pressedKeys = Set<UIKeyboardHIDUsage>()
    private var highFrameRate = true
    private var paused = false
    private var gameScene: GameScene? { gameView.scene as? GameScene }

    init(scene: GameScene) {
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = "arenaStage"
        accessibilityLabel = "Tank arena"
        gameView.frame = bounds
        gameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gameView.isMultipleTouchEnabled = true
        gameView.isAccessibilityElement = false
        gameView.ignoresSiblingOrder = true
        gameView.shouldCullNonVisibleNodes = true
        addSubview(gameView)
        gameView.presentScene(scene)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(scene: GameScene, highFrameRate: Bool, paused: Bool) {
        self.highFrameRate = highFrameRate
        self.paused = paused
        isAccessibilityElement = !paused
        isUserInteractionEnabled = !paused
        gameView.isUserInteractionEnabled = !paused
        if gameView.scene !== scene { gameView.presentScene(scene) }
        scene.isUserInteractionEnabled = !paused
        if paused { resetKeyboard(); scene.resetControls(); resignFirstResponder() }
        else if window != nil && !isFirstResponder { becomeFirstResponder() }
        applyFrameRate()
    }

    private func applyFrameRate() {
        let maximum = window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
        gameView.preferredFramesPerSecond = paused ? 30 : min(highFrameRate ? 120 : 60, maximum)
    }

    override var canBecomeFirstResponder: Bool { true }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Reapply against the attached display; makeUIView can run before a
        // window exists, including when moving between displays.
        applyFrameRate()
        if window != nil && !paused { becomeFirstResponder() }
        else { resetKeyboard(); gameScene?.resetControls() }
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !setKeys(presses, down: true) { super.pressesBegan(presses, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !setKeys(presses, down: false) { super.pressesEnded(presses, with: event) }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        resetKeyboard()
        gameScene?.resetControls()
        super.pressesCancelled(presses, with: event)
    }
    private func setKeys(_ presses: Set<UIPress>, down: Bool) -> Bool {
        guard let scene = gameScene else { return false }
        var handled = false
        for press in presses {
            guard let key = press.key?.keyCode,
                  [.keyboardW, .keyboardUpArrow, .keyboardS, .keyboardDownArrow,
                   .keyboardA, .keyboardLeftArrow, .keyboardD, .keyboardRightArrow,
                   .keyboardQ, .keyboardC, .keyboardSpacebar].contains(key) else { continue }
            handled = true
            if down && scene.isUserInteractionEnabled { pressedKeys.insert(key) }
            else { pressedKeys.remove(key) }
        }
        scene.input.forward = !pressedKeys.isDisjoint(with: [.keyboardW, .keyboardUpArrow])
        scene.input.reverse = !pressedKeys.isDisjoint(with: [.keyboardS, .keyboardDownArrow])
        scene.input.left = !pressedKeys.isDisjoint(with: [.keyboardA, .keyboardLeftArrow])
        scene.input.right = !pressedKeys.isDisjoint(with: [.keyboardD, .keyboardRightArrow])
        if handled { scene.input.fire = !pressedKeys.isDisjoint(with: [.keyboardQ, .keyboardC, .keyboardSpacebar]) }
        return handled
    }

    func resetKeyboard() { pressedKeys.removeAll() }
}
