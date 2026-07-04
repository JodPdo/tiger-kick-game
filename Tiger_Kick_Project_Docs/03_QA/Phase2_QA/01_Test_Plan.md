# Test Plan — Phase 2 — Core Loop

> อ้างอิงเอกสารกลางใน `_shared/` (Master Test Plan, Test Strategy, Severity, Regression, Bug Template)

## 1. ขอบเขตการทดสอบของเฟส
ทดสอบตาม 4 ชั้น (Unit → Integration → Manual → Playtest) + Regression ก่อน DoD
รายการทดสอบละเอียดอยู่ใน `Test_Cases.xlsx`

## 2. Definition of Done (จาก GDD ของเฟส)
1. เล่นวน core loop ได้ครบ: เตะ → จับ → สลับเสือ → เริ่มรอบใหม่
2. ทุกเครื่องเห็นการเปลี่ยนบทบาทตรงกัน ไม่มีเสือซ้อน/หาย
3. กล้องสลับถูกต้องตามบทบาททันทีที่ถูกจับ

## 3. จุดที่เน้นทดสอบเฉพาะเฟส
### Chaos Testing
- Disconnect / Reconnect / Host Lag / Packet Loss / High Ping
- ดูว่าเกม recover ได้ไหม ไม่ค้าง ไม่ desync ถาวร

### State Transition Test
- ทุกเส้นทางต้องผ่าน: Outer → Kick → Tiger → Round End → Restart → Outer

### RPC Validation
- RPC Spam / Delay / Duplicate / Invalid Sender
- Host ต้องกันได้ทั้งหมด (server-authoritative / anti-cheat)

## 4. Entry / Exit Criteria
- **Entry**: งานพัฒนาของเฟสเสร็จ, Smoke test ผ่าน, build รันได้
- **Exit**: ผ่านทุกชั้น + Regression + DoD ครบ และไม่มีบั๊ก S0/S1 ค้าง (ดู `Exit_Gate.md`)

## 5. ไฟล์ประกอบ
- `Test_Cases.xlsx` — รายการเทสพร้อมช่อง Pass/Fail
- `Test_Checklist.md` — เช็กลิสต์สรุปตาม DoD
- `Exit_Gate.md` — เงื่อนไขผ่านเฟส
