# Agent Handbook — Tiger Kick AI Team

คู่มือ (ภาษาไทย) อธิบายว่า "ทีม AI agent" ของโปรเจกต์ทำงานยังไง สำหรับทีมมนุษย์ 2 คนอ่านเข้าใจภาพรวม
> ไฟล์คำสั่งจริงของ agent อยู่ที่ `.claude/agents/*.md` (ภาษาอังกฤษ) — ห้ามแก้ที่นี่ ที่นี่คือ "เอกสาร"

## 1. แนวคิด: AI Development Organization
เราไม่ได้มีแค่ "หลาย agent" แต่จัดเป็น **องค์กรพัฒนาเกม** ที่มี 4 ชั้น:

```
Runtime Layer      .claude/agents/*.md         ← ตัว agent ที่ Claude Code เรียกใช้จริง
Context Layer      CLAUDE.md, AGENT_INDEX.md,   ← สิ่งที่ทุก agent อ่านร่วมกันก่อนทำงาน
                   DOCUMENT_ROUTING.yaml,
                   CURRENT_PHASE.md
Documentation      Tiger_Kick_Project_Docs/     ← GDD, TDD, QA, Management (คนอ่าน)
Execution Layer    _backlog.json, Kanban,       ← งานจริงที่ไหลผ่านระบบ
                   Milestones
```

## 2. ทีมมี 10 ตำแหน่ง
ดูรายละเอียดเต็มใน `AGENT_INDEX.md` — สรุปสั้น:

| Agent | ทำอะไร | เขียนโค้ด? |
|---|---|---|
| producer | จ่ายงาน, ปิด milestone, ตัดสินขั้นสุดท้าย | ไม่ |
| architect | อนุมัติการเปลี่ยน architecture/TDD | ไม่ |
| network-engineer | networking, RPC, sync | ใช่ |
| gameplay-engineer | movement, kick, tag, core loop | ใช่ |
| tools-devops | repo, CI, tooling, build | ใช่ |
| qa-engineer | เทส, เปิดบั๊ก, ตัดสิน DoD/Exit Gate | ใช่ (เทส) |
| code-reviewer | รีวิวโค้ดก่อน Done | ไม่ |
| designer | GDD, balance, playtest | ไม่ |
| polish-agent | art, audio, VFX, HUD | ใช่ |
| documentation-manager | กันเอกสารหลุดจากโค้ด | เฉพาะเอกสาร |

## 3. Agent Contract — ทุกตัวพูดภาษาเดียวกัน
ทุก agent ใช้โครง 11 หัวข้อเดียวกัน (`_AGENT_CONTRACT_TEMPLATE.md`):
Identity · Mission · Inputs · Required Reading · Responsibilities · Out of Scope ·
Decision Authority · Success Criteria · Outputs · Handoff Protocol · Escalation Rules
→ เพิ่ม agent ใหม่ = คัดลอกเทมเพลต เติมเนื้อหา เพิ่มแถวใน `AGENT_INDEX.md` + RACI

## 4. งานไหลยังไง (Card lifecycle)
```
producer หยิบการ์ดจาก _backlog.json (deps ครบ) → มอบให้ owner_agent
  → owner ทำ (Doing) → เขียน HANDOFF → code-reviewer → qa-engineer
  → ผ่าน = Done / ไม่ผ่าน = ตีกลับ owner
ครบการ์ดในเฟส → qa รัน Regression → Exit Gate → producer ปิด milestone → เฟสถัดไป
```
- ทุกการ์ดมี `owner_agent`, `status`, `depends_on` ใน `_backlog.json`
- ใครรับผิดชอบอะไรต่อเฟส: `04_Management/06_Agent_RACI.md`

## 5. กฎเหล็ก 4 ข้อ
1. **Server-authoritative** — สถานะที่ชี้ขาดผลเกม (ใครเป็นเสือ/การจับ) host ตัดสิน
2. **ห้ามข้าม Exit Gate** — บั๊ก S0/S1 บล็อกการปิดเฟสเสมอ
3. **อยู่ในขอบเขตตัวเอง** — เกินขอบเขต = เปิด handoff/escalate ไม่แก้เอง
4. **เปลี่ยนอะไรสำคัญ ต้องบันทึก** — design/architecture/balance → `03_Change_Log.md`

## 6. ภาษา
- `.claude/agents/*.md` = อังกฤษ · เอกสารทีม (`Tiger_Kick_Project_Docs/`) = ไทย · ชื่อไฟล์/โค้ด = อังกฤษ

## 7. อยากขยายทีมในอนาคต
ตัวอย่าง agent ที่อาจเพิ่ม: `animation-engineer`, `steam-integration-engineer`
ทำตามข้อ 3 — ระบบออกแบบให้ขยายได้โดยไม่ต้องรื้อของเดิม
