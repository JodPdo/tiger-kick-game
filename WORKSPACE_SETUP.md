# Workspace Setup — Tiger Kick

โฟลเดอร์นี้คือ workspace จริง (git repo เดียว) ที่รวม โค้ด Godot + เอกสาร + ทีม AI agent

## โครงสร้าง
```
Tiger-Kick/                       ← repo root (จะเป็น Godot res:// ด้วย)
├── .gitignore
├── WORKSPACE_SETUP.md            ← ไฟล์นี้
│
├── .claude/                      ← ทีม AI agent (Claude Code อ่านจากที่นี่)
│   ├── agents/*.md               10 agent contracts
│   └── settings.local.json
├── CLAUDE.md                     ← คำสั่งโปรเจกต์สำหรับ AI
├── AGENT_INDEX.md                ← ทะเบียน agent
├── CURRENT_PHASE.md              ← สถานะปัจจุบัน (อัปเดตเมื่อขยับเฟส)
├── DOCUMENT_ROUTING.yaml         ← แผนที่ว่าเอกสารไหนอยู่ไหน
├── _backlog.json                 ← การ์ดงานที่ agent อ่าน
│
├── Tiger_Kick_Project_Docs/      ← เอกสารทั้งหมด (มี .gdignore ให้ Godot ข้าม)
│   ├── 00_README_INDEX  01_Design  02_Technical
│   ├── 03_QA  04_Management  05_AI_Team  diagrams
│
└── (สร้างเมื่อเริ่ม Phase 0)
    ├── project.godot             ← Godot เปิดที่นี่
    ├── scenes/ scripts/ characters/ networking/
    ├── managers/ ui/ world/ resources/ tests/   (ตาม TDD §3)
    └── addons/                   ← GUT, GodotSteam (ภายหลัง)
```

## ทำไมจัดแบบนี้
- **.claude/ + control files อยู่ที่ root** — Claude Code ต้องเจอ `.claude/` ที่ราก repo และ agent อ้างพาธ `_backlog.json`, `Tiger_Kick_Project_Docs/...` แบบ relative จาก root
- **Godot project อยู่ที่ root เดียวกัน** — res:// = root; ใส่ `.gdignore` ในโฟลเดอร์เอกสารเพื่อให้ Godot ไม่ import เอกสาร
- **docs + code + AI อยู่ repo เดียว** — เวลาแก้โค้ด, เอกสาร, และมอบหมาย agent จะ commit ไปด้วยกัน ประวัติตรงกันเสมอ

## ขั้นตอนตั้งค่า (ครั้งเดียว)
1. วางโฟลเดอร์นี้ไว้ที่ `C:\Users\claw\Desktop\Tiger-Kick`
2. เปิด terminal ในโฟลเดอร์ แล้ว:
   ```
   git init
   git add .
   git commit -m "chore: docs + AI team scaffold (docs v0.10)"
   git branch -M main
   git remote add origin <your-github-repo-url>
   git push -u origin main
   ```
3. เริ่ม Phase 0: สร้างโปรเจกต์ Godot 4.7 ที่โฟลเดอร์นี้ (project.godot จะถูกสร้างที่ root)
   ตั้งโครง res:// ตาม TDD §3 (scenes/, scripts/, managers/ ...)
4. ติดตั้ง GUT ใน `addons/` แล้วเริ่มการ์ด `TK-P0-01`

## สิ่งที่ไม่ได้ย้ายมา (build artifacts — อยู่ที่เดิม)
- สคริปต์สร้างเอกสาร (`gen_*.js/.py/.sh`) — ใช้ตอนอยากสร้าง/แก้เอกสารใหม่เท่านั้น
- `Tiger_Kick_Project_Docs.zip`, ไฟล์ .docx/.pdf ที่ root (ซ้ำกับในโฟลเดอร์ docs แล้ว)
