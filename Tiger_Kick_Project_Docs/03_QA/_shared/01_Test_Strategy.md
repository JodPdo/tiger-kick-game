# Test Strategy — Tiger Kick

กลยุทธ์การทดสอบ 4 ชั้น + Regression และการวางระบบ CI

## 1. Unit Test (GUT)
- ทดสอบ logic ที่แยกออกจาก node ได้ เช่น การเปลี่ยนสถานะบทบาท, การคำนวณ cooldown, การ validate RPC
- รันอัตโนมัติทุก push ผ่าน CI
- เป้าหมาย: จับ logic error เร็วที่สุดโดยไม่ต้องเปิดเกม

## 2. Integration / Multiplayer Test
- รันหลายอินสแตนซ์ (หรือ headless client) เพื่อตรวจการซิงก์จริง
- ตรวจ: position drift ระหว่าง authority กับ remote, ความถูกต้องของ RPC, การส่งต่อ multiplayer authority
- จำลองสภาพเน็ตเวิร์กจริง: latency, packet loss, disconnect/reconnect

## 3. Manual QA Checklist
- เช็กลิสต์ทำมือที่ผูกกับ DoD ของเฟสโดยตรง (ไฟล์ `05_Test_Checklist` รายเฟส)
- ทุกข้อมีผล Pass / Fail / Blocked และช่องหมายเหตุ

## 4. Playtest
- เทสกับผู้เล่นจริง 4–8 คน เก็บ feedback + **บันทึกวิดีโอทุกแมตช์**
- เน้นวัด "ความรู้สึก" และความชัดของ UX ไม่ใช่แค่บั๊ก

## 5. Regression Test (อยู่ก่อน DoD)
- รัน test case ของเฟสก่อนหน้าทั้งหมดซ้ำ เพื่อยืนยันว่าไม่มีของเก่าพัง
- แบ่งชั้นตาม `04_Regression_Suite`: Smoke → Core → Regression → Release

## 6. CI Strategy
- **ทุก push**: รัน CI Smoke Test (Clone → Open → Import → Build → Run) + Unit test
- ถ้า CI แดง = ห้าม merge
- CI Smoke ช่วยจับ project พัง / dependency หาย / addon หาย ตั้งแต่ต้น

## 7. เมทริกซ์การเน้นทดสอบรายเฟส
| Phase | เน้นเป็นพิเศษ |
|---|---|
| 0 | CI Smoke Test, connection smoke |
| X | Developer QA (Logger/Config), unit test tooling |
| 1 | Performance Benchmark (2/4/8 players), sync drift |
| 2 | Chaos Testing, State Transition, RPC Validation, Anti-cheat |
| 3 | Balance Validation + ความแม่นของ analytics |
| 4 | UX QA + จังหวะ hitbox ตามเฟรมแอนิเมชัน |
| 5 | Release QA (Steam) + full regression |
