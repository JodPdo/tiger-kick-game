# Change Log — Tiger Kick

บันทึกการเปลี่ยนแปลงสำคัญของโปรเจกต์และเอกสาร (รูปแบบ Keep a Changelog)
เวอร์ชันล่าสุดอยู่บนสุด

## [0.22] — 2026-07-04 — Logger autoload ตั้งชื่อ `GameLog` (เลี่ยงชนกับ engine class `Logger`)
- Phase X: เพิ่ม autoload `GameLog` (ไฟล์ `managers/Logger.gd`) และ `ConfigManager` (`managers/ConfigManager.gd`)
- **บั๊กที่จับได้ตอน integration:** ตั้งชื่อ autoload ว่า `Logger` **ชนกับ Godot built-in class `Logger`** ที่ GUT `error_tracker.gd` ใช้ (`extends Logger` + `OS.add_logger`) → GUT error-tracking พังเงียบ (`rp_logger is null`) + ObjectDB leak. เปลี่ยนชื่อ singleton เป็น `GameLog` แก้หมด (GUT 37/37 clean, ไม่มี leak). ไฟล์คง `Logger.gd`; โค้ดเรียกผ่านชื่อ singleton `GameLog.info()/warn()/error()` — **ห้ามตั้ง autoload ชื่อ `Logger` อีก**
- ConfigManager: method `load()` เดิมชนกับ builtin `load(path)` → เปลี่ยนเป็น `load_config()` (API: `get_value/set_value/save/load_config` + static `resolve_value/apply_defaults` + `DEFAULTS`)
- ตัดสินโดย: producer (integration fix); code identifiers ตรวจโดย code-reviewer/qa

## [0.21] — 2026-07-04 — เพิ่ม guard ตรวจ _backlog.json ใน CI
- เพิ่ม `tools/validate_backlog.py` — ตรวจ JSON valid + id ไม่ซ้ำ + depends_on ชี้ id ที่มีจริง + ฟิลด์ id/status ครบ + status อยู่ในชุดที่อนุญาต
- เพิ่ม step ใน `ci.yml` (รันก่อนโหลด Godot, fail เร็ว) → ถ้า backlog เสีย/ถูกตัด build แดงทันที รู้ตัวก่อน agent หยิบงานผิด
- ไม่กระทบเกม/บิลด์ (เป็น dev tool ล้วน) · รันเองในเครื่องได้: `python3 tools/validate_backlog.py`
- ทดสอบแล้ว: ไฟล์ปกติ→ผ่าน, ไฟล์ถูกตัด→exit 1 (แดง)

## [0.20] — 2026-07-04 — ติดตั้ง GUT + ต่อ CI ให้รันเทสจริง (TK-PX-07 → review)
- vendored **GUT 9.7.0** ที่ `addons/gut/` (commit เข้า repo; .gitignore อนุญาตอยู่แล้ว)
- แก้ `.github/workflows/ci.yml`: เอา branch "skip if GUT missing" ออก → GUT รันทุก push/PR และ **fail build ถ้าเทสตก** (-gexit)
- เทสที่จะรันจริง: `tests/test_network_manager.gd` (เดิม) + `tests/test_tiger_assignment.gd` (ใหม่, 10 เคส) บน `managers/TigerSelector.gd`
- verify: รัน Godot ในแซนด์บ็อกซ์ไม่ได้ (network allowlist บล็อก CDN binary ของ Godot) → พิสูจน์ logic ด้วย Python port (9/9 ผ่าน) + static review (tab ล้วน) · green จริงมาจาก CI ตอน push
- TK-PX-07 → status **review** (handoff ครบ)
- ⚠️ **เหตุการณ์:** พบ `_backlog.json` โดนตัดหาย (truncate) ครั้งที่ 2 ระหว่าง agent เขียนไฟล์พร้อมกัน — กู้คืนครบ 44 การ์ด (คงสถานะ review ของ TK-P0-06 ไว้) · แนะนำเพิ่ม guard ตรวจ JSON valid (ดูข้อเสนอ)

