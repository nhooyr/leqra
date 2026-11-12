"""Check small-screen layouts against a running leqra server.

Run with Playwright Chromium installed and a dedicated server running.
python3 src/tests/mobile_layout_browser.py http://localhost:8080
"""

import argparse
from pathlib import Path
import re
import time

from playwright.sync_api import expect, sync_playwright


def mobile_context(browser, devices, width, height, **options):
    return browser.new_context(
        viewport={"width": width, "height": height}, has_touch=True, is_mobile=True,
        user_agent=devices["iPhone SE"]["user_agent"],
        **options,
    )


def open_page(context, url, errors):
    page = context.new_page()
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.add_init_script("localStorage.setItem('leqra.introTour.v1', '1')")
    page.goto(url)
    page.wait_for_function("() => !!window.leqra")
    return page


def check_landscape(browser, devices, errors, has_safe_area_override):
    index = Path(__file__).resolve().parents[1] / "web" / "index.html"
    with mobile_context(browser, devices, 568, 320) as context:
        page = open_page(context, index.as_uri(), errors)
        if has_safe_area_override:
            cdp = context.new_cdp_session(page)
            cdp.send("Emulation.setSafeAreaInsetsOverride", {
                "insets": {"top": 8, "right": 48, "bottom": 21, "left": 48}
            })
        page.locator("#roomSettings > summary").tap()
        page.locator('[data-room-mode="ctf"]').tap()
        page.locator("#roomRulesBtn").tap()
        rules = page.locator("#rulesDialog")
        expect(rules).to_be_visible()
        if has_safe_area_override:
            bounds = rules.bounding_box()
            assert bounds["x"] >= 48 and bounds["x"] + bounds["width"] <= 520, bounds
        rules.locator("[data-close-dialog]").tap()
        fixed_pause_size = page.locator("#pauseBtn").evaluate("""button => {
            const style = getComputedStyle(button);
            return {width: parseFloat(style.width), height: parseFloat(style.height)};
        }""")
        page.locator('[data-room-mode="infinity"]').tap()
        page.locator("#startRoomBtn").tap()
        expect(page.locator("#infiniteArena")).to_be_visible()
        expect(page.locator("#infiniteHeader > #gameHeader")).to_be_visible()
        page.locator("#infiniteScoreboardBtn").tap()
        layout = page.evaluate("""() => {
            const panel = document.querySelector('#infiniteLeaderboardPanel');
            const summary = document.querySelector('#infiniteScoreboardBtn');
            const list = panel.querySelector('#infiniteLeaderboard');
            list.replaceChildren(...Array.from({length: 10}, () => {
                const row = document.createElement('li');
                const name = document.createElement('span');
                const score = document.createElement('strong');
                name.textContent = 'LLLLLLLLLLLLLLLL';
                score.textContent = '-1000';
                row.append(name, score);
                return row;
            }));
            panel.scrollTop = panel.scrollHeight;
            const fire = document.querySelector('#infiniteFire');
            const hit = element => {
                const r = element.getBoundingClientRect();
                return element.contains(document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2));
            };
            const brand = document.querySelector('#gameHeader .brand').getBoundingClientRect();
            const actions = document.querySelector('#gameHeader .header-right').getBoundingClientRect();
            return {
                fireReachable: hit(fire), summaryReachable: hit(summary), scrollTop: panel.scrollTop,
                top: Math.min(brand.top, actions.top), left: brand.left, right: actions.right
            };
        }""")
        assert layout["fireReachable"] and layout["summaryReachable"] and layout["scrollTop"] > 0, layout
        if has_safe_area_override:
            assert layout["top"] >= 8 and layout["left"] >= 48 and layout["right"] <= 520, layout
        page.locator("#infiniteScoreboardBtn").tap()
        expect(page.locator("#infiniteLeaderboardPanel")).not_to_have_attribute("open", "")
        pause_button = page.locator("#pauseBtn")
        trigger = pause_button.bounding_box()
        assert trigger["width"] >= 30 and trigger["height"] >= 30, trigger
        assert abs(trigger["width"] - fixed_pause_size["width"]) <= 1, (trigger, fixed_pause_size)
        assert abs(trigger["height"] - fixed_pause_size["height"]) <= 1, (trigger, fixed_pause_size)
        pause_button.tap()
        pause = page.locator("#infinitePauseMenu")
        expect(pause).to_be_visible()
        expect(pause.get_by_text("The battle is paused. Tanks are safe.", exact=True)).to_be_visible()
        for name in ("BACK TO THE BATTLE", "Controls", "Exit Infinity"):
            button = pause.get_by_role("button", name=name, exact=True)
            expect(button).to_be_in_viewport(ratio=1)
            assert button.bounding_box()["height"] >= 44, name
        if has_safe_area_override:
            bounds = pause.locator(".screen-card").bounding_box()
            assert bounds["x"] >= 48 and bounds["x"] + bounds["width"] <= 520, bounds
            assert bounds["y"] >= 8 and bounds["y"] + bounds["height"] <= 299, bounds
        page.locator("#infiniteExit").tap()
        expect(page.locator("#infiniteArena")).to_be_hidden()
        expect(page.locator(".app > #gameHeader")).to_be_visible()
    print("PASS landscape rules, notch clearance, and Infinity leaderboard and pause layouts", flush=True)


