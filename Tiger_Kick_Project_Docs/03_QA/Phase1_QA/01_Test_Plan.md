# Test Plan — Phase 1 — Core Movement & Sync

> อ้างอิงเอกสารกลางใน `_shared/` (Master Test Plan, Test Strategy, Severity, Regression, Bug Template)

## 1. ขอบเขตการทดสอบของเฟส
ทดสอบตาม 4 ชั้น (Unit → Integration → Manual → Playtest) + Regression ก่อน DoD
รายการทดสอบละเอียดอยู่ใน `Test_Cases.xlsx`

## 2. Definition of Done (จาก GDD ของเฟส)
1. ผู้เล่น 4–8 คนวิ่งพร้อมกันได้ และทุกเครื่องเห็นตำแหน่งตรงกัน
2. Sprint ทำงานและรู้สึกต่างจากเดินปกติ
3. ไม่มีอาการ teleport/กระตุกรุนแรงในเน็ตเวิร์กปกติ

## 3. จุดที่เน้นทดสอบเฉพาะเฟส
### Performance Benchmark
- ทดสอบที่ 2 / 4 / 8 Players
- เก็บทุกครั้ง: FPS, Memory, Network, CPU

### Sync Drift
- วัด position drift ระหว่าง authority กับ remote ว่าลู่เข้าในเกณฑ์

### Overlay Accuracy
- debug overlay แสดง ping/authority ตรงจริง

## 4. Entry / Exit Criteria
- **Entry**: งานพัฒนาของเฟสเสร็จ, Smoke test ผ่าน, build รันได้
- **Exit**: ผ่านทุกชั้น + Regression + DoD ครบ และไม่มีบั๊ก S0/S1 ค้าง (ดู `Exit_Gate.md`)

## 5. ไฟล์ประกอบ
- `Test_Cases.xlsx` — รายการเทสพร้อมช่อง Pass/Fail
- `Test_Checklist.md` — เช็กลิสต์สรุปตาม DoD
- `Exit_Gate.md` — เงื่อนไขผ่านเฟส
