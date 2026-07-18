# Change Log — Tiger Kick

บันทึกการเปลี่ยนแปลงสำคัญของโปรเจกต์และเอกสาร (รูปแบบ Keep a Changelog)
เวอร์ชันล่าสุดอยู่บนสุด

## [0.50] — 2026-07-19 — Producer ruling: TK-P2-11/14/15/20/33 deferred to Phase 3 as carry-overs; TK-P2-14/15 gate TK-P3-03; TK-P2-29/31 kept open in Phase 2 (non-blocking); exact Phase 2 closure conditions recorded

- **Context:** following up on `[0.49]`'s Exit Gate reaffirmation, the human reviewed the full list of open Phase 2 cards and made an explicit deferral ruling rather than leaving them ambiguously open when Phase 2 closes.
- **Deferred to Phase 3 (phase/milestone relabeled, `deferral_ruling` recorded on each):**
  - `TK-P2-11` Jump Kick — never started; enhancement on an already-working, already-verified Kick, not a gate blocker.
  - `TK-P2-14` Countdown + `TK-P2-15` Match state machine (incl. **MatchEnd** — currently undefined anywhere in the codebase) — never started. **Both now block `TK-P3-03`** (`TK-P3-03.depends_on` updated): a real-people playtest session needs a visible synced countdown and a way for the match to actually end, or the session reads as broken/unfinished to first-time testers. Must land at the **start** of Phase 3, before playtesting begins.
  - `TK-P2-20` Late-join/late-connect handling — re-assessed: not S0/S1 in the happy path, and every Phase 2 human pass controlled the join sequence so the gap was never actually reachable; overrides this card's own prior "must close before Exit Gate" note.
  - `TK-P2-33` positive-side-effect regression pattern — hardens against a bug *class* (2 already-fixed occurrences: `TK-P2-32`, `TK-BUG-P2-01`); nothing currently broken depends on it. Recommended early in Phase 3, ideally before `TK-P3-06` (Charged Kick) adds its own similar glue code.
- **Kept open in Phase 2 (not relabeled, reaffirmed non-blocking, `closure_ruling` recorded):** `TK-P2-29` (Tag Sequence step 6 / Safe Circle wiring) and `TK-P2-31` (RoundManager N=1 edge case) — both pure edge-case/consistency items their own original filings already called non-blocking. Tracked as Phase 2 carry-over debt, same pattern as the existing "Open cross-phase items" section for Phase 1.
- **Phase 2 closure conditions (recorded, not yet met — Phase 2 remains OPEN):** the gate closes only once (1) `TK-P2-27`'s solo feel pass (re-scoped in `[0.49]`) has actually been run and recorded PASS — not yet run as of this entry, (2) `TK-P2-29`/`TK-P2-31` have a recorded ruling — done, this entry, and (3) the full regression suite is re-confirmed green at the moment of closing, per the pre-existing Exit Gate rule in `CLAUDE.md`. No S0/S1 bugs are open. Producer flips `CURRENT_PHASE.md`'s Phase 2 section to CLOSED only after (1) is reported PASS.

## [0.49] — 2026-07-19 — Producer ruling: TK-P2-27 re-scoped to solo feel-test; "fun with real people" verdict formally moved to TK-P3-03; Phase 2 Exit Gate reaffirmed as core-loop-playable + no S0/S1

