"""Run with Playwright and Chromium installed: python3 src/tests/intro_tour_browser.py."""

from pathlib import Path

from playwright.sync_api import expect, sync_playwright


def check_buttons(page, next_label):
    expect(page.locator("#introTourNext")).to_have_text(next_label)
    layout = page.locator(".intro-tour-actions > button").evaluate_all("""buttons =>
        buttons.map(button => {
            const {top, height} = button.getBoundingClientRect();
            return {top, height, shadow: getComputedStyle(button).boxShadow};
        })
    """)
    assert len(layout) == 3 and layout[0]["height"] >= 44, layout
    assert all(button == layout[0] for button in layout), layout


def check_control_rows(section, labels):
    rows = section.locator("dt")
    expect(rows).to_have_text(labels)
    tops = rows.evaluate_all("rows => rows.map(row => row.getBoundingClientRect().top)")
    assert all(first < second for first, second in zip(tops, tops[1:])), tops


def check_sidebar(page, touch):
    sidebar = page.locator("#gameSidebar")
    toggle = page.get_by_role("button", name="Open sidebar")
    dialog = page.get_by_role("dialog", name="Sidebar")
    expect(sidebar).to_be_hidden()
    expect(toggle).to_have_attribute("aria-expanded", "false")
    expect(toggle).to_be_in_viewport(ratio=1)
    if touch:
        toggle.tap()
    else:
        toggle.press("Space")
    expect(dialog).to_be_visible()
    expect(dialog.locator("#gameSidebar")).to_be_visible()
    expect(toggle).to_have_attribute("aria-expanded", "true")
    expect(dialog.locator(".power-row")).to_have_count(10)
    if touch:
        touch_instructions = dialog.get_by_text("Drag the joystick to drive and aim. Tap or hold Fire to shoot.")
        expect(touch_instructions).to_be_visible()
    last_pickup = dialog.locator(".power-row").last
    last_pickup.scroll_into_view_if_needed()
    expect(last_pickup).to_be_in_viewport(ratio=1)
    assert dialog.evaluate("dialog => dialog.scrollWidth === dialog.clientWidth")
    if touch:
        dialog.get_by_role("button", name="Close sidebar").tap()
    else:
        page.keyboard.press("Escape")
        expect(toggle).to_be_focused()
    expect(dialog).to_be_hidden()
    expect(sidebar).to_be_hidden()
    expect(toggle).to_have_attribute("aria-expanded", "false")


