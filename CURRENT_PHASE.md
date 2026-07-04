# CURRENT_PHASE.md — Tiger Kick

Single source of truth for "where are we now". **Update this whenever the phase/milestone/sprint moves.** Keep it tiny.

| Field | Value |
|---|---|
| Docs Version | v0.24 |
| Game Build | v0.2 — dev infra done (GameLog, ConfigManager, ErrorHandler, F3/F4 overlays, Settings); movement next |
| Current Phase | **Phase 1 — Movement** |
| Current Milestone | **M1 Movement** |
| Current Sprint | Player scene + movement + third-person camera + network spawn/sync |
| Exit Gate goal | Each peer spawns + controls its own player; movement syncs across 2 instances |

## Phase 0 — CLOSED ✅ (Exit Gate PASS, PR #1 merged)
- clone→opens · 2 instances connect · `[NET] peer joined` · GUT green, no S0/S1. Cards `TK-P0-01`…`TK-P0-06`.

## Phase X — CLOSED ✅ (Exit Gate PASS, PR #2 merged `fd82306`)
- [x] Debug overlay (F3) + Perf overlay (F4) toggles, FPS/ping/state (manual GUI confirmed)
- [x] Settings change→save→reload persists across restart (headless round-trip + manual GUI confirmed)
- [x] ≥1 unit-test suite passing (GUT 88/88, 1135 asserts), Regression + NET SMOKE PASS, no S0/S1
- Cards `TK-PX-01`…`TK-PX-07`. Autoloads: GameLog, ConfigManager, NetworkManager, ErrorHandler, DebugOverlay, PerfOverlay.

## Phase 1 — code complete (6/6 cards done, on `develop`) — HUMAN QA PENDING
- `TK-P1-01` Player.tscn · `TK-P1-02` movement+sprint · `TK-P1-03` third-person camera rig · `TK-P1-04` MultiplayerSpawner · `TK-P1-05` per-player authority · `TK-P1-06` synchronizer tuning + remote-physics guard
- Automated verified: import clean, **GUT 116/116** (1201 asserts), NET SMOKE PASS, host-spawn/authority/camera probes PASS, no S0/S1.

### Phase 1 Exit Gate (from Phase1_QA/03_Exit_Gate) — automated met, human pending
- [x] Regression passes (GUT 116/116 + net_smoke), no open S0/S1
- [x] each peer spawns + is authority of its own player (host-side probe verified)
- [ ] **HUMAN: play-test in editor** — WASD/mouse/sprint move; F3/F4 overlays; Settings save/reload
- [ ] **HUMAN: 2-window** — Host/Join, see each other, movement syncs smoothly (no jitter/drift), each controls only its own player
- [ ] Merge `develop` → `main` (PR #3)
- ⏸️ **Producer HALTED at user request for hands-on quality review before Phase 2.**

## Open cross-phase items (not blocking)
- `TK-P2-09` TigerSelector helper landed early (partial); full card OPEN pending `TK-P2-04` (Phase 2). Architect ack on `managers/` placement deferred to Phase 2.
- Phase-1 wiring picks up deferred infra: define InputMap actions (move/kick/tag) — unblocks Settings→Controls rebind (+ reconcile rebind string format "W"→"w"); audio Music/SFX bus layout still pending.
- Tech-debt: NetworkManager peer-teardown guard / MainMenu nits (task); PDF docs regen to 4.7.

## Next
Finish Phase 1 (Movement) → **Phase 2 (Core Loop)** — the "prove it's fun" milestone.