def check_split_infinity(browser, devices, errors):
    index = Path(__file__).resolve().parents[1] / "web" / "index.html"
    with mobile_context(browser, devices, 280, 640) as context:
        page = open_page(context, index.as_uri(), errors)
        page.evaluate("leqraInfinity.start('offline', {localName: 'Wingmate'})")
        for width, height, split in ((280, 640, "stacked"), (568, 320, "side")):
            page.set_viewport_size({"width": width, "height": height})
            expect(page.locator("#infiniteArena")).to_have_attribute("data-split", split)
            check_infinity_score_labels(page)
            divider = page.evaluate("""split => {
                const canvas = document.getElementById('infiniteCanvas'), c = canvas.getContext('2d');
                const width = canvas.clientWidth, height = canvas.clientHeight;
                const vertical = split === 'side';
                const x = Math.ceil(width / 2), y = Math.ceil(height / 2);
                const pixel = (px, py) => Array.from(c.getImageData(
                    Math.floor(px * canvas.width / width), Math.floor(py * canvas.height / height), 1, 1
                ).data).slice(0, 3);
                const rgb = color => color.slice(1).match(/../g).map(pair => parseInt(pair, 16));
                const {accent, arena} = leqraInfinityArt.theme;
                return [pixel(x, y), pixel(x + (vertical ? 3 : 0), y + (vertical ? 0 : 3)), rgb(accent), rgb(arena)];
            }""", split)
            assert divider[:2] == divider[2:], divider
            boxes = page.evaluate("""() => {
                const scores = [...document.querySelectorAll('#infiniteKills .infinite-personal-score')];
                const originalChildren = scores.map(score => [...score.childNodes].map(node => node.cloneNode(true)));
                scores.forEach((score, i) => {
                    score.textContent = `P${i+1} -999 (#99)`;
                });
                const boxes = Object.fromEntries(['gameHeader','infiniteKills','infiniteCanvas','infiniteFire','infiniteStick','pauseBtn','infiniteLocalLoadout'].map(id => {
                    const {left,top,right,bottom} = document.getElementById(id).getBoundingClientRect();
                    return [id,[left,top,right,bottom]];
                }));
                scores.forEach((score, i) => score.replaceChildren(...originalChildren[i]));
                return boxes;
            }""")
            for left, top, right, bottom in boxes.values():
                assert 0 <= left < right <= width + 1 and 0 <= top < bottom <= height + 1, boxes
            left, top, right, bottom = boxes["pauseBtn"]
            assert right - left >= 30 and bottom - top >= 30, boxes
            left, top, right, bottom = boxes["infiniteCanvas"]
            for control in ("infiniteFire", "infiniteStick"):
                if split == "stacked":
                    assert boxes[control][3] <= (top + bottom) / 2 + 1, boxes
                else:
                    assert boxes[control][2] <= (left + right) / 2 + 1, boxes
    print("PASS Player 2 divider, long scores, and primary touch controls", flush=True)


