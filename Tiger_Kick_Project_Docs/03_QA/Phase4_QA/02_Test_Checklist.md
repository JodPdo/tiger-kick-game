# Test Checklist — Phase 4 — Feel & Polish

เช็กลิสต์ทำมือ ใช้ควบคู่ `Test_Cases.xlsx` (บันทึกผลละเอียดในไฟล์ Excel)

## A. ยืนยัน Definition of Done
- [ ] (DoD) การเตะ/จับ/สลับบทบาทมี feedback ภาพ+เสียงที่ชัด
- [ ] (DoD) ผู้เล่นเข้าใจสถานะบทบาททันทีจากภาพ/UI
- [ ] (DoD) มีคลิปโมเมนต์ที่ 'อยากแชร์' เกิดขึ้นจริงระหว่างเทส

## B. รายการทดสอบหลัก
- [ ] TK4-01 — Feedback ภาพ+เสียงตอนเตะ  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK4-02 — Feedback ตอนสลับบทบาท  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK4-03 — Hitbox ออกตรงเฟรมแอนิเมชัน  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK4-04 — UX: ผู้เล่นใหม่เข้าใจบทบาท  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK4-05 — UX: กล้อง FP ไม่เวียนหัว  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK4-06 — UI รอบ/เวลาชัด  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK4-07 — Regression: core loop ยังทำงาน  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK4-08 — ไม่มี perf regression จาก VFX  
  ผล: ☐ Pass ☐ Fail ☐ Blocked

## C. ก่อนตัดสิน Exit Gate
- [ ] รัน Regression (Smoke + Core + Regression เต็ม) ผ่าน
- [ ] ไม่มีบั๊ก S0 (Crash) ค้าง
- [ ] ไม่มีบั๊ก S1 (Desync) ค้าง
- [ ] กรอก `Test_Report` และให้ QA + Tech Lead เซ็นอนุมัติ
