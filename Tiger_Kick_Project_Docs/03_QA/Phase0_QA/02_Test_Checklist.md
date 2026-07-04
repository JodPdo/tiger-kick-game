# Test Checklist — Phase 0 — Setup & Networking Foundation

เช็กลิสต์ทำมือ ใช้ควบคู่ `Test_Cases.xlsx` (บันทึกผลละเอียดในไฟล์ Excel)

## A. ยืนยัน Definition of Done
- [ ] (DoD) clone repo แล้วเปิดใน Godot ได้ทันทีโดยไม่มี error
- [ ] (DoD) เปิดสองอินสแตนซ์ กด Host และ Join แล้วเชื่อมต่อกันสำเร็จ
- [ ] (DoD) มี log/ข้อความยืนยันว่า peer เข้ามาแล้ว

## B. รายการทดสอบหลัก
- [ ] TK0-01 — CI Smoke: clone→open→import→build→run  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK0-02 — เปิดโปรเจกต์ครั้งแรกไม่มี error  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK0-03 — Host สร้างเซิร์ฟเวอร์สำเร็จ  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK0-04 — Join เชื่อมต่อ host ได้ (localhost)  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK0-05 — Log ยืนยัน peer_connected  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK0-06 — Disconnect แล้วไม่ crash  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK0-07 — Reconnect ได้หลังหลุด  
  ผล: ☐ Pass ☐ Fail ☐ Blocked
- [ ] TK0-08 — Join ด้วย IP ผิดแล้ว handle ได้  
  ผล: ☐ Pass ☐ Fail ☐ Blocked

## C. ก่อนตัดสิน Exit Gate
- [ ] รัน Regression (Smoke + Core + Regression เต็ม) ผ่าน
- [ ] ไม่มีบั๊ก S0 (Crash) ค้าง
- [ ] ไม่มีบั๊ก S1 (Desync) ค้าง
- [ ] กรอก `Test_Report` และให้ QA + Tech Lead เซ็นอนุมัติ
