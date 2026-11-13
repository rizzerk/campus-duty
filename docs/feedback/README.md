# Playtest feedback

Comments from judges, classmates and other players, grouped and ranked so they turn into work.

## Collecting

- **Comments.** Write down what people said, close to their words. Note who they are by role (judge, classmate, gamer, teammate), not by name.
- **Playtest log.** The game appends one line per finished shift to `playtest_log.jsonl` in its user data folder. Ask testers for that file after they play. Nothing in it identifies them.
  - Windows: `%APPDATA%\Godot\app_userdata\Campus Duty\playtest_log.jsonl`
  - macOS: `~/Library/Application Support/Godot/app_userdata/Campus Duty/playtest_log.jsonl`
  - Linux: `~/.local/share/godot/app_userdata/Campus Duty/playtest_log.jsonl`
  - From the editor: **Project → Open User Data Folder**.

Each line holds the day, seed, stars, why the shift ended, accuracy, students served, wrong calls by problem, favors, catches, false alarms and the clock time when it ended.

## Reports

One file per session: `YYYY-MM-DD-<source>.md`. Each report has:

1. Who played and which build.
2. What landed, so it stays.
3. Themes, ranked by how many people raised them and how much they hurt the experience, each with evidence (quotes and log numbers), the files or data involved, and one proposed fix.
4. What we're not doing, and why.

The top themes become GitHub issues labelled `feedback` plus a priority (`must`, `should`, `could`) and an area.
