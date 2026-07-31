# CLAUDE.md — Tiger Kick

Shared project context. **Every agent loads this first.** Keep it short; link out instead of duplicating.

## Project
Tiger Kick (เสือเตะตูด) — a multiplayer party game for 4–8 players, inspired by a Thai folk game. Goal of the whole project: **prove Phase 2 (Core Loop) is fun first, then expand.**

- **Engine:** Godot 4.7, GDScript (C# optional), High-Level Multiplayer, target Steam (PC)
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
- **Pick work from `_backlog_index.json`, not `_backlog.json`.** The full backlog is ~83k tokens; the index is the same 82 cards with only the decision fields. Do not read `_backlog.json` to find your work.
  - `python3 tools/split_backlog.py --agent <your-name>` — your queue, ready cards first
  - `python3 tools/split_backlog.py --card <ID>` — pull the one card you are starting, in full
  - Take cards where `owner_agent` = you and `ready` is `true` (the index computes `ready` as `status: "todo"` **and** every id in `depends_on` already `done`). Never start a card whose dependencies are unmet — `blocked_by` names what it is waiting on.
  - `_backlog_index.json` is **generated — never hand-edit it.** After changing `_backlog.json`, run `python3 tools/split_backlog.py`. CI runs `--check` and fails on drift.
- **Review is mandatory:** finished code goes to `code-reviewer`, then `qa-engineer`. A different agent always reviews.
  - **Exception:** dev-tooling changes that touch neither game code nor runtime behavior (e.g. `tools/`, CI scripts, lint/validation scripts) may close after `code-reviewer` alone — `qa-engineer` is not required.
  - Anything touching game code — gameplay, engine scenes, RPC/networking, or anything that runs in the shipped build — always needs both `code-reviewer` and `qa-engineer`, no exceptions.
- **Definition of Done (global minimum):**
  - Meets the card's Acceptance Criteria / DoD
  - Smoke test passes before push (CI runs it too)
  - No open S0 (crash) or S1 (desync) bugs
  - Unit test added for any node-independent logic
- **Exit Gate:** a phase closes only after Regression passes and the phase Exit Gate is met. S0/S1 bugs **block** the gate. Never skip a gate.

## Parallel work rules

Agents may run at the same time, but only under these rules. They exist because this project has already been bitten twice: `_backlog.json` was corrupted by concurrent writes (that is why `tools/validate_backlog.py` exists), and TK-P2-05's QA verdict had to be qualified because the GUT run picked up another agent's uncommitted `GameManager.gd` changes from the shared working tree.

**Who may run concurrently**

- **Read-only agents — always safe, run as many as you like.** `architect`, `code-reviewer`, `producer` hold no `Edit` tool or touch docs only. Reviewing several cards in parallel is the cheapest speedup available, and the most valuable: both reviewers sit on the critical path of every card.
- **Code-writing agents — one per git worktree, never two in the same tree.** `gameplay-engineer`, `network-engineer`, `tools-devops`, `polish-agent`, `qa-engineer` all write files. Create the worktree first:
  ```bash
  bash tools/new_worktree.sh <agent-name> [card-id]
  ```
- **Never run two agents on cards that share a `depends_on` chain.** The index already tells you: only start cards where `ready` is `true`. Two `ready` cards are by definition independent.
- **One writer for `_backlog.json`: `producer`.** Every other agent reports its result and lets `producer` write it. This is the rule that was broken when the file was corrupted.

**Why a worktree, not just a branch:** each worktree has its own `.godot/` import cache, so concurrent `--headless --import` runs cannot race; its own checkout, so `GUT` (which runs all of `tests/`) measures *your* card and not a neighbour's half-finished work; and its own ENet port band via `tests/net/_port_alloc.sh`, so parallel net probes do not collide on 7777–7781. The primary tree and CI keep the documented default ports unchanged.

**Before reporting a card done, from inside your own worktree**

- Run GUT there, not in the primary tree — a green suite that included someone else's uncommitted code proves nothing.
- Push your `agent/<name>[/<card>]` branch and open a PR rather than merging into a shared branch yourself.
- Remove the worktree once merged: `bash tools/new_worktree.sh --remove <agent-name>`.

**Still serial on purpose:** `code-reviewer` → `qa-engineer` on a single card stays sequential. Parallelism buys throughput across *different* cards; it must not be used to review and QA the same diff at once.

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
