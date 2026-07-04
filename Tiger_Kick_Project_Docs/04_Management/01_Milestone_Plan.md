# Milestone Plan — Tiger Kick

แผนหมุดหมายของโปรเจกต์ ผูกกับ Exit Gate ของแต่ละเฟส (เฟสถัดไปเริ่มได้เมื่อ Gate ก่อนหน้าผ่าน)

## Milestones
| Milestone | เฟส | ประมาณระยะเวลา | เกณฑ์ผ่าน (Exit Gate) | ขึ้นกับ |
|---|---|---|---|---|
| M0 Foundation | Phase 0 | ~1 สัปดาห์ | 2 เครื่องเชื่อมต่อกันได้ | — |
| MX Dev Infra | Phase X | ~1 สัปดาห์ | Debug overlay + Settings + unit test | M0 |
| M1 Movement | Phase 1 | ~1–2 สัปดาห์ | 4–8 คนวิ่งซิงก์, benchmark ผ่าน | MX |
| M2 Core Loop | Phase 2 | ~2 สัปดาห์ | core loop ครบ, ไม่มี desync | M1 |
| M3 Fun Proven | Phase 3 | ~1–2 สัปดาห์ | playtest ยืนยันสนุก + balance | M2 |
| M4 Polish | Phase 4 | ~1–2 สัปดาห์ | feedback ชัด, regression ผ่าน | M3 |
| M5 Ship | Phase 5 | ต่อเนื่อง | Steam ทำงาน, Release Readiness ผ่าน | M4 |

## หลักการ
- M2 (Core Loop) และ M3 (Fun Proven) คือหมุดหมายเสี่ยงสูงสุด — ห้ามข้าม
- ทุก Milestone ปิดด้วยการรัน Regression ก่อน แล้วจึงตัดสิน Exit Gate
- ระยะเวลาเป็นค่าประมาณสำหรับทีมเล็ก ปรับตามจริงและบันทึกใน Change Log
