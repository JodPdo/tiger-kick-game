# CURRENT_PHASE.md — Tiger Kick

Single source of truth for "where are we now". **Update this whenever the phase/milestone/sprint moves.** Keep it tiny.

| Field | Value |
|---|---|
| Docs Version | v0.31 |
| Game Build | v0.3 — movement done (spawn/authority/camera/sync, 2-window verified); core loop next |
| Current Phase | **Phase 2 — Core Loop** (started; Ability System design APPROVED) |
| Current Milestone | **M2 Core Gameplay** |
| Current Sprint | ⏸️ CHECKPOINT (session break) — **THREE cards awaiting ONE HUMAN N-WINDOW run** (all automation GREEN; the Start-Match path now reaches the arena so all three are testable in a single 3+ window session — full 25-item checklist in the TK-P2-13 qa report): (1) `TK-P2-13` **Start Match** = automation GREEN (code-review **3 rounds** → APPROVE-WITH-NITS; found+killed a real S1 [Godot per-peer node-path-cache poisoning on scene transition → clients spawned Player-less] via a host-side **readiness barrier** + 3 side-door guards + grace-timer force-disconnect; qa PASS own run: **GUT 184/184**, net_smoke + spawn_probe + new host-first **spawn_probe_together** PASS, falsification confirmed both ways, no S0/S1). (2) `TK-P2-12` Waiting Room (roster S1–S7). (3) `TK-P2-10` Jump (steps a–e — was blocked with no arena path; Start now provides it). `TK-P2-01` Kick = DONE. **RESUME:** run the single human N-window checklist (Start happy-path N=3–8 + barrier B1/B2/B3 + WaitingRoom roster + Jump) → each card PASS → flip to done + close. Then next unblocked: `TK-P2-11` Jump-Kick (after Jump done), `TK-P2-14` Countdown (after Start done), `TK-P2-17` Kick Stagger, `TK-P2-18` Pounce. **Followup cards filed from TK-P2-13 review/qa:** `TK-P2-20` late-join-after-start (network, S2), `TK-P2-21` B2 headless probe + stale-wording fix (tools-devops), `TK-P2-22` nits bundle (grace-timer stop, disconnect_peer is_server guard, WaitingRoom literal-true + roster-broadcast guard, slot-capacity), `TK-P2-23` Change Log + TDD §9 barrier/poison doc (docs). Also open: `TK-P2-19` (CI kick-pipeline probe). **Agents:** architect + code-reviewer upgraded fable5→opus (`a25043e`) — opus reviewer caught the TK-P2-13 S1 that automation missed. |
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
- [x] Merge `develop` → `main` — **DONE**: Phase 1 close (`400e7f9` Exit Gate PASS) landed in `main` via **PR #4** (`386cf22`, 2026-07-05), which absorbed the pending PR #3. Phase 1 fully on `main`.
- Audit note [0.28]: S1-A "WASD dead (device:16)" was a FALSE ALARM (human-verified); the 116/116-green-but-broken lesson → per-card pure-function tests missed glue bugs; fixed by adding the 2-instance spawn probe to CI.

## Open cross-phase items (not blocking)
- `TK-P2-09` TigerSelector helper landed early (partial); full card OPEN pending `TK-P2-04` (Phase 2). Architect ack on `managers/` placement deferred to Phase 2.
- Phase-1 wiring picks up deferred infra: define InputMap actions (move/kick/tag) — unblocks Settings→Controls rebind (+ reconcile rebind string format "W"→"w"); audio Music/SFX bus layout still pending.
- Tech-debt: NetworkManager peer-teardown guard / MainMenu nits (task); PDF docs regen to 4.7.

## Next — Phase 2 (Core Loop), the "prove it's fun" milestone
**Gate before any Phase 2 code:** `architect` must approve the **Ability System** design (`TK-P2-16`: refactor Player → Movement / Camera / Ability components + base HumanAbility/TigerAbility; Kick/Tag re-slot as abilities, **Jump/Sprint stay as MovementComponent primitives** per design doc §2/§3 + architect ruling [0.33]/[0.34]). Then Phase 2 starts at that scaffold.
- Phase 2 card order (from `_backlog.json`, +8 new Cowork cards): `TK-P2-16` (Ability scaffold, first) → `TK-P2-01` Kick (ability, DONE) + `TK-P2-10` Jump (movement primitive) / `TK-P2-11` Jump-Kick → `TK-P2-12..15` match flow (Waiting Room → Start → Countdown → GameManager state machine) → Tag Sequence (`TK-P2-02..08`) → `TK-P2-09` first-Tiger (TigerSelector ready). `TK-P3-05` Tiger body-language (Crouch→Lean→Peek) proves the ability system.
- Ability catalog (Phase 3-5): Tiger{Crouch, Lean, Sprint, Pounce, Peek} · Human{Kick, Hide, Emote}.