def check_narrow_online(browser, devices, url, errors):
    with mobile_context(browser, devices, 280, 480) as context:
        page = open_page(context, url, errors)
        page.locator("#infinityToggleLabel").tap()
        page.locator("#copyInviteBtn").tap()
        page.wait_for_function("() => leqra.getState().online?.connected")
        page.locator("#startRoomBtn").tap()
        page.wait_for_function("() => leqra.getState().phase === 'playing'")
        links = page.evaluate("""() => {
            const bounds = selector => {
                const {left, top, right, bottom} = document.querySelector(selector).getBoundingClientRect();
                return {left, top, right, bottom};
            };
            return {github: bounds('.github-link'), room: bounds('#roomBtn'),
                header: bounds('#gameHeader'), viewportWidth: innerWidth};
        }""")
        github, room = links["github"], links["room"]
        assert (github["right"] <= room["left"] or room["right"] <= github["left"] or
                github["bottom"] <= room["top"] or room["bottom"] <= github["top"]), links
        for rect in (github, room, links["header"]):
            assert 0 <= rect["left"] < rect["right"] <= links["viewportWidth"] + 1, links
        page.locator("#chatBtn").tap()
        positions = page.evaluate("""() => {
            const viewport = window.visualViewport;
            // Simulate the short visual viewport left above a soft keyboard.
            Object.defineProperties(viewport, {
                height: {value: 140, configurable: true},
                offsetTop: {value: 35, configurable: true}
            });
            viewport.dispatchEvent(new Event('resize'));
            const bounds = id => {
                const {top, bottom} = document.getElementById(id).getBoundingClientRect();
                return {top, bottom};
            };
            return {panel: bounds('chatPanel'), close: bounds('chatCloseBtn'), input: bounds('chatInput')};
        }""")
        assert all(35 <= rect["top"] <= rect["bottom"] <= 175 for rect in positions.values()), positions
        page.locator("#chatCloseBtn").tap()
        expect(page.locator("#chatPanel")).to_be_hidden()
    print("PASS narrow online header and chat with a short keyboard viewport", flush=True)


def check_mobile_header(browser, devices, url, errors, has_safe_area_override, screenshots):
    with mobile_context(browser, devices, 390, 844) as context:
        context.add_init_script("localStorage.setItem('leqra.feedback.v1', JSON.stringify({fps: true}))")
        page = open_page(context, url, errors)
        expect(page.locator("#infinityPreviewScores")).to_be_visible()
        check_infinity_score_labels(page, "#infinityPreviewScores")
        page.locator("#infinityToggleLabel").tap()
        page.locator("#copyInviteBtn").tap()
        page.wait_for_function("() => leqra.getState().online?.connected")
        cdp = context.new_cdp_session(page) if has_safe_area_override else None
        def check_header(name):
            for width, height in ((320, 568), (390, 844), (440, 956), (568, 320), (844, 390)):
                page.set_viewport_size({"width": width, "height": height})
                page.wait_for_function("landscape => document.body.classList.contains('touch-landscape') === landscape",
                                       arg=width > height)
                insets = {"top": 47, "right": 0, "bottom": 34, "left": 0} if height > width else {
                    "top": 8, "right": 48, "bottom": 21, "left": 48
                }
                if cdp:
                    cdp.send("Emulation.setSafeAreaInsetsOverride", {"insets": insets})
                else:
                    insets = dict.fromkeys(insets, 0)
                page.evaluate("() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))")
                geometry = page.evaluate("""name => {
                    const box = element => {
                        const {left, top, right, bottom, width, height} = element.getBoundingClientRect();
                        return {left, top, right, bottom, width, height};
                    };
                    const header = document.querySelector('#gameHeader');
                    const link = header.querySelector('.github-link');
                    const hit = element => {
                        const rect = element.getBoundingClientRect();
                        return element.contains(document.elementFromPoint(
                            rect.left + rect.width / 2, rect.top + rect.height / 2));
                    };
                    return {
                        header: box(header), brand: box(header.querySelector('.brand')),
                        brandMark: box(header.querySelector('.brand-mark')),
                        brandName: box(header.querySelector('.brand-name')),
                        link: box(link), icon: box(link.querySelector('svg')), version: box(link.querySelector('span')),
                        buttons: [...header.querySelectorAll('.header-right > button')]
                            .filter(button => button.getClientRects().length).map(button => ({id: button.id, hit: hit(button), ...box(button)})),
                        linkHit: hit(link),
                        arena: box(document.querySelector(name === 'infinity' ? '#infiniteStatusbar' : '.arena-shell')),
                        scrollX, scrollWidth: document.documentElement.scrollWidth, viewportWidth: innerWidth
                    };
                }""", name)
                assert geometry["scrollX"] == 0 and geometry["scrollWidth"] <= width, geometry
                header = geometry["header"]
                assert header["top"] >= insets["top"] and geometry["arena"]["top"] >= header["bottom"] - 1, geometry
                assert geometry["icon"]["width"] >= 14, geometry
                assert geometry["linkHit"], geometry
                if geometry["brandMark"]["width"]:
                    # Account for the tank tile's rotation, not just its CSS box.
                    assert geometry["brandMark"]["right"] + 6 <= geometry["brandName"]["left"], geometry
                link = geometry["link"]
                for part in (geometry["icon"], geometry["version"]):
                    assert link["left"] <= part["left"] < part["right"] <= link["right"], geometry
                    assert link["top"] <= part["top"] < part["bottom"] <= link["bottom"], geometry
                for button in geometry["buttons"]:
                    assert button["hit"], geometry
                    assert header["top"] <= button["top"] < button["bottom"] <= header["bottom"], geometry
                    assert button["left"] >= insets["left"] and button["right"] <= width - insets["right"], geometry
                    assert button["height"] >= 30, geometry
                assert max(button["height"] for button in geometry["buttons"]) - min(
                    button["height"] for button in geometry["buttons"]
                ) <= 1, geometry
                if name == "infinity":
                    check_infinity_viewport(page, width, height, insets, score_below_fps=width <= 600)
                indicator = "#infiniteFPSIndicator" if name == "infinity" else "#fpsIndicator"
                performance_label = r"^fps: \d+(?:, ping: \d+ ms)?$" if name == "menu" else r"^fps: \d+, ping: (?:\d+ ms|—)$"
                expect(page.locator(indicator)).to_have_text(re.compile(performance_label))
                if screenshots:
                    page.screenshot(path=str(screenshots / f"{name}-header-{width}x{height}.png"))
        check_header("menu")
        page.locator("#startRoomBtn").tap()
        page.wait_for_function("() => leqra.getState().phase === 'playing'")
        check_header("fixed")
        page.locator("#pauseBtn").tap()
        page.locator("#returnRoomBtn").tap()
        page.get_by_role("dialog", name="End this match?", exact=True).get_by_role(
            "button", name="END MATCH", exact=True
        ).tap()
        expect(page.locator("#roomScreen")).to_be_visible()
        if not page.locator("#roomSettings").evaluate("element => element.open"):
            page.locator("#roomSettings > summary").tap()
        page.locator('[data-room-mode="infinity"]').tap()
        page.locator("#startRoomBtn").tap()
        expect(page.locator("#infiniteArena")).to_be_visible()
        check_header("infinity")
    print("PASS mobile menu, fixed, and Infinity headers, source icon/version, aligned actions, and safe areas", flush=True)


