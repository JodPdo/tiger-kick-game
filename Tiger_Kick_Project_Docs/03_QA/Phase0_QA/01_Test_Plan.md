# Test Plan — Phase 0 — Setup & Networking Foundation

> อ้างอิงเอกสารกลางใน `_shared/` (Master Test Plan, Test Strategy, Severity, Regression, Bug Template)

## 1. ขอบเขตการทดสอบของเฟส
ทดสอบตาม 4 ชั้น (Unit → Integration → Manual → Playtest) + Regression ก่อน DoD
รายการทดสอบละเอียดอยู่ใน `Test_Cases.xlsx`

## 2. Definition of Done (จาก GDD ของเฟส)
1. clone repo แล้วเปิดใน Godot ได้ทันทีโดยไม่มี error
2. เปิดสองอินสแตนซ์ กด Host และ Join แล้วเชื่อมต่อกันสำเร็จ
3. มี log/ข้อความยืนยันว่า peer เข้ามาแล้ว

## 3. จุดที่เน้นทดสอบเฉพาะเฟส
### CI Smoke Test (ทุก push)
- Clone → Open Project → Import → Build → Run
- จับ project พัง / dependency หาย / addon หาย ตั้งแต่ต้น

### Connection Smoke
- Host/Join บน localhost
- connect / disconnect / reconnect

## 4. Entry / Exit Criteria
- **Entry**: งานพัฒนาของเฟสเสร็จ, Smoke test ผ่าน, build รันได้
- **Exit**: ผ่านทุกชั้น + Regression + DoD ครบ และไม่มีบั๊ก S0/S1 ค้าง (ดู `Exit_Gate.md`)

## 5. ไฟล์ประกอบ
- `Test_Cases.xlsx` — รายการเทสพร้อมช่อง Pass/Fail
- `Test_Checklist.md` — เช็กลิสต์สรุปตาม DoD
- `Exit_Gate.md` — เงื่อนไขผ่านเฟส
