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
2. **Morning memo.** Ma'am Lorna, the University Registrar, posts today's rules. Each day adds one new rule.
3. **The shift.** Students come to the window one at a time:
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

**Rule bending.** Some students push you to break the rules: the Dean's "nephew," sob stories, the occasional merienda. Bending is fast and makes that student happy, but the line sees it (patience drops) and Ma'am Lorna spot-checks three random transactions at the end of each day. Getting caught costs rating.

**Student traits.** Traits change how a student behaves, never the correct answer, and each has a visual tell on the portrait:

| Trait | Effect | Visual tell |
| --- | --- | --- |
| Impatient | Patience drains twice as fast | Sweat drop, scowl |
| Confused freshman | Asks for the wrong thing; the real problem is elsewhere | Freshman lanyard, wide eyes |
| Palusot | Insists everything is fine, hands over doubtful papers | Shifty eyes, smirk |
| Kapit | Pressures you to skip the rules | Sunglasses |
| With parent | Twice the patience, but argues every routing | Parent portrait behind |

**Regulars.** A few recurring students (for example #112, who needs IT 312, and #24, who keeps losing his ID) have 4–5 story beats across the season. Your choices decide how their stories end.

## The season (10 days)

| Day | Phase | What's new |
| --- | --- | --- |
| 1 | Prep week | Tutorial: applicant checklists, flagging, stamping |
| 2 | 4th-year enrollment | Graduating students missing requirements |
| 3 | 3rd-year enrollment | Closed sections and the section picker |
| 4 | 2nd-year enrollment | Unpaid balances go to the Cashier |
| 5 | 1st-year enrollment | ISMIS login resets at the window |
| 6 | Open market | Hardest day: every problem at once, slots draining live, rush waves |
| 7 | Adjustment, day 1 | Adviser signatures, fake signatures, the Hold bench |
| 8 | Adjustment, day 2 | Overloads (over 24 units) go to the Dean |
| 9 | Extension | Only listed departments may adjust; turn the rest away |
| 10 | Classes begin | Payment window: match cash to the assessment |

After day 10, the supervisor's evaluation gives one of three endings based on accuracy and integrity: **kept the post**, **on probation**, or **not renewed**.

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
| Wrong department on extension day | Turn away politely |
| Payment doesn't match assessment | Send back to recheck, or give change |

## Screens

- **Menus:** splash, title, save slots, SA creator, settings, pause, credits
- **Daily loop:** season calendar, morning memo, the window (the shift), day report, desk upgrades
- **Inside a shift:** section picker, route menu, ISMIS reset, rulebook, Hold bench, shift failed
- **Story and endings:** thank-you notes, regulars logbook, the end-of-season evaluation

## Art and audio

- **Style:** chunky pixel-art UI at a 1280×720 base resolution, in USC green `#1F5A3D` and gold `#E0B23A`, with a mint office wall and warm wood desks.
- **Portraits:** students are built from layered parts (hair, eyes, brows, mouth, clothes, accessories) picked at random and tinted for skin tone, hair color and shirt color, so no two students look quite alike.
- **Type:** Jersey 20 for game text, JetBrains Mono for the ISMIS screen.
- **Dialogue:** short Bisaya lines with English subtitles.
- **Audio:** free sound packs: stamps, paper shuffles, queue murmur, a bell for "next," one music loop per screen type.

## Status

**Playable now:** days 2–8, from the morning memo through the shift to the day report. This covers inspection, all five actions, the section picker, ISMIS resets, live offices and the Hold bench, student traits, rule bending and the spot check.

**Still to come:** days 1, 9 and 10; title screen, saves and settings; season calendar and desk upgrades; regulars; endings; audio and final art.

## Running it

Open `project.godot` in Godot 4 and press F5. The rules and generator tests run headless with `tests/run_tests.sh`.

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
