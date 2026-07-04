# Test Checklist — Phase 1 — Core Movement & Sync

เช็กลิสต์ทำมือ ใช้ควบคู่ `Test_Cases.xlsx` (บันทึกผลละเอียดในไฟล์ Excel)

## A. ยืนยัน Definition of Done
- [ ] (DoD) ผู้เล่น 4–8 คนวิ่งพร้อมกันได้ และทุกเครื่องเห็นตำแหน่งตรงกัน
- [ ] (DoD) Sprint ทำงานและรู้สึกต่างจากเดินปกติ
- [ ] (DoD) ไม่มีอาการ teleport/กระตุกรุนแรงในเน็ตเวิร์กปกติ

## B. รายการทดสอบหลัก
- [ ] TK1-01 — เคลื่อนที่พื้นฐานทุกทิศ  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK1-02 — Sprint เร่งความเร็ว  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK1-03 — Sync ตำแหน่ง 2 เครื่องตรงกัน  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK1-04 — Benchmark 2 players  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK1-05 — Benchmark 4 players  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK1-06 — Benchmark 8 players  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK1-07 — ไม่มี teleport/jitter  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK1-08 — Spawn/Despawn ตามเข้า-ออก  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK1-09 — Overlay แสดง ping ตรง  
  ผล: ☐ Pass ☐ Fail ☐ Blocked

## C. ก่อนตัดสิน Exit Gate
- [ ] รัน Regression (Smoke + Core + Regression เต็ม) ผ่าน
- [ ] ไม่มีบั๊ก S0 (Crash) ค้าง
- [ ] ไม่มีบั๊ก S1 (Desync) ค้าง
- [ ] กรอก `Test_Report` และให้ QA + Tech Lead เซ็นอนุมัติ
