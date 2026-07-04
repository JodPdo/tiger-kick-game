# Test Checklist — Phase 5 — Feature Expansion & Steam

เช็กลิสต์ทำมือ ใช้ควบคู่ `Test_Cases.xlsx` (บันทึกผลละเอียดในไฟล์ Excel)

## A. ยืนยัน Definition of Done
- [ ] (DoD) ผู้เล่นสร้าง/เข้าร่วม lobby ผ่าน Steam และเล่นด้วยกันได้
- [ ] (DoD) ฟีเจอร์ใหม่แต่ละตัวผ่านเกณฑ์ความสนุกก่อนเข้าเกมจริง

## B. รายการทดสอบหลัก
- [ ] TK5-01 — Steam: สร้าง lobby  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK5-02 — Steam: join/invite  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK5-03 — Cloud Save ซิงก์ข้ามเครื่อง  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK5-04 — Achievement ยิงถูกเงื่อนไข  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK5-05 — Steam Overlay ทำงาน  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK5-06 — Install/Update สะอาด  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK5-07 — Offline mode ไม่ crash  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK5-08 — Feature flag: ปิดฟีเจอร์ใหม่  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK5-09 — Full Release regression  
  ผล: ☐ Pass ☐ Fail ☐ Blocked

## C. ก่อนตัดสิน Exit Gate
- [ ] รัน Regression (Smoke + Core + Regression เต็ม) ผ่าน
- [ ] ไม่มีบั๊ก S0 (Crash) ค้าง
- [ ] ไม่มีบั๊ก S1 (Desync) ค้าง
- [ ] กรอก `Test_Report` และให้ QA + Tech Lead เซ็นอนุมัติ
