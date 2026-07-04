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

## Active this phase (Phase 1)
- **Lead agents:** `gameplay-engineer` (Player/movement/camera), `network-engineer` (spawn/authority/sync) · **Always on:** `producer`, `qa-engineer`, `code-reviewer`, `documentation-manager`
- **Doing:** `TK-P1-01` Player.tscn (CharacterBody3D + Camera3D + MultiplayerSynchronizer)
- **Queued:** `TK-P1-02` movement+sprint, `TK-P1-03` third-person camera rig (dep P1-01); `TK-P1-04` MultiplayerSpawner (dep P1-01) → `TK-P1-05` authority → `TK-P1-06` synchronizer tuning

## Open cross-phase items (not blocking)
- `TK-P2-09` TigerSelector helper landed early (partial); full card OPEN pending `TK-P2-04` (Phase 2). Architect ack on `managers/` placement deferred to Phase 2.
- Phase-1 wiring picks up deferred infra: define InputMap actions (move/kick/tag) — unblocks Settings→Controls rebind (+ reconcile rebind string format "W"→"w"); audio Music/SFX bus layout still pending.
- Tech-debt: NetworkManager peer-teardown guard / MainMenu nits (task); PDF docs regen to 4.7.

## Next
Finish Phase 1 (Movement) → **Phase 2 (Core Loop)** — the "prove it's fun" milestone.
