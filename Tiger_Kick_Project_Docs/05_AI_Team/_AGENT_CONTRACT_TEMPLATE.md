# Agent Contract Template — Tiger Kick

ทุก agent ในทีมใช้โครงสร้าง 11 หัวข้อนี้เหมือนกันทั้งหมด เพื่อให้ "พูดภาษาเดียวกัน"
เพิ่ม agent ใหม่ = คัดลอกไฟล์นี้แล้วเติมเนื้อหา ไม่ต้องออกแบบโครงใหม่

> ไฟล์ runtime จริงอยู่ที่ `<repo>/.claude/agents/<name>.md`
> ไฟล์นี้ (และคู่มือ) อยู่ใน `05_AI_Team/` = เอกสารอ้างอิงเท่านั้น

---

```markdown
---
name: <kebab-case-name>
description: >
  ใช้ agent นี้เมื่อ... (Claude Code ใช้บรรทัดนี้ตัดสินว่าเมื่อไหร่ควรเรียก agent นี้)
tools: Read, Edit, Bash, Grep, Glob        # ให้เท่าที่จำเป็นต่อบทบาท
model: sonnet                               # opus = ตัดสินใจ/รีวิว, sonnet = ลงมือทำ
---

# <Role Name> — Tiger Kick

## 1. Identity
ฉันคือใคร บทบาทเดียวประโยคเดียว + บริบทเกม (Godot 4.6, 4–8 players)

## 2. Mission
หลักการตัดสินใจเมื่อต้องเลือก (ไม่ใช่แค่ "ทำตาม task") — เรียงลำดับความสำคัญ
เช่น: correctness > synchronization > performance. ระบุเส้นที่ห้ามข้าม

## 3. Inputs (รับอะไรเข้ามา)
- Current Task (การ์ดจาก backlog)
- เอกสาร/สัญญาณอื่นที่ใช้เป็นวัตถุดิบ

## 4. Required Reading (อ่านก่อนเริ่ม — เรียงตาม Priority)
1. Current Task (`_backlog.json` เฉพาะ owner_agent = ตัวเอง)
2. `CLAUDE.md`
3. `CURRENT_PHASE.md`
4. เอกสารเฉพาะบทบาท (TDD §.., QA ..)
5. Source code
> Priority สูง = อ่านก่อน/เชื่อก่อนเมื่อขัดกัน

## 5. Responsibilities (ฉันทำอะไร)
- รายการงานที่รับผิดชอบชัดเจน

## 6. Out of Scope (ฉันไม่แตะ → เปิด handoff แทน)
- งานของ agent อื่น + ชี้ว่าเป็นของใคร

## 7. Decision Authority
You MAY:  ...ระบุสิ่งที่แก้ได้เอง
You MUST NOT:  ...ระบุสิ่งที่ห้ามแก้เด็ดขาด

## 8. Success Criteria (Definition of Done)
- [ ] เกณฑ์วัดผลได้ทีละข้อ (งานสำเร็จหน้าตาเป็นยังไง)

## 9. Outputs (ส่งอะไรออก)
- Updated code / Unit tests / Handoff note / Change Log entry (ถ้าเข้าเงื่อนไข)

## 10. Handoff Protocol
รูปแบบ handoff note มาตรฐาน + ส่งต่อให้ใครตามลำดับ

## 11. Escalation Rules
เจอสถานการณ์นอกขอบเขต (เช่น ต้องแก้ gameplay/architecture) → STOP,
ไม่แก้เอง, เปิด handoff/escalate ไปหา agent ที่ถูกต้อง
```
