# 40 — Picking a dropped game back up

*From `todo.md`, 2026-09-17: "In case one side crashes, can we easily reconnect
to a running game? It would be ideal if the original connection string would
still work, and the reconnecting client could ask for a current state, but I'm
willing to solve this otherwise."*

**Built:** the survivor invites again, and the crashed side joins from its menu.
The guest sits in whichever seat the host is not in, and the panel explains the
steps when the connection closes. See AUTHORING's *Playing over a network*, and
`test_net_a_crashed_peer_rejoins_the_game`. The original string cannot work
twice, because a WebRTC offer belongs to the connection that made it.

## Still open

- **Not tried in two browsers.** The panel decides the link dropped from the
  data channel's `readyState` reading `closed`, or the connection's state reading
  `failed` (`netpanel.refresh`). [Assumption: a closed tab brings the channel to
  `closed` within seconds. A network drop may sit in `disconnected` for up to
  30 s before that, and until then the panel says nothing.]
- **A crashed browser tab.** [Assumption: a local copy of the last agreed state
  would let *either* side host. [24](24-save-and-load.md) refused saving during
  a networked game. A copy read back only by a reconnect is not a save a player
  loads, but that decision would be reopened.] Ask first.
