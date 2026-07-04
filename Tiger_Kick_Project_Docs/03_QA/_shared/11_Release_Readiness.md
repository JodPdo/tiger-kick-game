# Release Readiness Checklist — Tiger Kick

เช็กลิสต์สุดท้ายก่อนปล่อยขึ้น Steam (ใช้ร่วมกับ Release regression suite)
ทุกข้อต้องผ่านหรือมีเหตุผลรองรับก่อนกดปล่อย

## 1. คุณภาพและการทดสอบ
- [ ] Smoke suite ผ่าน
- [ ] Core suite ผ่าน
- [ ] Regression เต็มผ่าน
- [ ] Performance benchmark (2/4/8) ผ่านเกณฑ์
- [ ] Crash (S0) = 0
- [ ] Desync (S1) = 0

## 2. การเชื่อมต่อ Steam
- [ ] Install / Update สะอาด
- [ ] Steam Cloud ซิงก์ได้
- [ ] Achievements ยิงถูกเงื่อนไข
- [ ] Lobby / Invite / Overlay ทำงาน
- [ ] Offline mode ไม่ crash

## 3. เอกสารและการปล่อย
- [ ] Known Issues บันทึกครบ (พร้อม severity)
- [ ] Release Notes เขียนแล้ว
- [ ] Change Log อัปเดตเวอร์ชันที่จะปล่อย
- [ ] Backup Build เก็บไว้ (rollback ได้)

## 4. อนุมัติปล่อย (Go / No-Go)
- ผล: ☐ Go   ☐ No-Go (เหตุผล: __________)
- QA: ______  Tech Lead: ______  วันที่ ______
