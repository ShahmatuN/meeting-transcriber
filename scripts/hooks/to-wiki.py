#!/usr/bin/env python3
"""After-meeting command: file a finished transcript into a personal wiki.

Set as Settings -> Output -> After Each Meeting, for example:

    TO_WIKI_DIR="$HOME/Notes" TO_WIKI_OWNER="Jane Doe" /path/to/scripts/hooks/to-wiki.py

The wiki is a folder with AGENTS.md and raw/ that the `meeting-to-wiki`
Claude Code skill maintains. Two steps, in this order:

1. Copy the transcript byte for byte into raw/ under the folder's naming
   convention. This step needs nothing but the disk, so a transcript reaches
   raw/ even when the second step fails.
2. Run Claude Code headless in the wiki folder for the rest of the skill
   (process raw/ into the wiki, mark the file processed).

Reads from the app: MT_TRANSCRIPT, MT_DATE, MT_TITLE, MT_PARTICIPANTS (one per
line). Configuration: TO_WIKI_DIR and TO_WIKI_OWNER (first and last name of
the person who records), TO_WIKI_CLAUDE (the claude binary, found on PATH or in
~/.local/bin otherwise), TO_WIKI_SKIP_CLAUDE=1 to stop after step 1.

The last line printed is the one the app shows in its notification.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

CLAUDE_TIMEOUT_SECONDS = 25 * 60
ALLOWED_TOOLS = "Read Write Edit Glob Grep Bash(ls:*) Bash(wc:*) Bash(head:*) Bash(date:*)"
# Only granted when the name was built without participants, see prompt_for.
RENAME_TOOL = "Bash(mv:*)"
# APFS and HFS+ cap a file name at 255 bytes of UTF-8; the stem budget leaves
# room for ".md" and a " (NN)" collision suffix.
MAX_STEM_BYTES = 255 - len(".md") - len(" (99)")


def surname(participant: str) -> str:
    """`k.markidonov`, `k.markidonov@corp.io` and `Kirill Markidonov` all give
    `Markidonov`; a single word is kept as it is."""
    name = participant.split("@", 1)[0].strip()
    if " " in name:
        name = name.split()[-1]
    elif "." in name:
        name = name.rsplit(".", 1)[-1]
    return name[:1].upper() + name[1:]


def topic(title: str) -> str:
    """A meeting title as a file-name part: no path or drive separators."""
    cleaned = " ".join(title.replace("/", " ").replace(":", " ").replace("\\", " ").split())
    return cleaned or "Meeting"


def raw_name(date: str, owner: str, participants: list, title: str) -> tuple:
    """The raw/ file name, without extension, by the wiki's convention:
    one other person is a 1-1 named after them, several are listed by surname
    with the topic, nobody named is filed under the owner's full name.

    Returns the stem and how many surnames were left out of it: a name is a
    file name, and a company-wide call (36 invitees measured) builds one that
    no filesystem accepts, so surnames are dropped from the end until the stem
    fits MAX_STEM_BYTES. The topic stays, since it is what the file is found by."""
    owner_first = owner.split()[0]
    owner_last = owner.split()[-1].lower()
    others = []
    for person in participants:
        name = surname(person)
        if name and name.lower() != owner_last and name not in others:
            others.append(name)
    if not others:
        return f"{date} {owner} - {topic(title)}", 0
    if len(others) == 1:
        return f"{date} {owner_first} {others[0]} - 1-1", 0
    kept = list(others)
    stem = f"{date} {owner_first} {' '.join(kept)} - {topic(title)}"
    while len(stem.encode()) > MAX_STEM_BYTES and len(kept) > 1:
        kept.pop()
        stem = f"{date} {owner_first} {' '.join(kept)} - {topic(title)}"
    return stem, len(others) - len(kept)


def unique_path(raw_dir: Path, stem: str) -> Path:
    """Never overwrite: a second 1-1 with the same person on the same day
    becomes `<name> (2).md`."""
    candidate = raw_dir / f"{stem}.md"
    counter = 2
    while candidate.exists():
        candidate = raw_dir / f"{stem} ({counter}).md"
        counter += 1
    return candidate


def find_claude() -> str:
    configured = os.environ.get("TO_WIKI_CLAUDE")
    if configured:
        return configured
    found = shutil.which("claude")
    if found:
        return found
    fallback = Path.home() / ".local" / "bin" / "claude"
    return str(fallback) if fallback.exists() else ""


def prompt_for(relative: str, may_rename: bool, dropped: int = 0, participants: list = ()) -> str:
    """With no participants known the name carries only the app's title (often
    a bare `Google Meet abc-defg-hij`), so the model, which has read the
    transcript, may rename the file by the convention. Content stays as is.
    When the name could not hold every participant, the full list travels in
    the prompt instead, so the model still knows who was invited."""
    rename = (
        "Участники встречи приложению неизвестны, поэтому имя файла собрано из названия окна. "
        "Если по содержанию понятны участники или тема, переименуй файл через `mv` по конвенции "
        "`raw/` из скилла (не перезаписывая существующий файл) и дальше работай с новым именем. "
        if may_rename else ""
    )
    truncated = (
        f"В имя файла не поместились {dropped} фамилий; "
        f"полный список приглашённых: {', '.join(participants)}. "
        if dropped else ""
    )
    return (
        f"Новый транскрипт встречи уже сохранён байт-в-байт в `{relative}`: фаза 1 скилла "
        "meeting-to-wiki выполнена, содержимое этого файла не меняй, кроме маркера processed в фазе 3. "
        + rename + truncated +
        "Выполни по скиллу meeting-to-wiki фазы 2 и 3 для этого файла. Пользователя рядом нет: "
        "ничего не спрашивай, решения, принятые за пользователя, перечисли в отчёте. "
        "Последней строкой ответа выведи одну строку, которая начинается с «ИТОГ:», "
        "с тем, что обновлено (карточки, договорённости, вопросы к пользователю)."
    )


def fail(message: str) -> int:
    print(message)
    return 1


def main() -> int:
    transcript = os.environ.get("MT_TRANSCRIPT", "")
    wiki = os.environ.get("TO_WIKI_DIR", "")
    owner = os.environ.get("TO_WIKI_OWNER", "").strip()
    if not transcript or not Path(transcript).is_file():
        return fail("to-wiki: no transcript to file (MT_TRANSCRIPT is empty or missing)")
    if not wiki or not owner:
        return fail("to-wiki: set TO_WIKI_DIR and TO_WIKI_OWNER in the command")
    wiki_dir = Path(wiki).expanduser()
    raw_dir = wiki_dir / "raw"
    if not (wiki_dir / "AGENTS.md").is_file() or not raw_dir.is_dir():
        return fail(f"to-wiki: {wiki_dir} has no AGENTS.md or raw/")

    participants = [p for p in os.environ.get("MT_PARTICIPANTS", "").splitlines() if p.strip()]
    date = os.environ.get("MT_DATE", "")
    stem, dropped = raw_name(date, owner, participants, os.environ.get("MT_TITLE", ""))
    may_rename = stem.startswith(f"{date} {owner} - ")
    target = unique_path(raw_dir, stem)
    shutil.copyfile(transcript, target)
    if target.stat().st_size != Path(transcript).stat().st_size:
        return fail(f"to-wiki: copy to raw/{target.name} came out a different size")
    relative = f"raw/{target.name}"
    print(f"Saved {relative}")

    if os.environ.get("TO_WIKI_SKIP_CLAUDE") == "1":
        print(f"{relative} saved, wiki not processed (TO_WIKI_SKIP_CLAUDE)")
        return 0
    claude = find_claude()
    if not claude:
        return fail(f"{relative} saved, wiki not processed: claude not found")
    try:
        result = subprocess.run(
            [claude, "-p", prompt_for(relative, may_rename, dropped, participants),
             "--permission-mode", "acceptEdits",
             "--allowedTools", f"{ALLOWED_TOOLS} {RENAME_TOOL}" if may_rename else ALLOWED_TOOLS],
            cwd=wiki_dir, capture_output=True, text=True, timeout=CLAUDE_TIMEOUT_SECONDS,
            stdin=subprocess.DEVNULL, check=False,
        )
    except subprocess.TimeoutExpired:
        return fail(f"{relative} saved, wiki processing timed out")
    print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    if result.returncode != 0:
        return fail(f"{relative} saved, wiki not processed (claude exit {result.returncode})")
    summary = [line for line in result.stdout.splitlines() if line.strip().startswith("ИТОГ:")]
    print(summary[-1].strip() if summary else f"{relative} filed into the wiki")
    return 0


if __name__ == "__main__":
    sys.exit(main())
