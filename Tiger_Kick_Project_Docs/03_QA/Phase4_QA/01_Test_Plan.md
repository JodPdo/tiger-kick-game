# Test Plan — Phase 4 — Feel & Polish

> อ้างอิงเอกสารกลางใน `_shared/` (Master Test Plan, Test Strategy, Severity, Regression, Bug Template)

## 1. ขอบเขตการทดสอบของเฟส
ทดสอบตาม 4 ชั้น (Unit → Integration → Manual → Playtest) + Regression ก่อน DoD
รายการทดสอบละเอียดอยู่ใน `Test_Cases.xlsx`

## 2. Definition of Done (จาก GDD ของเฟส)
1. การเตะ/จับ/สลับบทบาทมี feedback ภาพ+เสียงที่ชัด
2. ผู้เล่นเข้าใจสถานะบทบาททันทีจากภาพ/UI
3. มีคลิปโมเมนต์ที่ 'อยากแชร์' เกิดขึ้นจริงระหว่างเทส

## 3. จุดที่เน้นทดสอบเฉพาะเฟส
### UX QA
- Player เข้าใจไหม / Role ชัดไหม / UI อ่านง่ายไหม / Camera เวียนหัวไหม
- เฟสนี้วัด Feeling ไม่ใช่แค่ Bug

### Animation-frame Hitbox
- hitbox ต้อง spawn ตรงเฟรมแอนิเมชัน (เช่น ~เฟรม 12) ไม่ใช่ทันทีที่กด

### Regression
- core loop ของ Phase 2 ต้องยังทำงานหลังใส่ polish

## 4. Entry / Exit Criteria
- **Entry**: งานพัฒนาของเฟสเสร็จ, Smoke test ผ่าน, build รันได้
- **Exit**: ผ่านทุกชั้น + Regression + DoD ครบ และไม่มีบั๊ก S0/S1 ค้าง (ดู `Exit_Gate.md`)

## 5. ไฟล์ประกอบ
- `Test_Cases.xlsx` — รายการเทสพร้อมช่อง Pass/Fail
- `Test_Checklist.md` — เช็กลิสต์สรุปตาม DoD
- `Exit_Gate.md` — เงื่อนไขผ่านเฟส
