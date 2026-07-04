# Test Checklist — Phase 2 — Core Loop

เช็กลิสต์ทำมือ ใช้ควบคู่ `Test_Cases.xlsx` (บันทึกผลละเอียดในไฟล์ Excel)

## A. ยืนยัน Definition of Done
- [ ] (DoD) เล่นวน core loop ได้ครบ: เตะ → จับ → สลับเสือ → เริ่มรอบใหม่
- [ ] (DoD) ทุกเครื่องเห็นการเปลี่ยนบทบาทตรงกัน ไม่มีเสือซ้อน/หาย
- [ ] (DoD) กล้องสลับถูกต้องตามบทบาททันทีที่ถูกจับ

## B. รายการทดสอบหลัก
- [ ] TK2-01 — Core loop ครบวง  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-02 — Kick ทำงาน + cooldown  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-03 — Tag เปลี่ยนบทบาท  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-04 — ไม่มีเสือซ้อน/เสือหาย  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-05 — กล้องสลับ FP/TP ถูกต้อง  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-06 — State transition ครบทุกเส้น  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-07 — Chaos: packet loss  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-08 — Chaos: disconnect เสือกลางรอบ  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-09 — Chaos: high ping/host lag  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-10 — RPC invalid sender ถูกปฏิเสธ  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-11 — RPC spam/duplicate กันได้  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK2-12 — Round Restart รีเซ็ตครบ  
  ผล: ☐ Pass ☐ Fail ☐ Blocked

## C. ก่อนตัดสิน Exit Gate
- [ ] รัน Regression (Smoke + Core + Regression เต็ม) ผ่าน
- [ ] ไม่มีบั๊ก S0 (Crash) ค้าง
- [ ] ไม่มีบั๊ก S1 (Desync) ค้าง
- [ ] กรอก `Test_Report` และให้ QA + Tech Lead เซ็นอนุมัติ
