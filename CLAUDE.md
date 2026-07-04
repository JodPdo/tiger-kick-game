# CLAUDE.md — Tiger Kick

Shared project context. **Every agent loads this first.** Keep it short; link out instead of duplicating.

## Project
Tiger Kick (เสือเตะตูด) — a multiplayer party game for 4–8 players, inspired by a Thai folk game. Goal of the whole project: **prove Phase 2 (Core Loop) is fun first, then expand.**

- **Engine:** Godot 4.6, GDScript (C# optional), High-Level Multiplayer, target Steam (PC)
- **Team:** 2 humans + a team of AI agents (see `AGENT_INDEX.md`)
- **Status:** see `CURRENT_PHASE.md` (single source of truth for phase/milestone/sprint)

## Core loop (one paragraph)
One player is the **Tiger** (first-person, limited view) inside a Safe Circle. Everyone else (third-person) sneaks in to **Kick** the Tiger and flee. The Tiger tries to **Tag** anyone who gets close. On a successful tag a 7-step **Tag Sequence** plays (grab → throw → transform) and the tagged player becomes the new Tiger. Rounds are 3–5 min.

## How to find things
Do not guess which doc to read — use the routing table.
- **`DOCUMENT_ROUTING.yaml`** — topic → exact file. Check here first.
- **`Tiger_Kick_Project_Docs/00_README_INDEX.md`** — human onboarding index.

## Working agreement (all agents)
- **Kanban flow:** every task moves one way — `Backlog → Todo → Doing → Review → Done`. WIP in Doing ≤ 1–2 per agent.
- **Pick work from `_backlog.json`:** take cards where `owner_agent` = you, `status: "todo"`, and every id in `depends_on` is already `done`. Never start a card whose dependencies are unmet.
- **Review is mandatory:** finished code goes to `code-reviewer`, then `qa-engineer`. A different agent always reviews.
- **Definition of Done (global minimum):**
  - Meets the card's Acceptance Criteria / DoD
  - Smoke test passes before push (CI runs it too)
  - No open S0 (crash) or S1 (desync) bugs
  - Unit test added for any node-independent logic
- **Exit Gate:** a phase closes only after Regression passes and the phase Exit Gate is met. S0/S1 bugs **block** the gate. Never skip a gate.

## Conventions
- **Language:** agent files (`.claude/agents/*.md`) = English. Team docs (`Tiger_Kick_Project_Docs/`) = Thai. File/folder names and code identifiers = English always.
- **Server authority:** state that decides the game (who is the Tiger, a tag/kick result) is host-authoritative. Clients send intent via RPC; host confirms.
- **Change control:** any change to game design, balance, or architecture must be recorded in `04_Management/03_Change_Log.md`. Architecture changes need `architect` approval.

## Escalation ladder
- Need gameplay change → hand off to `gameplay-engineer`
- Need architecture / TDD change → escalate to `architect`
- Design / balance / scope question → escalate to `designer` (and `producer`)
- Exit Gate / S0–S1 blocker / cross-agent conflict → escalate to `producer`

## Agent roster
See `AGENT_INDEX.md`. Responsibilities per phase: `04_Management/06_Agent_RACI.md`.