def check_infinity_viewport(page, width, height, insets, score_below_fps=False):
    geometry = page.evaluate("""() => {
        const box = selector => {
            const element = typeof selector === 'string' ? document.querySelector(selector) : selector;
            const {left, top, right, bottom, height, width} = element.getBoundingClientRect();
            return {left, top, right, bottom, height, width};
        };
        return {
            arena: box('#infiniteArena'), stage: box('.infinite-stage'),
            canvas: box('#infiniteCanvas'), footer: box('.infinite-underbar'),
            loadouts: box('#infiniteLoadouts'), primary: box('#infinitePilotLoadout1'),
            statusbar: box('#infiniteStatusbar'), scores: box('#infiniteKills'),
            fps: box('#infiniteFPSIndicator'), title: box('#infiniteStatusbar .arena-title'),
            titleChildren: [...document.querySelector('#infiniteStatusbar .arena-title').children]
                .filter(element => element.getClientRects().length).map(box),
            scoreboard: box('#infiniteScoreboardBtn'),
            viewport: {width: innerWidth, height: innerHeight}
        };
    }""")
    arena, stage, canvas, footer = (geometry[key] for key in ("arena", "stage", "canvas", "footer"))
    assert abs(arena["top"]) <= 1 and abs(arena["bottom"] - height) <= 1, geometry
    assert abs(arena["left"]) <= 1 and abs(arena["right"] - width) <= 1, geometry
    assert abs(stage["bottom"] - footer["top"]) <= 1, geometry
    assert abs(canvas["bottom"] - stage["bottom"]) <= 1 and canvas["height"] > 0, geometry
    assert abs(footer["bottom"] - arena["bottom"]) <= 1, geometry
    # A single pilot uses its content height, with only the device's home-indicator
    # inset below it. The fixed-maze cockpit's two-pilot reserve must not leak in.
    assert abs(geometry["loadouts"]["height"] - geometry["primary"]["height"]) <= 1, geometry
    assert footer["height"] <= geometry["loadouts"]["height"] + max(6, insets["bottom"]) + 10, geometry
    check_infinity_score_labels(page)
    scores, fps, statusbar = (geometry[key] for key in ("scores", "fps", "statusbar"))
    for child in geometry["titleChildren"]:
        assert geometry["title"]["left"] <= child["left"] < child["right"] <= geometry["title"]["right"] + .5, geometry
    visible = ("scores", "title", "scoreboard", *(("fps",) if fps["width"] else ()))
    for key in visible:
        rect = geometry[key]
        assert statusbar["left"] <= rect["left"] < rect["right"] <= statusbar["right"] + 1, geometry
        assert statusbar["top"] <= rect["top"] < rect["bottom"] <= statusbar["bottom"] + 1, geometry
    for index, key in enumerate(visible):
        rect = geometry[key]
        for other_key in visible[index + 1:]:
            other = geometry[other_key]
            assert (rect["right"] <= other["left"] + .5 or other["right"] <= rect["left"] + .5 or
                    rect["bottom"] <= other["top"] + .5 or other["bottom"] <= rect["top"] + .5), geometry
    if score_below_fps:
        assert scores["top"] >= fps["bottom"] - 1, geometry
        # Tiny screens may need a wider second row to keep callsigns readable.
        if width >= 390:
            assert abs((scores["left"] + scores["right"]) / 2 - (fps["left"] + fps["right"]) / 2) <= 1, geometry
    return geometry


