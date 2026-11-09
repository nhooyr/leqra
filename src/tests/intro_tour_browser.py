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


index = (Path(__file__).resolve().parents[2] / "index.html").as_uri()
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(chromium_sandbox=True)
    for width, height, touch in [(1280, 900, False), (620, 900, False),
                                 (320, 568, True), (844, 390, True)]:
        context = browser.new_context(viewport={"width": width, "height": height},
                                      is_mobile=touch, has_touch=touch)
        page = context.new_page()
        page.goto(index)
        mouse_help = page.locator("#introTourDesktop")
        touch_help = page.locator("#introTourTouch")
        keyboard_help = page.locator("#introTourKeyboard")
        expect(page.locator("#introTourDialog")).to_be_visible()
        expect(keyboard_help.get_by_role("heading", name="Keyboard")).to_be_visible()
        check_control_rows(keyboard_help, ["Movement", "Fire"])
        expect(page.locator("#introTourMoveKeys")).to_have_text("W A S D (or ↑ ← ↓ →)")
        expect(page.locator("#introTourFireKeys")).to_have_text("Q / C / SPACE / ENTER")
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
        check_buttons(page, "Next")
        page.locator("#introTourNext").click()
        check_buttons(page, "Done")
        page.locator("#introTourNext").click()
        expect(page.locator("#introTourDialog")).to_be_hidden()
        github = page.get_by_role("link", name="View leqra on GitHub")
        expect(github).to_be_visible()
        expect(github).to_have_attribute("href", "https://github.com/nhooyr/leqra")
        assert page.evaluate("document.documentElement.scrollWidth === innerWidth")
        if width == 1280:
            page.locator("#roomSettings > summary").click()
            page.locator("#roomControlsBtn").click()
            page.locator('[data-bind="0:fire"]').click()
            page.keyboard.press("z")
            page.locator('[data-bind="0:forward"]').click()
            page.keyboard.press("i")
            page.locator("#openIntroTour").click()
            expect(page.locator("#introTourMoveKeys")).to_have_text("I A S D (or ↑ ← ↓ →)")
            expect(page.locator("#introTourFireKeys")).to_have_text("Z / C / SPACE / ENTER")
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
        context.close()
    browser.close()