## [0.19] — 2026-07-04 — เพิ่ม unit test spec สำหรับสุ่มเสือตัวแรก (TK-P2-09)
- เพิ่ม `managers/TigerSelector.gd` — pure helper (static, node-independent, inject RNG) แยก logic การสุ่ม/แจกบทบาทออกจาก multiplayer เพื่อให้ unit-test ได้
- เพิ่ม `tests/test_tiger_assignment.gd` (GUT) 10 เคส: mock 4 peers → เสือ 1 ตัวเสมอ, เสืออยู่ในลิสต์จริง, fairness (ทุกคนถูกสุ่มได้), single/empty/stale-id edge, anti-repeat, determinism (seed เดียวกันได้ผลเดียวกัน)
- indentation เป็น tab ล้วน (ตรวจแล้ว) · รันได้เมื่อ GUT ลง (TK-PX-07) · integration เข้า GameManager/RPC ยังทำตามการ์ด TK-P2-09 ผ่าน review

## [0.18] — 2026-07-04 — เพิ่มการ์ดสุ่มเสือตัวแรก (TK-P2-09)
- เพิ่ม `_backlog.json`: **TK-P2-09** สุ่มเสือตัวแรกตอนเริ่มรอบ (host-authoritative + broadcast)
- กติกาสถาปัตย์: HOST สุ่มคนเดียว (randomize() ครั้งเดียว) แล้ว broadcast ผ่าน @rpc(authority, call_local, reliable) — client ห้ามสุ่มเอง กัน desync (S1)
- ผูก: depends_on [TK-P2-04 Role state machine] · เรียกโดย RoundManager (TK-P2-07) ตอนสถานะ Random Tiger · pair กับ network-engineer
- edge cases: รวม host ในการสุ่ม, สุ่มใหม่ถ้าคนถูกเลือกหลุด, ทุกรอบใหม่สุ่มใหม่ · optional anti-repeat = Phase 3
- Backlog รวม 44 การ์ด (Phase 2 = 9 ใบ)

