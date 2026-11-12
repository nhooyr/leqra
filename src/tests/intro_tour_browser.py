"""Check the quick tour in isolated Chromium/WebKit: python3 src/tests/intro_tour_browser.py [server URL]."""

import argparse
import re
from collections import Counter
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

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


def check_keycaps(row, labels):
    keys = row.locator('kbd:not(.control-mouse-key)')
    assert Counter(keys.all_text_contents()) == Counter(labels), keys.all_text_contents()
    assert row.locator('.control-keycaps').count() > 0
    layout = keys.evaluate_all("""keys => keys.map(key => {
        const r=key.getBoundingClientRect(),p=key.closest('dd').getBoundingClientRect(),s=getComputedStyle(key);
        return {left:r.left,right:r.right,parentLeft:p.left,parentRight:p.right,height:r.height,font:parseFloat(s.fontSize)};
    })""")
    assert all(key['left'] >= key['parentLeft']-1 and key['right'] <= key['parentRight']+1 and
               key['height'] >= 20 and key['font'] >= 10 for key in layout), layout


def check_mouse_symbols(page):
    for selector in ('#introTourMouseAim', '#introTourMouseFire'):
        symbol = page.locator(selector + ' .control-mouse-key')
        expect(symbol).to_have_count(1)
        expect(symbol.locator('svg[aria-hidden="true"]')).to_have_count(1)
        assert 'mouse' in symbol.get_attribute('aria-label').lower()


def check_roster_tools_order(page):
    ids=page.locator('#roomPlayers .room-disclosure-content').evaluate('node => [...node.children].map(child=>child.id)')
    order=[ids.index(key) for key in ('rosterTools','roomRoleStrip','roomP2RoleStrip','roomRoster','roomSpectators','localControlsNote')]
    assert order[0]==0 and order==sorted(order),ids


def check_remapped_tour(page, touch, screenshot_dir=None):
    page.locator('#roomControlsBtn').click()
    for binding, key in (('0:forward','i'), ('0:fire','z'), ('1:forward','u')):
        page.locator('[data-bind="'+binding+'"]').click()
        page.keyboard.press(key)
    page.locator('#p1MouseAimEnabled').uncheck()
    page.locator('#p1MouseFireEnabled').uncheck()
    page.locator('#openIntroTour').click()
    check_keycaps(page.locator('#introTourMoveKeys'), ['I','A','S','D','U','←','↓','→'])
    check_keycaps(page.locator('#introTourFireKeys'), ['Z','C','SPACE','ENTER'])
    expect(page.locator('#introTourDesktop')).to_be_hidden()
    page.locator('#introTourSkip').click()
    page.locator('#p1MouseAimEnabled').check()
    page.locator('#p1MouseFireEnabled').check()
    page.locator('#openIntroTour').click()
    check_mouse_symbols(page)
    if not touch:
        expect(page.locator('#introTourDesktop')).to_be_visible()
    page.locator('#introTourSkip').click()
    page.locator('[data-close-dialog="controlsDialog"]').click()
    page.locator('#roomPlayers').evaluate('node => node.open = true')
    check_roster_tools_order(page)
    page.locator('#addLocalBtn').click()
    page.locator('#roomControlsBtn').click()
    page.locator('#openIntroTour').click()
    check_keycaps(page.locator('#introTourMoveKeys'), ['I','A','S','D'])
    check_keycaps(page.locator('#introTourFireKeys'), ['Z','C'])
    check_mouse_symbols(page)
    assert page.locator('#introTourDialog').evaluate('node => node.scrollWidth <= node.clientWidth')
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
    if screenshot_dir is not None:
        page.screenshot(path=str(screenshot_dir))
    page.locator('#introTourSkip').click()
    page.locator('[data-close-dialog="controlsDialog"]').click()