def check_infinity_score_labels(page, selector="#infiniteKills"):
    button = "#infinityPreviewScoreboardBtn" if selector == "#infinityPreviewScores" else "#infiniteScoreboardBtn"
    expect(page.locator(button)).to_be_visible()
    expect(page.locator(button)).to_have_text("LEADERBOARD", use_inner_text=True)
    scores = page.evaluate("""selector => ({
        touch: document.body.classList.contains('touch-ui'),
        rows: [...document.querySelectorAll(selector + ' .infinite-personal-score')].map(row => ({
            visible: row.innerText.trim(), identity: row.getAttribute('aria-label')
        }))
    })""", selector)
    assert scores["rows"], scores
    for index, row in enumerate(scores["rows"]):
        assert f"(P{index + 1})" in row["identity"], scores
        if scores["touch"]:
            assert re.fullmatch(r"score: -?\d+, rank: #\d+", row["visible"]), scores
            assert row["identity"].endswith(row["visible"]), scores
        else:
            assert row["visible"] == row["identity"], scores
            assert re.fullmatch(r".+ \(P\d\): score: -?\d+, rank: #\d+", row["visible"]), scores


def check_network_ping(browser, devices, url, errors, screenshots):
    with mobile_context(browser, devices, 390, 844, service_workers="block") as context:
        def delay_preview_response(route):
            response = route.fetch()
            time.sleep(.24)
            route.fulfill(response=response)
        context.route("**/api/infinity", delay_preview_response)
        context.add_init_script("""(() => {
            localStorage.setItem('leqra.feedback.v1', JSON.stringify({fps: true}));
            // Delay real server pongs without changing their echoed timestamps.
            // A rendering frame interval cannot satisfy the resulting RTT check.
            const add = WebSocket.prototype.addEventListener;
            WebSocket.prototype.addEventListener = function(type, listener, options) {
                if (type !== 'message' || !this.url.includes('/ws/infinite'))
                    return add.call(this, type, listener, options);
                return add.call(this, type, function(event) {
                    let packet;
                    try { packet = JSON.parse(event.data); } catch (_) {}
                    const deliver = () => listener.call(this, event);
                    if (packet?.type === 'pong') {
                        setTimeout(() => {
                            window.__delayedInfinityPongs = (window.__delayedInfinityPongs || 0) + 1;
                            deliver();
                        }, 240);
                    } else deliver();
                }, options);
            };
        })();""")
        page = open_page(context, url, errors)
        expect(page.locator("#infinityPreviewOnlineCount")).to_have_text(re.compile(r"^\d+ online$"))
        expect(page.locator("#infiniteArena")).to_be_hidden()
        page.wait_for_function("""() => {
            const match = document.querySelector('#fpsIndicator').innerText.match(/ping: (\\d+) ms/);
            return match && Number(match[1]) >= 220;
        }""", timeout=10000)
        if screenshots:
            page.screenshot(path=str(screenshots / "preview-ping-390x844.png"))
        page.locator("#startRoomBtn").tap()
        expect(page.locator("#infiniteArena")).to_be_visible()
        page.wait_for_function("""() => {
            const match = document.querySelector('#infiniteFPSIndicator').innerText.match(/ping: (\\d+) ms/);
            return window.__delayedInfinityPongs > 0 && match && Number(match[1]) >= 220;
        }""", timeout=10000)
        expect(page.locator("#infiniteFPSIndicator")).to_have_text(re.compile(r"^fps: \d+, ping: \d+ ms$"))
        for width, height in ((320, 568), (390, 844), (440, 956), (568, 320), (844, 390)):
            page.set_viewport_size({"width": width, "height": height})
            page.wait_for_function("landscape => document.body.classList.contains('touch-landscape') === landscape",
                                   arg=width > height)
            page.wait_for_timeout(180)  # Allow the resize debounce and compositor to settle before capture.
            check_infinity_viewport(page, width, height, dict.fromkeys(("top", "right", "bottom", "left"), 0),
                                    score_below_fps=width <= 600)
            if screenshots:
                page.screenshot(path=str(screenshots / f"public-ping-{width}x{height}.png"))
        page.evaluate("() => { leqraInfinity.close(); leqraInfinity.start('offline'); }")
        expect(page.locator("#infiniteFPSIndicator")).to_have_text(re.compile(r"^fps: \d+$"))
        check_infinity_score_labels(page)
    print("PASS preview HTTP ping before joining, Public Infinity round-trip ping, and offline ping omission", flush=True)