## [0.17] — 2026-07-04 — เพิ่มการ์ด backlog Phase 4 (Art/Character) 4 ใบ
- เพิ่มใน `_backlog.json`: **TK-P4-05** (โมเดล+rig เสือ), **TK-P4-06** (โมเดล+rig ผู้เล่น base เปล่า + material slot), **TK-P4-07** (Toon Shader + Rim Light pipeline), **TK-P4-08** (ระบบแต่งตัว Lobby + network sync)
- ผูก dependency: P4-07 ← [P4-05, P4-06] · P4-08 ← [P4-06] · owner: polish-agent (05/06/07), gameplay-engineer (08, handoff network sync ให้ network-engineer)
- ทุกใบมี `notes` ชี้ ref → Character_Art_Bible.md + refs/*.png และระบุ DoD ย่อ
- Backlog รวมเป็น 43 การ์ด (Phase 4 = 8 ใบ) · หมายเหตุ: 05_Backlog.md/.csv/.xlsx (human view) ยังไม่ regen — รอทำรอบเดียวพร้อมกันได้

## [0.16] — 2026-07-04 — ล็อกสเปกผู้เล่น (ไม่ใช่เสือ) จาก character sheet + แก้ขนาดเสือ/ผู้เล่น
- รับ **character sheet ผู้เล่น** จากคุณเป็นมาตรฐาน → อัปเดต Art Bible §4, §4B, §7
- **ขนาด (แก้ conflict):** เสือ **~2.0m** (ใหญ่กว่า) · ผู้เล่น **1.2–1.4m** — แก้ §3 เดิมที่เขียนว่าเสือเตี้ยกว่าผู้เล่น (ขัดกับ sheet) ให้ถูกต้อง
- **สเปกผู้เล่น:** low-poly toon ทรงเรียบ สีขาวเปล่า = ผ้าใบ · ~1K–2K tris · Toon Shader + Rim Light · turnaround 4 มุม
- **Customization (Cosmetic Only, ที่ Lobby):** สีพื้น 8 สี · decal (หน้ายิ้ม/ดาว/มงกุฎ/"สู้ๆ"/"KICK ME!" ฯลฯ) · accessory 4 หมวด (หมวก/กระเป๋า/ผ้าพันคอ/แว่น)
- **Animation:** เพิ่ม Jump เข้า set · ยืนยันตัวหลักผู้เล่น: วิ่ง/กระโดด/เตะ/โดนเตะ-ล้ม · ใช้ rig ร่วมกับเสือได้
- ที่วางไฟล์: `01_Design/refs/player_style_ref.png`

## [0.15] — 2026-07-04 — ล็อกสเปกผลิตตัวเสือจาก character sheet
- รับ **character sheet เสือ (turnaround 6 มุม)** จากคุณเป็นมาตรฐานหน้าตา → อัปเดต Art Bible §3, §9
- **สเปกที่ล็อก:** ทรงง่าย/อ่านชัด · โทนสีสด · **Toon Shader + Rim Light** · โพลีต่ำ **~1K–2K tris**
- **มาร์กกิ้ง:** เสือส้ม+ลายดำ+พุงครีม + **รอยเท้าแมวกลางพุง** (signature) · Turnaround: Front/3-4/Side/Back
- **ยืนยันแล้ว:** เสือขาวใน sheet = **palette variant เฉย ๆ** (ไม่ใช่สกิน/บทบาท) — เสือมาตรฐาน = ส้ม+ลายดำ+พุงครีม
- ที่วางไฟล์: `01_Design/refs/tiger_style_ref.png` (Art Bible ชี้ path นี้แล้ว)

## [0.14] — 2026-07-04 — ล็อกสไตล์ Art = Toon/Low-poly (อ้างอิง MECCHA CHAMELEON) + เพิ่มระบบแต่งตัวที่ Lobby
- **Art Direction ล็อก:** Stylized/Toon + Low-poly (cel-shaded, รันบน integrated GPU ได้) อ้างอิงหลัก = MECCHA CHAMELEON — บันทึกใน `01_Design/Character_Art_Bible.md` §1
- **ตัวเสือ:** low-poly toon เสือ ทรงป้อมน่ารักแต่ดุนิด ๆ, **สีตัวตายตัว (ผู้เล่นแก้ไม่ได้)** เพื่อ readability
- **ผู้เล่น (ไม่ใช่เสือ):** โมเดลฐานเรียบ/เป็นผ้าใบ **ทาสี/แต่งตัวเองได้** — feature ใหม่ §4B
- **ขอบเขต feature "แต่งตัว":** เป็น **COSMETIC ล้วน ทำที่หน้า Lobby ก่อนแมตช์เท่านั้น** ไม่ใช่กลไกพรางตัว (ต่างจาก MECCHA) และ **ไม่กระทบ Core Loop เดิม** (แอบ→เตะ→หนี) — ตัดสินโดยคุณ (มนุษย์) 2026-07-04
- **ผลต่อ Tiger Indicator (§5):** ห้ามพึ่ง "สีตัว" อย่างเดียวชี้เสืออีกต่อไป เพราะผู้เล่นเลือกสีเองได้ → ต้องซ้อนหลายชั้น (โมเดลเสือแยก + เอฟเฟกต์/ไอคอน)
- **Phase placement:** ระบบแต่งตัววางไว้ **Phase 4 (Polish) ขั้นต่ำ / เต็มรูปแบบก่อน Ship** — ยังไม่แตะ Phase 0–2 (พิสูจน์ความสนุกก่อน) — ทีมยืนยัน scope + เพิ่มการ์ด backlog ก่อนลงมือ
- ผู้เสนอ/อนุมัติ: คุณ (มนุษย์) · ต้องให้ `designer` เซ็นก่อน `polish-agent` ลงมือ (ตามกติกา Art Bible §10)

## [0.13] — 2026-07-04 — แก้ path NetworkManager ให้ตรง TDD §3 (managers/ → networking/)
- ย้าย `NetworkManager.gd` จาก `res://managers/` ไป `res://networking/` เพื่อให้ตรงกับ TDD §3 (Folder Structure) ที่กำหนด `networking/` เป็นที่อยู่ของ NetworkManager/RPC/sync ส่วน `managers/` สงวนให้ GameManager/RoundManager/ConfigManager/Logger
- เหตุ: การ์ด TK-P0-04 ระบุ path `managers/` ซึ่งขัดกับ TDD; TDD คือ source of truth ด้านสถาปัตย์ (ตาม DOCUMENT_ROUTING) จึงทำโค้ดให้ตรง TDD — ถือเป็นการ *conform* ไม่ใช่ *เปลี่ยน* สถาปัตย์
- อัปเดต: `project.godot` [autoload] → `res://networking/NetworkManager.gd`, preload path ใน `tests/test_network_manager.gd`
- อนุมัติโดย: producer (ไม่ต้องขอ architect เพราะเป็นการทำตาม TDD เดิม ไม่ได้แก้ TDD)

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