def check_public_headers(page, paired, screenshot=None):
    def check(header_id, title_id):
        expect(page.locator('#'+title_id)).to_have_text('Public Infinity')
        layout=page.locator('#'+header_id).evaluate("""header => {
            const box=node=>{const r=node.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom};};
            const nodes=[header.querySelector('h2'),header.querySelector('.fps-indicator'),header.querySelector('.infinite-scoreboard-toggle')];
            const overlap=(a,b)=>a.left<b.right-1&&b.left<a.right-1&&a.top<b.bottom-1&&b.top<a.bottom-1;
            const bounds=nodes.map(box),r=box(header);
            return {bounds,header:r,overlap:overlap(bounds[0],bounds[1])||overlap(bounds[1],bounds[2]),
                center:Math.abs((bounds[1].left+bounds[1].right-r.left-r.right)/2),overflow:header.scrollWidth>header.clientWidth};
        }""")
        assert not layout['overlap'] and not layout['overflow'] and layout['center']<=1,layout
        assert all(item['left']>=layout['header']['left']-1 and item['right']<=layout['header']['right']+1 for item in layout['bounds']),layout
    page.locator('#infinityToggle').check()
    check('infinityPreviewBar','infinityPreviewTitle')
    page.evaluate("paired=>leqraInfinity.start('online',{name:'HEADER PILOT',...(paired?{localName:'HEADER WING'}:{})})",paired)
    expect(page.locator('#infiniteOnlineCount')).to_have_text(re.compile(r'^[1-9]\d* online$'))
    expect(page.locator('#infiniteKills .infinite-score-value').last).to_have_text(re.compile(r'^: \(-?\d+, #[1-9]\d*\)$'))
    check('infiniteStatusbar','infiniteArenaTitle')
    if screenshot:
        page.screenshot(path=str(screenshot))
    page.locator('#pauseBtn').click()
    page.locator('#infiniteExit').click()
    page.locator('#infinityToggle').uncheck()


