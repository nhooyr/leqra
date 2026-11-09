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
        expect(page.locator("#introTourDialog")).to_be_visible()
        if touch:
            expect(mouse_help).to_be_hidden()
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
        context.close()
    browser.close()
