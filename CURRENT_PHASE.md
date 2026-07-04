# CURRENT_PHASE.md — Tiger Kick

Single source of truth for "where are we now". **Update this whenever the phase/milestone/sprint moves.** Keep it tiny.

| Field | Value |
|---|---|
| Docs Version | v0.24 |
| Game Build | v0.2 — dev infra (GameLog, ConfigManager, ErrorHandler, F3 debug + F4 perf overlays, Settings menu) |
| Current Phase | **Phase X — Development Infrastructure** (code complete, Exit Gate pending PR merge + manual GUI check) |
| Current Milestone | **MX Dev Infra** |
| Current Sprint | Dev Infra — DONE (7/7 cards) |
| Exit Gate goal | Logger + ConfigManager + Settings + debug/perf overlays in place; GUT/CI green |

## Phase 0 — CLOSED ✅ (Exit Gate PASS, merged to main via PR #1)
- [x] clone repo → opens in Godot 4.7 with no errors (CI headless import)
- [x] two instances Host/Join → connect successfully (automated localhost harness `tests/net/`, 3–4× PASS; GUI 2-window confirmatory done)
- [x] log confirms peer joined (`[NET] peer joined`)
- [x] Regression suite passes, no open S0/S1 (GUT 15/15)
- Cards done: `TK-P0-01`…`TK-P0-06`. Follow-ups: 2-machine LAN test, `managers/`→`networking/` doc reconcile, PDF regen 4.7.

## Phase X — code complete (7/7 cards done, on `develop`)
- `TK-PX-07` GUT 9.7.0 + CI mandatory + backlog validator · `TK-PX-01` GameLog autoload · `TK-PX-04` ConfigManager · `TK-PX-02` DebugOverlay (F3) · `TK-PX-06` ErrorHandler · `TK-PX-05` Settings menu · `TK-PX-03` PerfOverlay (F4)
- Autoloads: GameLog, ConfigManager, NetworkManager, ErrorHandler, DebugOverlay, PerfOverlay

### Phase X Exit Gate (from PhaseX_QA/03_Exit_Gate)
- [x] ≥1 unit-test suite passing (GUT 88/88, 1135 asserts, exit 0)
- [x] Settings save/load persists across restart (headless round-trip probe: master_volume/fullscreen survive a fresh process)
- [x] Regression passes, no open S0/S1 (GUT 88/88 + NET SMOKE PASS)
- [ ] **Manual GUI confirm (human):** F3 debug overlay shows FPS/ping/state realtime; F4 perf overlay; Settings screen change→save→reopen persists visually
- [ ] Merge `develop` → `main` (PR #2)

## Open cross-phase items (not blocking)
- `TK-P2-09` TigerSelector helper landed early (partial); full card OPEN pending `TK-P2-04` (Phase 2). Architect ack on `managers/` placement deferred to Phase 2.
- Deferred from Phase X: Controls rebind needs Phase-1 InputMap actions (+ rebind string-format reconcile "W"→"w"); audio Music/SFX bus layout not yet configured.

## Next
Merge Phase X → **Phase 1 (Movement)**: `TK-P1-01` Player.tscn (dep `TK-PX-07` ✓ done) → movement/sprint → third-person camera → spawner/authority/synchronizer.
