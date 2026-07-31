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

## 8. Checklist บังคับ: ผลลัพธ์ที่ยืนยันผ่าน RPC ต้องมี scene-tree test ว่า "ผลลง _โหนดที่ถูกต้อง_"
**บริบท (บั๊กคลาสเดียวกันเกิดซ้ำ 2 ครั้งแล้ว):** เมื่อ ability / outcome ที่ host เป็นคนตัดสิน ต้อง resolve ว่า "ผลของ RPC broadcast นี้ลงกับ _โหนดจริงตัวไหน_" (ซึ่งไม่จำเป็นต้องเป็นโหนดที่โค้ดกำลังรันอยู่) — โค้ด glue ตรงจุด resolve นี้เคยผิดเงียบ ๆ ทั้งที่ pure logic ผ่าน unit test เขียว 300+ asserts:
- **`TK-P2-32`** — `KickAbility.host_validate()` เล็งผู้เล่นที่ใกล้ที่สุด "คนไหนก็ได้" แทนที่จะกรอง `role == tiger` → มองไม่เห็นตอน N=2 (ผู้เล่นอีกคน = เสือพอดี) โผล่เฉพาะ N≥3
- **`TK-BUG-P2-01`** — `KickAbility.on_confirmed()` เช็ก stagger กับโหนดของ _ผู้เตะเอง_ (`_body`) แทนที่จะ resolve _เป้าหมาย_ ที่ถูกยืนยัน → เงื่อนไขเป็นเท็จถาวร `start_stagger()` เป็น dead code ทุก N

**กติกา (ทำทุกครั้งที่การ์ดมี on_confirmed()/local-apply/host-authoritative outcome แบบ "รันทุก peer ต้อง resolve โหนดที่ถูก"):**
- แยก pure logic (unit-tested แยก) ออกจาก glue ที่ resolve โหนด — **glue ต้องมี test ของตัวเอง** ไม่ใช่พึ่ง unit test ของ pure helper
- เขียน scene-tree GUT test ด้วย `Player.tscn` จริง (**ไม่ mock**), ตั้งชื่อโหนด = peer_id, สร้างสถานการณ์ที่ "โหนดผิด" จะถูกเลือกถ้า resolution พัง (เช่น N≥3 คละ role, หรือ target ≠ `_body`)
- **assert ผลลัพธ์ที่สังเกตได้จริง** (role พลิก, `is_staggered() == true`, position เปลี่ยน) บนโหนดที่ถูก + ยืนยันว่าโหนดอื่น (ผู้เตะ / bystander / peer ที่ไม่ได้เป็นเจ้าของ) **ไม่โดน** — ห้ามหยุดแค่ "รันแล้วไม่ crash"
- **พิสูจน์ว่า test เป็น load-bearing:** break logic ที่ resolve โหนดชั่วคราว → ยืนยัน test แดง → คืนค่า (อย่าเชื่อแค่ว่ามันเขียว)
- ขอบเขตที่คลุมแล้ว (`TK-P2-33`): `KickAbility.on_confirmed()` (kick stagger targeting), `GameManager.apply_role_switch()` / `assign_first_tiger()` / `_apply_tiger_position_correction()`, `RoundManager.start_new_round()`
- การ์ด ability / host-authoritative outcome ใหม่ (เช่น **`TK-P3-06`** Charged Kick/Knockdown: ตัวนับต่อผู้เล่น + knockdown/invuln) ต้องใช้ pattern นี้ตั้งแต่แรก — assert ว่าตัวนับ/สถานะลงกับ _โหนดที่ resolve ถูก_ ไม่ใช่รอให้เกิดครั้งที่ 3 แล้วค่อยตามแก้
