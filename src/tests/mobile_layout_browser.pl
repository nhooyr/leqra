#!/usr/bin/env perl
package main;
use v5.34;
use strict;
use warnings;
use utf8;
use Encode ();
binmode STDOUT, ":encoding(UTF-8)";
binmode STDERR, ":encoding(UTF-8)";
use FindBin;
use lib "$FindBin::Bin/lib";
use Leqra::Browser;

my ($args, $browser, $errors, $parser, $playwright);
# Check small-screen layouts against a running leqra server.
# 
# Run with Playwright Chromium installed and a dedicated server running.
# perl src/tests/mobile_layout_browser.pl http://localhost:8080
sub mobile_context {
    my ($browser, $devices, $width, $height, $options) = @_;
    $options //= {};
    return $browser->newContext({viewport => {'width' => $width, 'height' => $height}, hasTouch => JSON::PP::true, isMobile => JSON::PP::true, userAgent => $devices->{'iPhone SE'}->{'userAgent'}, %{$options}});
}
sub open_page {
    my ($context, $url, $errors) = @_;
    my ($page);
    $page = $context->newPage();
    capture_event($page, 'pageerror', $errors, '(error) => String(error)');
    $page->addInitScript('localStorage.setItem(\'leqra.introTour.v1\', \'1\')');
    $page->goto($url);
    wait_js($page, '() => !!window.leqra');
    return $page;
}
sub check_landscape {
    my ($browser, $devices, $errors, $has_safe_area_override) = @_;
    my ($bounds, $button, $cdp, $context, $fixed_pause_size, $index, $layout, $name, $page, $pause, $pause_button, $rules, $trigger);
    $index = path($0)->absolute->parent(2)->child('web')->child('index.html');
    $context = main::mobile_context($browser, $devices, 568, 320);
    $page = main::open_page($context, URI::file->new_abs("" . $index)->as_string, $errors);
    if (truth_value($has_safe_area_override)) {
        $cdp = $context->newCDPSession($page);
        $cdp->send('Emulation.setSafeAreaInsetsOverride', {'insets' => {'top' => 8, 'right' => 48, 'bottom' => 21, 'left' => 48}});
    }
    $page->locator('#roomSettings > summary')->tap();
    $page->locator('[data-room-mode="ctf"]')->tap();
    $page->locator('#roomRulesBtn')->tap();
    $rules = $page->locator('#rulesDialog');
    expect_locator($rules, 'to_be_visible');
    if (truth_value($has_safe_area_override)) {
        $bounds = $rules->boundingBox();
        assert_ok((do { my $boolean_value = (($bounds->{'x'} >= 48)); truth_value($boolean_value) ? ((($bounds->{'x'} + $bounds->{'width'}) <= 520)) : $boolean_value }), $bounds);
    }
    $rules->locator('[data-close-dialog]')->tap();
    $fixed_pause_size = evaluate_js($page->locator('#pauseBtn'), 'button => {
            const style = getComputedStyle(button);
            return {width: parseFloat(style.width), height: parseFloat(style.height)};
        }');
    $page->locator('[data-room-mode="infinity"]')->tap();
    $page->locator('#startRoomBtn')->tap();
    expect_locator($page->locator('#infiniteArena'), 'to_be_visible');
    expect_locator($page->locator('#infiniteHeader > #gameHeader'), 'to_be_visible');
    $page->locator('#infiniteScoreboardBtn')->tap();
    $layout = evaluate_js($page, '() => {
            const panel = document.querySelector(\'#infiniteLeaderboardPanel\');
            const summary = document.querySelector(\'#infiniteScoreboardBtn\');
            const list = panel.querySelector(\'#infiniteLeaderboard\');
            list.replaceChildren(...Array.from({length: 10}, () => {
                const row = document.createElement(\'li\');
                const name = document.createElement(\'span\');
                const score = document.createElement(\'strong\');
                name.textContent = \'LLLLLLLLLLLLLLLL\';
                score.textContent = \'-1000\';
                row.append(name, score);
                return row;
            }));
            panel.scrollTop = panel.scrollHeight;
            const fire = document.querySelector(\'#infiniteFire\');
            const hit = element => {
                const r = element.getBoundingClientRect();
                return element.contains(document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2));
            };
            const brand = document.querySelector(\'#gameHeader .brand\').getBoundingClientRect();
            const actions = document.querySelector(\'#gameHeader .header-right\').getBoundingClientRect();
            return {
                fireReachable: hit(fire), summaryReachable: hit(summary), scrollTop: panel.scrollTop,
                top: Math.min(brand.top, actions.top), left: brand.left, right: actions.right
            };
        }');
    assert_ok((do { my $boolean_value = $layout->{'fireReachable'}; truth_value($boolean_value) ? do { my $boolean_value = $layout->{'summaryReachable'}; truth_value($boolean_value) ? (($layout->{'scrollTop'} > 0)) : $boolean_value } : $boolean_value }), $layout);
    if (truth_value($has_safe_area_override)) {
        assert_ok((do { my $boolean_value = (($layout->{'top'} >= 8)); truth_value($boolean_value) ? do { my $boolean_value = (($layout->{'left'} >= 48)); truth_value($boolean_value) ? (($layout->{'right'} <= 520)) : $boolean_value } : $boolean_value }), $layout);
    }
    $page->locator('#infiniteScoreboardBtn')->tap();
    expect_locator($page->locator('#infiniteLeaderboardPanel'), 'not_to_have_attribute', 'open', '');
    $pause_button = $page->locator('#pauseBtn');
    $trigger = $pause_button->boundingBox();
    assert_ok((do { my $boolean_value = (($trigger->{'width'} >= 30)); truth_value($boolean_value) ? (($trigger->{'height'} >= 30)) : $boolean_value }), $trigger);
    assert_ok(((abs(($trigger->{'width'} - $fixed_pause_size->{'width'})) <= 1)), [$trigger, $fixed_pause_size]);
    assert_ok(((abs(($trigger->{'height'} - $fixed_pause_size->{'height'})) <= 1)), [$trigger, $fixed_pause_size]);
    $pause_button->tap();
    $pause = $page->locator('#infinitePauseMenu');
    expect_locator($pause, 'to_be_visible');
    expect_locator($pause->getByText('The battle is paused. Tanks are safe.', {exact => JSON::PP::true}), 'to_be_visible');
    for $name (@{['BACK TO THE BATTLE', 'Controls', 'Exit Infinity']}) {
        $button = $pause->getByRole('button', {name => $name, exact => JSON::PP::true});
        expect_locator($button, 'to_be_in_viewport', {ratio => 1});
        assert_ok((($button->boundingBox()->{'height'} >= 44)), $name);
    }
    if (truth_value($has_safe_area_override)) {
        $bounds = $pause->locator('.screen-card')->boundingBox();
        assert_ok((do { my $boolean_value = (($bounds->{'x'} >= 48)); truth_value($boolean_value) ? ((($bounds->{'x'} + $bounds->{'width'}) <= 520)) : $boolean_value }), $bounds);
        assert_ok((do { my $boolean_value = (($bounds->{'y'} >= 8)); truth_value($boolean_value) ? ((($bounds->{'y'} + $bounds->{'height'}) <= 299)) : $boolean_value }), $bounds);
    }
    $page->locator('#infiniteExit')->tap();
    expect_locator($page->locator('#infiniteArena'), 'to_be_hidden');
    expect_locator($page->locator('.app > #gameHeader'), 'to_be_visible');
    $context->close();
    print(join(" ", 'PASS landscape rules, notch clearance, and Infinity leaderboard and pause layouts'), "\n");
}
sub check_split_infinity {
    my ($browser, $devices, $errors) = @_;
    my ($bottom, $boxes, $context, $control, $divider, $height, $index, $left, $page, $right, $split, $top, $width);
    $index = path($0)->absolute->parent(2)->child('web')->child('index.html');
    $context = main::mobile_context($browser, $devices, 280, 640);
    $page = main::open_page($context, URI::file->new_abs("" . $index)->as_string, $errors);
    evaluate_js($page, 'leqraInfinity.start(\'offline\', {localName: \'Wingmate\'})');
    for my $item (@{[[280, 640, 'stacked'], [568, 320, 'side']]}) {
        my $tuple_118_12 = $item;
        my $width = $tuple_118_12->[0];
        my $height = $tuple_118_12->[1];
        my $split = $tuple_118_12->[2];
        $page->setViewportSize({'width' => $width, 'height' => $height});
        expect_locator($page->locator('#infiniteArena'), 'to_have_attribute', 'data-split', $split);
        main::check_infinity_score_labels($page);
        my $divider = evaluate_js($page, 'split => {
                const canvas = document.getElementById(\'infiniteCanvas\'), c = canvas.getContext(\'2d\');
                const width = canvas.clientWidth, height = canvas.clientHeight;
                const vertical = split === \'side\';
                const x = Math.ceil(width / 2), y = Math.ceil(height / 2);
                const pixel = (px, py) => Array.from(c.getImageData(
                    Math.floor(px * canvas.width / width), Math.floor(py * canvas.height / height), 1, 1
                ).data).slice(0, 3);
                const rgb = color => color.slice(1).match(/../g).map(pair => parseInt(pair, 16));
                const {accent, arena} = leqraInfinityArt.theme;
                return [pixel(x, y), pixel(x + (vertical ? 3 : 0), y + (vertical ? 0 : 3)), rgb(accent), rgb(arena)];
            }', $split);
        assert_ok((value_eq(array_slice($divider, 0, 2), array_slice($divider, 2, undef))), $divider);
        my $boxes = evaluate_js($page, '() => {
                const scores = [...document.querySelectorAll(\'#infiniteKills .infinite-personal-score\')];
                const originalChildren = scores.map(score => [...score.childNodes].map(node => node.cloneNode(true)));
                scores.forEach((score, i) => {
                    score.textContent = `P${i+1} -999 (#99)`;
                });
                const boxes = Object.fromEntries([\'gameHeader\',\'infiniteKills\',\'infiniteCanvas\',\'infiniteFire\',\'infiniteStick\',\'pauseBtn\',\'infiniteLocalLoadout\'].map(id => {
                    const {left,top,right,bottom} = document.getElementById(id).getBoundingClientRect();
                    return [id,[left,top,right,bottom]];
                }));
                scores.forEach((score, i) => score.replaceChildren(...originalChildren[i]));
                return boxes;
            }');
        for my $item (@{[values %{$boxes}]}) {
            my $tuple_148_16 = $item;
            my $left = $tuple_148_16->[0];
            my $top = $tuple_148_16->[1];
            my $right = $tuple_148_16->[2];
            my $bottom = $tuple_148_16->[3];
            assert_ok((do { my $boolean_value = ((0 <= $left) && ($left < $right) && ($right <= ($width + 1))); truth_value($boolean_value) ? ((0 <= $top) && ($top < $bottom) && ($bottom <= ($height + 1))) : $boolean_value }), $boxes);
        }
        my $tuple_150_12 = $boxes->{'pauseBtn'};
        my $left = $tuple_150_12->[0];
        my $top = $tuple_150_12->[1];
        my $right = $tuple_150_12->[2];
        my $bottom = $tuple_150_12->[3];
        assert_ok((do { my $boolean_value = ((($right - $left) >= 30)); truth_value($boolean_value) ? ((($bottom - $top) >= 30)) : $boolean_value }), $boxes);
        my $tuple_152_12 = $boxes->{'infiniteCanvas'};
        $left = $tuple_152_12->[0];
        $top = $tuple_152_12->[1];
        $right = $tuple_152_12->[2];
        $bottom = $tuple_152_12->[3];
        for my $control (@{['infiniteFire', 'infiniteStick']}) {
            if (truth_value((value_eq($split, 'stacked')))) {
                assert_ok((($boxes->[$control]->[3] <= ((($top + $bottom) / 2) + 1))), $boxes);
            } else {
                assert_ok((($boxes->[$control]->[2] <= ((($left + $right) / 2) + 1))), $boxes);
            }
        }
    }
    $context->close();
    print(join(" ", 'PASS Player 2 divider, long scores, and primary touch controls'), "\n");
}
sub check_narrow_online {
    my ($browser, $devices, $url, $errors) = @_;
    my ($context, $github, $links, $page, $positions, $rect, $room);
    $context = main::mobile_context($browser, $devices, 280, 480);
    $page = main::open_page($context, $url, $errors);
    $page->locator('#infinityToggleLabel')->tap();
    $page->locator('#copyInviteBtn')->tap();
    wait_js($page, '() => leqra.getState().online?.connected');
    $page->locator('#startRoomBtn')->tap();
    wait_js($page, '() => leqra.getState().phase === \'playing\'');
    $links = evaluate_js($page, '() => {
            const bounds = selector => {
                const {left, top, right, bottom} = document.querySelector(selector).getBoundingClientRect();
                return {left, top, right, bottom};
            };
            return {github: bounds(\'.github-link\'), room: bounds(\'#roomBtn\'),
                header: bounds(\'#gameHeader\'), viewportWidth: innerWidth};
        }');
    my $tuple_177_8 = [$links->{'github'}, $links->{'room'}];
    $github = $tuple_177_8->[0];
    $room = $tuple_177_8->[1];
    assert_ok((do { my $boolean_value = (($github->{'right'} <= $room->{'left'})); truth_value($boolean_value) ? $boolean_value : do { my $boolean_value = (($room->{'right'} <= $github->{'left'})); truth_value($boolean_value) ? $boolean_value : do { my $boolean_value = (($github->{'bottom'} <= $room->{'top'})); truth_value($boolean_value) ? $boolean_value : (($room->{'bottom'} <= $github->{'top'})) } } }), $links);
    for $rect (@{[$github, $room, $links->{'header'}]}) {
        assert_ok(((0 <= $rect->{'left'}) && ($rect->{'left'} < $rect->{'right'}) && ($rect->{'right'} <= ($links->{'viewportWidth'} + 1))), $links);
    }
    $page->locator('#chatBtn')->tap();
    $positions = evaluate_js($page, '() => {
            const viewport = window.visualViewport;
            // Simulate the short visual viewport left above a soft keyboard.
            Object.defineProperties(viewport, {
                height: {value: 140, configurable: true},
                offsetTop: {value: 35, configurable: true}
            });
            viewport.dispatchEvent(new Event(\'resize\'));
            const bounds = id => {
                const {top, bottom} = document.getElementById(id).getBoundingClientRect();
                return {top, bottom};
            };
            return {panel: bounds(\'chatPanel\'), close: bounds(\'chatCloseBtn\'), input: bounds(\'chatInput\')};
        }');
    assert_ok(!scalar(grep { my $rect = $_; !(((35 <= $rect->{'top'}) && ($rect->{'top'} <= $rect->{'bottom'}) && ($rect->{'bottom'} <= 175))) } @{[values %{$positions}]}), $positions);
    $page->locator('#chatCloseBtn')->tap();
    expect_locator($page->locator('#chatPanel'), 'to_be_hidden');
    $context->close();
    print(join(" ", 'PASS narrow online header and chat with a short keyboard viewport'), "\n");
}
sub check_mobile_header {
    my ($browser, $devices, $url, $errors, $has_safe_area_override, $screenshots) = @_;
    my ($cdp, $check_header, $context, $page);
    $context = main::mobile_context($browser, $devices, 390, 844);
    $context->addInitScript('localStorage.setItem(\'leqra.feedback.v1\', JSON.stringify({fps: true}))');
    $page = main::open_page($context, $url, $errors);
    expect_locator($page->locator('#infinityPreviewScores'), 'to_be_visible');
    main::check_infinity_score_labels($page, '#infinityPreviewScores');
    $page->locator('#infinityToggleLabel')->tap();
    $page->locator('#copyInviteBtn')->tap();
    wait_js($page, '() => leqra.getState().online?.connected');
    $cdp = (truth_value($has_safe_area_override) ? $context->newCDPSession($page) : undef);
    $check_header = sub {
        my ($name) = @_;
        my ($button, $geometry, $header, $height, $indicator, $insets, $link, $part, $performance_label, $width);
        for my $item (@{[[320, 568], [390, 844], [440, 956], [568, 320], [844, 390]]}) {
            my $tuple_214_16 = $item;
            my $width = $tuple_214_16->[0];
            my $height = $tuple_214_16->[1];
            $page->setViewportSize({'width' => $width, 'height' => $height});
            wait_js($page, 'landscape => document.body.classList.contains(\'touch-landscape\') === landscape', (($width > $height)), {});
            my $insets = (truth_value((($height > $width))) ? {'top' => 47, 'right' => 0, 'bottom' => 34, 'left' => 0} : {'top' => 8, 'right' => 48, 'bottom' => 21, 'left' => 48});
            if (truth_value($cdp)) {
                $cdp->send('Emulation.setSafeAreaInsetsOverride', {'insets' => $insets});
            } else {
                $insets = {map { $_ => 0 } keys %{$insets}};
            }
            evaluate_js($page, '() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))');
            my $geometry = evaluate_js($page, 'name => {
                    const box = element => {
                        const {left, top, right, bottom, width, height} = element.getBoundingClientRect();
                        return {left, top, right, bottom, width, height};
                    };
                    const header = document.querySelector(\'#gameHeader\');
                    const link = header.querySelector(\'.github-link\');
                    const hit = element => {
                        const rect = element.getBoundingClientRect();
                        return element.contains(document.elementFromPoint(
                            rect.left + rect.width / 2, rect.top + rect.height / 2));
                    };
                    return {
                        header: box(header), brand: box(header.querySelector(\'.brand\')),
                        brandMark: box(header.querySelector(\'.brand-mark\')),
                        brandName: box(header.querySelector(\'.brand-name\')),
                        link: box(link), icon: box(link.querySelector(\'svg\')), version: box(link.querySelector(\'span\')),
                        buttons: [...header.querySelectorAll(\'.header-right > button\')]
                            .filter(button => button.getClientRects().length).map(button => ({id: button.id, hit: hit(button), ...box(button)})),
                        linkHit: hit(link),
                        arena: box(document.querySelector(name === \'infinity\' ? \'#infiniteStatusbar\' : \'.arena-shell\')),
                        scrollX, scrollWidth: document.documentElement.scrollWidth, viewportWidth: innerWidth
                    };
                }', $name);
            assert_ok((do { my $boolean_value = (value_eq($geometry->{'scrollX'}, 0)); truth_value($boolean_value) ? (($geometry->{'scrollWidth'} <= $width)) : $boolean_value }), $geometry);
            my $header = $geometry->{'header'};
            assert_ok((do { my $boolean_value = (($header->{'top'} >= $insets->{'top'})); truth_value($boolean_value) ? (($geometry->{'arena'}->{'top'} >= ($header->{'bottom'} - 1))) : $boolean_value }), $geometry);
            assert_ok((($geometry->{'icon'}->{'width'} >= 14)), $geometry);
            assert_ok($geometry->{'linkHit'}, $geometry);
            if (truth_value($geometry->{'brandMark'}->{'width'})) {
                assert_ok((($geometry->{'brandMark'}->{'right'} <= $geometry->{'brandName'}->{'left'})), $geometry);
            }
            my $link = $geometry->{'link'};
            for my $part (@{[$geometry->{'icon'}, $geometry->{'version'}]}) {
                assert_ok((($link->{'left'} <= $part->{'left'}) && ($part->{'left'} < $part->{'right'}) && ($part->{'right'} <= $link->{'right'})), $geometry);
                assert_ok((($link->{'top'} <= $part->{'top'}) && ($part->{'top'} < $part->{'bottom'}) && ($part->{'bottom'} <= $link->{'bottom'})), $geometry);
            }
            for my $button (@{$geometry->{'buttons'}}) {
                assert_ok($button->{'hit'}, $geometry);
                assert_ok((($header->{'top'} <= $button->{'top'}) && ($button->{'top'} < $button->{'bottom'}) && ($button->{'bottom'} <= $header->{'bottom'})), $geometry);
                assert_ok((do { my $boolean_value = (($button->{'left'} >= $insets->{'left'})); truth_value($boolean_value) ? (($button->{'right'} <= ($width - $insets->{'right'}))) : $boolean_value }), $geometry);
                assert_ok((($button->{'height'} >= 30)), $geometry);
            }
            assert_ok((((max(@{[map { my $button = $_; $button->{'height'} } @{$geometry->{'buttons'}}]}) - min(@{[map { my $button = $_; $button->{'height'} } @{$geometry->{'buttons'}}]})) <= 1)), $geometry);
            if (truth_value((value_eq($name, 'infinity')))) {
                main::check_infinity_viewport($page, $width, $height, $insets, (($width <= 600)));
            }
            my $indicator = (truth_value((value_eq($name, 'infinity'))) ? '#infiniteFPSIndicator' : '#fpsIndicator');
            my $performance_label = (truth_value((value_eq($name, 'menu'))) ? '^fps: \\d+(?:, ping: \\d+ ms)?$' : '^fps: \\d+, ping: (?:\\d+ ms|—)$');
            expect_locator($page->locator($indicator), 'to_have_text', regex($performance_label));
            if (truth_value($screenshots)) {
                $page->screenshot({path => format_value($screenshots->child(($name . '-header-' . $width . 'x' . $height . '.png')))});
            }
        }
    };
    $check_header->('menu');
    $page->locator('#startRoomBtn')->tap();
    wait_js($page, '() => leqra.getState().phase === \'playing\'');
    $check_header->('fixed');
    $page->locator('#pauseBtn')->tap();
    $page->locator('#returnRoomBtn')->tap();
    $page->getByRole('dialog', {name => 'End this match?', exact => JSON::PP::true})->getByRole('button', {name => 'END MATCH', exact => JSON::PP::true})->tap();
    expect_locator($page->locator('#roomScreen'), 'to_be_visible');
    if (truth_value((!truth_value(evaluate_js($page->locator('#roomSettings'), 'element => element.open'))))) {
        $page->locator('#roomSettings > summary')->tap();
    }
    $page->locator('[data-room-mode="infinity"]')->tap();
    $page->locator('#startRoomBtn')->tap();
    expect_locator($page->locator('#infiniteArena'), 'to_be_visible');
    $check_header->('infinity');
    $context->close();
    print(join(" ", 'PASS mobile menu, fixed, and Infinity headers, source icon/version, aligned actions, and safe areas'), "\n");
}
sub check_infinity_viewport {
    my ($page, $width, $height, $insets, $score_below_fps) = @_;
    my ($arena, $canvas, $child, $footer, $fps, $geometry, $index, $key, $other, $other_key, $rect, $scores, $stage, $statusbar, $visible);
    $score_below_fps //= JSON::PP::false;
    $geometry = evaluate_js($page, '() => {
        const box = selector => {
            const element = typeof selector === \'string\' ? document.querySelector(selector) : selector;
            const {left, top, right, bottom, height, width} = element.getBoundingClientRect();
            return {left, top, right, bottom, height, width};
        };
        return {
            arena: box(\'#infiniteArena\'), stage: box(\'.infinite-stage\'),
            canvas: box(\'#infiniteCanvas\'), footer: box(\'.infinite-underbar\'),
            loadouts: box(\'#infiniteLoadouts\'), primary: box(\'#infinitePilotLoadout1\'),
            statusbar: box(\'#infiniteStatusbar\'), scores: box(\'#infiniteKills\'),
            fps: box(\'#infiniteFPSIndicator\'), title: box(\'#infiniteStatusbar .arena-title\'),
            titleChildren: [...document.querySelector(\'#infiniteStatusbar .arena-title\').children]
                .filter(element => element.getClientRects().length).map(box),
            scoreboard: box(\'#infiniteScoreboardBtn\'),
            viewport: {width: innerWidth, height: innerHeight}
        };
    }');
    my $tuple_315_4 = [map { my $key = $_; $geometry->[$key] } @{['arena', 'stage', 'canvas', 'footer']}];
    $arena = $tuple_315_4->[0];
    $stage = $tuple_315_4->[1];
    $canvas = $tuple_315_4->[2];
    $footer = $tuple_315_4->[3];
    assert_ok((do { my $boolean_value = ((abs($arena->{'top'}) <= 1)); truth_value($boolean_value) ? ((abs(($arena->{'bottom'} - $height)) <= 1)) : $boolean_value }), $geometry);
    assert_ok((do { my $boolean_value = ((abs($arena->{'left'}) <= 1)); truth_value($boolean_value) ? ((abs(($arena->{'right'} - $width)) <= 1)) : $boolean_value }), $geometry);
    assert_ok(((abs(($stage->{'bottom'} - $footer->{'top'})) <= 1)), $geometry);
    assert_ok((do { my $boolean_value = ((abs(($canvas->{'bottom'} - $stage->{'bottom'})) <= 1)); truth_value($boolean_value) ? (($canvas->{'height'} > 0)) : $boolean_value }), $geometry);
    assert_ok(((abs(($footer->{'bottom'} - $arena->{'bottom'})) <= 1)), $geometry);
    assert_ok(((abs(($geometry->{'loadouts'}->{'height'} - $geometry->{'primary'}->{'height'})) <= 1)), $geometry);
    assert_ok((($footer->{'height'} <= (($geometry->{'loadouts'}->{'height'} + max(6, $insets->{'bottom'})) + 10))), $geometry);
    main::check_infinity_score_labels($page);
    my $tuple_326_4 = [map { my $key = $_; $geometry->[$key] } @{['scores', 'fps', 'statusbar']}];
    $scores = $tuple_326_4->[0];
    $fps = $tuple_326_4->[1];
    $statusbar = $tuple_326_4->[2];
    for $child (@{$geometry->{'titleChildren'}}) {
        assert_ok((($geometry->{'title'}->{'left'} <= $child->{'left'}) && ($child->{'left'} < $child->{'right'}) && ($child->{'right'} <= ($geometry->{'title'}->{'right'} + 0.5))), $geometry);
    }
    $visible = ['scores', 'title', 'scoreboard', @{(truth_value($fps->{'width'}) ? ['fps'] : [])}];
    for $key (@{$visible}) {
        $rect = $geometry->[$key];
        assert_ok((($statusbar->{'left'} <= $rect->{'left'}) && ($rect->{'left'} < $rect->{'right'}) && ($rect->{'right'} <= ($statusbar->{'right'} + 1))), $geometry);
        assert_ok((($statusbar->{'top'} <= $rect->{'top'}) && ($rect->{'top'} < $rect->{'bottom'}) && ($rect->{'bottom'} <= ($statusbar->{'bottom'} + 1))), $geometry);
    }
    for my $item (@{[map { [$_, $visible->[$_]] } 0 .. $#{$visible}]}) {
        my $tuple_334_8 = $item;
        my $index = $tuple_334_8->[0];
        my $key = $tuple_334_8->[1];
        my $rect = $geometry->[$key];
        for my $other_key (@{array_slice($visible, ($index + 1), undef)}) {
            my $other = $geometry->[$other_key];
            assert_ok((do { my $boolean_value = (($rect->{'right'} <= ($other->{'left'} + 0.5))); truth_value($boolean_value) ? $boolean_value : do { my $boolean_value = (($other->{'right'} <= ($rect->{'left'} + 0.5))); truth_value($boolean_value) ? $boolean_value : do { my $boolean_value = (($rect->{'bottom'} <= ($other->{'top'} + 0.5))); truth_value($boolean_value) ? $boolean_value : (($other->{'bottom'} <= ($rect->{'top'} + 0.5))) } } }), $geometry);
        }
    }
    if (truth_value($score_below_fps)) {
        assert_ok((($scores->{'top'} >= ($fps->{'bottom'} - 1))), $geometry);
        if (truth_value((($width >= 390)))) {
            assert_ok(((abs(((($scores->{'left'} + $scores->{'right'}) / 2) - (($fps->{'left'} + $fps->{'right'}) / 2))) <= 1)), $geometry);
        }
    }
    return $geometry;
}
sub check_infinity_score_labels {
    my ($page, $selector) = @_;
    my ($button, $index, $row, $scores);
    $selector //= '#infiniteKills';
    $button = (truth_value((value_eq($selector, '#infinityPreviewScores'))) ? '#infinityPreviewScoreboardBtn' : '#infiniteScoreboardBtn');
    expect_locator($page->locator($button), 'to_be_visible');
    expect_locator($page->locator($button), 'to_have_text', 'LEADERBOARD', {useInnerText => JSON::PP::true});
    $scores = evaluate_js($page, 'selector => ({
        touch: document.body.classList.contains(\'touch-ui\'),
        rows: [...document.querySelectorAll(selector + \' .infinite-personal-score\')].map(row => ({
            visible: row.innerText.trim(), identity: row.getAttribute(\'aria-label\')
        }))
    })', $selector);
    assert_ok($scores->{'rows'}, $scores);
    for my $item (@{[map { [$_, $scores->{'rows'}->[$_]] } 0 .. $#{$scores->{'rows'}}]}) {
        my $tuple_359_8 = $item;
        my $index = $tuple_359_8->[0];
        my $row = $tuple_359_8->[1];
        assert_ok((contains_value($row->{'identity'}, ('(P' . ($index + 1) . ')'))), $scores);
        if (truth_value($scores->{'touch'})) {
            assert_ok(match_re('score: -?\\d+, rank: #\\d+', $row->{'visible'}, 1), $scores);
            assert_ok((substr($row->{'identity'}, -length($row->{'visible'})) eq $row->{'visible'}), $scores);
        } else {
            assert_ok((value_eq($row->{'visible'}, $row->{'identity'})), $scores);
            assert_ok(match_re('.+ \\(P\\d\\): score: -?\\d+, rank: #\\d+', $row->{'visible'}, 1), $scores);
        }
    }
}
sub check_network_ping {
    my ($browser, $devices, $url, $errors, $screenshots) = @_;
    my ($context, $delay_preview_response, $height, $page, $width);
    $context = main::mobile_context($browser, $devices, 390, 844, {'service_workers' => 'block'});
    $context->addInitScript(q{(() => {
        const request = window.fetch.bind(window);
        window.fetch = async (...args) => {
            const response = await request(...args);
            if (new URL(args[0] instanceof Request ? args[0].url : args[0], location.href).pathname === '/api/infinity')
                await new Promise(resolve => setTimeout(resolve, 240));
            return response;
        };
    })();});
    $context->addInitScript('(() => {
            localStorage.setItem(\'leqra.feedback.v1\', JSON.stringify({fps: true}));
            // Delay real server pongs without changing their echoed timestamps.
            // A rendering frame interval cannot satisfy the resulting RTT check.
            const add = WebSocket.prototype.addEventListener;
            WebSocket.prototype.addEventListener = function(type, listener, options) {
                if (type !== \'message\' || !this.url.includes(\'/ws/infinite\'))
                    return add.call(this, type, listener, options);
                return add.call(this, type, function(event) {
                    let packet;
                    try { packet = JSON.parse(event.data); } catch (_) {}
                    const deliver = () => listener.call(this, event);
                    if (packet?.type === \'pong\') {
                        setTimeout(() => {
                            window.__delayedInfinityPongs = (window.__delayedInfinityPongs || 0) + 1;
                            deliver();
                        }, 240);
                    } else deliver();
                }, options);
            };
        })();');
    $page = main::open_page($context, $url, $errors);
    expect_locator($page->locator('#infinityPreviewOnlineCount'), 'to_have_text', regex('^\\d+ online$'));
    expect_locator($page->locator('#infiniteArena'), 'to_be_hidden');
    wait_js($page, '() => {
            const match = document.querySelector(\'#fpsIndicator\').innerText.match(/ping: (\\d+) ms/);
            return match && Number(match[1]) >= 220;
        }', undef, {timeout => 10000});
    if (truth_value($screenshots)) {
        $page->screenshot({path => format_value($screenshots->child('preview-ping-390x844.png'))});
    }
    $page->locator('#startRoomBtn')->tap();
    expect_locator($page->locator('#infiniteArena'), 'to_be_visible');
    wait_js($page, '() => {
            const match = document.querySelector(\'#infiniteFPSIndicator\').innerText.match(/ping: (\\d+) ms/);
            return window.__delayedInfinityPongs > 0 && match && Number(match[1]) >= 220;
        }', undef, {timeout => 10000});
    expect_locator($page->locator('#infiniteFPSIndicator'), 'to_have_text', regex('^fps: \\d+, ping: \\d+ ms$'));
    for my $item (@{[[320, 568], [390, 844], [440, 956], [568, 320], [844, 390]]}) {
        my $tuple_413_12 = $item;
        my $width = $tuple_413_12->[0];
        my $height = $tuple_413_12->[1];
        $page->setViewportSize({'width' => $width, 'height' => $height});
        wait_js($page, 'landscape => document.body.classList.contains(\'touch-landscape\') === landscape', (($width > $height)), {});
        $Leqra::Browser::HANDLE->await($page->waitForTimeout(180));
        main::check_infinity_viewport($page, $width, $height, {map { $_ => 0 } keys %{['top', 'right', 'bottom', 'left']}}, (($width <= 600)));
        if (truth_value($screenshots)) {
            $page->screenshot({path => format_value($screenshots->child(('public-ping-' . $width . 'x' . $height . '.png')))});
        }
    }
    evaluate_js($page, '() => { leqraInfinity.close(); leqraInfinity.start(\'offline\'); }');
    expect_locator($page->locator('#infiniteFPSIndicator'), 'to_have_text', regex('^fps: \\d+$'));
    main::check_infinity_score_labels($page);
    $context->close();
    print(join(" ", 'PASS preview HTTP ping before joining, Public Infinity round-trip ping, and offline ping omission'), "\n");
}
sub check_pause_scorecard {
    my ($browser, $devices, $url, $errors, $screenshots) = @_;
    my ($containment, $context, $final_row, $geometry, $height, $options, $page, $panel, $restored, $width);
    for my $item (@{[[1280, 900], [390, 844]]}) {
        my $tuple_429_8 = $item;
        my $width = $tuple_429_8->[0];
        my $height = $tuple_429_8->[1];
        my $options = {'viewport' => {'width' => $width, 'height' => $height}};
        if (truth_value((($width < 760)))) {
            @{$options}{keys %{{'has_touch' => JSON::PP::true, 'is_mobile' => JSON::PP::true, 'user_agent' => $devices->{'iPhone SE'}->{'userAgent'}}}} = values %{{'has_touch' => JSON::PP::true, 'is_mobile' => JSON::PP::true, 'user_agent' => $devices->{'iPhone SE'}->{'userAgent'}}};
        }
        my $context = $browser->newContext({%{$options}});
        my $page = main::open_page($context, $url, $errors);
        expect_locator($page->locator('#infinityPreviewScores'), 'to_be_visible');
        main::check_infinity_score_labels($page, '#infinityPreviewScores');
        evaluate_js($page, '() => leqraInfinity.start(\'offline\')');
        main::check_infinity_score_labels($page);
        $page->locator('#pauseBtn')->click();
        my $panel = $page->locator('#infinitePauseSidebar #infiniteLeaderboardPanel');
        expect_locator($panel, 'to_be_visible');
        evaluate_js($panel->locator('#infiniteLeaderboard'), 'list => {
                list.replaceChildren(...Array.from({length: 12}, (_, i) => {
                    const row = document.createElement(\'li\'), name = document.createElement(\'span\');
                    const score = document.createElement(\'strong\');
                    row.value = i < 10 ? i + 1 : i === 10 ? 40 : 75;
                    name.textContent = i >= 10 ? `LLLLLLLLLLLLLLLL (P${i - 9})` : `Pilot ${i + 1}`;
                    score.textContent = i >= 10 ? \'-12345678\' : String(1200 - i);
                    row.style.setProperty(\'--tank-color\', \'#32c5ff\');
                    if (i >= 10) {
                        row.className = \'off-board-local\';
                        row.dataset.local = i === 10 ? \'p1\' : \'p2\';
                        row.style.setProperty(\'--local-highlight\', \'#32c5ff\');
                    }
                    row.append(name, score);
                    return row;
                }));
            }');
        $panel->scrollIntoViewIfNeeded();
        my $geometry = evaluate_js($panel, 'panel => {
                const summary = panel.querySelector(\'summary\'), rect = panel.getBoundingClientRect();
                const style = getComputedStyle(panel), titleStyle = getComputedStyle(summary);
                return {
                    overflow: style.overflow, summaryPosition: titleStyle.position,
                    border: style.borderTopWidth, radius: style.borderTopLeftRadius,
                    summaryRadius: titleStyle.borderTopLeftRadius,
                    markerPosition: getComputedStyle(panel.querySelector(\'li\')).listStylePosition,
                    cornersPaintedBySummary: [rect.left + 2, rect.right - 2].map(x =>
                        summary.contains(document.elementFromPoint(x, rect.top + 2))),
                    width: rect.width, scrollWidth: panel.scrollWidth
                };
            }');
        assert_ok((do { my $boolean_value = (value_eq($geometry->{'overflow'}, 'visible')); truth_value($boolean_value) ? (value_eq($geometry->{'summaryPosition'}, 'static')) : $boolean_value }), $geometry);
        assert_ok((do { my $boolean_value = (value_eq($geometry->{'border'}, '1px')); truth_value($boolean_value) ? (value_eq($geometry->{'radius'}, '8px')) : $boolean_value }), $geometry);
        assert_ok((do { my $boolean_value = (value_eq($geometry->{'summaryRadius'}, '7px')); truth_value($boolean_value) ? (value_eq($geometry->{'markerPosition'}, 'inside')) : $boolean_value }), $geometry);
        if (truth_value((value_eq($browser->browserType()->name(), 'chromium')))) {
            assert_ok((!truth_value(scalar(grep { $_ } @{$geometry->{'cornersPaintedBySummary'}}))), $geometry);
        }
        assert_ok((($geometry->{'scrollWidth'} <= $geometry->{'width'})), $geometry);
        my $final_row = $panel->locator('li')->last();
        $final_row->scrollIntoViewIfNeeded();
        expect_locator($final_row, 'to_be_in_viewport', {ratio => 1});
        my $containment = evaluate_js($panel, 'panel => {
                const rect = panel.getBoundingClientRect();
                const contained = [...panel.querySelectorAll(\'li, p\')].every(child => {
                    const r = child.getBoundingClientRect();
                    return r.left >= rect.left && r.right <= rect.right && r.bottom <= rect.bottom;
                });
                const separate = [...panel.querySelectorAll(\'li\')].every(row => {
                    const score = row.querySelector(\'strong\').getBoundingClientRect();
                    return [...row.querySelector(\'span\').getClientRects()].every(name =>
                        name.right <= score.left + .5 || score.right <= name.left + .5 ||
                        name.bottom <= score.top + .5 || score.bottom <= name.top + .5);
                });
                return contained && separate;
            }');
        assert_ok($containment, 'containment');
        if (truth_value($screenshots)) {
            $panel->screenshot({path => format_value($screenshots->child(('pause-scorecard-' . $width . 'x' . $height . '.png')))});
        }
        $page->locator('#infiniteResumeBtn')->click();
        my $restored = $page->locator('.infinite-stage > #infiniteLeaderboardPanel');
        expect_locator($restored, 'to_be_attached');
        expect_locator($restored, 'not_to_have_attribute', 'open', '');
        $page->locator('#infiniteScoreboardBtn')->click();
        expect_locator($restored, 'to_be_visible');
        $context->close();
    }
    print(join(" ", 'PASS Infinity pause scorecard corners, complete border, and arena restoration'), "\n");
}
sub check_standalone_header {
    my ($browser, $devices, $url, $errors, $screenshots) = @_;
    my ($action, $cdp, $chromium, $context, $geometry, $height, $hidden, $insets, $mode, $name, $page, $safe_area_css, $shown, $ua, $width);
    $ua = replace_re(' (?:Version|Safari)/[\\d.]+', '', $devices->{'iPhone 13'}->{'userAgent'});
    $context = $browser->newContext({viewport => {'width' => 390, 'height' => 844}, hasTouch => JSON::PP::true, isMobile => JSON::PP::true, userAgent => $ua, serviceWorkers => 'block'});
    $context->addInitScript('(() => {
            localStorage.setItem(\'leqra.feedback.v1\', JSON.stringify({fps: true}));
            Object.defineProperty(navigator, \'standalone\', {get: () => true});
            const match = window.matchMedia.bind(window);
            window.matchMedia = query => {
                const result = match(query);
                if (query !== \'(display-mode: standalone)\') return result;
                return new Proxy(result, {get(target, key) {
                    if (key === \'matches\') return true;
                    const value = Reflect.get(target, key, target);
                    return typeof value === \'function\' ? value.bind(target) : value;
                }});
            };
        })();');
    $chromium = (value_eq($browser->browserType()->name(), 'chromium'));
    if (truth_value((!truth_value($chromium)))) {
        my $index = path($0)->absolute->parent(2)->child('web/index.html');
        my ($asset) = $index->slurp_utf8 =~ /href="(assets\/v[^\/"]+\/style\.css)"/;
        my $css = $index->parent->child($asset)->slurp_utf8;
        for my $side (qw(top right bottom left)) {
            $css = replace_text($css, "env(safe-area-inset-$side)", "var(--test-safe-$side, 0px)");
        }
        fixture_response($context, $url, $asset, $css, 'text/css');
    }
    $page = main::open_page($context, $url, $errors);
    $cdp = (truth_value($chromium) ? $context->newCDPSession($page) : undef);
    $page->locator('#infinityToggleLabel')->tap();
    $page->locator('#copyInviteBtn')->tap();
    wait_js($page, '() => leqra.getState().online?.connected');
    $page->locator('#startRoomBtn')->tap();
    wait_js($page, '() => leqra.getState().phase === \'playing\'');
    for $mode (@{['fixed', 'infinity']}) {
        if (truth_value((value_eq($mode, 'infinity')))) {
            $page->locator('#pauseBtn')->tap();
            $page->locator('#returnRoomBtn')->tap();
            $page->getByRole('dialog', {name => 'End this match?', exact => JSON::PP::true})->getByRole('button', {name => 'END MATCH', exact => JSON::PP::true})->tap();
            expect_locator($page->locator('#roomScreen'), 'to_be_visible');
            if (truth_value((!truth_value(evaluate_js($page->locator('#roomSettings'), 'element => element.open'))))) {
                $page->locator('#roomSettings > summary')->tap();
            }
            $page->locator('[data-room-mode="infinity"]')->tap();
            $page->locator('#startRoomBtn')->tap();
            expect_locator($page->locator('#infiniteArena'), 'to_be_visible');
        }
        for my $item (@{[['narrow', 320, 568, {'top' => 47, 'right' => 0, 'bottom' => 34, 'left' => 0}], ['portrait', 390, 844, {'top' => 47, 'right' => 0, 'bottom' => 34, 'left' => 0}], ['screenshot', 440, 956, {'top' => 62, 'right' => 0, 'bottom' => 34, 'left' => 0}], ['landscape', 844, 390, {'top' => 0, 'right' => 47, 'bottom' => 21, 'left' => 47}], ['restored', 390, 844, {'top' => 47, 'right' => 0, 'bottom' => 34, 'left' => 0}]]}) {
            my $tuple_561_16 = $item;
            my $name = $tuple_561_16->[0];
            my $width = $tuple_561_16->[1];
            my $height = $tuple_561_16->[2];
            my $insets = $tuple_561_16->[3];
            $page->setViewportSize({'width' => $width, 'height' => $height});
            if (truth_value($cdp)) {
                $cdp->send('Emulation.setSafeAreaInsetsOverride', {'insets' => $insets});
            } else {
                evaluate_js($page, 'insets => {
                        for (const [side, value] of Object.entries(insets))
                            document.documentElement.style.setProperty(\'--test-safe-\' + side, value + \'px\');
                    }', $insets);
            }
            evaluate_js($page, '() => {
                    window.dispatchEvent(new PageTransitionEvent(\'pageshow\', {persisted: true}));
                    window.dispatchEvent(new Event(\'focus\'));
                    document.dispatchEvent(new Event(\'visibilitychange\'));
                    visualViewport.dispatchEvent(new Event(\'resize\'));
                }');
            wait_js($page, 'landscape => document.body.classList.contains(\'touch-landscape\') === landscape', (($width > $height)), {});
            $Leqra::Browser::HANDLE->await($page->waitForTimeout(180));
            my $geometry = evaluate_js($page, '() => {
                    const box = element => {
                        const {left, top, right, bottom, height} = element.getBoundingClientRect();
                        return {left, top, right, bottom, height};
                    };
                    const hit = element => {
                        const rect = element.getBoundingClientRect();
                        return element.contains(document.elementFromPoint(
                            rect.left + rect.width / 2, rect.top + rect.height / 2));
                    };
                    const header = document.querySelector(\'#gameHeader\');
                    return {
                        standalone: navigator.standalone && matchMedia(\'(display-mode: standalone)\').matches,
                        app: box(document.querySelector(\'.app\')), header: box(header), scrollX, scrollY,
                        actions: [...header.querySelectorAll(\'.github-link, .header-right > button\')]
                            .filter(button => button.getClientRects().length).map(button => ({
                                id: button.id || button.className, hit: hit(button), ...box(button)
                            }))
                    };
                }');
            assert_ok((do { my $boolean_value = $geometry->{'standalone'}; truth_value($boolean_value) ? (value_eq($geometry->{'scrollX'}, $geometry->{'scrollY'}) && value_eq($geometry->{'scrollY'}, 0)) : $boolean_value }), $geometry);
            assert_ok(((abs(($geometry->{'app'}->{'bottom'} - $height)) <= 1)), $geometry);
            assert_ok((($geometry->{'header'}->{'top'} >= $insets->{'top'})), $geometry);
            for my $action (@{$geometry->{'actions'}}) {
                assert_ok($action->{'hit'}, $geometry);
                assert_ok((($insets->{'top'} <= $action->{'top'}) && ($action->{'top'} < $action->{'bottom'}) && ($action->{'bottom'} <= $geometry->{'header'}->{'bottom'})), $geometry);
                assert_ok((($insets->{'left'} <= $action->{'left'}) && ($action->{'left'} < $action->{'right'}) && ($action->{'right'} <= ($width - $insets->{'right'}))), $geometry);
            }
            if (truth_value((value_eq($mode, 'infinity')))) {
                my $shown = main::check_infinity_viewport($page, $width, $height, $insets, (($width <= 600)));
                evaluate_js($page, '() => {
                        const checkbox = document.querySelector(\'#showFPS\');
                        checkbox.checked = false;
                        checkbox.dispatchEvent(new Event(\'change\'));
                    }');
                my $hidden = main::check_infinity_viewport($page, $width, $height, $insets);
                assert_ok((($hidden->{'statusbar'}->{'height'} <= ($shown->{'statusbar'}->{'height'} + 1))), [$shown, $hidden]);
                assert_ok((($hidden->{'stage'}->{'height'} >= ($shown->{'stage'}->{'height'} - 1))), [$shown, $hidden]);
                evaluate_js($page, '() => {
                        const checkbox = document.querySelector(\'#showFPS\');
                        checkbox.checked = true;
                        checkbox.dispatchEvent(new Event(\'change\'));
                    }');
            }
            if (truth_value($screenshots)) {
                $page->screenshot({path => format_value($screenshots->child(('standalone-' . $mode . '-header-' . $name . '.png')))});
            }
        }
    }
    $context->close();
    print(join(" ", 'PASS simulated standalone status bar, safe areas, rotation, and foreground restoration'), "\n");
}
unless (caller) {
    $parser = {};
    $args = do { my %args = ('url' => 'http://localhost:8080', 'engine' => 'chromium', 'screenshots' => undef); my $help; GetOptions('engine=s' => \$args{'engine'}, 'screenshots=s' => \$args{'screenshots'}, 'help|h' => \$help) or die 'Usage: perl mobile_layout_browser.pl url --engine --screenshots
'; if ($help) { print 'Usage: perl mobile_layout_browser.pl url --engine --screenshots
'; exit 0; } $args{'url'} = shift @ARGV if @ARGV; die 'invalid engine
' if defined($args{'engine'}) && !grep { value_eq($_, $args{'engine'}) } @{['chromium', 'webkit']}; $args{'screenshots'} = path($args{'screenshots'}) if defined($args{'screenshots'}); \%args; };
    if (truth_value($args->{'screenshots'})) {
        $args->{'screenshots'}->mkpath;
    }
    $playwright = start_playwright();
    if (truth_value((value_eq($args->{'engine'}, 'chromium')))) {
        $browser = $playwright->launch(type => 'chrome', chromiumSandbox => JSON::PP::true);
    } else {
        $browser = $playwright->launch(type => 'webkit');
    }
    $errors = [];
    eval {
        main::check_landscape($browser, browser_devices(), $errors, (value_eq($args->{'engine'}, 'chromium')));
        main::check_split_infinity($browser, browser_devices(), $errors);
        main::check_narrow_online($browser, browser_devices(), $args->{'url'}, $errors);
        main::check_mobile_header($browser, browser_devices(), $args->{'url'}, $errors, (value_eq($args->{'engine'}, 'chromium')), $args->{'screenshots'});
        main::check_pause_scorecard($browser, browser_devices(), $args->{'url'}, $errors, $args->{'screenshots'});
        main::check_standalone_header($browser, browser_devices(), $args->{'url'}, $errors, $args->{'screenshots'});
        main::check_network_ping($browser, browser_devices(), $args->{'url'}, $errors, $args->{'screenshots'});
        assert_ok((!truth_value($errors)), $errors);
    1;
    };
    my $caught_error = $@;
    $browser->close();
    die $caught_error if $caught_error;
}