index = (Path(__file__).resolve().parents[1] / "web" / "index.html").as_uri()
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(chromium_sandbox=True)
    for width, height, touch in [(1280, 900, False), (620, 900, False),
                                 (320, 568, True), (844, 390, True)]:
        context = browser.new_context(viewport={"width": width, "height": height},
                                      is_mobile=touch, has_touch=touch)
        page = context.new_page()
        page.goto(index + "?test=1")
        mouse_help = page.locator("#introTourDesktop")
        touch_help = page.locator("#introTourTouch")
        keyboard_help = page.locator("#introTourKeyboard")
        expect(page.locator("#introTourDialog")).to_be_visible()
        assert page.locator('[data-intro-page="0"] > section').evaluate_all("nodes => nodes.map(node => node.id)") == ["introTourTouch", "introTourKeyboard", "introTourDesktop"]
        expect(keyboard_help.get_by_role("heading", name="Keyboard")).to_be_visible()
        check_control_rows(keyboard_help, ["Movement", "Fire"])
        expect(page.locator("#introTourMoveKeys")).to_have_text("W A S D (or ↑ ← ↓ →)")
        expect(page.locator("#introTourFireKeys")).to_have_text("Q/C/SPACE/ENTER")
        if touch:
            expect(mouse_help).to_be_hidden()
            expect(touch_help.get_by_role("heading", name="Touch")).to_be_visible()
            check_control_rows(touch_help, ["Movement", "Aim", "Fire"])
            expect(touch_help).to_contain_text("the same joystick")
        else:
            expect(mouse_help).to_be_visible()
            expect(mouse_help).to_contain_text("Left-click to fire")
        expect(page.locator("#introTourBack")).to_be_disabled()
        check_buttons(page, "Next")
        page.locator("#introTourNext").click()
        maze_step = page.locator('[data-intro-page="1"]')
        expect(maze_step.locator("li > strong")).to_have_text(["Laser", "Grenade", "Starman"])
        sidebar_note = maze_step.get_by_text(
            "There are more power-ups. Check the sidebar for the full list and details."
        )
        expect(sidebar_note).to_be_visible()
        if touch:
            page.locator("#introTourDialog").evaluate("dialog => dialog.scrollTop = dialog.scrollHeight")
            expect(sidebar_note).to_be_in_viewport(ratio=1)
        check_buttons(page, "Next")
        page.locator("#introTourNext").click()
        check_buttons(page, "Done")
        expect(page.locator('[data-intro-page="2"] li > strong')).to_have_text(
            ["Infinity", "Elimination", "Capture the Flag", "King of the Hill", "Survival"]
        )
        page.locator("#introTourNext").click()
        expect(page.locator("#introTourDialog")).to_be_hidden()
        github = page.locator(".github-link")
        expect(github).to_be_visible()
        expect(github).to_have_attribute("href", "https://github.com/nhooyr/leqra")
        assert page.evaluate("document.documentElement.scrollWidth === innerWidth")
        if width <= 920:
            if not touch:
                page.locator("#startRoomBtn").click()
                page.wait_for_function("leqra.getState().phase === 'playing'")
            if width == 320:
                page.evaluate("""() => {
                    __test.setLocalRules({...__test.currentRules(), teamMode:'ffa'});
                    for (let count = __test.localRoom.players.length; count < 8; count++) {
                        __test.addRoomSeat('bot');
                    }
                }""")
                dots = page.locator("#miniScores .mini-score i")
                expect(dots).to_have_count(8)
                assert all(width >= 4 for width in dots.evaluate_all(
                    "dots => dots.map(dot => dot.getBoundingClientRect().width)"
                ))
            check_sidebar(page, touch)
        if width == 1280:
            expect(page.locator("#sidebarDetailsBtn")).to_be_hidden()
            expect(page.locator("#gameSidebar")).to_be_visible()
            page.locator("#roomSettings > summary").click()
            room_name = page.locator("#localRoomName")
            room_name.fill("")
            room_name.focus()
            unicode_room = "🎮" * 128
            page.keyboard.insert_text(unicode_room)
            expect(room_name).to_have_value(unicode_room)
            page.locator("#roomControlsBtn").click()
            page.locator('[data-bind="0:fire"]').click()
            page.keyboard.press("z")
            page.locator('[data-bind="0:forward"]').click()
            page.keyboard.press("i")
            expect(page.locator("#openIntroTour")).to_have_text("QUICK TOUR")
            page.locator("#p1MouseAimEnabled").uncheck()
            page.locator("#p1MouseFireEnabled").uncheck()
            page.locator("#openIntroTour").click()
            expect(page.locator("#introTourMoveKeys")).to_have_text("I A S D (or ↑ ← ↓ →)")
            expect(page.locator("#introTourFireKeys")).to_have_text("Z/C/SPACE/ENTER")
            expect(page.locator("#introTourDesktop")).to_be_hidden()
            page.locator("#introTourSkip").click()
            page.locator("#p1MouseAimEnabled").check()
            page.locator("#p1MouseFireEnabled").check()
            page.locator("#openIntroTour").click()
            expect(page.locator("#introTourDesktop")).to_be_visible()
            page.locator("#introTourSkip").click()
            page.locator('[data-close-dialog="controlsDialog"]').click()
            page.locator("#startRoomBtn").click()
            page.wait_for_function("leqra.getState().phase === 'playing'")
            github.evaluate("""link => link.addEventListener('click', event => {
                event.preventDefault();
                link.dataset.activated = 'true';
            })""")
            github.press("Enter")
            expect(github).to_have_attribute("data-activated", "true")
            for key in ("Space", "Enter"):
                page.locator("#pauseBtn").press(key)
                expect(page.locator("#onlineMenuScreen")).to_be_visible()
                page.locator("#onlineReturnBtn").press(key)
                expect(page.locator("#onlineMenuScreen")).to_be_hidden()
        context.close()
    browser.close()
