# AGENT_INDEX.md — Tiger Kick

The AI team. Read this to know **who exists** and **which agent to call**. Full contracts live in `.claude/agents/<name>.md`. Responsibilities per phase: `04_Management/06_Agent_RACI.md`.

## Roster (10 agents)

| Agent | Role | Model | Writes code? | Call it when… |
|---|---|---|---|---|
| `producer` | Orchestrator / PM + Tech Lead | opus | No | Assign cards, track milestones, approve Exit Gate, resolve conflicts |
| `architect` | Architecture authority | opus | No | Approve/deny changes to TDD, architecture, dependencies, refactors |
| `network-engineer` | Networking | sonnet | Yes | NetworkManager, RPC, sync, MultiplayerSpawner, anti-desync, Steam lobby |
| `gameplay-engineer` | Gameplay | sonnet | Yes | Movement, Kick, Tag, Tag Sequence, Role state machine, RoundManager, menus |
| `tools-devops` | Tooling / CI | sonnet | Yes | Repo setup, CI, GUT harness, Logger, debug/perf overlay, Settings, builds |
| `qa-engineer` | QA | sonnet | Yes (tests) | Test cases, checklists, regression, file bugs, judge phase DoD |
| `code-reviewer` | Reviewer | opus | No | Review any diff before it reaches Done |
| `designer` | Game/systems design | sonnet | No | GDD, balance, playtest sessions, tuning, fun analysis |
| `polish-agent` | Art / audio / UX | sonnet | Yes | Models, animation, SFX, VFX, HUD, feedback (mostly Phase 4) |
| `documentation-manager` | Docs integrity | sonnet | No (docs only) | Keep README/TDD/GDD/Change Log in sync with code; flag drift |

## When agents are active (by phase)
- **Phase 0 (now):** producer, tools-devops, network-engineer, gameplay-engineer, qa-engineer, code-reviewer
- **Phase X:** + tools-devops heavy
- **Phase 1–2:** network-engineer + gameplay-engineer heavy; architect on structure calls
- **Phase 3:** designer leads (playtest)
- **Phase 4:** polish-agent leads
- **Phase 5:** tools-devops + network-engineer (Steam)
- **Every phase:** qa-engineer, code-reviewer, producer, documentation-manager

## Adding a new agent
Copy `Tiger_Kick_Project_Docs/05_AI_Team/_AGENT_CONTRACT_TEMPLATE.md`, fill all 11 sections, save to `.claude/agents/<name>.md`, then add a row here and in the RACI. Examples of likely future agents: `animation-engineer`, `steam-integration-engineer`.
