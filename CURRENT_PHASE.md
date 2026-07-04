# CURRENT_PHASE.md — Tiger Kick

Single source of truth for "where are we now". **Update this whenever the phase/milestone/sprint moves.** Keep it tiny.

| Field | Value |
|---|---|
| Docs Version | v0.21 |
| Game Build | v0.1 — networking foundation (MainMenu + Host/Join + TestArena, 2-instance connect verified) |
| Current Phase | **Phase X — Development Infrastructure** |
| Current Milestone | **MX Dev Infra** |
| Current Sprint | Dev Infra (Logger, Config, overlays, Settings) |
| Exit Gate goal | Logger + ConfigManager + Settings + debug/perf overlays in place; GUT/CI green |

## Phase 0 — CLOSED ✅ (Exit Gate PASS, merged to main via PR #1)
- [x] clone repo → opens in Godot 4.7 with no errors (CI headless import)
- [x] two instances Host/Join → connect successfully (automated localhost harness `tests/net/`, 3–4× PASS; GUI 2-window confirmatory done)
- [x] log confirms peer joined (`[NET] peer joined`)
- [x] Regression suite passes, no open S0/S1 (GUT 15/15)
- Cards done: `TK-P0-01`…`TK-P0-06`. Follow-ups: 2-machine LAN test, `managers/`→`networking/` doc reconcile, PDF regen 4.7.

## Active this phase (Phase X)
- **Lead agent:** `tools-devops` · **Always on:** `producer`, `qa-engineer`, `code-reviewer`, `documentation-manager`
- **Done:** `TK-PX-07` (GUT 9.7.0 + CI mandatory + backlog validator)
- **Doing:** `TK-PX-01` (Logger autoload), `TK-PX-04` (ConfigManager)
- **Queued:** `TK-PX-02` (debug overlay), `TK-PX-06` (error handling), `TK-PX-05` (Settings menu), `TK-PX-03` (perf overlay)

## Open cross-phase items (not blocking)
- `TK-P2-09` TigerSelector helper landed early (partial); full card OPEN pending `TK-P2-04` (Phase 2). Architect ack on `managers/` placement deferred to Phase 2.

## Next
Finish Phase X (Dev Infra) → **Phase 1 (Movement)**.
