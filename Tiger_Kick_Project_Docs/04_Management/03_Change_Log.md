# Change Log — Tiger Kick

บันทึกการเปลี่ยนแปลงสำคัญของโปรเจกต์และเอกสาร (รูปแบบ Keep a Changelog)
เวอร์ชันล่าสุดอยู่บนสุด

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
