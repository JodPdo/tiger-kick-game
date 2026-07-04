# Agent RACI — Tiger Kick

ใครรับผิดชอบอะไรในแต่ละเฟส เพื่อไม่ให้ agent ทำงานชนกัน
**R** = Responsible (ลงมือทำ) · **A** = Accountable (อนุมัติ/รับผิดชอบสุดท้าย) · **C** = Consulted (ปรึกษา) · **I** = Informed (รับรู้)

> `producer` เป็น **A** (ผู้ปิด Exit Gate) ทุกเฟสเสมอ · `architect` เป็น **A** ของการเปลี่ยน architecture ทุกเฟส

## เมทริกซ์ตามเฟส

| Agent | P0 Setup | PX DevInfra | P1 Movement | P2 Core Loop | P3 Playtest | P4 Polish | P5 Steam |
|---|---|---|---|---|---|---|---|
| producer | A | A | A | A | A | A | A |
| architect | C | C | C | A | I | I | C |
| network-engineer | R | C | R | R | I | I | R |
| gameplay-engineer | R | I | R | R | C | C | I |
| tools-devops | R | R | I | I | R | I | R |
| qa-engineer | R | R | R | R | R | R | R |
| code-reviewer | R | R | R | R | C | R | R |
| designer | I | I | C | C | R | C | C |
| polish-agent | — | — | I | C | C | R | I |
| documentation-manager | R | C | C | R | C | C | C |

## กติกาการชี้ขาด
- **โค้ดทุกใบ**: ผู้เขียน = R, `code-reviewer` = R (ตรวจ), `qa-engineer` = R (เทส) — ต้องผ่านทั้งคู่ก่อน Done
- **เปลี่ยน architecture / TDD**: ต้องได้ **A จาก `architect`** ก่อนลงมือ + `documentation-manager` อัปเดตเอกสาร
- **เปลี่ยน design / balance / scope**: `designer` = R, `producer` = A, บันทึกใน Change Log
- **ปิดเฟส (Exit Gate)**: `qa-engineer` = R (รัน + ตัดสินเบื้องต้น), `producer` = A (อนุมัติปิด milestone)
- **เอกสารไม่ตรงโค้ด**: `documentation-manager` = R (แจ้ง + แก้), agent เจ้าของโค้ด = C

## เมื่อเพิ่ม agent ใหม่
เพิ่มแถวในตารางนี้ + แถวใน `AGENT_INDEX.md` + สร้าง contract ใน `.claude/agents/`