def check_pause_scorecard(browser, devices, url, errors, screenshots):
    for width, height in ((1280, 900), (390, 844)):
        options = {"viewport": {"width": width, "height": height}}
        if width < 760:
            options.update(has_touch=True, is_mobile=True, user_agent=devices["iPhone SE"]["user_agent"])
        with browser.new_context(**options) as context:
            page = open_page(context, url, errors)
            expect(page.locator("#infinityPreviewScores")).to_be_visible()
            check_infinity_score_labels(page, "#infinityPreviewScores")
            page.evaluate("() => leqraInfinity.start('offline')")
            check_infinity_score_labels(page)
            page.locator("#pauseBtn").click()
            panel = page.locator("#infinitePauseSidebar #infiniteLeaderboardPanel")
            expect(panel).to_be_visible()
            panel.locator("#infiniteLeaderboard").evaluate("""list => {
                list.replaceChildren(...Array.from({length: 12}, (_, i) => {
                    const row = document.createElement('li'), name = document.createElement('span');
                    const score = document.createElement('strong');
                    row.value = i < 10 ? i + 1 : i === 10 ? 40 : 75;
                    name.textContent = i >= 10 ? `LLLLLLLLLLLLLLLL (P${i - 9})` : `Pilot ${i + 1}`;
                    score.textContent = i >= 10 ? '-12345678' : String(1200 - i);
                    row.style.setProperty('--tank-color', '#32c5ff');
                    if (i >= 10) {
                        row.className = 'off-board-local';
                        row.dataset.local = i === 10 ? 'p1' : 'p2';
                        row.style.setProperty('--local-highlight', '#32c5ff');
                    }
                    row.append(name, score);
                    return row;
                }));
            }""")
            panel.scroll_into_view_if_needed()
            geometry = panel.evaluate("""panel => {
                const summary = panel.querySelector('summary'), rect = panel.getBoundingClientRect();
                const style = getComputedStyle(panel), titleStyle = getComputedStyle(summary);
                return {
                    overflow: style.overflow, summaryPosition: titleStyle.position,
                    border: style.borderTopWidth, radius: style.borderTopLeftRadius,
                    summaryRadius: titleStyle.borderTopLeftRadius,
                    markerPosition: getComputedStyle(panel.querySelector('li')).listStylePosition,
                    cornersPaintedBySummary: [rect.left + 2, rect.right - 2].map(x =>
                        summary.contains(document.elementFromPoint(x, rect.top + 2))),
                    width: rect.width, scrollWidth: panel.scrollWidth
                };
            }""")
            assert geometry["overflow"] == "visible" and geometry["summaryPosition"] == "static", geometry
            assert geometry["border"] == "1px" and geometry["radius"] == "8px", geometry
            assert geometry["summaryRadius"] == "7px" and geometry["markerPosition"] == "inside", geometry
            # WebKit hit-testing can include rectangular child bounds at rounded
            # edges; inspect its screenshots as well as the geometric checks.
            if browser.browser_type.name == "chromium":
                assert not any(geometry["cornersPaintedBySummary"]), geometry
            assert geometry["scrollWidth"] <= geometry["width"], geometry
            final_row = panel.locator("li").last
            final_row.scroll_into_view_if_needed()
            expect(final_row).to_be_in_viewport(ratio=1)
            containment = panel.evaluate("""panel => {
                const rect = panel.getBoundingClientRect();
                const contained = [...panel.querySelectorAll('li, p')].every(child => {
                    const r = child.getBoundingClientRect();
                    return r.left >= rect.left && r.right <= rect.right && r.bottom <= rect.bottom;
                });
                const separate = [...panel.querySelectorAll('li')].every(row => {
                    const score = row.querySelector('strong').getBoundingClientRect();
                    return [...row.querySelector('span').getClientRects()].every(name =>
                        name.right <= score.left + .5 || score.right <= name.left + .5 ||
                        name.bottom <= score.top + .5 || score.bottom <= name.top + .5);
                });
                return contained && separate;
            }""")
            assert containment
            if screenshots:
                panel.screenshot(path=str(screenshots / f"pause-scorecard-{width}x{height}.png"))
            page.locator("#infiniteResumeBtn").click()
            restored = page.locator(".infinite-stage > #infiniteLeaderboardPanel")
            expect(restored).to_be_attached()
            expect(restored).not_to_have_attribute("open", "")
            page.locator("#infiniteScoreboardBtn").click()
            expect(restored).to_be_visible()
    print("PASS Infinity pause scorecard corners, complete border, and arena restoration", flush=True)


