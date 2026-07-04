# Tiger Kick — Master Test Plan (QA)

เอกสารระดับโปรเจกต์ที่กำหนดภาพรวม QA ทั้งหมดของ Tiger Kick ใช้ร่วมกันทุกเฟส
เอกสารรายเฟสจะอ้างอิงเอกสารกลางชุดนี้ ไม่เขียนซ้ำ

## 1. เป้าหมายของ QA
พิสูจน์ว่าแต่ละเฟส "ทำงานถูกต้องและเสถียรพอ" ตาม Definition of Done (DoD) ก่อนขึ้นเฟสถัดไป
โดยเน้นเป็นพิเศษที่ความถูกต้องของ Multiplayer (ไม่มี desync / เสือซ้อน / เสือหาย) และความสนุกของ Core Loop

## 2. QA Architecture (ลำดับการตรวจ)
ทุกเฟสเดินตามสายนี้ และ **Regression Test ต้องอยู่ก่อน DoD เสมอ**

```
Development
   ↓
Unit Test (GUT)
   ↓
Integration / Multiplayer Test
   ↓
Manual QA Checklist
   ↓
Playtest
   ↓
Regression Test        ← ต้องผ่านก่อน
   ↓
Definition of Done
   ↓
Exit Gate
   ↓
Next Phase
```

เหตุผล: ต้อง "เล่นผ่าน → Regression → DoD → Exit" ไม่ใช่ "DoD → Regression"
เพราะ DoD คือประตูสุดท้าย และต้องยืนยันว่าไม่มีของเก่าพังก่อนถึงจะปิดเฟสได้

## 3. 4 ชั้นการทดสอบ (สรุป — รายละเอียดใน 01_Test_Strategy)
1. **Unit Test (GUT)** — logic ที่แยกจาก node ได้
2. **Integration / Multiplayer Test** — รันหลายอินสแตนซ์/headless ตรวจ sync และ RPC
3. **Manual QA Checklist** — เช็กลิสต์ทำมือตาม DoD
4. **Playtest** — เทสกับคนจริง เก็บ feedback + วิดีโอ
เสริมด้วย **Regression Test** ที่โตขึ้นทุกเฟส

## 4. ขอบเขต (Scope)
| อยู่ในขอบเขต QA | อยู่นอกขอบเขต (ช่วง prototype) |
|---|---|
| Networking, Core Loop, Role Switching | Localization ครบภาษา |
| Performance (FPS/Memory/Network) | การทดสอบบนคอนโซล |
| ความถูกต้องของ state / RPC / anti-cheat พื้นฐาน | Security audit เชิงลึก |
| ความสนุกและความชัดของ UX | Load test ระดับ production |

## 5. บทบาทและความรับผิดชอบ
| บทบาท | หน้าที่ |
|---|---|
| Developer | เขียน Unit test, รัน Smoke ก่อน push, แก้บั๊ก |
| QA / ผู้ทดสอบ | รัน Manual checklist, Integration, บันทึกบั๊ก, ตัดสิน Exit Gate |
| Playtest Lead | จัด session เทสกับคนจริง, เก็บ metric + วิดีโอ |
| Tech Lead | อนุมัติ Exit Gate, จัดลำดับความสำคัญบั๊ก |

## 6. เครื่องมือและสภาพแวดล้อม
- **GUT (Godot Unit Test)** — unit test ใน Godot
- **GitHub Actions** — CI รัน Smoke + Unit test ทุก push
- **หลายอินสแตนซ์ / headless client** — integration/network test
- **Test Cases.xlsx** — บันทึกผลรายเฟส (Pass/Fail)
- สภาพแวดล้อม: localhost ก่อน แล้วขยับเป็น LAN และ internet (จำลอง latency/packet loss)

## 7. Entry / Exit Criteria (ภาพรวม)
- **Entry**: งานพัฒนาของเฟสเสร็จ, build รันได้, Smoke test ผ่าน
- **Exit**: ผ่าน 4 ชั้น + Regression + DoD ครบ และไม่มีบั๊ก S0/S1 ค้าง (ดู `09` Exit Gate รายเฟส)

## 8. เอกสารที่เกี่ยวข้อง
- `01_Test_Strategy.md` — กลยุทธ์ 4 ชั้น + CI
- `02_Severity_and_Bug_Lifecycle.md` — S0–S4 และวงจรบั๊ก
- `03_Bug_Template.md` — เทมเพลตรายงานบั๊ก
- `04_Regression_Suite.md` — Smoke / Core / Regression / Release
- `05_Test_Report_Template.md` — เทมเพลตสรุปผล
- `PhaseN_QA/` — Test Plan, Test Cases.xlsx, Checklist, Exit Gate ของแต่ละเฟส
