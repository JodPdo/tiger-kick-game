# Test Checklist — Phase 3 — Playtest & Tuning

เช็กลิสต์ทำมือ ใช้ควบคู่ `Test_Cases.xlsx` (บันทึกผลละเอียดในไฟล์ Excel)

## A. ยืนยัน Definition of Done
- [ ] (DoD) มีข้อสรุปชัดว่า core loop สนุกพอจะไปต่อหรือไม่
- [ ] (DoD) ได้ชุดค่าพารามิเตอร์ที่ผู้เล่นส่วนใหญ่รู้สึกสนุก

## B. รายการทดสอบหลัก
- [ ] TK3-01 — Analytics เก็บ round time ถูก  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK3-02 — Kick Success % คำนวณถูก  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK3-03 — Balance: Tiger Win อยู่ 40–60%  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK3-04 — Playtest session มีวิดีโอครบ  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK3-05 — แบบสอบถามเก็บครบ  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK3-06 — ชุดค่าปรับจูนสลับได้  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK3-07 — Heatmap ตำแหน่งบันทึกได้  
  ผล: ☐ Pass ☐ Fail ☐ Blocked

## C. ก่อนตัดสิน Exit Gate
- [ ] รัน Regression (Smoke + Core + Regression เต็ม) ผ่าน
- [ ] ไม่มีบั๊ก S0 (Crash) ค้าง
- [ ] ไม่มีบั๊ก S1 (Desync) ค้าง
- [ ] กรอก `Test_Report` และให้ QA + Tech Lead เซ็นอนุมัติ
