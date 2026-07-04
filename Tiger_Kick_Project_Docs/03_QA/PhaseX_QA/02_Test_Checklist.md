# Test Checklist — Phase X — Development Infrastructure

เช็กลิสต์ทำมือ ใช้ควบคู่ `Test_Cases.xlsx` (บันทึกผลละเอียดในไฟล์ Excel)

## A. ยืนยัน Definition of Done
- [ ] (DoD) เปิด-ปิด Debug overlay ได้ และเห็น FPS/ping/state แบบเรียลไทม์
- [ ] (DoD) เปลี่ยน Settings แล้วบันทึก/โหลดกลับมาได้หลังปิดเปิดเกม
- [ ] (DoD) มี unit test อย่างน้อย 1 ชุดที่รันผ่าน

## B. รายการทดสอบหลัก
- [ ] TKX-01 — Logger เขียนไฟล์ตามระดับ  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TKX-02 — Log rotation/archive  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TKX-03 — Debug overlay toggle  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TKX-04 — Settings save/load  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TKX-05 — Rebind ปุ่ม (Controls)  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TKX-06 — GUT รันเทสผ่าน  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TKX-07 — Error handling รวมศูนย์  
  ผล: ☐ Pass ☐ Fail ☐ Blocked

## C. ก่อนตัดสิน Exit Gate
- [ ] รัน Regression (Smoke + Core + Regression เต็ม) ผ่าน
- [ ] ไม่มีบั๊ก S0 (Crash) ค้าง
- [ ] ไม่มีบั๊ก S1 (Desync) ค้าง
- [ ] กรอก `Test_Report` และให้ QA + Tech Lead เซ็นอนุมัติ
