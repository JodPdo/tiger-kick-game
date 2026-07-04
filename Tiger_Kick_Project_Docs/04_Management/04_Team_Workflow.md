# Team Workflow — Tiger Kick (ทีม 2 คน)

เครื่องมือทำงานแบบเบาสำหรับทีม 2 คน (ฉัน + เพื่อน) เป้าหมายคือเห็นภาพรวมงานและบั๊กโดยไม่เพิ่ม overhead

> แนะนำใช้ **GitHub (Projects + Issues + Milestones)** เพราะใช้ Git + GitHub อยู่แล้ว ครบในที่เดียว ฟรี ไม่ต้องสลับเครื่องมือ
> ทางเลือก: Trello หรือ Notion (ถ้าชอบ UI แบบ board มากกว่า) — แนวคิดด้านล่างใช้ได้กับทุกเครื่องมือ

## 1. Kanban Board
คอลัมน์: **Backlog → Todo → Doing → Review → Done**

| คอลัมน์ | ความหมาย |
|---|---|
| Backlog | งาน/ไอเดียทั้งหมดที่ยังไม่จัดลำดับ |
| Todo | งานที่เลือกจะทำในช่วงนี้ (ดึงจาก Backlog) |
| Doing | กำลังทำอยู่ |
| Review | เสร็จแล้ว รออีกคนตรวจ (โยงกับ QA: Smoke/Regression/DoD) |
| Done | ผ่าน Review + ตรงตาม DoD/AC แล้ว |

กติกาสำหรับทีม 2 คน:
- **WIP limit**: คอลัมน์ Doing ไม่เกิน 1–2 การ์ดต่อคน เพื่อโฟกัส
- การ์ดเดินทางเดียว ซ้าย → ขวา
- ทุกการ์ดในเฟสปัจจุบันควรมาจาก Task/DoD ในเอกสารเฟสนั้น
- Review = อีกคนเป็นคนตรวจเสมอ (สลับกันได้) เพื่อจับของพังก่อนเข้า Done

## 2. Issue Tracker
ใช้ **GitHub Issues** — ทุกบั๊กเปิดเป็น Issue ไม่ต้องจำกันเอง

- ใช้เทมเพลตจาก `_shared/03_Bug_Template.md`
- ตัวอย่าง: `BUG-014 — Tiger can leave Safe Circle` · Severity: **S1** · Priority: **High**
- Bug Lifecycle (New → Triaged → ... → Verified → Closed) แมปกับสถานะ Issue + label

Label ที่แนะนำ:

| กลุ่ม | Label |
|---|---|
| Type | `bug`, `feature`, `task`, `chore` |
| Severity | `S0-crash`, `S1-desync`, `S2-gameplay`, `S3-ui`, `S4-cosmetic` |
| Priority | `prio-high`, `prio-med`, `prio-low` |
| Phase | `phase-0`, `phase-x`, `phase-1` … `phase-5` |

- บั๊ก S0/S1 = บล็อก Exit Gate (ตาม QA) → ควรติด label เด่นและแก้ก่อน
- โยง Issue กับ RTM (`_shared/06`) ในช่อง Bug ID

## 3. Milestones
ใช้ **GitHub Milestones** ผูกกับ `Management/01_Milestone_Plan.md` (M0–M5) — ปิด milestone เมื่อ Exit Gate ของเฟสนั้นผ่าน

| Milestone | เฟส | ปิดเมื่อ (Exit Gate) |
|---|---|---|
| M0 Networking | Phase 0 | 2 เครื่องเชื่อมต่อกันได้ |
| MX Dev Infra | Phase X | Debug overlay + Settings + unit test |
| M1 Movement | Phase 1 | 4–8 คนวิ่งซิงก์ + benchmark |
| M2 Core Gameplay | Phase 2 | core loop ครบ ไม่มี desync |
| M3 First Playtest | Phase 3 | playtest ยืนยันสนุก + balance |
| M4 Polish | Phase 4 | feedback ชัด + regression |
| M5 Ship | Phase 5 | Release Readiness ผ่าน |

## 4. จังหวะการทำงานประจำ (2 คน)
- เริ่มวัน: ดู board ด้วยกันสั้น ๆ หยิบการ์ด Todo → Doing
- ก่อน push: รัน Smoke test (จาก QA) — CI ช่วยเช็กอัตโนมัติ
- เสร็จการ์ด → ย้ายเข้า Review ให้อีกคนตรวจ
- ปิดการ์ด (Done) เมื่อ DoD/AC ครบ และไม่มีบั๊ก S0/S1 ค้าง

## เชื่อมโยงกับเอกสารอื่น
- Bug Template / Severity / Bug Lifecycle / Regression → `_shared/`
- Milestone Plan / Risk Register / Change Log → `Management/`
- Requirement Traceability (RTM) → `_shared/06`
