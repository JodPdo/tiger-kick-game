# Test Plan — Phase 5 — Feature Expansion & Steam

> อ้างอิงเอกสารกลางใน `_shared/` (Master Test Plan, Test Strategy, Severity, Regression, Bug Template)

## 1. ขอบเขตการทดสอบของเฟส
ทดสอบตาม 4 ชั้น (Unit → Integration → Manual → Playtest) + Regression ก่อน DoD
รายการทดสอบละเอียดอยู่ใน `Test_Cases.xlsx`

## 2. Definition of Done (จาก GDD ของเฟส)
1. ผู้เล่นสร้าง/เข้าร่วม lobby ผ่าน Steam และเล่นด้วยกันได้
2. ฟีเจอร์ใหม่แต่ละตัวผ่านเกณฑ์ความสนุกก่อนเข้าเกมจริง

## 3. จุดที่เน้นทดสอบเฉพาะเฟส
### Release QA (Steam)
- Install / Update / Cloud Save / Achievement / Invite / Overlay / Offline
- ทดสอบทั้งหมดก่อน Release

### Feature Flag Isolation
- เปิด/ปิดฟีเจอร์ใหม่ทีละตัวเพื่อเทสแยก

### Full Regression
- รัน Release suite ครบทุกเฟสก่อนปล่อย

## 4. Entry / Exit Criteria
- **Entry**: งานพัฒนาของเฟสเสร็จ, Smoke test ผ่าน, build รันได้
- **Exit**: ผ่านทุกชั้น + Regression + DoD ครบ และไม่มีบั๊ก S0/S1 ค้าง (ดู `Exit_Gate.md`)

## 5. ไฟล์ประกอบ
- `Test_Cases.xlsx` — รายการเทสพร้อมช่อง Pass/Fail
- `Test_Checklist.md` — เช็กลิสต์สรุปตาม DoD
- `Exit_Gate.md` — เงื่อนไขผ่านเฟส
