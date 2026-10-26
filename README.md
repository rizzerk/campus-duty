# Campus Duty
 
A registrar window sim set during enrollment season at the University of San Carlos. You play a Student Assistant (SA) at Window 3 of the Registrar's Office. Students line up with problems; you check their papers against their ISMIS record, then fix the problem yourself, send them to the right office, or turn them away. Make the wrong call and they come back angrier.
 
| | |
| --- | --- |
| Genre | Inspection and routing sim with light story |
| Art | 2D pixel-art UI; character style still open |
| Engine | Godot 4, 2D |
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
 
**Student traits.** Traits change how a student behaves, never the correct answer, and each has a visual tell on the portrait.


## Team
 
| Person | Role |
| --- | --- |
| Razel | Gameplay programming: shift logic, rules check, scoring, saves |
| Zsof | Pixel art and UX: portraits, screens, UI |
| Torcy | Writing and level design: cases, Bisaya dialogue, regulars' stories, playtesting |
 