def check_mouse_preferences(browser, url, width, height, touch, screenshot_dir=None):
    tip_text='Hold any fire key to rapid fire.'
    with browser.new_context(viewport={'width':width,'height':height},is_mobile=touch,has_touch=touch,service_workers='block') as context:
        page=context.new_page();errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
        page.add_init_script("localStorage.setItem('leqra.introTour.v1','1')")
        page.goto(url);page.wait_for_function('() => !!window.leqraInfinity')
        page.locator('#roomControlsBtn').click()
        geometry=page.evaluate("""() => {
            const rect=node=>{const r=node.getBoundingClientRect();return {width:r.width,height:r.height,right:r.right};};
            return {key:rect(document.querySelector('[data-bind="0:fireAlt"]')),
                toggles:['p1MouseAimEnabled','p1MouseFireEnabled'].map(id=>rect(document.getElementById(id)))};
        }""")
        assert all(abs(item['width']-geometry['key']['width'])<=1 and
                   abs(item['height']-geometry['key']['height'])<=1 and
                   abs(item['right']-geometry['key']['right'])<=1 for item in geometry['toggles']),geometry
        aim=page.locator('#p1MouseAimEnabled');fire=page.locator('#p1MouseFireEnabled')
        def caption(node):
            return node.evaluate("""input=>{const state=input.nextElementSibling,r=state.getBoundingClientRect(),s=getComputedStyle(state),cols=s.gridTemplateColumns.split(' ').map(parseFloat),gap=parseFloat(s.columnGap),left=r.left+(r.width-cols.reduce((a,b)=>a+b,0)-gap)/2;return {display:s.display,cols,icon:left,text:left+cols[0]+gap,content:getComputedStyle(state,'::after').content};}""")
        on=caption(aim)
        assert on['display']=='grid' and len(on['cols'])==2 and abs(on['cols'][0]-16)<.1,on
        expect(aim).to_have_attribute('type','checkbox');expect(fire).to_have_attribute('type','checkbox')
        expect(aim).to_be_checked();expect(fire).to_be_checked()
        aim.press('Space');expect(aim).not_to_be_checked();expect(aim).to_be_focused();expect(fire).to_be_checked()
        off=caption(aim)
        assert on['cols']==off['cols'] and abs(on['icon']-off['icon'])<.1 and abs(on['text']-off['text'])<.1,(on,off)
        assert 'ON' in on['content'] and 'OFF' in off['content'],(on,off)
        box=aim.bounding_box();aim.click(position={'x':box['width']-3,'y':box['height']/2});expect(aim).to_be_checked()
        fire.press('Space');expect(fire).not_to_be_checked();expect(fire).to_be_focused();expect(aim).to_be_checked()
        aim.press('Space');expect(aim).not_to_be_checked()
        box=fire.bounding_box();fire.click(position={'x':box['width']-3,'y':box['height']/2});expect(fire).to_be_checked();expect(aim).not_to_be_checked()
        off_caption=caption(aim);on_caption=caption(fire)
        assert abs(off_caption['icon']-on_caption['icon'])<.1 and abs(off_caption['text']-on_caption['text'])<.1,(off_caption,on_caption)
        stored=page.evaluate("JSON.parse(localStorage.getItem('leqra.feedback.v1'))")
        assert stored['mouseAim'] is False and stored['mouseFire'] is True,stored
        page.reload();page.wait_for_function('() => !!window.leqraInfinity');page.locator('#roomControlsBtn').click()
        expect(page.locator('#p1MouseAimEnabled')).not_to_be_checked();expect(page.locator('#p1MouseFireEnabled')).to_be_checked()
        assert page.locator('#controlsKeyboardHelp').inner_text().count(tip_text)==1
        expect(page.locator('#controlsKeyboardHelp .controls-shortcuts kbd')).to_have_text(['P','ESC','M','F'])
        expect(page.locator('#controlsKeyboardHelp .controls-shortcuts .control-keycaps').first).to_have_text('P/ESC')
        expect(page.locator('#controlsKeyboardHelp .controls-firing-help')).to_have_text(tip_text+' With one local tank, both keyboard layouts control it.')
        assert page.locator('#controlsKeyboardHelp').evaluate("node=>node.querySelector('.controls-firing-help').getBoundingClientRect().top>=node.querySelector('.controls-shortcuts').getBoundingClientRect().bottom")
        if screenshot_dir:
            page.screenshot(path=str(screenshot_dir/f'{browser.browser_type.name}-{width}-mouse-checkboxes.png'))
        page.locator('#openIntroTour').click()
        tip=page.locator('#introTourKeyboard .intro-fire-tip');expect(tip).to_have_text(tip_text)
        page.locator('#introTourDialog').evaluate('node => node.scrollTop=node.scrollHeight')
        expect(tip).to_be_in_viewport(ratio=1)
        next_button=page.locator('#introTourNext');expect(next_button).to_be_in_viewport(ratio=1)
        assert next_button.evaluate("""node=>{const r=node.getBoundingClientRect();return r.height>=44&&node.contains(document.elementFromPoint(r.x+r.width/2,r.y+r.height/2));}""")
        assert page.locator('#introTourDialog').evaluate('node => node.scrollWidth <= node.clientWidth')
        if screenshot_dir:
            page.screenshot(path=str(screenshot_dir/f'{browser.browser_type.name}-{width}-tour-fire-tip.png'))
        next_button.click();expect(page.locator('#introTourTitle')).to_have_text('Use the maze')
        page.locator('#introTourSkip').click();page.locator('[data-close-dialog="controlsDialog"]').click()
        for paired in (False,True):
            page.evaluate("paired=>leqraInfinity.start('offline',{name:'ONE',...(paired?{localName:'TWO'}:{}),roomRules:{infinityRandomBots:false}})",paired)
            page.locator('#pauseBtn').click()
            manual=page.locator('#infinitePauseSidebar #manualContent')
            expect(manual.locator('.manual-controls .control-player')).to_have_count(2 if paired else 1)
            shared=manual.locator('.manual-shared-controls')
            if not paired:
                solo_tip=manual.locator('.manual-controls > .manual-fire-tip');expect(solo_tip).to_have_text(tip_text)
                expect(shared.locator('.manual-fire-tip')).to_have_count(0)
                assert solo_tip.evaluate("tip=>tip.getBoundingClientRect().top>=tip.previousElementSibling.getBoundingClientRect().bottom")
                page.locator('#infiniteExit').click()
                continue
            shared_tip=shared.locator(':scope > .manual-fire-tip');expect(shared_tip).to_have_text(tip_text)
            expect(manual.locator('.manual-controls .manual-fire-tip')).to_have_count(0)
            manual.scroll_into_view_if_needed()
            data=shared_tip.evaluate("""tip=>{const shared=tip.parentElement,controls=shared.previousElementSibling,rows=[...controls.querySelectorAll('.control-player')],r=tip.getBoundingClientRect(),s=getComputedStyle(shared);return {outside:!tip.closest('.control-player'),after:r.top>=Math.max(...rows.map(row=>row.getBoundingClientRect().bottom)),border:parseFloat(s.borderTopWidth),borderStyle:s.borderTopStyle,neutral:!rows.map(row=>getComputedStyle(row.querySelector('.control-pilot')).color).includes(getComputedStyle(tip).color),first:shared.firstElementChild===tip,noNames:!tip.querySelector('.pilot-identity,.control-pilot')};}""")
            assert data['outside'] and data['after'] and data['border']>=1 and data['borderStyle']!='none' and data['neutral'] and data['first'] and data['noNames'],data
            if screenshot_dir and paired:
                page.screenshot(path=str(screenshot_dir/f'{browser.browser_type.name}-{width}-shared-fire-tip.png'))
            page.locator('#infiniteExit').click()
        assert not errors,errors
        print(f'PASS {browser.browser_type.name} {width}: native full-width mouse checkboxes, independent saved states, accessible tour Next, shared neutral fire tip for one/two pilots',flush=True)


