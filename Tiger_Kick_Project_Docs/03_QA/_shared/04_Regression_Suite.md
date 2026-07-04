# Regression Suite — Tiger Kick

Regression Suite โตขึ้นทุกเฟส แบ่งเป็น 4 ชั้นตามความครอบคลุมและเวลาในการรัน
เลือกชั้นให้เหมาะกับสถานการณ์ (ยิ่งใกล้ release ยิ่งรันครบ)

## ชั้นของ Regression
```
Smoke  →  Core  →  Regression  →  Release
(เร็วสุด)                        (ครบสุด)
```

### 1. Smoke (รันทุก push / ก่อนเริ่มงาน)
เป้าหมาย: ยืนยันว่าเกม "เปิดและเชื่อมต่อได้"
- Host ได้
- Join ได้
- Move ได้

### 2. Core (ก่อนปิดงานประจำวัน / ก่อน merge ใหญ่)
เป้าหมาย: ยืนยันว่า Core Loop ยังทำงาน
- Kick
- Tag
- Role Switch
- Round Restart

### 3. Regression (ก่อน Exit Gate ของแต่ละเฟส)
เป้าหมาย: รัน **ทุก Test Case** ของเฟสปัจจุบันและเฟสก่อนหน้า
- รวมทุก case ใน `PhaseN_QA/Test_Cases.xlsx` ของทุกเฟสที่ผ่านมา

### 4. Release (ก่อนปล่อยจริงบน Steam)
เป้าหมาย: รัน **ทุกอย่าง** รวม Release QA ของ Steam
- ทุก Test Case + Steam (Install/Update/Cloud/Achievement/Invite/Overlay/Offline)
- Performance benchmark เต็ม + Chaos testing

## หลักการดูแล Suite
- ทุกบั๊ก S0/S1 ที่แก้แล้ว ต้องเพิ่มเป็น regression case กันเกิดซ้ำ
- โครงสร้างนี้ขยายได้โดยไม่ต้องรื้อใหม่ เพียงเพิ่ม case เข้าในชั้นที่เหมาะสม