- **Context:** with `TK-P2-30`, `TK-P2-17`, `TK-P2-18`, and `TK-BUG-P2-01` all closed (human 2-instance PASS), the only Phase 2 item left open was `TK-P2-27`'s human feel-test pass — but no second tester is currently available for a live N≥2 session.
- **Decision 1 — `TK-P2-27` re-scoped to a SOLO (N=1) pass:** covers (a) per-role speed-profile feel (Outer 4.0/x1.5 vs Tiger 4.0/4.0-capped, the one item never yet confirmed), Pounce feel, and kick-flee rhythm — all things a solo tester can judge directly against their own Tiger/Outer. Item (b) FP/TP camera swap was already confirmed live on 2026-07-16 and is unaffected. Full rationale in `_backlog.json`'s `TK-P2-27.rescope_note`.
- **Decision 2 — the "is this actually FUN with real people" verdict moves to `TK-P3-03`** (First Playtest, Phase 3, already designer-owned): real multiplayer dynamics (chase/hide tension, whether the Tiger's no-sprint-advantage cap feels fair, whether Kick Stagger's escape window matters against a real player's reflexes) can only be judged with actual other players — that was never solo-observable, and now has an explicit home instead of being informally bundled into a QA feel-test card.
- **Decision 3 — new card `TK-P3-07` (test bot, tools-devops):** extends the existing `tests/net` headless-peer harness pattern (`spawn_probe_together_peer.gd`, `tag_detect_probe_peer.gd`, `spawn_probe_slowjoin_peer.gd`) into a standing bot client — approach the Tiger, kick, flee in a random direction, repeat — so solo testing has a real second body to interact with, and future N≥3 sessions (which this backlog has repeatedly needed and lacked, e.g. `TK-P2-32`'s N≥3 kick-targeting bug and `TK-P3-06`'s Charged Kick counter) are easier to set up. Explicitly scoped as a TEST/DEV TOOL, not a shipped bot-opponent game mode — Tiger Kick's core loop stays Human-vs-Human per the GDD.
- **Decision 4 — Phase 2 Exit Gate reaffirmed, no scope change:** the gate remains "core loop playable + no open S0/S1" (already proven — every Phase 2 mechanic has an automation-green + human-verified pass on record), matching `CURRENT_PHASE.md`'s original Exit Gate goal. The subjective "is it fun" call was always a Phase 3 (`TK-P3-03`/`TK-P3-04`) question, not a Phase 2 gate criterion — this decision documents that the original phase structure holds, it does not relax anything.

## [0.48] — 2026-07-18 — TK-BUG-P2-01 (S2 bug): Kick Stagger `on_confirmed()` gated on the KICKER's own node instead of the resolved TARGET — dead code, now fixed (code-complete, review-pending)

- **Bug (S2, found by human 2-instance test on TK-P2-17):** 12 kicks landed on the Tiger, zero stagger observed, zero `[KICK] stagger applied locally` log line. `characters/abilities/KickAbility.gd`'s `on_confirmed()` runs, via `AbilityController`'s `rpc_confirm` `call_local` broadcast, on the KICKER's own KickAbility node on every peer (Kick is a `HumanAbility` living on the acting Outer's own AbilityController/Player subtree) — so `_body` inside `on_confirmed()` was always the kicker's Player node, never the target's. The stagger gate checked `_body.role == RoleRules.TIGER` (the kicker is by definition never Tiger) and `String(_body.name) == String(target_id)` (the kicker's own name is by definition never `target_id`) — both permanently false for the node this code actually ran on. `MovementComponent.start_stagger()` was structurally unreachable through this path, at any N. Same bug CLASS as `TK-P2-32` (dead/misrouted wiring invisible to green unit tests), 2nd occurrence — filed `TK-BUG-P2-01`, with a QA follow-up (`TK-P2-33`) to formalize a "positively assert the side-effect fired" regression pattern repo-wide.
- **Fix (gameplay-engineer):** `on_confirmed()` now explicitly RESOLVES the confirmed TARGET's own Player node off the shared "Players" root (`players_root.get_node_or_null(str(target_id))`) — the same peer-id → live-node lookup convention `managers/GameManager.gd`'s `apply_role_switch()` / `_apply_tiger_position_correction()` already establish, reused rather than inventing a new one — then gates on `target_node.is_multiplayer_authority()` ("do I own the targeted player") in place of the old permanently-false identity check, before calling `start_stagger()` on the resolved target's own `MovementComponent`. The Tiger-only role check and the knockback-direction-from-kicker-position computation moved to operate off the resolved `target_node` as well. The pre-existing degenerate "kicker not found → ZERO-direction fallback" and "target not found → no-op, no crash" behaviors are preserved. No RPC/authority-model change — this is a client-side node-resolution fix inside an already-existing owner-side cosmetic effect, not a new networking surface.
- **Regression:** new scene-tree-level (real `Player.tscn` instances, not mocks) coverage in `tests/test_kick_rules.gd` — asserts the resolved target's `MovementComponent.is_staggered()` actually flips true (the observable side effect), not just "no crash": (1) stagger applies to the resolved TARGET and never to the kicker's own `MovementComponent`; (2) a peer that does not own the targeted Player applies no local stagger; (3) a non-Tiger target is never staggered even if locally owned; (4) a vanished/never-spawned target does not crash `on_confirmed()`. Verified LOAD-BEARING by temporarily reinstating the pre-fix `_body`-anchored gate: the new "resolves to the target" test fails RED (23/24 in that file) against the old code, and passes GREEN (24/24) against the fix — then the temporary revert was itself reverted, leaving only the fix in place. Full suite: GUT **351/351** (23 scripts, 1723 asserts), no S0/S1, no SCRIPT ERROR, no orphans; all 4 net probes (`run_net_smoke.sh`, `run_spawn_probe.sh`, `run_spawn_probe_together.sh`, `run_tag_detect_probe.sh`) PASS.
- **Status:** code-complete + regression-green, handed to `code-reviewer` → `qa-engineer` per the mandatory review flow; `_backlog.json` `TK-BUG-P2-01` left at `review` (not `done`). `TK-P2-17` stays `doing` — needs a fresh human 2-instance CASE 1 + CASE 2 re-run (not the full checklist) once this fix clears review/QA, since that is the exact surface that just failed.

## [0.47] — 2026-07-18 — TK-P2-30 (S2 bug): readiness-barrier grace no longer force-disconnects a healthy but backgrounded/slow client — grace EXTENSION (code-complete, review-pending-human)

- **Bug (S2, reproduced 2 of the last 5 test sessions, blocking the team's required human 2-instance passes):** the TK-P2-13 Start-Match readiness barrier's grace timer (`networking/PlayerSpawner.gd`'s `ArenaReadyGrace`, `ARENA_READY_GRACE_SEC` = 8.0s) fired ONCE and then **force-disconnected every peer that had not yet sent `_rpc_arena_ready()`** — including a perfectly healthy client whose OS window was simply **unfocused/backgrounded** during Start Match.
- **Root cause (identified, documented):** an occluded/backgrounded window's frame loop is throttled hard by the OS compositor + vsync (down to a handful of fps, sometimes effectively paused while occluded). Godot drives BOTH scene-load completion (the deferred `change_scene_to_file` → `TestArena` instancing → `PlayerSpawner._ready()`) AND the multiplayer poll/flush that actually SENDS the queued reliable `_rpc_arena_ready` packet from that same main loop — so a healthy-but-backgrounded client's readiness announcement can legitimately land well past 8s, and the old timer killed it as if it had crashed. Confirmed NOT a project-config issue: `project.godot` sets no `low_processor_usage_mode` / `max_fps` / vsync override (all Godot defaults), so this is stock engine + OS occluded-window behavior, not a Tiger-Kick misconfiguration.
- **Fix (server-side, host stays fully authoritative):** at each grace elapse, a still-unready peer that is **still connected at the ENet layer** (present in `NetworkManager.get_connected_peer_ids()` / `multiplayer.get_peers()`) is proven alive (not crashed), so the host **EXTENDS** the grace (keeps the whole barrier held — still never spawning toward an absent peer, so zero new path-cache-poison risk) instead of killing it, up to `ARENA_READY_MAX_GRACE_EXTENSIONS` (**new const = 3**, so worst-case hold = 8s × (1 + 3) = **32s** before a genuinely-wedged peer is dropped). Only a peer that is truly gone from the transport, or that burns the entire extension budget while still connected (ENet alive but its game thread never progresses == genuinely wedged), reaches the original TK-P2-13 force-disconnect-then-spawn fallback — so one hung peer still can never deadlock the match forever. Decision logic extracted to a new pure static `networking/ArenaBarrierRules.decide_grace_action()` (same pure-helper/thin-shell split as `RoundRules`/`StaggerRules`/`SafeCircleRules`). This is an **evidence-gated wait, NOT a blind bigger timeout** (candidate fix (a) rejected on its own — an occluded window can be throttled arbitrarily long, so no single fixed number is defensible; the extension only ever grows the wait while the peer is provably still connected).
- **Server authority preserved (CLAUDE.md):** the host alone decides barrier membership and release; it just waits longer, and only on live transport-level evidence the peer is alive. A client can neither force an early release nor hold itself in past the hard cap. No game-deciding state moved client-side.
- **Tunable recorded:** new `ARENA_READY_MAX_GRACE_EXTENSIONS = 3` and the reinterpretation of `ARENA_READY_GRACE_SEC = 8.0` (now the per-extension interval, unchanged value) live as consts on `networking/PlayerSpawner.gd` (network-timing constants, not design-balance — no `Game_Balance.md` entry needed, same as the existing grace const).
- **Regression:** GUT **347/347** (23 scripts, 1717 asserts) incl. new `tests/test_arena_barrier_rules.gd` (11 cases, pure decision logic incl. the max-extensions=0 → original-behavior boundary). New headless net probe `tests/net/run_spawn_probe_slowjoin.sh` (+ `spawn_probe_slowjoin_peer.gd`), B2-pattern: a client that enters the arena at 11s (past the real 8s grace) is EXTENDED and spawns cleanly — **PASSes with the fix, FAILs against the pre-fix behavior** (proven load-bearing by temporarily setting the cap to 0: host logs the exact `force-disconnecting still-unready peer` bug and the client fails). All 4 pre-existing net probes still PASS (net_smoke, spawn_probe, spawn_probe_together [barrier happy-path], tag_detect_probe).
- **Deferred / flagged (NOT done here):** the broader issue that a backgrounded client in a *live match* also throttles its ongoing position/state replication (not just this barrier) is real but out of this card's scope — it belongs with `TK-P2-20` (late-join/reconnect) and/or an `architect` call on whether to force uninterrupted processing/flush for a backgrounded multiplayer client (candidate fix (c) — a rendering/perf-domain change with side effects, not needed to fix this S2). Noted in the card handoff for follow-up, not silently applied.
- **Status:** code-complete + regression-green; per the TK-P2-13/20/21 host-authoritative spawn-barrier surface convention, this changes RPC/timer behavior so it still needs `code-reviewer` → `qa-engineer` and a **human 2-instance pass** (alt-tab a client during Start Match, confirm it is NOT dropped) before Done. `_backlog.json` `TK-P2-30` set to `review-pending-human`, checklist written into its note. Not closed on automation alone.

## [0.46] — 2026-07-16 — TK-P2-07 designer ruling: round-timeout Tiger re-pick = KEEP anti-repeat (Phase 2 placeholder, no code change)

- **Context:** `gameplay-engineer` implemented TK-P2-07 (RoundManager timer + timer-based Round Restart) and made an unescalated design call — at round-timeout the just-expired Tiger is **EXCLUDED** from re-selection (passes `_current_tiger_id` into `TigerSelector.pick_first_tiger()`'s existing `avoid` param) so a timed-out round doesn't immediately hand the reign back to the same player. `code-reviewer` correctly flagged this as a design/balance question (`managers/RoundManager.gd`'s `_on_round_timeout()` + the "FLAG FOR DESIGNER" comment) and routed it to `designer` per CLAUDE.md's escalation ladder. Scope note: this ruling is ONLY about the timeout **re-pick bias**; the timer-baseline round-end itself (not an alternate kick-count/etc. end-condition) is settled and correctly deferred to TK-P3-04 — not in question.
- **RULING: keep anti-repeat as implemented for Phase 2. No code change.** The just-expired Tiger stays excluded from the timeout re-pick when ≥2 candidates exist (graceful fallback to full pool at 1 candidate is already correct/tested).
- **Rationale (fun-first):**
  1. This bias only affects a **corner case** — the timeout path (Tiger caught *nobody* for the full 3–5 min, an already-anticlimactic "dull round"). The main role-flip path (a successful Tag) is deterministic — the tagged player becomes Tiger — and is untouched by this.
  2. In that corner case, anti-repeat is **strictly better for the two pillars** "บทบาทพลิกไว" (roles flip fast) and "ไม่มีใครปลอดภัยตลอด" (no one is safe forever): handing the reign straight back to the player who just sat through a boring reign is the single worst-feeling outcome ("…again?"), and there is no fun argument for occasionally re-inflicting it. A guaranteed fresh Tiger is the better feel.
  3. Cost is **zero**: the `avoid` path already exists and is unit-tested (`tests/test_tiger_assignment.gd::test_anti_repeat_avoids_previous_tiger`, built for TK-P2-09). No new code, no new rule surface.
  4. Does **not** violate the "minimal rules / เข้าใจง่ายใน 10 วินาที" pillar: the exclusion is **invisible to players** (they only ever see "a new Tiger"), so it is a selection-bias, not a player-facing rule to learn.
- **Relationship to [0.18] ("ทุกรอบใหม่สุ่มใหม่ · optional anti-repeat = Phase 3"):** that note flagged anti-repeat as an *optional refinement whose final feel is decided in Phase 3* — it did **not** mandate uniform-random for Phase 2. This ruling is fully consistent: it sets a **placeholder** for the prove-the-loop phase and does **not** lock the final answer.
- **Deferred to TK-P3-04 (real playtest):** whether repeat should stay a hard exclusion, be allowed (uniform), or become a **weighted** "not-recently-Tiger" bias across multiple rounds (needs Tiger-history tracking, which does not exist yet). Revisit if playtesting shows the hard exclusion feels unfair with small player counts or that letting the same Tiger occasionally continue is actually funnier. `Game_Balance.md` §4 "Round length" row already carries the "pending playtest" posture this sits under.
- **Process note:** the engineer's call is retroactively approved *as a placeholder*, but `code-reviewer` was right to block on it — an unescalated design/balance choice must be ruled by `designer` before close, exactly as happened here.

## [0.45] — 2026-07-16 — TK-P2-28 APPROVED (architect ruling: owner-auth Tiger + host backstop = Phase 2-correct)

- **TK-P2-28 (architect ruling) APPROVED:** owner-authoritative Tiger position + host-side best-effort correction (`managers/GameManager.gd`'s `correct_tiger_position`/`_apply_tiger_position_correction` + `characters/components/MovementComponent.gd`'s owner-side clamp) is architecturally correct for Phase 2 — defense-in-depth level matching existing Phase 1/2 movement + role systems. True host-authoritative Tiger containment (effective against modified/cheating clients) deferred to **Phase 3+ anti-cheat hardening, not a Phase 2 must-fix.**
- **Rationale:** (1) Owner-authoritative position is project-wide documented architecture (Game_Balance.md §1: "ตำแหน่ง = owner-authoritative"); every Player's position works this way — not unique to Tiger. (2) Host-authority boundary CLAUDE.md guards ("state that decides the game — Tag/Kick/role-swap") remains intact: these are all re-derived host-side regardless of a Tiger's claimed position (a cheating Tiger cannot forge a role change, tag, or kick result). (3) Design ruling [0.42] point 3 wording "a client cannot walk a Tiger through the boundary by local movement alone" is satisfied: honest-client path (owner clamp + host backstop per TK-P2-06) fully covers this; "by local movement alone" describes honest clients, and the parenthetical anchors requirement to existing Phase 1/2 movement model (owner-authoritative). (4) Phase 2's goal is proving the loop is fun; no anti-cheat work scheduled on roadmap.
- **No code changes.** `GameManager.gd` doc already accurately describes limitation; leave code untouched.

## [0.44] — 2026-07-16 — TK-P2-06 CLOSED (human 2-instance PASS) + 2 follow-ups filed

- **TK-P2-06 (Safe Circle boundary) CLOSED:** human confirmed the 2-instance pass — (1) Tiger cannot walk through the boundary (invisible wall at 5.0m holds), (2) Outer players move in/out of the circle freely (role gate confines only the Tiger), (3) pushing the wall produces no jitter/no rubber-band — live confirmation that the [0.43] tolerance fix (0.05m host-side slack) actually killed the correction-RPC-spam bug network-engineer caught, not just in GUT. Flipped `_backlog.json` status `review-pending-human` → `done`.
- **Follow-up `TK-P2-29` filed** (gameplay-engineer, non-blocking): Tag Sequence step 6's old-Tiger exit teleport still uses its pre-TK-P2-06 placeholder exit-radius math (`GameManager.gd`'s `[TAG-SEQ] ... step6 exit=... (placeholder, TK-P2-06 pending)` log line) — now that the real `SafeCircleRules`/`safe_circle_radius` exist, step 6 should use them directly instead of a separate placeholder guess.
- **Follow-up `TK-P2-30` filed** (network-engineer, non-blocking): human testing raised whether the Start-Match readiness barrier's 8s grace timer (`PlayerSpawner.gd`'s `ArenaReadyGrace`, from TK-P2-13) gives a genuinely slow-but-legitimate client enough headroom before force-disconnecting it, or whether that peer deserves a cleaner recovery path — flagged as related to `TK-P2-20` (late-join-after-start), possibly one mechanism should cover both.
- Both follow-ups are non-blocking; they do not reopen or gate `TK-P2-06`. `TK-P2-28` (architect ruling on true host-authoritative Tiger containment, filed [0.43]) remains open separately.

## [0.43] — 2026-07-15 — TK-P2-06 Safe Circle: code-complete, dual review CHANGES-REQUIRED (1 network defect) + architecture follow-up filed

- **Implementation (gameplay-engineer):** two halves per the TK-P2-06 design ruling — owner-side local prediction (`characters/components/SafeCircleRules.gd` pure radial clamp, horizontal-only; wired into `MovementComponent._physics_process()`, Tiger-only, Outer always passes through) + host-side backstop (`managers/GameManager.gd` host-only `_physics_process()` poll + new `correct_tiger_position` `@rpc(authority,call_local,reliable)`, modeled on `apply_role_switch`). New `tests/test_safe_circle.gd` (26 cases). GUT 272/272 (1422 asserts, 19 scripts), all 4 net probes PASS.
- **code-reviewer verdict:** APPROVE-WITH-NITS. Pure math, role gate, TK-P1-06 non-authority-no-op invariant, radius consistency all verified correct. 2 non-blocking flags routed onward (see below).
- **network-engineer verdict: NOT network-safe as-is — 1 required fix.** `SafeCircleRules.is_inside()`'s exact (no-epsilon) boundary check means the host reads the owner's own float32-clamped position and roughly half the time sees it as a few ULP outside after replication round-trip — since a Tiger pinned against the wall is the single most common state this boundary creates, this fires a reliable, all-peers-broadcast correction RPC ~15-30×/sec/Tiger against an *honest* client. **Required:** epsilon tolerance on the host check. **Strongly recommended:** target the RPC to the owning peer only (`rpc_id`) instead of broadcasting to everyone; correct the `GameManager.gd` comment claiming this RPC "stops" a cheating client — it doesn't (see next point).
- **Architecture flag (both reviewers, independently):** because Tiger position is owner-authoritative (existing model, `Game_Balance.md` §1), the host correction only ever writes the *owning* peer — a genuinely malicious client that skips its local clamp overwrites the correction on its very next authoritative tick, so it is **not actually contained**, only cooperating/transient-bug clients are helped. This is a faithful application of the existing architecture, not a defect in this card — **filed as follow-up `TK-P2-28`** (architect) to rule whether Phase 2 accepts this defense-in-depth level or a true host-authoritative-Tiger-position change is warranted. Non-blocking; the honest-client path (the only one reachable in the current human-testing process) is unaffected either way.
- **Status:** `TK-P2-06` stays `doing` — required network fix sent back to gameplay-engineer; re-review + qa-engineer + human 2-instance pass still to come before Done.

## [0.42] — 2026-07-15 — TK-P2-09 CLOSED (human 2-instance PASS) + Safe Circle boundary ruling for TK-P2-06

- **TK-P2-09 (first-Tiger, host-authoritative) CLOSED:** human confirmed the required 2-instance test — exactly one Tiger, every window agreed on the same peer, no double-Tiger/no missing-Tiger. Flipped `_backlog.json` status `review-pending-human` → `done`. This was the last gate after code-review APPROVE + network-engineer network-safe + QA automation-green (GUT 246/246); per DoD, automation alone was not sufficient for a new live @rpc/host-authority surface, so it stayed open until this human pass. Unblocks `TK-P2-27` (all 3 deps — TK-P2-04, TK-P2-05, TK-P2-09 — now done) and gives `TK-P2-07` (RoundManager) a real Tiger-assignment call site to replace the interim `GameManager._ready()` hook.
- **Safe Circle boundary — design ruling (human/producer):** during the TK-P2-09 pass, the Tiger was observed walking out of the Safe Circle. **Not a bug** — Safe Circle boundary logic is `TK-P2-06`'s scope and does not exist yet. Ruling recorded for `TK-P2-06` implementation:
  - **Tiger is confined inside the circle** — invisible wall at radius **5.0m** (value already locked, [0.34]) blocks the Tiger from exiting.
  - **Outer/human players move freely in and out** — required so they can walk in to Kick the Tiger and flee back out.
  - **Host-authoritative** — the host clamps/rejects position; a client cannot walk a Tiger through the boundary via local movement alone (same server-authority invariant as the rest of Phase 1/2 movement + role systems).
  - If ambiguous at implementation time, `gameplay-engineer` escalates to `designer` before deviating — do not guess.
- Recorded in `_backlog.json`: `TK-P2-09.closed_note`, new `TK-P2-06.design_ruling` field.

## [0.41] — 2026-07-14 — TK-P2-04 Role state machine: valid-transition guard + per-role speed profile wired (code-complete, review-pending)

- **Investigation, not silent closure:** confirmed TK-P2-03/TK-P2-16 groundwork already covered role state + AbilityController distribution + GameManager's authoritative broadcast in full. Two genuinely missing pieces implemented this pass, both flagged in `_backlog.json`'s own scope note before starting:
- **(1) Explicit valid-transition guard:** new `characters/RoleRules.gd` (pure static `is_valid_role()`) — `Player.set_role()` previously accepted any `StringName` unchecked; now fails closed (rejects + logs, leaves `role` unchanged) on anything not `&"outer"`/`&"tiger"`. Separate from `managers/TagSequenceRules.is_valid_role_swap()` (that one sanity-checks a swap's peer IDs on GameManager; this one sanity-checks the role VALUE itself, on PlayerRoot where `role` lives).
- **(2) Per-role MovementComponent speed profile wired for the first time** — this is the "property" half of the card title (`Ability_System_Design.md` §5 step 3 / §6) and Game_Balance.md §2's own "ค่าเป้า...จนกว่า role speed profile จะ wire" note: `MovementComponent` gained `outer_walk_speed`/`outer_sprint_speed` (4.0/6.0) and `tiger_walk_speed`/`tiger_sprint_speed` (4.0/4.0, sprint gives the Tiger no advantage — hunt-not-chase intent) `@export` tunables, a `set_role()` that applies them (called from `Player.set_role()` alongside the pre-existing `ability_controller.set_role()` call), a `_ready()` that self-applies the default role at spawn (same pattern `AbilityController._ready()` already uses), and a pure `speed_profile_multiplier()` helper. **No new balance decision** — these values were already recorded/approved in [0.33]/[0.34]; this only wires them into gameplay for the first time (previously the code still ran the old flat 5.0/×1.4 for every role regardless).
- **TK-P2-05 hook:** new `role_changed(new_role)` signal on `Player`, emitted at the end of a successful `set_role()`, for CameraComponent's future FP/TP swap (TK-P2-05, explicitly NOT built here) or any other future per-role reactor to subscribe to.
- **Tests:** `tests/test_role_state_machine.gd` (16 cases) — pure `RoleRules`/`speed_profile_multiplier` cases, bare-instance `MovementComponent.set_role()` cases, and full `Player.tscn` integration cases (spawn defaults, distribution to both components, signal emission, invalid-role rejection, idempotency). Full regression: GUT 238/238 (1378 asserts), no S0/S1.
- **Side finding, fixed test-locally, filed as followup (`TK-P2-26`, tools-devops):** discovered a pre-existing GUT test-suite-ordering hazard — `tests/test_network_manager.gd`'s `host()`/`disconnect_from_game()` leaves the shared root `MultiplayerAPI` in a "disconnected" (not "offline") state for the rest of the process, breaking any alphabetically-later test script that instantiates `Player.tscn`. Worked around locally in `test_role_state_machine.gd`'s own `before_all()` (resets the SceneTree's `MultiplayerAPI`) — does not touch `networking/NetworkManager.gd` or any production/authority code.
- **Status:** code-complete, REVIEW-PENDING — handed to `code-reviewer` then `qa-engineer` per standard flow; no network-engineer handoff needed (no new RPC/authority surface).

## [0.40] — 2026-07-14 — TK-P2-03 architecture: first GameManager introduced, scene-local placement + minimal scope (TK-P2-03)
- **Architect ruling:** Tag Sequence 7-step now owned by a new **GameManager node (scene-local, not autoload)** introduced at TK-P2-03 with **minimal scope = Tag Sequence orchestration + `is_tag_sequence_active` lock only** — NOT the full match state machine (WaitingRoom → Countdown → Playing → MatchEnd remains TK-P2-15 scope). step 7 ("return to Playing") = unlock only, no enum state in GameManager.
- **Placement:** child node of world/TestArena.tscn, sibling to Players/PlayerSpawner (mirrors PlayerSpawner precedent for networking/match-flow nodes). Authority = 1 (server) by default since GameManager is a static scene node that is never spawn()ed and never a descendant of Player (thus not subject to Player._enter_tree() recursive authority set, unlike AbilityController which must override itself per §4a).
- **RPC ownership:** `apply_role_switch` RPC lives on GameManager (host-authoritative, @rpc("authority","call_local","reliable")) per Ability_System_Design.md §5; does not violate AbilityController's "ability RPC surface" ownership (§8) because role-swap is match flow (GameManager-owned per §5), not ability RPC. ability subclass (TagAbility) has no @rpc of its own per §3.
- **Boundary rule recorded in `Ability_System_Design.md` §8a:** new subsection documenting the architect ruling, placement rationale, and an explicit OPEN QUESTION for TK-P2-15 (must decide whether to promote GameManager to autoload for WaitingRoom↔Arena scene transitions, or keep it scene-local and start the state machine at Countdown only, with pre-arena state elsewhere + hand-off mechanism).
- **Architect APPROVED 2026-07-14.** Autoload-vs-scene-local promotion explicitly deferred to TK-P2-15 as a decision requirement (cannot be left silent).

## [0.39] — 2026-07-13 — TK-P2-02 Tag Detection: architect approval — sensor vs hitbox architectural distinction + RPC-free invariant
- **Architect ruling:** Tag detection placed as **plain Player-root sensor component** (TagDetector Area3D) distinct from ability-owned hitboxes (e.g., KickHitbox) — detection sensors are **role-agnostic, RPC-free, host-side consumption by GameManager**, while hitboxes nest under ability nodes and tie to ability RPC surface.
- **Boundary rule recorded in `Ability_System_Design.md` §2 + §4b:** sensors ≠ abilities; sensor has no owning ability; hitbox must be ability-owned. RPC-free invariant: TagDetector must never grow its own `@rpc` — state transport off the host must go through host-authority nodes (AbilityController/GameManager).
- **Clarification in §3:** "Tag = HOST" refers to Tag action/Tag Sequence (GameManager-owned, TK-P2-03), NOT the passive detection sensor (TK-P2-02).
- **Impact:** resolves apparent Kick-vs-Tag inconsistency for future agents building on this architecture.
- **Verification:** TDD/GDD/routing still valid; no code changes required for this condition.

## [0.38] — 2026-07-13 — TK-P2-13 Start Match: host-authoritative + PlayerSpawner readiness barrier (S1 fix)
- **Start Match = host-authoritative broadcast** (ui/WaitingRoom.gd `_rpc_start_match` + managers/RosterHelper.gd min-player guard) — host กด Start ใน Waiting Room → `@rpc("authority","call_local","reliable")` ยิง broadcast ให้ทุก peer กระโดดเข้า `world/TestArena.tscn` พร้อมกัน (idempotent `_match_started` guard, host-only ยิง RPC แค่ครั้งเดียว)
- **S1 bug ที่เปิดออกมา + fix:** เพราะ peer ทั้งหมด already connected ระหว่างอยู่ใน Waiting Room → when host spawn() any Player ต่อ peer ที่ยังไม่เข้า arena Godot ต้องส่งให้ peer นั้น node-path-cache entry สำหรับ `TestArena/PlayerSpawner` (cache id N); client ที่ยังกำลัง tear down Waiting Room ไม่สามารถ resolve path นั้น ("Node not found: TestArena/PlayerSpawner") → cache id N **ไม่เคย register** บน peer นั้น ถาวร; ต่อมาเมื่อ host spawn() Player ที่ peer นั้นตัวเอง → "ID N not found in cache" / "spawner is null" → spawn drop → **client ลงมาใน arena โดยไม่มี Player ตัวเอง = S1 im ม้วน (นิ่ง ไม่เห็นอะไร)** **Fix = host-side readiness barrier** ใน `networking/PlayerSpawner.gd`: host ห้ามสปอว์นใคร (ไม่ถึงตัวเอง) จนกว่า **every connected peer's PlayerSpawner อยู่ใน tree แล้ว** (แต่ละ client ส่ง `_rpc_arena_ready()` ตอน _ready()); แล้วค่อยสปอว์นทั้งหมดพร้อมกัน (host slot 0, peer ascending id); grace timer 8s force-disconnect peer ที่ไม่เคยพร้อม (convert silent desync → clean recoverable disconnect via new `NetworkManager.disconnect_peer()`); barrier side-door 3 บาน (join / disconnect / grace-timeout ระหว่าง barrier) ปกป้องไว้
- **Verification:** code-review 3 รอบ (opus) → APPROVE-WITH-NITS · qa PASS (GUT 184/184, net_smoke + spawn_probe + new host-first `spawn_probe_together` CI-gated, falsification both ways) · human N-window PASS 2026-07-13
- **Open follow-ups:** TK-P2-20 (late-join-after-start), TK-P2-21 (B2 headless probe + stale wording), TK-P2-22 (nits bundle), TK-P2-19 (CI kick probe)

## [0.37] — 2026-07-07 — TK-P2-10 Jump: code-complete, REVIEW-PENDING (1 review round, S2 fixed)
- **Jump = movement primitive** (characters/components/MovementComponent.gd + new characters/components/JumpRules.gd pure helper), NOT a new characters/abilities/*Ability.gd. This is a re-confirmation, not a new decision -- Ability_System_Design.md §2/§3 and [0.34] below ("Jump=primitive") already ruled this explicitly; CURRENT_PHASE.md's looser "Jump re-slot as abilities" sprint-summary line is stale phrasing from before that detail, superseded by the dated design doc per CLAUDE.md/DOCUMENT_ROUTING precedence. No new architect escalation was needed.
- **Implementation:** `jump_speed` @export tunable (5.0 m/s placeholder, see Game_Balance.md below) · `JumpRules.can_jump(is_on_floor, is_jumping)`/`jump_velocity(jump_speed)` pure statics (GUT-tested) · new `_is_jumping` flag on MovementComponent (own authoritative "did I jump and not land yet" tracking, independent of `is_on_floor()` which is not live on non-authority copies) mirrored onto a new `Player.is_jumping` replicated property (channel A, ON_CHANGE, same pattern as `stance`/`lean`) · new InputMap action `jump` = spacebar (device -1/all) · jump trigger gated on `Input.mouse_mode == MOUSE_MODE_CAPTURED` (same UI/ESC-ESC guard Kick's input uses)
- **Sync:** `.:position` already replicated the full Vector3 (X/Y/Z) before this card -- no change needed there. New: `.:is_jumping` added to Player.tscn's SceneReplicationConfig so remote peers/host can see "this Player has jumped and not landed yet" for animation/feel, since non-authority copies never run physics locally (TK-P1-06 invariant) and so cannot derive it from their own `is_on_floor()`.
- **code-review round 1: CHANGES-REQUIRED → fixed.** Blocking [S2]: the landing-clear branch cleared `_is_jumping` on `is_grounded` alone, keyed off the SAME read the jump-trigger gate used, reducing `JumpRules.can_jump()`'s own is_jumping guard to dead code -- a stale `is_on_floor()`-true tick while still RISING (a known CharacterBody3D lag on slopes/moving floors, never reproducing on the flat TestArena) could silently clear the flag and permit an illegal mid-air re-jump. **Fix:** landing now requires `is_grounded AND velocity.y <= 0.0` (non-upward motion), and the whole landing-clear + jump-trigger decision was extracted into a new `MovementComponent.step_jump(is_grounded, current_velocity_y, jump_input_pressed) -> float` instance method specifically so the ORDERING itself (not just the pure `can_jump()`/`jump_velocity()` statics it wraps) is GUT-reachable without a live physics tick -- added `tests/test_jump_rules.gd` glue coverage (`test_step_jump_no_double_jump_mid_air_even_with_stale_grounded_true` etc.) exercising the exact regression scenario the review caught.
- **nits fixed:** JumpRules.gd Change Log citation corrected to [0.34]/[0.33] (was [0.36]) · renamed `_airborne`/`is_airborne()`/`Player.airborne` → `_is_jumping`/`is_jumping()`/`Player.is_jumping` (review nit: the old name over-promised -- it is only ever true from an actual jump impulse to landing, NOT general "not on the ground", e.g. a ledge-fall never sets it; the TK-P2-11 hook doc now explicitly flags that scope gap) · Player.gd doc corrected ("mirrored every tick, but the underlying flag/value only changes at 2 transitions", was wrongly "every tick") · `jump` InputMap event now `device -1` (all devices, matching editor-authored convention), `kick`'s pre-existing `device 32` left untouched (out of scope) · confirmed both new `.uid` files exist for commit (`characters/components/JumpRules.gd.uid`, `tests/test_jump_rules.gd.uid`)
- **TK-P2-11 hook left:** `MovementComponent.is_jumping()` getter, documented as owner-side PREDICTION only -- explicitly flagged NOT authoritative (the mirrored `Player.is_jumping` is channel-A/spoofable, same "cheat = wrong pose only" class as `stance`/`lean`) AND explicitly scoped to "jumped, not landed yet" (does NOT cover falling off a ledge); Jump-Kick's host_validate() must independently decide how to authoritatively verify jumping/airborne-ness, and must decide whether "Jump Kick" also covers ledge-falls. Left as open questions for that card, not resolved here.
- **Balance:** added `jump_speed` placeholder (5.0 m/s) to Game_Balance.md §4 -- not yet in GDD, tune Phase 3 per this card's own DoD note.

## [0.36] — 2026-07-06 — TK-P2-16 ปิด (มนุษย์เทส 2 หน้าต่างผ่าน) → เริ่ม Kick
- **TK-P2-16 (Ability scaffold) เสร็จสมบูรณ์** — มนุษย์ยืนยัน 2-window: spawn slot/sprint sync/mouse-look/ESC-2-step/host-quit ครบ (refactor 3 step ไม่พังเกม)
- เริ่ม **TK-P2-01 Kick** = ability HOST_AUTHORITATIVE ตัวแรกบน scaffold; เพิ่ม InputMap action `kick` = left mouse button (project.godot)
- nits ที่ผูกกับ Kick: set_role early-guard, ability_id collision assert, `on_confirmed` ต้องไม่ authoritative (forger self-echo เป็น cosmetic)

## [0.35] — 2026-07-05 — แก้ authority model ของ Ability RPC (§4a) — review จับ + architect เคาะ
- **defect:** review TK-P2-16 Step 3 (Fable 5) จับว่า TK-BUG-P1-01 (recursive authority) ทำให้ AbilityController ได้ authority = client เจ้าของ ไม่ใช่ server → `@rpc("authority")` = "owner" → (1) confirm/reject จาก host โดน drop (2) **client forge rpc_confirm ข้าม host_validate ได้ = server-authority พลิกกลับ (S1)** (3) host กด ability ตัวเองไม่ได้ (self-RPC) — เป็น interaction ข้ามการ์ดที่ per-card review มองไม่เห็น, จับได้ตอน scaffold ว่าง (ก่อน Kick)
- **architect ruling (option a, พร้อม probe พิสูจน์ empirically):** AbilityController เรียก `set_multiplayer_authority(1)` ใน `_enter_tree` ตัวเอง (วิ่งหลัง recursive set, override เฉพาะ subtree ตัวเอง; sibling synchronizer/position ไม่กระทบ) → `@rpc("authority")` กลับมาหมายถึง host, engine drop RPC ปลอม (fail-closed) · + host-local activation path (`_host_process_request` เรียกตรงเมื่อ is_server, reject local เลี่ยง self-RPC)
- บันทึกใน `Ability_System_Design.md` **§4a** (authority ของแต่ละ node); TK-P2-01 Kick ต้องยึด: owner=`_body.is_multiplayer_authority()`, host=`multiplayer.is_server()`
- implement: `network-engineer` (RPC/authority domain) แก้ `AbilityController.gd` อย่างเดียว + tripwire test (authority==1)

## [0.34] — 2026-07-05 — บันทึก Game Balance / Physics + การ์ด Pounce/Kick-Stagger
- สร้าง **`01_Design/Game_Balance.md`** = balance/physics source of truth (แทน GDD §Balance / TDD §Physics ที่เป็น PDF) + เดินสาย DOCUMENT_ROUTING (`design.game_balance`)
- **บันทึกค่า (ค่าเสนอ จูน P3):** Kinematic CharacterBody3D server-auth · Human walk 4.0/sprint 6.0 · Tiger ≤4.0 (cap รวม sprint) · Pounce burst ~8 · Safe Circle radius 5.0m (locked — reconcile marker P0-05 ~6.0 ตอน TK-P2-06) · Kick range 1.5 · Sprint=primitive per-role
- **กฎ locked:** เสือ = นักล่าซุ่ม จับด้วย Pounce+จังหวะคนเข้าเตะ ไม่วิ่งไล่
- **การ์ดใหม่:** `TK-P2-17` Kick Stagger (เสือเซ ~0.3s + ดันถอยเล็กน้อย, host-auth, ห้าม stun เต็ม; dep TK-P2-01) · `TK-P2-18` Pounce (ดึงมา Phase 2, TigerAbility burst ~8 m/s = กลไกจับหลัก, host validate; dep TK-P2-16) — backlog 55→57
- อัปเดต notes `TK-P2-16` ยืนยันทิศ architect (Jump=primitive, Tag=GameManager, Sprint ออกจาก Tiger)

## [0.33] — 2026-07-05 — อนุมัติ Ability System (architecture + design + balance) → เริ่ม Phase 2
- **architect เคาะ + มนุษย์อนุมัติ** design Ability System (`TK-P2-16`) — บันทึกเต็มใน `02_Technical/Ability_System_Design.md` (source of truth; TDD.pdf เป็น binary → regen ทีหลัง)
- **โครง:** Player → MovementComponent / CameraComponent / AbilityController → [abilities]; base `Ability`/`HumanAbility`/`TigerAbility`; component = child Node
- **server-authority:** แกน `HOST_AUTHORITATIVE` vs `LOCAL_ONLY` (default HOST); RPC รวมศูนย์ที่ AbilityController ไฟล์เดียว (ability subclass ห้ามมี @rpc); role มาจาก host RPC ห้ามเข้า synchronizer; 2-channel replication (owner-sync pose vs host-RPC result)
- **architect ปรับทิศ (มนุษย์ยืนยัน):** Jump = movement primitive (ไม่ใช่ ability) · Tag Sequence 7 ขั้น = GameManager ไม่ใช่ ability · TagAbility จบแค่ "host ตัดสินว่าจับโดน"
- **BALANCE (มนุษย์ตัดสิน — design/balance change):** Sprint = primitive ทุกคนมี **แต่ความเร็ว per-role**: Human walk 4.0/sprint 6.0, **Tiger รวม sprint ≤ 4.0** (เสือซุ่มไม่วิ่งไล่ จับด้วย Pounce+จังหวะคนเข้าเตะ) → TigerAbility เหลือ {Crouch, Lean, Pounce, Peek}. ค่าเดิม 5.0/×1.4 ใช้ต่อจน role profile wire (จูนจริง Phase 3)
- **migration:** TK-P2-16 = Step1 แยก Movement → Step2 แยก Camera → Step3 AbilityController เปล่า (แต่ละ step no-regress: GUT+net_smoke+spawn probe); Kick = Step4 (TK-P2-01)
- **doc impact ค้าง (มอบ documentation-manager/regen):** TDD §4/§6/§8.1/§9.1 + routing §10 conflict (แก้ให้ชี้ design doc แล้ว) + KickHitbox/TagArea ย้ายไปใต้ ability node

## [0.32] — 2026-07-05 — Phase 1 (M1 Movement) CLOSED ✅
- Exit Gate ผ่านครบ: **มนุษย์เทส 2 หน้าต่างผ่าน** (spawn ไม่ทับ, ESC-ESC Leave, host ปิด→client กลับเมนู, เดิน/กล้อง sync) + CI เขียว (GUT 119/119 + net_smoke + spawn probe เป็น gate แล้ว)
- `TK-P1-07` done (CI wiring). การ์ด Phase 1 ครบ: TK-P1-01..07 + TK-BUG-P1-01/02
- **บทเรียน:** "116/116 เขียว แต่เกมพัง" → เทส pure-function ล้วนมองไม่เห็น glue bug; แก้เชิงระบบด้วยการเพิ่ม 2-instance spawn probe เข้า CI (ไม่ให้เกิดซ้ำ)
- เหลือ: merge PR #3 (มนุษย์) · **gate ก่อน Phase 2 = architect อนุมัติ design Ability System (TK-P2-16)**

## [0.31] — 2026-07-05 — แก้บั๊ก Phase 1 reopen เสร็จ (ผ่าน review 2 รอบ + qa)
- `TK-BUG-P1-01` (S1): authority ย้ายไป `Player._enter_tree()` (จาก name contract + tripwire) และ spawner เปลี่ยนเป็น `MultiplayerSpawner.spawn_function` ส่ง `{id, position}` ถึงทุก peer โดยไม่พึ่ง authority-gated sync (`spawn=false` บน position/rotation; `_spawnable_scenes` ถอดออกกัน footgun) — spawn probe: client ลง slot ตัวเอง ไม่ทับ host ไม่ (0,0,0) ไม่มี pending-spawn error
- `TK-BUG-P1-02` (S2): signal `NetworkManager.server_disconnected` → `world/TestArena.gd` (ใหม่) พากลับ MainMenu + คืนเมาส์; Leave = ESC-ESC (ESC แรก consume ใน Player ตอน CAPTURED — แก้ single-ESC race ที่ reviewer จับได้จากการยิง key จริง); guard `host()/join()` = ERR_ALREADY_IN_USE
- เทสใหม่: NetworkManager 3 เคส + `tests/net/spawn_probe_peer.gd`/`run_spawn_probe.sh` (เช็ค XZ-tolerance กัน false-pass จาก gravity settle) — GUT 119/119, net_smoke + spawn probe + windowed ESC probe ผ่านหมด
- late-join ตรวจแล้ว**ไม่ใช่ปัญหา** (reviewer ทดลอง 3-instance: late joiner เห็นตำแหน่งปัจจุบันทันที)
- เหลือ: `TK-P1-07` (net smoke + spawn probe เข้า ci.yml) + **มนุษย์เทส 2 หน้าต่าง** = เงื่อนไขปิด Phase 1

## [0.30] — 2026-07-05 — ปรับ model ทีม AI agent
- `producer` / `architect` / `code-reviewer`: opus → **claude-fable-5** · `designer`: sonnet → **claude-opus-4-8** (7 ตัวที่เหลือคง sonnet) — แก้ทั้ง frontmatter `.claude/agents/*.md` และตาราง AGENT_INDEX.md
- ตัดสินโดย: มนุษย์ (project owner)

## [0.29] — 2026-07-05 — ทิศทางสถาปัตย์ใหม่: Ability System (รอ architect อนุมัติ design) + การ์ดใหม่ 8 ใบ
- **adopt Ability System** — `TK-P2-16` scaffold: refactor PlayerController → Movement / Camera / Ability (+ base HumanAbility/TigerAbility) เป็น **งานแรกของ Phase 2** หลังปิด Phase 1; ของเดิม (Kick/Jump/Tag) re-slot เป็น ability — **ต้องให้ `architect` อนุมัติ design ก่อนลงมือ**
- `TK-P3-05` Tiger Body-Language (Crouch → Lean L/R → Peek) = สกิลตัวอย่างพิสูจน์ระบบ (hunt-not-chase)
- Ability catalog (แผน Phase 3-5): Tiger{Crouch, Lean, Sprint, Pounce, Peek} · Human{Kick, Hide, Emote}
- การ์ดใหม่จาก Cowork 8 ใบ: `TK-P2-10/11` (Jump, Jump Kick), `TK-P2-12..15` (Waiting Room → Start Match → Countdown → Match state machine), `TK-P2-16`, `TK-P3-05` — backlog รวม 52→55 ใบ (รวม bug cards ด้านล่าง)
- เสนอ/ตัดสินโดย: มนุษย์ (project owner)

## [0.28] — 2026-07-05 — Audit อิสระ Phase 0-X-1 → REOPEN Phase 1 (แก้บั๊กก่อนเข้า Phase 2)
- producer (Fable 5) ตรวจงานใหม่ทั้งหมดแบบ adversarial + มนุษย์ยืนยันด้วยการเทส 2 หน้าต่างจริง
- **S1-A "เดินไม่ได้ (device:16)" = FALSE ALARM** — มนุษย์เทสจริง: WASD เดินได้ปกติ device:16 ไม่กระทบคีย์บอร์ด (ไม่แก้ project.godot)
- **บั๊กจริงที่ยืนยัน → REOPEN Phase 1:**
  - `TK-BUG-P1-01` (S1, blocker): client spawn ทับหัว host / โผล่ (0,0,0) + engine error "unable to process the pending spawn" ทุก join — สาเหตุ: `PlayerSpawner._on_spawned()` เซ็ต authority หลัง `_ready()` → แก้โดยย้ายไป `Player._enter_tree()`/spawn_function
  - `TK-BUG-P1-02` (S2): host ปิดเกม → client ค้างในสนามว่าง ไม่มีทางออก — แก้: signal `server_disconnected` → กลับ MainMenu + ปุ่ม Leave (`disconnect_from_game()` ยังไม่มี caller เลย)
  - `TK-P1-07`: net smoke เข้า `ci.yml` + 2-instance integration probe (เกณฑ์ no-ERROR + client ไม่ทับ host) — อุดช่องที่เทส pure-function ล้วนมองไม่เห็น glue bugs
- ลำดับที่ตกลง: แก้บั๊ก → มนุษย์เทส 2 หน้าต่าง → ปิด Phase 1 / PR #3 → architect เคาะ Ability System → เริ่ม Phase 2 ที่ TK-P2-16

## [0.27] — 2026-07-05 — Phase 1 code ครบ: synchronizer tuning + remote-physics guard
- `TK-P1-06`: MultiplayerSynchronizer sync เฉพาะ position+rotation, mode ALWAYS→ON_CHANGE (ไม่ส่ง packet ตอนนิ่ง, spawn=true คง seed แรก), non-authority peer skip move_and_slide/gravity (puppet ขับด้วย sync ล้วน กัน jitter), guard is_valid_int ใน _on_spawned
- **Phase 1 (M1 Movement) code ครบ 6/6** — เหลือ Exit Gate: มนุษย์ทดสอบ GUI 2 หน้าต่าง (เดิน/กล้อง/no-jitter) + merge PR #3

## [0.26] — 2026-07-05 — Phase 1: spawner + camera rig + per-player authority
- `TK-P1-04` MultiplayerSpawner: spawn Player ต่อ peer id (host-authoritative), despawn on disconnect, กล้อง current เฉพาะ local (host-local path + client replicated)
- `TK-P1-03` third-person camera rig: `Player→CameraRig→SpringArm3D→Camera3D`, mouse-look (yaw/pitch clamp -60..+30), camera-relative movement, contract `get_view_camera()`
- `TK-P1-05` per-player authority: `set_multiplayer_authority(peer_id)` (host+client path), synchronizer follows recursive → แต่ละ peer คุม player ตัวเอง
- ค้าง (TK-P1-06): skip move_and_slide/gravity บน non-authority peer (กัน jitter) + synchronizer property tuning + guard `int(node.name)` ใน _on_spawned

## [0.25] — 2026-07-05 — Phase 1: movement + InputMap actions
- `TK-P1-02` movement: WASD + gravity + Sprint (Shift) ใน `characters/Player.gd`, ค่า walk 5.0 m/s / sprint ×1.4 จาก TDD §11 (export ปรับได้), input gate `is_multiplayer_authority()`
- เพิ่ม **InputMap actions** ใน `project.godot` `[input]`: `move_forward`(W)/`move_back`(S)/`move_left`(A)/`move_right`(D)/`sprint`(Shift) — ปลดล็อกงาน Controls-rebind ที่ค้างจาก TK-PX-05 ด้วย (ชื่อ action ตรงกับ REBIND_KEYS)
- ค้าง (ผูกไว้ TK-P1-05/06): non-authority peer ยังรัน move_and_slide → ต้อง skip บน remote กัน jitter ตอน authority per-player + synchronizer active

## [0.24] — 2026-07-04 — Phase X ครบ: Settings menu + PerfOverlay (จบ MX Dev Infra)
- `SettingsMenu` (`ui/SettingsMenu.gd/.tscn`, TK-PX-05): Graphics/Audio/Controls tabs → ConfigManager (get/set/save), apply DisplayServer/AudioServer แบบ guard headless + missing-bus; เข้าถึงจากปุ่ม Settings ใหม่ใน MainMenu (แก้ TK-P0-03 แบบ additive — NET SMOKE ยืนยันไม่ regress Host/Join)
- `PerfOverlay` (`ui/PerfOverlay.gd`, TK-PX-03): overlay กด F4 ใช้ Performance singleton (memory/draw/objects/primitives/nodes/process/physics), แยกจาก DebugOverlay (F3, layer 100 vs 101)
- Autoload set: GameLog, ConfigManager, NetworkManager, ErrorHandler, DebugOverlay, PerfOverlay
- **Follow-ups (non-blocking, ยกไป Phase ถัดไป):** (1) Controls rebind รอ InputMap actions ของ Phase 1 (ตอนนี้ placeholder + เก็บใน config) + reconcile รูปแบบ string ("W"→"w"); (2) audio bus layout (Music/SFX) ยังไม่ตั้ง — slider warn+no-op จนกว่าจะเพิ่ม
- verified: GUT 88/88 (1135 asserts) exit 0, ไม่มี rp_logger/leak, NET SMOKE PASS
- **Phase X (MX Dev Infra) เสร็จครบ 7 การ์ด**

## [0.23] — 2026-07-04 — Phase X: เพิ่ม DebugOverlay + ErrorHandler autoloads
- `DebugOverlay` (`ui/DebugOverlay.gd`, TK-PX-02): overlay กด F3 เปิด/ปิด แสดง FPS/ping/scene/role/peers, refresh 0.25s, ไม่ crash ตอน offline
- `ErrorHandler` (`managers/ErrorHandler.gd`, TK-PX-06): `report()/report_if()` route ผ่าน GameLog.error — convention จับ error สำคัญแทน bare push_error (ไม่ hook engine logger เลี่ยงชน GUT error_tracker)
- Autoload set ปัจจุบัน: GameLog, ConfigManager, NetworkManager, ErrorHandler, DebugOverlay
- verified: GUT 52/52 (1083 asserts) exit 0, ไม่มี rp_logger/leak

## [0.22] — 2026-07-04 — Logger autoload ตั้งชื่อ `GameLog` (เลี่ยงชนกับ engine class `Logger`)
- Phase X: เพิ่ม autoload `GameLog` (ไฟล์ `managers/Logger.gd`) และ `ConfigManager` (`managers/ConfigManager.gd`)
- **บั๊กที่จับได้ตอน integration:** ตั้งชื่อ autoload ว่า `Logger` **ชนกับ Godot built-in class `Logger`** ที่ GUT `error_tracker.gd` ใช้ (`extends Logger` + `OS.add_logger`) → GUT error-tracking พังเงียบ (`rp_logger is null`) + ObjectDB leak. เปลี่ยนชื่อ singleton เป็น `GameLog` แก้หมด (GUT 37/37 clean, ไม่มี leak). ไฟล์คง `Logger.gd`; โค้ดเรียกผ่านชื่อ singleton `GameLog.info()/warn()/error()` — **ห้ามตั้ง autoload ชื่อ `Logger` อีก**
- ConfigManager: method `load()` เดิมชนกับ builtin `load(path)` → เปลี่ยนเป็น `load_config()` (API: `get_value/set_value/save/load_config` + static `resolve_value/apply_defaults` + `DEFAULTS`)
- ตัดสินโดย: producer (integration fix); code identifiers ตรวจโดย code-reviewer/qa

## [0.21] — 2026-07-04 — เพิ่ม guard ตรวจ _backlog.json ใน CI
- เพิ่ม `tools/validate_backlog.py` — ตรวจ JSON valid + id ไม่ซ้ำ + depends_on ชี้ id ที่มีจริง + ฟิลด์ id/status ครบ + status อยู่ในชุดที่อนุญาต
- เพิ่ม step ใน `ci.yml` (รันก่อนโหลด Godot, fail เร็ว) → ถ้า backlog เสีย/ถูกตัด build แดงทันที รู้ตัวก่อน agent หยิบงานผิด
- ไม่กระทบเกม/บิลด์ (เป็น dev tool ล้วน) · รันเองในเครื่องได้: `python3 tools/validate_backlog.py`
- ทดสอบแล้ว: ไฟล์ปกติ→ผ่าน, ไฟล์ถูกตัด→exit 1 (แดง)

## [0.20] — 2026-07-04 — ติดตั้ง GUT + ต่อ CI ให้รันเทสจริง (TK-PX-07 → review)
- vendored **GUT 9.7.0** ที่ `addons/gut/` (commit เข้า repo; .gitignore อนุญาตอยู่แล้ว)
- แก้ `.github/workflows/ci.yml`: เอา branch "skip if GUT missing" ออก → GUT รันทุก push/PR และ **fail build ถ้าเทสตก** (-gexit)
- เทสที่จะรันจริง: `tests/test_network_manager.gd` (เดิม) + `tests/test_tiger_assignment.gd` (ใหม่, 10 เคส) บน `managers/TigerSelector.gd`
- verify: รัน Godot ในแซนด์บ็อกซ์ไม่ได้ (network allowlist บล็อก CDN binary ของ Godot) → พิสูจน์ logic ด้วย Python port (9/9 ผ่าน) + static review (tab ล้วน) · green จริงมาจาก CI ตอน push
- TK-PX-07 → status **review** (handoff ครบ)
- ⚠️ **เหตุการณ์:** พบ `_backlog.json` โดนตัดหาย (truncate) ครั้งที่ 2 ระหว่าง agent เขียนไฟล์พร้อมกัน — กู้คืนครบ 44 การ์ด (คงสถานะ review ของ TK-P0-06 ไว้) · แนะนำเพิ่ม guard ตรวจ JSON valid (ดูข้อเสนอ)

## [0.19] — 2026-07-04 — เพิ่ม unit test spec สำหรับสุ่มเสือตัวแรก (TK-P2-09)
- เพิ่ม `managers/TigerSelector.gd` — pure helper (static, node-independent, inject RNG) แยก logic การสุ่ม/แจกบทบาทออกจาก multiplayer เพื่อให้ unit-test ได้
- เพิ่ม `tests/test_tiger_assignment.gd` (GUT) 10 เคส: mock 4 peers → เสือ 1 ตัวเสมอ, เสืออยู่ในลิสต์จริง, fairness (ทุกคนถูกสุ่มได้), single/empty/stale-id edge, anti-repeat, determinism (seed เดียวกันได้ผลเดียวกัน)
- indentation เป็น tab ล้วน (ตรวจแล้ว) · รันได้เมื่อ GUT ลง (TK-PX-07) · integration เข้า GameManager/RPC ยังทำตามการ์ด TK-P2-09 ผ่าน review

## [0.18] — 2026-07-04 — เพิ่มการ์ดสุ่มเสือตัวแรก (TK-P2-09)
- เพิ่ม `_backlog.json`: **TK-P2-09** สุ่มเสือตัวแรกตอนเริ่มรอบ (host-authoritative + broadcast)
- กติกาสถาปัตย์: HOST สุ่มคนเดียว (randomize() ครั้งเดียว) แล้ว broadcast ผ่าน @rpc(authority, call_local, reliable) — client ห้ามสุ่มเอง กัน desync (S1)
- ผูก: depends_on [TK-P2-04 Role state machine] · เรียกโดย RoundManager (TK-P2-07) ตอนสถานะ Random Tiger · pair กับ network-engineer
- edge cases: รวม host ในการสุ่ม, สุ่มใหม่ถ้าคนถูกเลือกหลุด, ทุกรอบใหม่สุ่มใหม่ · optional anti-repeat = Phase 3
- Backlog รวม 44 การ์ด (Phase 2 = 9 ใบ)

## [0.17] — 2026-07-04 — เพิ่มการ์ด backlog Phase 4 (Art/Character) 4 ใบ
- เพิ่มใน `_backlog.json`: **TK-P4-05** (โมเดล+rig เสือ), **TK-P4-06** (โมเดล+rig ผู้เล่น base เปล่า + material slot), **TK-P4-07** (Toon Shader + Rim Light pipeline), **TK-P4-08** (ระบบแต่งตัว Lobby + network sync)
- ผูก dependency: P4-07 ← [P4-05, P4-06] · P4-08 ← [P4-06] · owner: polish-agent (05/06/07), gameplay-engineer (08, handoff network sync ให้ network-engineer)
- ทุกใบมี `notes` ชี้ ref → Character_Art_Bible.md + refs/*.png และระบุ DoD ย่อ
- Backlog รวมเป็น 43 การ์ด (Phase 4 = 8 ใบ) · หมายเหตุ: 05_Backlog.md/.csv/.xlsx (human view) ยังไม่ regen — รอทำรอบเดียวพร้อมกันได้

## [0.16] — 2026-07-04 — ล็อกสเปกผู้เล่น (ไม่ใช่เสือ) จาก character sheet + แก้ขนาดเสือ/ผู้เล่น
- รับ **character sheet ผู้เล่น** จากคุณเป็นมาตรฐาน → อัปเดต Art Bible §4, §4B, §7
- **ขนาด (แก้ conflict):** เสือ **~2.0m** (ใหญ่กว่า) · ผู้เล่น **1.2–1.4m** — แก้ §3 เดิมที่เขียนว่าเสือเตี้ยกว่าผู้เล่น (ขัดกับ sheet) ให้ถูกต้อง
- **สเปกผู้เล่น:** low-poly toon ทรงเรียบ สีขาวเปล่า = ผ้าใบ · ~1K–2K tris · Toon Shader + Rim Light · turnaround 4 มุม
- **Customization (Cosmetic Only, ที่ Lobby):** สีพื้น 8 สี · decal (หน้ายิ้ม/ดาว/มงกุฎ/"สู้ๆ"/"KICK ME!" ฯลฯ) · accessory 4 หมวด (หมวก/กระเป๋า/ผ้าพันคอ/แว่น)
- **Animation:** เพิ่ม Jump เข้า set · ยืนยันตัวหลักผู้เล่น: วิ่ง/กระโดด/เตะ/โดนเตะ-ล้ม · ใช้ rig ร่วมกับเสือได้
- ที่วางไฟล์: `01_Design/refs/player_style_ref.png`

## [0.15] — 2026-07-04 — ล็อกสเปกผลิตตัวเสือจาก character sheet
- รับ **character sheet เสือ (turnaround 6 มุม)** จากคุณเป็นมาตรฐานหน้าตา → อัปเดต Art Bible §3, §9
- **สเปกที่ล็อก:** ทรงง่าย/อ่านชัด · โทนสีสด · **Toon Shader + Rim Light** · โพลีต่ำ **~1K–2K tris**
- **มาร์กกิ้ง:** เสือส้ม+ลายดำ+พุงครีม + **รอยเท้าแมวกลางพุง** (signature) · Turnaround: Front/3-4/Side/Back
- **ยืนยันแล้ว:** เสือขาวใน sheet = **palette variant เฉย ๆ** (ไม่ใช่สกิน/บทบาท) — เสือมาตรฐาน = ส้ม+ลายดำ+พุงครีม
- ที่วางไฟล์: `01_Design/refs/tiger_style_ref.png` (Art Bible ชี้ path นี้แล้ว)

## [0.14] — 2026-07-04 — ล็อกสไตล์ Art = Toon/Low-poly (อ้างอิง MECCHA CHAMELEON) + เพิ่มระบบแต่งตัวที่ Lobby
- **Art Direction ล็อก:** Stylized/Toon + Low-poly (cel-shaded, รันบน integrated GPU ได้) อ้างอิงหลัก = MECCHA CHAMELEON — บันทึกใน `01_Design/Character_Art_Bible.md` §1
- **ตัวเสือ:** low-poly toon เสือ ทรงป้อมน่ารักแต่ดุนิด ๆ, **สีตัวตายตัว (ผู้เล่นแก้ไม่ได้)** เพื่อ readability
- **ผู้เล่น (ไม่ใช่เสือ):** โมเดลฐานเรียบ/เป็นผ้าใบ **ทาสี/แต่งตัวเองได้** — feature ใหม่ §4B
- **ขอบเขต feature "แต่งตัว":** เป็น **COSMETIC ล้วน ทำที่หน้า Lobby ก่อนแมตช์เท่านั้น** ไม่ใช่กลไกพรางตัว (ต่างจาก MECCHA) และ **ไม่กระทบ Core Loop เดิม** (แอบ→เตะ→หนี) — ตัดสินโดยคุณ (มนุษย์) 2026-07-04
- **ผลต่อ Tiger Indicator (§5):** ห้ามพึ่ง "สีตัว" อย่างเดียวชี้เสืออีกต่อไป เพราะผู้เล่นเลือกสีเองได้ → ต้องซ้อนหลายชั้น (โมเดลเสือแยก + เอฟเฟกต์/ไอคอน)
- **Phase placement:** ระบบแต่งตัววางไว้ **Phase 4 (Polish) ขั้นต่ำ / เต็มรูปแบบก่อน Ship** — ยังไม่แตะ Phase 0–2 (พิสูจน์ความสนุกก่อน) — ทีมยืนยัน scope + เพิ่มการ์ด backlog ก่อนลงมือ
- ผู้เสนอ/อนุมัติ: คุณ (มนุษย์) · ต้องให้ `designer` เซ็นก่อน `polish-agent` ลงมือ (ตามกติกา Art Bible §10)

## [0.13] — 2026-07-04 — แก้ path NetworkManager ให้ตรง TDD §3 (managers/ → networking/)
- ย้าย `NetworkManager.gd` จาก `res://managers/` ไป `res://networking/` เพื่อให้ตรงกับ TDD §3 (Folder Structure) ที่กำหนด `networking/` เป็นที่อยู่ของ NetworkManager/RPC/sync ส่วน `managers/` สงวนให้ GameManager/RoundManager/ConfigManager/Logger
- เหตุ: การ์ด TK-P0-04 ระบุ path `managers/` ซึ่งขัดกับ TDD; TDD คือ source of truth ด้านสถาปัตย์ (ตาม DOCUMENT_ROUTING) จึงทำโค้ดให้ตรง TDD — ถือเป็นการ *conform* ไม่ใช่ *เปลี่ยน* สถาปัตย์
- อัปเดต: `project.godot` [autoload] → `res://networking/NetworkManager.gd`, preload path ใน `tests/test_network_manager.gd`
- อนุมัติโดย: producer (ไม่ต้องขอ architect เพราะเป็นการทำตาม TDD เดิม ไม่ได้แก้ TDD)

## [0.12] — 2026-07-04 — อัปเกรด Engine Godot 4.6 → 4.7
- เปลี่ยนเวอร์ชัน Engine จาก Godot 4.6 เป็น Godot 4.7 (เป็น stable build ใหม่กว่า ไม่มี breaking change ต่อ High-Level Multiplayer/ENet ที่ใช้ใน Phase 0 และตรงกับ build ที่ติดตั้งจริงบนเครื่อง — `Godot_v4.7-stable_win64_console.exe`, verified `4.7.stable.official`)
- อนุมัติโดย: producer
- อัปเดตทุกจุดที่อ้างอิงเวอร์ชัน Engine: CLAUDE.md, WORKSPACE_SETUP.md, _backlog.json (TK-P0-01), 05_Backlog.md/.csv, _AGENT_CONTRACT_TEMPLATE.md, .claude/agents/{gameplay-engineer, network-engineer, tools-devops}.md
- หมายเหตุ: รายการ [0.2] ด้านล่างเป็นบันทึกประวัติศาสตร์ (Unity → Godot 4.6 ตอนนั้น) คงไว้ตามเดิมเพื่อความถูกต้องของประวัติ ไม่แก้ไขย้อนหลัง

## [0.11] — เพิ่ม Character & Art Bible
- เพิ่ม 01_Design/Character_Art_Bible.md (สไตล์/สี/Tiger indicator/animation set) — designer เป็นเจ้าของ, polish-agent ต้องทำตาม
- เดินสาย: DOCUMENT_ROUTING (design.character_art_bible) + Required Reading ของ designer และ polish-agent
- ซ่อม _backlog.json ที่เสีย (กู้ 26 การ์ดเดิม + สร้างส่วนที่ขาด ครบ 39 การ์ด valid)

## [0.10] — README: ลำดับภายในโฟลเดอร์
- เพิ่มหัวข้อ "Reading Order within Each Folder" (Sequential vs Reference/Living)
- อธิบายว่าไฟล์ชุดไหนอ่านเรียง ชุดไหนเปิดเฉพาะตอนใช้ และเหตุผล

## [0.9] — จัดโครงรวม + ยกระดับ README เป็น Onboarding Guide
- รวมเอกสารทั้งหมดเป็นโครงเดียว Tiger_Kick_Project_Docs (01_Design / 02_Technical / 03_QA / 04_Management)
- README เพิ่ม: Current Status, How to Read the Diagrams, If you are…, Project Mental Model
- เพิ่มไดอะแกรม Mental Model และ Dev/QA Workflow (diagrams/)

## [0.8] — เพิ่ม Backlog รายเฟส
- เพิ่ม Management/05_Backlog (md/pdf) + 05_Backlog.csv + 05_Backlog.xlsx
- ดึงงานย่อยทุกเฟสเป็น backlog 39 การ์ด พร้อม ID (TK-P#-##), priority, label, milestone
- ไฟล์ csv/xlsx import เข้า GitHub Projects / Trello / Notion ได้ทันที

## [0.7] — Team Workflow (ทีม 2 คน)
- เพิ่ม Management/04_Team_Workflow: Kanban Board, Issue Tracker, Milestones
- แนะนำใช้ GitHub Projects + Issues + Milestones (ครบในที่เดียว)
- นิยาม label (type/severity/priority/phase) และผูกกับ QA/RTM/Milestone Plan

## [0.6] — เพิ่ม Technical Design Document (TDD)
- สร้าง TDD พร้อมไดอะแกรมจริง: Architecture, Scene Tree, Class Diagram, Round Flow, State (Player/Tag), Network Flow
- เพิ่ม Round Flow (Lobby → Random Tiger → Countdown → Playing → Tag Sequence → Round End → Score → Next Round)
- กำหนด Safe Circle Specification (รัศมี, ผู้เล่นเข้าวง, เสือออกนอกวง)
- เพิ่มตาราง Game Balance (ค่าเริ่มต้นเสนอ, ปรับใน Phase 3) และตาราง RPC/Signals

## [0.5] — เปลี่ยน Tag เป็น Tag Sequence
- Phase 2 GDD: เปลี่ยน "Tag จับทันที" เป็น Tag Sequence 7 ขั้น (จับ → ทุ่ม → กลายร่าง → สลับบทบาท → เสือเดิมออกนอกวง → Playing)
- กำหนดงบเวลา Tag Sequence ≤ 1.2–1.5 วินาที (Grab 0.2–0.3s, Throw 0.3–0.5s, Transform 0.5–0.7s)
- เพิ่ม signal: tag_sequence_started / tag_sequence_finished
- Phase 4 GDD: เพิ่ม Grab/Throw Animation, Transform VFX, Camera Shake, เสียงคำรามเสือ
- อัปเดต GDD หลัก (หัวข้อ Core Loop / Role Switching) ให้ตรงกัน

## [0.4] — เพิ่มชุดเอกสาร PM และ QA เสริม
- เพิ่ม Management/: Milestone Plan, Risk Register, Change Log
- เพิ่มใน _shared/: RTM, Test Data, Automation Matrix, Risk Matrix, Metrics Dashboard, Release Readiness

## [0.3] — QA Package
- สร้าง QA Package แบบ Hybrid (เอกสารกลาง + รายเฟส 7 เฟส)
- กำหนด QA Architecture: Regression อยู่ก่อน DoD ก่อน Exit Gate
- เพิ่ม Severity S0–S4 และ Bug Lifecycle

## [0.2] — เปลี่ยน Engine และเพิ่ม Phase X
- เปลี่ยนจาก Unity เป็น Godot 4.6 (High-Level Multiplayer)
- เพิ่ม Phase X — Development Infrastructure
- เสริมทุกเฟสด้วยข้อเสนอระดับ Senior/TD

## [0.1] — เอกสารเริ่มต้น
- สร้าง GDD (Game Design Document)
- แบ่งแผนพัฒนาเป็น Phase 0–5

## วิธีใช้
- ทุกการเปลี่ยนแปลง scope, ค่าปรับจูน, หรือโครงสร้างเอกสาร ให้เพิ่มรายการที่นี่
- ก่อน Release ให้สรุปเป็นหัวข้อเวอร์ชันที่จะปล่อย