def check_context(browser, url, width, height, touch, screenshot_dir=None):
    with browser.new_context(viewport={"width": width, "height": height}, is_mobile=touch,
                             has_touch=touch, service_workers="block") as context:
        page = context.new_page()
        errors=[]
        page.on('pageerror',lambda error:errors.append(str(error)))
        page.goto(url)
        mouse_help = page.locator("#introTourDesktop")
        touch_help = page.locator("#introTourTouch")
        keyboard_help = page.locator("#introTourKeyboard")
        expect(page.locator("#introTourDialog")).to_be_visible()
        assert page.locator('[data-intro-page="0"] > section').evaluate_all("nodes => nodes.map(node => node.id)") == ["introTourTouch", "introTourKeyboard", "introTourDesktop"]
        expect(keyboard_help.get_by_role("heading", name="Keyboard")).to_be_visible()
        check_control_rows(keyboard_help, ["Movement", "Fire"])
        check_keycaps(page.locator("#introTourMoveKeys"), ["W","A","S","D","↑","←","↓","→"])
        check_keycaps(page.locator("#introTourFireKeys"), ["Q","C","SPACE","ENTER"])
        if touch:
            expect(mouse_help).to_be_hidden()
            expect(touch_help.get_by_role("heading", name="Touch")).to_be_visible()
            check_control_rows(touch_help, ["Movement", "Aim", "Fire"])
            expect(touch_help).to_contain_text("the same joystick")
        else:
            expect(mouse_help).to_be_visible()
            check_mouse_symbols(page)
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
            ["Public Infinity", "Elimination", "Capture the Flag", "King of the Hill", "Survival"]
        )
        page.locator("#introTourNext").click()
        expect(page.locator("#introTourDialog")).to_be_hidden()
        github = page.locator(".github-link")
        expect(github).to_be_visible()
        expect(github).to_have_attribute("href", "https://github.com/nhooyr/leqra")
        assert page.evaluate("document.documentElement.scrollWidth === innerWidth")
        if width in (320,390) and urlsplit(url).scheme in ('http','https'):
            check_public_headers(page,False)
        toggle=page.locator('#infinityToggle')
        if toggle.is_enabled() and toggle.is_checked():
            toggle.uncheck()
        screenshot = screenshot_dir / f'{browser.browser_type.name}-{width}-tour-keycaps.png' if screenshot_dir else None
        check_remapped_tour(page, touch, screenshot)
        if width in (320,390) and urlsplit(url).scheme in ('http','https'):
            header_shot=screenshot_dir / f'{browser.browser_type.name}-{width}-public-p2-header.png' if screenshot_dir else None
            check_public_headers(page,True,header_shot)
        if width <= 920:
            if not touch:
                page.locator("#startRoomBtn").click()
                page.wait_for_function("() => leqra.getState().phase === 'playing'")
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
            page.locator("#startRoomBtn").click()
            page.wait_for_function("() => leqra.getState().phase === 'playing'")
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
        assert not errors,errors
        print(f'PASS {browser.browser_type.name} {width}x{height}: themed keycaps, remapped solo/P2 aliases, mouse symbols, and touch/tour layout', flush=True)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('url', nargs='?')
    parser.add_argument('--browser', action='append', choices=('chromium','webkit'))
    parser.add_argument('--screenshots', type=Path, help='Optional output directory outside the repository')
    args=parser.parse_args()
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
    target=args.url or (Path(__file__).resolve().parents[1] / 'web/index.html').as_uri()
    parts=urlsplit(target);query=dict(parse_qsl(parts.query));query['test']='1'
    target=urlunsplit((parts.scheme,parts.netloc,parts.path,urlencode(query),parts.fragment))
    with sync_playwright() as playwright:
        for engine in args.browser or ('chromium','webkit'):
            browser=getattr(playwright,engine).launch(**({'chromium_sandbox':True} if engine=='chromium' else {}))
            try:
                for width,height,touch in ((1280,900,False),(620,900,False),(320,568,True),(390,844,True),(844,390,True)):
                    check_context(browser,target,width,height,touch,args.screenshots)
                for width,height,touch in ((1280,900,False),(500,800,True),(320,568,True),(390,844,True),(844,390,True)):
                    check_mouse_preferences(browser,target,width,height,touch,args.screenshots)
            finally:
                browser.close()
