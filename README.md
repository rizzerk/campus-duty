# Campus Duty

A registrar window sim set during enrollment season at the University of San Carlos. You play a Student Assistant (SA) at Window 3 of the Registrar's Office. Students line up with problems; you check their papers against their ISMIS record, then fix the problem yourself, send them to the right office, or turn them away. Make the wrong call and they come back angrier.


| | |
| --- | --- |
| Genre | Inspection and routing sim with light story |
| Art | 2D pixel-art UI with layered, randomized student portraits |
| Engine | Godot 4, GDScript |
| Platform | PC, mouse and keyboard |
| Players | Single-player |
| Length | 10 in-game days, about 6 minutes each (roughly 1 hour) |
| Team | 3 people, 4 weeks (Game Development course final project) |
| Inspirations | Papers, Please; every Carolinian who has stood in the enrollment line |

## The core loop

Each day:

1. **Season calendar.** Pick up where you left off and see what's new today.
2. **Morning memo.** Ma'am Lorna, the University Registrar, posts today's rules. Day 1 includes full onboarding guidance; Day 2+ never repeats the tutorial, showing the daily office bulletin (enrollment schedule, announcements, policy changes, and expected events) before jumping straight into the shift.
3. **The shift.** Students come to the window one at a time while daily events and random spot inspections unfold:
   - **Triage** the line. Call priority students (graduating, PWD) out of turn.
   - **Inspect.** Compare the student's papers with their ISMIS record and flag any mismatch.
   - **Decide.** Fix it at the window, route them (Cashier, Consultation, Dean's office), put them on the Hold bench, or reject them.
4. **Day report.** Stars, mistakes, a "Because of you" list of consequences, and the supervisor's spot check.
5. **Desk upgrades.** Spend stars, then go on to the next day.

If the line's patience hits zero, Ma'am Lorna takes over and the shift ends early.

## Key mechanics

**Papers vs record.** Students hand over forms (add/drop form, consultation slip, receipt, assessment slip, ID). You click a field on the paper and the matching field on screen to flag a mismatch: a fake signature, a failed prerequisite, a wrong amount, a mismatched ID number.

**Section picker puzzle.** When a section is full, a weekly timetable opens. Pick an open section that doesn't clash with the student's other classes. On open market day, slots drain in real time while you choose.

**Live offices and the Hold bench.** Each office has a live status (advisers on break, long cashier line, Dean only handles overloads). Sending someone to a closed office is a wasted trip. Hold parks a student on a bench (3 seats) until the office reopens.

**Rule bending and spot checks.** Some students push you to break the rules: the Dean's "nephew," sob stories, the occasional merienda. Bending is fast and makes that student happy, but the line sees it (patience drops). Instead of repeating tutorials on Day 2+, Ma'am Lorna conducts random live mid-shift spot checks—praising accurate streaks, warning against favors or false alarms, and citing specific rules you missed—followed by her formal end-of-day audit from Day 4 onward.

**Student traits and personalities.** Traits change how a student behaves, never the correct answer, and each has a visual tell on the portrait. Alongside concise routine lines, students also roll distinct personalities (`nervous`, `confident`, `rude`, `funny`, `lost`, `friendly`, `panicked`, `overprepared`):

| Trait | Effect | Visual tell |
| --- | --- | --- |
| Impatient | Patience drains twice as fast | Sweat drop, scowl |
| Confused freshman | Asks for the wrong thing; the real problem is elsewhere | Freshman lanyard, wide eyes |
| Palusot | Insists everything is fine, hands over doubtful papers | Shifty eyes, smirk |
| Kapit | Pressures you to skip the rules | Sunglasses |
| With parent | Twice the patience, but argues every routing | Parent portrait behind |

**Regulars and special events.** Recurring students—including `#112 Jericho Gomez` (camping out for `IT 312`), `#104 Carlo Bacalso` (who loses his ID on the 13C jeepney), and `#118 Mae Alcantara` (with her color-coded scholarship slips)—return across multiple days. Shifts are also punctuated by special customer encounters and timed office events such as coworker announcements, scholarship interview rushes, thermal printer hiccups, ISMIS network lag, and office cutoffs.

## Achievements

Achievements reward playing the window well, and a few reward playing it badly. An "Achievement unlocked" toast slides in the moment one is earned, in the middle of a shift or on the day report. The full list opens from the title screen and from the day report, where the button counts what that shift unlocked.

| Kind | Examples |
| --- | --- |
| Skill in one call or shift | **On a Roll** (10 correct calls in a row), **By the Book** (8+ calls, no wrong calls, false alarms or favors), **Sharp Eye** (10 catches, no false alarms), **Line Cleared** |
| Using the mechanics | **Seniors First** (call a priority student out of turn), **Full House** (fill the Hold bench), **Right This Way** (correct trips to the Cashier, Consultation and the Dean in one shift), **Not Today** (turn down a favor and still get the call right) |
| Season goals | **Gold Star** (3 stars in a shift), **Market Survivor** (3 stars on open market day), **Star Employee** (20 stars in one season), **See You Next Sem** |
| Lifetime, with progress bars | **Familiar Faces** (help Jericho, Carlo and Mae), **Forgery Detector**, **Section Wizard**, **Turn It Off and On**, **Eagle Eye**, **Window 3 Veteran** |
| Secret until earned | Three, shown as ??? on the list |

There are 24 in all. Unlocks and lifetime counters are kept across seasons and restarts in `user://achievements.json`. To start over, use **Project → Open User Data Folder** in the editor and delete that file.

**For the team:**
- Names, descriptions, badge text and goals live in `data/achievements.json`, so they can be reworded or rebalanced without touching code.
- An entry with `stat` and `goal` becomes a lifetime achievement on its own. Any other entry also needs a rule in `scripts/rules/achievement_rules.gd`.
- Badges are drawn as text on gold squares in `scripts/ui/achievement_badge.gd` until pixel-art icons replace them.

## The season (10 days)

| Day | Phase | What's new |
| --- | --- | --- |
| 1 | Prep week | Full onboarding with Ma'am Lorna: ID scanning, flagging, asking, approvals, rejections, triage, and office schedules |
| 2 | 4th-year enrollment | Graduating students missing requirements, impatient seniors, daily office bulletins |
| 3 | 3rd-year enrollment | Closed sections, the section picker, missing IDs, and harmless abbreviations |
| 4 | 2nd-year enrollment | Unpaid balances go to the Cashier, rule-bending favors, and end-of-day spot checks |
| 5 | 1st-year enrollment | ISMIS login resets at the window, birthday verification, and multi-problem priority order |
| 6 | Open market | Hardest day: every problem at once, slots draining live, rush waves |
| 7 | Adjustment, day 1 | Adviser signatures, fake signatures, the Hold bench |
| 8 | Adjustment, day 2 | Overloads (over 24 units) go to the Dean before 11:30 AM |
| 9 | Extension | Only listed departments may adjust; turn the rest away |
| 10 | Classes begin | Payment window: match cash to the assessment |

After day 10, the supervisor's evaluation gives one of three endings based on weighted accuracy, integrity and how many shifts the line gave up on: **kept the post**, **on probation**, or **not renewed**.

## Problem types

| Problem | Correct handling |
| --- | --- |
| Missing requirement (applicant) | Return with the list of what to bring |
| Closed section | Section picker |
| Unpaid balance | Send to Cashier |
| Can't log in to ISMIS | Reset at the window |
| Missing adviser signature | Send to Consultation |
| Overload (over 24 units) | Send to Dean's office |
| Fake signature | Reject |
| Failed prerequisite (5.0) | Reject (INC goes to Consultation) |
| Wrong department on extension day | Turn away: Wrong department (check the ISMIS Department against the memo) |
| Payment doesn't match assessment | Send back to recheck, or give change |

## Screens

- **Menus:** splash, title, save slots, SA creator, settings, pause, credits
- **Daily loop:** season calendar, morning memo, the window (the shift), day report, desk upgrades
- **Inside a shift:** section picker, route menu, ISMIS reset, rulebook, Hold bench, shift failed
- **Story and endings:** thank-you notes, regulars logbook, the end-of-season evaluation
- **Achievements:** the unlock toast, and the achievements list on the title screen and the day report

## Art and audio

- **Style:** chunky pixel-art UI at a 1280×720 base resolution, in USC green `#1F5A3D` and gold `#E0B23A`, with a mint office wall and warm wood desks.
- **Portraits:** students are built from layered parts (hair, eyes, brows, mouth, clothes, accessories) picked at random and tinted for skin tone, hair color and shirt color, so no two students look quite alike.
- **Type:** Jersey 20 for game text, JetBrains Mono for the ISMIS screen.
- **Dialogue:** short Bisaya lines with English subtitles.
- **Audio:** free sound packs: stamps, paper shuffles, queue murmur, a bell for "next," one music loop per screen type.

## Status

**Playable now:** days 1–9, from the season calendar and morning memo through the shift to the day report. This covers full Day 1 onboarding with Ma'am Lorna, Day 2+ office bulletins (no repeated tutorial), inspection, all five actions, the section picker, ISMIS resets, live offices and the Hold bench, the extension-day department check, student traits and personalities, recurring regulars (`#112`, `#104`, `#118`), mid-shift special events, rule bending, both live mid-shift and end-of-day spot checks, and achievements.

**Still to come:** day 10; title screen, saves and settings; desk upgrades; endings; audio and final art.

## Running it

Open `project.godot` in Godot 4 and press F5. The rules, generator and achievement tests run headless with `tests/run_tests.sh`. It looks for Godot at the default macOS path. Elsewhere, set `GODOT` to your Godot executable first, for example in Git Bash on Windows:

```sh
GODOT="/path/to/Godot_v4.7.1-stable_win64.exe" sh tests/run_tests.sh
```

## Team

| Person | Role |
| --- | --- |
| Razel | Gameplay programming: shift logic, rules check, scoring, saves |
| Zsof | Pixel art and UX: portraits, screens, UI |
| Torcy | Writing and level design: cases, Bisaya dialogue, regulars' stories, playtesting |

## Scope

**Must have:** papers vs record, route/fix/hold/reject, line patience, the section picker, days 2–8, day report.

**Should have:** rule bending and spot checks, student traits, regulars, desk upgrades, days 1, 9 and 10, three endings.

**Could have:** more regulars, extra events, a harder "next semester" mode.
