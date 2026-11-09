"""Check room setup, roster focus, chat IME and matchmaking in Chromium.

Start a dedicated leqra server with `go run ./src`, then run
`python3 src/tests/audit_browser.py [http://localhost:8080]`.
Install Playwright and its Chromium browser first.
"""

import argparse
import json
import os

from playwright.sync_api import expect, sync_playwright


def load_room(context, url, errors):
    page = context.new_page()
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.add_init_script("localStorage.setItem('leqra.introTour.v1', '1')")
    page.goto(url)
    page.wait_for_function("() => !!window.leqra")
    return page


def open_details(page, element_id):
    details = page.locator(f"#{element_id}")
    if details.get_attribute("open") is None:
        details.locator(":scope > summary").click()


def share_room(page):
    page.locator("#copyInviteBtn").click()
    page.wait_for_function("() => leqra.getState().phase === 'onlineLobby'")
    return page.evaluate("leqra.getState().online.code")


def check_promotion(browser, url, errors):
    with browser.new_context() as host_context, browser.new_context() as guest_context:
        host = load_room(host_context, url, errors)
        guest = load_room(guest_context, url, errors)
        for page, size in [(host, "large"), (guest, "compact")]:
            open_details(page, "roomSettings")
            page.locator("#roomMapSize").select_option(size)

        persisted = "localStorage.getItem('leqra.roomSetup.v2')"
        original = guest.evaluate(persisted)
        assert json.loads(original)["modes"]["elimination"]["mapSize"] == "compact"
        code = share_room(host)
        guest.locator("#joinOtherBtn").click()
        guest.locator("#joinCode").fill(code)
        guest.locator("#pilotName").fill("GUEST")
        guest.locator("#joinRoomBtn").click()
        guest.wait_for_function("() => leqra.getState().phase === 'onlineLobby'")
        expect(guest.locator("#roomMapSize")).to_have_value("large")
        assert guest.evaluate(persisted) == original

        host.close()
        guest.wait_for_function("""() => {
            const state = leqra.getState();
            return state.room.host === state.online.id;
        }""")
        expect(guest.locator("#roomMapSize")).to_have_value("large")
        assert guest.evaluate(persisted) == original
        guest.locator("#leaveRoomBtn").click()
        guest.wait_for_function("() => leqra.getState().mode === 'room'")
        expect(guest.locator("#roomMapSize")).to_have_value("compact")
    print("PASS host promotion keeps the guest's local setup", flush=True)


def check_team_focus(browser, url, errors):
    for online in (False, True):
        with browser.new_context() as context:
            page = load_room(context, url, errors)
            if online:
                share_room(page)
            for details in ("roomSettings", "roomPlayers"):
                open_details(page, details)
            page.locator("#addBotBtn").click()
            roster = page.locator("#roomRoster .seat-row")
            expect(roster).to_have_count(5)
            page.locator("#roomTeamMode").select_option("teams")

            team = page.locator('#roomRoster select[data-team="1"]')
            expect(team).to_have_value("1")
            team.focus()
            team.select_option("2")
            expect(team).to_have_value("2")
            expect(team).to_be_focused()
            assert roster.evaluate_all("rows => rows.map(row => row.dataset.seat)") == ["0", "2", "1", "3", "4"]
    print("PASS local and online team regrouping preserve keyboard focus", flush=True)


def check_chat_composition(browser, url, errors):
    with browser.new_context() as context:
        page = load_room(context, url, errors)
        share_room(page)
        page.locator("#chatBtn").click()
        chat = page.locator("#chatInput")
        expect(chat).to_be_focused()
        page.evaluate("""() => {
            window.testEscapeComposition = [];
            window.addEventListener('keydown', event => {
                if (event.code === 'Escape') testEscapeComposition.push(event.isComposing);
            }, true);
        }""")
        cdp = context.new_cdp_session(page)
        cdp.send("Input.imeSetComposition", {"text": "田中", "selectionStart": 2, "selectionEnd": 2})
        page.keyboard.press("Escape")
        assert page.evaluate("window.testEscapeComposition") == [True]
        expect(page.locator("#chatPanel")).to_be_visible()
        expect(chat).to_be_focused()

        cdp.send("Input.imeSetComposition", {"text": "", "selectionStart": 0, "selectionEnd": 0})
        page.keyboard.press("Escape")
        expect(page.locator("#chatPanel")).to_be_hidden()
    print("PASS composing Escape stays in chat and ordinary Escape closes it", flush=True)


def frame_type(payload, expected):
    try:
        return json.loads(payload).get("type") == expected
    except (ValueError, AttributeError):
        return False


def check_queue_notice(browser, url, errors):
    with browser.new_context() as context:
        page = load_room(context, url, errors)
        page.locator("#matchmakingBtn").click()
        with page.expect_websocket() as connection:
            page.locator("#queueStartBtn").click()
        socket = connection.value
        expect(page.locator("#queueActive")).to_be_visible()
        with socket.expect_event("framereceived", lambda payload: frame_type(payload, "room")):
            page.locator("#queueCancelBtn").click()

        notice = page.locator("#queueNotice")
        message = "Matchmaking cancelled. Your party is still together in this room."
        expect(notice).to_be_visible()
        expect(notice).to_have_text(message)
        expect(page.locator("#queueActive")).to_be_hidden()

        for _ in range(2):
            page.locator("#queueCloseBtn").click()
            with socket.expect_event("framereceived", lambda payload: frame_type(payload, "queue_catalog")):
                page.locator("#matchmakingBtn").click()
            expect(notice).to_have_text(message)
        page.locator('[data-queue="elimination-2"]').click()
        expect(notice).not_to_have_text(message)
    print("PASS queue cancellation stays visible through room and catalog updates", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default=os.environ.get("LEQRA_URL", "http://localhost:8080"))
    url = parser.parse_args().url.rstrip("/") + "/"
    errors = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(chromium_sandbox=True)
        try:
            check_promotion(browser, url, errors)
            check_team_focus(browser, url, errors)
            check_chat_composition(browser, url, errors)
            check_queue_notice(browser, url, errors)
        finally:
            browser.close()
    assert not errors, errors
