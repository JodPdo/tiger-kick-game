# CURRENT_PHASE.md — Tiger Kick

Single source of truth for "where are we now". **Update this whenever the phase/milestone/sprint moves.** Keep it tiny.

| Field | Value |
|---|---|
| Docs Version | v0.12 |
| Game Build | v0.0 — Godot 4.7 project scaffold in repo (TK-P0-01/02 done) |
| Current Phase | **Phase 0 — Setup & Networking** |
| Current Milestone | **M0 Networking** |
| Current Sprint | Networking Foundation |
| Exit Gate goal | 2 machines connect to each other |

## Active this phase
- **Lead agents:** `tools-devops`, `network-engineer`, `gameplay-engineer`
- **Always on:** `producer`, `qa-engineer`, `code-reviewer`, `documentation-manager`
- **Done:** `TK-P0-01` (Godot 4.7 installed), `TK-P0-02` (project scaffold)
- **Open cards:** `TK-P0-03` … `TK-P0-06` (see `_backlog.json`)

## Exit Gate — Phase 0 (from 03_QA/Phase0_QA/03_Exit_Gate)
- [x] clone repo → opens in Godot with no errors (Godot 4.7; verified by CI headless import on push)
- [ ] two instances Host/Join → connect successfully
- [ ] log confirms peer joined
- [ ] Regression suite passes, no open S0/S1

## Next
Phase X — Development Infrastructure (MX Dev Infra) → then Phase 1 (Movement).
