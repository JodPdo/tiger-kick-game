# CURRENT_PHASE.md — Tiger Kick

Single source of truth for "where are we now". **Update this whenever the phase/milestone/sprint moves.** Keep it tiny.

| Field | Value |
|---|---|
| Docs Version | v0.31 |
| Game Build | v0.3 — movement done (spawn/authority/camera/sync, 2-window verified); core loop next |
| Current Phase | **Phase 2 — Core Loop** (started; Ability System design APPROVED) |
| Current Milestone | **M2 Core Gameplay** |
| Current Sprint | ⏸️ PARKED — `TK-P2-16` scaffold DONE (human-confirmed). `TK-P2-01` Kick = code-complete, WIP-committed, **review-pending** (reviewer hit session limit). Resume: re-run code-reviewer on Kick. |
| Exit Gate goal | Kick + Tag + 7-step Tag Sequence + role swap on the ability scaffold; core loop playable |

## Phase 0 — CLOSED ✅ (Exit Gate PASS, PR #1 merged)
- clone→opens · 2 instances connect · `[NET] peer joined` · GUT green, no S0/S1. Cards `TK-P0-01`…`TK-P0-06`.

## Phase X — CLOSED ✅ (Exit Gate PASS, PR #2 merged `fd82306`)
- [x] Debug overlay (F3) + Perf overlay (F4) toggles, FPS/ping/state (manual GUI confirmed)
- [x] Settings change→save→reload persists across restart (headless round-trip + manual GUI confirmed)
- [x] ≥1 unit-test suite passing (GUT 88/88, 1135 asserts), Regression + NET SMOKE PASS, no S0/S1
- Cards `TK-PX-01`…`TK-PX-07`. Autoloads: GameLog, ConfigManager, NetworkManager, ErrorHandler, DebugOverlay, PerfOverlay.

## Phase 1 — CLOSED ✅ (Exit Gate PASS — human 2-window test + CI green)
- 6 build cards `TK-P1-01`…`TK-P1-06` + audit reopen fixes `TK-BUG-P1-01` (spawn authority/position via spawn_function + `_enter_tree`), `TK-BUG-P1-02` (host-quit → MainMenu + ESC-ESC Leave), `TK-P1-07` (CI gates on net smoke + spawn probe).
- [x] each peer spawns at its own slot (no stack/origin) + is authority of its own player
- [x] host quits → client returns to MainMenu; ESC-ESC Leave works (single ESC does NOT disconnect)
- [x] movement/camera sync across 2 windows — **human 2-window test PASSED**
- [x] Regression: GUT 119/119 (1206 asserts) + net_smoke + spawn probe (now CI-gated), no open S0/S1
- [ ] Merge `develop` → `main` (PR #3) — pending human
- Audit note [0.28]: S1-A "WASD dead (device:16)" was a FALSE ALARM (human-verified); the 116/116-green-but-broken lesson → per-card pure-function tests missed glue bugs; fixed by adding the 2-instance spawn probe to CI.

## Open cross-phase items (not blocking)
- `TK-P2-09` TigerSelector helper landed early (partial); full card OPEN pending `TK-P2-04` (Phase 2). Architect ack on `managers/` placement deferred to Phase 2.
- Phase-1 wiring picks up deferred infra: define InputMap actions (move/kick/tag) — unblocks Settings→Controls rebind (+ reconcile rebind string format "W"→"w"); audio Music/SFX bus layout still pending.
- Tech-debt: NetworkManager peer-teardown guard / MainMenu nits (task); PDF docs regen to 4.7.

## Next — Phase 2 (Core Loop), the "prove it's fun" milestone
**Gate before any Phase 2 code:** `architect` must approve the **Ability System** design (`TK-P2-16`: refactor Player → Movement / Camera / Ability components + base HumanAbility/TigerAbility; Kick/Jump/Tag re-slot as abilities). Then Phase 2 starts at that scaffold.
- Phase 2 card order (from `_backlog.json`, +8 new Cowork cards): `TK-P2-16` (Ability scaffold, first) → abilities (`TK-P2-01` Kick, `TK-P2-10/11` Jump/Jump-Kick) → `TK-P2-12..15` match flow (Waiting Room → Start → Countdown → GameManager state machine) → Tag Sequence (`TK-P2-02..08`) → `TK-P2-09` first-Tiger (TigerSelector ready). `TK-P3-05` Tiger body-language (Crouch→Lean→Peek) proves the ability system.
- Ability catalog (Phase 3-5): Tiger{Crouch, Lean, Sprint, Pounce, Peek} · Human{Kick, Hide, Emote}.
