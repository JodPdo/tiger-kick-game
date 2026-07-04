# Test Plan — Phase 3 — Playtest & Tuning

> อ้างอิงเอกสารกลางใน `_shared/` (Master Test Plan, Test Strategy, Severity, Regression, Bug Template)

## 1. ขอบเขตการทดสอบของเฟส
ทดสอบตาม 4 ชั้น (Unit → Integration → Manual → Playtest) + Regression ก่อน DoD
รายการทดสอบละเอียดอยู่ใน `Test_Cases.xlsx`

## 2. Definition of Done (จาก GDD ของเฟส)
1. มีข้อสรุปชัดว่า core loop สนุกพอจะไปต่อหรือไม่
2. ได้ชุดค่าพารามิเตอร์ที่ผู้เล่นส่วนใหญ่รู้สึกสนุก

## 3. จุดที่เน้นทดสอบเฉพาะเฟส
### Balance Validation
- ตั้ง threshold: Tiger Win 40–60%, Runner Win 40–60%
- ถ้า Tiger Win ~90% = Balance Fail ต้องจูน
- ตรวจ: Average Round Time, Kick Success %

### Analytics Accuracy
- ค่าที่เก็บ (win%, time, distance) ตรงกับความจริง

### Playtest Protocol
- งานให้ผู้เล่นทำ + แบบสอบถามสั้น + บันทึกวิดีโอทุกแมตช์

## 4. Entry / Exit Criteria
- **Entry**: งานพัฒนาของเฟสเสร็จ, Smoke test ผ่าน, build รันได้
- **Exit**: ผ่านทุกชั้น + Regression + DoD ครบ และไม่มีบั๊ก S0/S1 ค้าง (ดู `Exit_Gate.md`)

## 5. ไฟล์ประกอบ
- `Test_Cases.xlsx` — รายการเทสพร้อมช่อง Pass/Fail
- `Test_Checklist.md` — เช็กลิสต์สรุปตาม DoD
- `Exit_Gate.md` — เงื่อนไขผ่านเฟส
