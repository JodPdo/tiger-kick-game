# AGENT_INDEX.md — Tiger Kick

The AI team. Read this to know **who exists** and **which agent to call**. Full contracts live in `.claude/agents/<name>.md`. Responsibilities per phase: `04_Management/06_Agent_RACI.md`.

## Roster (10 agents)

The **Model** column quotes the `model:` value in each agent's frontmatter verbatim, so it can be checked against the file it describes. Re-verify with:

```bash
grep -H "^model:" .claude/agents/*.md
```

| Agent | Role | Model (`.claude/agents/*.md`) | Writes code? | Call it when… |
|---|---|---|---|---|
| `producer` | Orchestrator / PM + Tech Lead | `claude-opus-4-8` | No | Assign cards, track milestones, approve Exit Gate, resolve conflicts |
| `architect` | Architecture authority | `claude-opus-4-8` | No | Approve/deny changes to TDD, architecture, dependencies, refactors |
| `network-engineer` | Networking | `claude-opus-4-8` | Yes | NetworkManager, RPC, sync, MultiplayerSpawner, anti-desync, Steam lobby |
| `gameplay-engineer` | Gameplay | `sonnet` | Yes | Movement, Kick, Tag, Tag Sequence, Role state machine, RoundManager, menus |
| `tools-devops` | Tooling / CI | `sonnet` | Yes | Repo setup, CI, GUT harness, Logger, debug/perf overlay, Settings, builds |
| `qa-engineer` | QA | `claude-opus-4-8` | Yes (tests) | Test cases, checklists, regression, file bugs, judge phase DoD |
| `code-reviewer` | Reviewer | `claude-opus-4-8` | No | Review any diff before it reaches Done |
| `designer` | Game/systems design | `claude-opus-4-8` | No | GDD, balance, playtest sessions, tuning, fun analysis |
| `polish-agent` | Art / audio / UX | `sonnet` | Yes | Models, animation, SFX, VFX, HUD, feedback (mostly Phase 4) |
| `documentation-manager` | Docs integrity | `haiku` | No (docs only) | Keep README/TDD/GDD/Change Log in sync with code; flag drift |

**Cost/latency note:** 6 of 10 agents run on the top tier, and two of them (`code-reviewer`, `qa-engineer`) sit on the critical path of *every* code card because review is mandatory. That is a deliberate quality trade, but it is the main driver of turnaround time — revisit the tier here before blaming the workflow.

## Picking work — read the index, not the whole backlog

`_backlog.json` is ~83,000 tokens. Do **not** read it just to find your cards. Use the generated slim index instead:

```bash
python3 tools/split_backlog.py --agent <your-name>   # your queue, ready cards first
python3 tools/split_backlog.py --card TK-P2-05       # one card in full, when you start it
```

`_backlog_index.json` is a **generated file** — never hand-edit it. After changing `_backlog.json`, regenerate with `python3 tools/split_backlog.py`; CI runs `--check` and fails on drift.

## When agents are active (by phase)
- **Phase 0 (now):** producer, tools-devops, network-engineer, gameplay-engineer, qa-engineer, code-reviewer
- **Phase X:** + tools-devops heavy
- **Phase 1–2:** network-engineer + gameplay-engineer heavy; architect on structure calls
- **Phase 3:** designer leads (playtest)
- **Phase 4:** polish-agent leads
- **Phase 5:** tools-devops + network-engineer (Steam)
- **Every phase:** qa-engineer, code-reviewer, producer, documentation-manager

## Adding a new agent
Copy `Tiger_Kick_Project_Docs/05_AI_Team/_AGENT_CONTRACT_TEMPLATE.md`, fill all 11 sections, save to `.claude/agents/<name>.md`, then add a row here (quoting the frontmatter `model:` value exactly) and in the RACI. Examples of likely future agents: `animation-engineer`, `steam-integration-engineer`.
