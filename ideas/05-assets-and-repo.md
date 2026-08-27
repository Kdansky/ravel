# 05 — Assets and what the repository carries

**Closed.** Named assets shipped (`ff55754`), the generated placeholder shipped,
and the third gap was a misunderstanding.

## Named assets, not scheme prefixes

A picture is named once and referenced by key:

```json
"assets": { "archmage_tower": { "src": "https://i.imgur.com/0vnj0kx.jpeg", "max": 4092 } }
```

Chosen over `file:` / `url:` / `shape:` prefixes because it answers a question
prefixes do not: **a picture needs options**, and those want one home rather
than one per call site. Naming also makes the name the cache key, so twenty
cards sharing a picture cost one download.

It bought most of what the prefixes were for. The old failure — a typo landing
in whichever branch its shape happened to match, with an error message about
something else entirely — is gone for the case that actually happens: a bare
word resolves against `assets`, and the validator answers *nothing is named 'x'
in the assets section* with a did-you-mean.

**What is left is the small half and is deliberately left.** A filename and a
shape spec are still told apart by *does it contain a dot*. That holds until a
shape name contains one or a file lacks an extension, and nothing is close to
either. The migration would edit every game file; the cheap fix if it ever bites
is to require a named entry for anything not obviously a shape, and that
machinery now exists.

## The placeholder, for a better reason than the one first written

Every exit that cannot produce a picture falls through to
`art.render(art.auto(key))` — a missing file, a refused URL, a failed fetch, a
shape the engine cannot draw — each saying once which it was.

The original reason was that art was about to leave the repository. It is not.
The real reason is the failures that are **not the author's doing**: a remote
host refusing, or the common one, somebody playing a game file that arrived over
the network, which carries the JSON and none of the sender's assets. A card with
no image reads as a bug in the game; a shape derived from its key reads as a
card.

**The key is hashed, not the text.** The key is identity, the text is
presentation, and a copy-edit should not repaint a card.

The validator's *its image 'x.jpg' is not in games/assets* **stays**. It was to
be removed when a missing file was about to become normal; it did not, so a
local file that is not there is still an authoring mistake. The placeholder is
what the *player* sees, not permission to lose the art.

## Art stays in git

> *I do not actually require the art to be removed from git, that was a
> misunderstanding. I want the engine to be able to use art that's not hosted
> here, and we have done that already.*

The real requirement was remote art, and it shipped with named assets. Two
measurements from the cancelled plan are worth keeping, because someone will ask
again: the pack is **2.83 MiB, essentially all art**, and removing files going
forward would not shrink a clone — only `git filter-repo` does, and that
invalidates every existing clone to save two and a half megabytes.

Had it gone ahead, the rule would have been about weight and role rather than
file type: a photograph dressing a card goes, a glyph the game is played with
stays. Chess's twelve piece sprites are 25 KB for the set, and a chessboard
drawn with placeholders is not chess.

## Refused

- **A general URI scheme.** Closed set, no `data:`, no relative paths, no scheme
  the engine does not implement — and the path-traversal rule stays whatever
  else changes: a local asset is a bare filename, never a path.