def check_standalone_header(browser, devices, url, errors, screenshots):
    # Model the installed app's UA and JS display-mode signals. This is a layout
    # regression, not a claim that desktop Playwright runs the iOS Home Screen shell.
    ua = re.sub(r" (?:Version|Safari)/[\d.]+", "", devices["iPhone 13"]["user_agent"])
    with browser.new_context(viewport={"width": 390, "height": 844}, has_touch=True,
                             is_mobile=True, user_agent=ua, service_workers="block") as context:
        context.add_init_script("""(() => {
            localStorage.setItem('leqra.feedback.v1', JSON.stringify({fps: true}));
            Object.defineProperty(navigator, 'standalone', {get: () => true});
            const match = window.matchMedia.bind(window);
            window.matchMedia = query => {
                const result = match(query);
                if (query !== '(display-mode: standalone)') return result;
                return new Proxy(result, {get(target, key) {
                    if (key === 'matches') return true;
                    const value = Reflect.get(target, key, target);
                    return typeof value === 'function' ? value.bind(target) : value;
                }});
            };
        })();""")
        chromium = browser.browser_type.name == "chromium"
        if not chromium:
            # Desktop WebKit cannot set native iOS safe areas. Retain every
            # production rule and simulate just the environment values instead.
            def safe_area_css(route):
                response = route.fetch()
                css = response.text()
                for side in ("top", "right", "bottom", "left"):
                    css = css.replace(f"env(safe-area-inset-{side})", f"var(--test-safe-{side}, 0px)")
                route.fulfill(response=response, body=css)
            context.route("**/style.css*", safe_area_css)
        page = open_page(context, url, errors)
        cdp = context.new_cdp_session(page) if chromium else None
        page.locator("#infinityToggleLabel").tap()
        page.locator("#copyInviteBtn").tap()
        page.wait_for_function("() => leqra.getState().online?.connected")
        page.locator("#startRoomBtn").tap()
        page.wait_for_function("() => leqra.getState().phase === 'playing'")
        for mode in ("fixed", "infinity"):
            if mode == "infinity":
                page.locator("#pauseBtn").tap()
                page.locator("#returnRoomBtn").tap()
                page.get_by_role("dialog", name="End this match?", exact=True).get_by_role(
                    "button", name="END MATCH", exact=True
                ).tap()
                expect(page.locator("#roomScreen")).to_be_visible()
                if not page.locator("#roomSettings").evaluate("element => element.open"):
                    page.locator("#roomSettings > summary").tap()
                page.locator('[data-room-mode="infinity"]').tap()
                page.locator("#startRoomBtn").tap()
                expect(page.locator("#infiniteArena")).to_be_visible()
            for name, width, height, insets in (
                ("narrow", 320, 568, {"top": 47, "right": 0, "bottom": 34, "left": 0}),
                ("portrait", 390, 844, {"top": 47, "right": 0, "bottom": 34, "left": 0}),
                ("screenshot", 440, 956, {"top": 62, "right": 0, "bottom": 34, "left": 0}),
                ("landscape", 844, 390, {"top": 0, "right": 47, "bottom": 21, "left": 47}),
                ("restored", 390, 844, {"top": 47, "right": 0, "bottom": 34, "left": 0}),
            ):
                page.set_viewport_size({"width": width, "height": height})
                if cdp:
                    cdp.send("Emulation.setSafeAreaInsetsOverride", {"insets": insets})
                else:
                    page.evaluate("""insets => {
                        for (const [side, value] of Object.entries(insets))
                            document.documentElement.style.setProperty('--test-safe-' + side, value + 'px');
                    }""", insets)
                page.evaluate("""() => {
                    window.dispatchEvent(new PageTransitionEvent('pageshow', {persisted: true}));
                    window.dispatchEvent(new Event('focus'));
                    document.dispatchEvent(new Event('visibilitychange'));
                    visualViewport.dispatchEvent(new Event('resize'));
                }""")
                page.wait_for_function("landscape => document.body.classList.contains('touch-landscape') === landscape",
                                       arg=width > height)
                page.wait_for_timeout(180)  # The WebKit viewport restoration debounce is 110ms.
                geometry = page.evaluate("""() => {
                    const box = element => {
                        const {left, top, right, bottom, height} = element.getBoundingClientRect();
                        return {left, top, right, bottom, height};
                    };
                    const hit = element => {
                        const rect = element.getBoundingClientRect();
                        return element.contains(document.elementFromPoint(
                            rect.left + rect.width / 2, rect.top + rect.height / 2));
                    };
                    const header = document.querySelector('#gameHeader');
                    return {
                        standalone: navigator.standalone && matchMedia('(display-mode: standalone)').matches,
                        app: box(document.querySelector('.app')), header: box(header), scrollX, scrollY,
                        actions: [...header.querySelectorAll('.github-link, .header-right > button')]
                            .filter(button => button.getClientRects().length).map(button => ({
                                id: button.id || button.className, hit: hit(button), ...box(button)
                            }))
                    };
                }""")
                assert geometry["standalone"] and geometry["scrollX"] == geometry["scrollY"] == 0, geometry
                assert abs(geometry["app"]["bottom"] - height) <= 1, geometry
                assert geometry["header"]["top"] >= insets["top"], geometry
                for action in geometry["actions"]:
                    assert action["hit"], geometry
                    assert insets["top"] <= action["top"] < action["bottom"] <= geometry["header"]["bottom"], geometry
                    assert insets["left"] <= action["left"] < action["right"] <= width - insets["right"], geometry
                if mode == "infinity":
                    shown = check_infinity_viewport(page, width, height, insets, score_below_fps=width <= 600)
                    page.evaluate("""() => {
                        const checkbox = document.querySelector('#showFPS');
                        checkbox.checked = false;
                        checkbox.dispatchEvent(new Event('change'));
                    }""")
                    hidden = check_infinity_viewport(page, width, height, insets)
                    assert hidden["statusbar"]["height"] <= shown["statusbar"]["height"] + 1, (shown, hidden)
                    assert hidden["stage"]["height"] >= shown["stage"]["height"] - 1, (shown, hidden)
                    page.evaluate("""() => {
                        const checkbox = document.querySelector('#showFPS');
                        checkbox.checked = true;
                        checkbox.dispatchEvent(new Event('change'));
                    }""")
                if screenshots:
                    page.screenshot(path=str(screenshots / f"standalone-{mode}-header-{name}.png"))
    print("PASS simulated standalone status bar, safe areas, rotation, and foreground restoration", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="http://localhost:8080")
    parser.add_argument("--engine", choices=("chromium", "webkit"), default="chromium")
    parser.add_argument("--screenshots", type=Path, help="Optional output directory outside the repository")
    args = parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as playwright:
        if args.engine == "chromium":
            browser = playwright.chromium.launch(chromium_sandbox=True)
        else:
            browser = playwright.webkit.launch()
        errors = []
        try:
            check_landscape(browser, playwright.devices, errors, args.engine == "chromium")
            check_split_infinity(browser, playwright.devices, errors)
            check_narrow_online(browser, playwright.devices, args.url, errors)
            check_mobile_header(browser, playwright.devices, args.url, errors, args.engine == "chromium", args.screenshots)
            check_pause_scorecard(browser, playwright.devices, args.url, errors, args.screenshots)
            check_standalone_header(browser, playwright.devices, args.url, errors, args.screenshots)
            check_network_ping(browser, playwright.devices, args.url, errors, args.screenshots)
            assert not errors, errors
        finally:
            browser.close()
