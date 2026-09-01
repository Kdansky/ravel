"""Refuse to overwrite a game file while there is uncommitted work.

A generator writes its whole game file every time, so anything hand-edited into
that file since the last run is gone — silently, with the suite still green,
because a hand-edited generated file looks exactly like one that is not. That is
not hypothetical: make_puzzle_strike.py drifted seventy-six cards behind
puzzle_strike.json while reactions were being built, and one run would have
thrown the feature away.

Committed work is recoverable and uncommitted work is not, so that is the line.
The workflow is: commit, run, look at the diff, commit again.

    --out PATH   write somewhere else; the guard does not apply, since nothing
                 the repository ships is being overwritten
    --force      write anyway. For when you know what you are discarding.
"""

import os
import subprocess
import sys


def _porcelain(repo):
    try:
        out = subprocess.run(["git", "status", "--porcelain"], cwd=repo,
                             capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        # No git, no history to protect. A checkout that is not a repository is
        # somebody's tarball, and refusing to build it would be theatre.
        return None
    if out.returncode != 0:
        return None
    return [l for l in out.stdout.splitlines() if l.strip()]


def destination(default_out, argv=None):
    """Where this generator should write, or None if it must not write at all.

    Prints its own reason when it refuses, so a generator's __main__ is two
    lines: ask, and write if it was given somewhere to write.
    """
    default_out = os.path.normpath(os.path.abspath(default_out))
    argv = list(sys.argv[1:] if argv is None else argv)
    force = "--force" in argv
    out = None
    if "--out" in argv:
        i = argv.index("--out")
        if i + 1 >= len(argv):
            print("--out needs a path", file=sys.stderr)
            return None
        out = argv[i + 1]

    # Writing somewhere of the caller's choosing overwrites nothing that ships.
    if out is not None:
        return out
    if force or os.environ.get("RAVEL_ALLOW_DIRTY"):
        return default_out

    # Up from game/games/<name>.json until something looks like the checkout.
    repo = os.path.dirname(default_out)
    while repo != os.path.dirname(repo) and not os.path.isdir(os.path.join(repo, ".git")):
        repo = os.path.dirname(repo)
    dirty = _porcelain(repo)
    if not dirty:
        return default_out

    rel = os.path.relpath(default_out, repo)
    print("Refusing to write %s: there is uncommitted work in the tree.\n" % rel, file=sys.stderr)
    print("A generator rewrites its game file whole, so anything hand-edited into", file=sys.stderr)
    print("it since the last run is gone. Committed work can be recovered and", file=sys.stderr)
    print("uncommitted work cannot, which is where the line is.\n", file=sys.stderr)
    for line in dirty[:20]:
        print("  " + line, file=sys.stderr)
    if len(dirty) > 20:
        print("  ... and %d more" % (len(dirty) - 20), file=sys.stderr)
    print("\nCommit, then run again. Or --out <path> to write elsewhere,", file=sys.stderr)
    print("or --force if you know what you are discarding.", file=sys.stderr)
    return None
