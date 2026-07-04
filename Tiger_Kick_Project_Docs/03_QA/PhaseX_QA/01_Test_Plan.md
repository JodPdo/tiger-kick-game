# Test Plan — Phase X — Development Infrastructure

> อ้างอิงเอกสารกลางใน `_shared/` (Master Test Plan, Test Strategy, Severity, Regression, Bug Template)

## 1. ขอบเขตการทดสอบของเฟส
ทดสอบตาม 4 ชั้น (Unit → Integration → Manual → Playtest) + Regression ก่อน DoD
รายการทดสอบละเอียดอยู่ใน `Test_Cases.xlsx`

## 2. Definition of Done (จาก GDD ของเฟส)
1. เปิด-ปิด Debug overlay ได้ และเห็น FPS/ping/state แบบเรียลไทม์
2. เปลี่ยน Settings แล้วบันทึก/โหลดกลับมาได้หลังปิดเปิดเกม
3. มี unit test อย่างน้อย 1 ชุดที่รันผ่าน

## 3. จุดที่เน้นทดสอบเฉพาะเฟส
### Developer QA — Logger
- Logger → Generate Error → Log File → Rotation → Archive
- ตรวจว่าระดับ log (info/warn/error) ถูกต้อง และไฟล์หมุนเวียนได้

### Config Persistence
- เปลี่ยน settings → ปิดเปิดเกม → โหลดค่ากลับถูกต้อง

### Unit Test Tooling
- GUT รันได้ และมีเทสตัวอย่างผ่าน

## 4. Entry / Exit Criteria
- **Entry**: งานพัฒนาของเฟสเสร็จ, Smoke test ผ่าน, build รันได้
- **Exit**: ผ่านทุกชั้น + Regression + DoD ครบ และไม่มีบั๊ก S0/S1 ค้าง (ดู `Exit_Gate.md`)

## 5. ไฟล์ประกอบ
- `Test_Cases.xlsx` — รายการเทสพร้อมช่อง Pass/Fail
- `Test_Checklist.md` — เช็กลิสต์สรุปตาม DoD
- `Exit_Gate.md` — เงื่อนไขผ่านเฟส
