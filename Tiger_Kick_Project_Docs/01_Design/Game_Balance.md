# Game Balance & Physics Model — source of truth

> แทน **GDD §Game Balance** + **TDD §Physics** (ทั้งคู่เป็น .pdf แก้ยาก → ยึดไฟล์นี้; PDF จะ regen ตาม tech-debt)
> ตัดสินโดย: มนุษย์ (project owner) / `designer` — บันทึก Change Log [0.34]
> ค่าทั้งหมดเป็น **"ค่าเสนอ" จูนจริงใน Phase 3 (playtest)** เว้นระบุเป็น locked

## 1. โมเดลฟิสิกส์
- **Kinematic** — `CharacterBody3D` + `move_and_slide()` (ไม่ใช่ RigidBody)
- **Server-authoritative** — ผลที่ตัดสินเกม (Kick/Tag/Pounce โดน, role) host เป็นคนตัดสินผ่าน RPC; ตำแหน่ง = owner-authoritative (แต่ละ peer author ตัวเอง, sync ทางเดียว) ดู `02_Technical/Ability_System_Design.md` §4
- gravity = 9.8 m/s² (engine default; ไม่ระบุใน GDD)

## 2. ความเร็ว (m/s) — per-role
| บทบาท | walk | sprint | หมายเหตุ |
|---|---|---|---|
| **Human (Outer)** | 4.0 | 6.0 | |
| **Tiger** | ≤ 4.0 | **≤ 4.0 (cap รวม sprint)** | เสือกด sprint ได้แต่เพดาน = human walk |
| **Pounce burst (Tiger)** | — | **~8.0** (ชั่วขณะ) | ดู §4 — กลไกจับหลัก |

- **Sprint = movement primitive ที่ทุกคนมี** แต่ **ค่าความเร็วเป็น per-role** (เสือ cap ≤ walk) — ไม่ใช่ ability ของเสือ
- ⚠️ **ค่าปัจจุบันในโค้ด** (จนกว่า role speed profile จะ wire ที่ TK-P2-16 Step 3+): walk 5.0 / sprint ×1.4. ค่าในตารางนี้คือ **เป้า** ที่จะ apply ตอน MovementComponent มี role profile

## 3. กฎเชิงดีไซน์ (locked intent)
> **เสือ = นักล่าซุ่ม (hunt, not chase).** เสือช้ากว่า/เท่าคน จับด้วย **Pounce + จังหวะที่คนเข้ามาเตะ** ไม่ใช่วิ่งไล่. body-language (Crouch→Lean→Peek, TK-P3-05) เสริมความรู้สึกซุ่ม.

## 4. กลไกหลัก (ค่าเสนอ)
| ค่า | เสนอ | สถานะ |
|---|---|---|
| **Safe Circle radius** | **5.0 m** | locked (balance value) — ⚠️ marker ใน `world/TestArena.tscn` (P0-05) วาดไว้ ~6.0 ต้อง reconcile ตอน TK-P2-06 |
| **Kick range** | 1.5 m | เสนอ (จูน P3; host validate ระยะ kicker↔tiger) |
| **Kick Stagger** | เสือเซ ~0.3s + ดันถอยเล็กน้อย (ห้าม stun เต็ม) | การ์ด TK-P2-17 |
| **Pounce burst** | ~8 m/s ระยะสั้น | การ์ด TK-P2-18 (TigerAbility, HOST validate) |
| **Round length** | 3–5 นาที | GDD (ยังไม่ทำ) |
| Cooldowns (Kick/Pounce) | TBD | จูน P3 |

## 5. Ability resolution (สรุปจาก Ability_System_Design.md)
- **HOST_AUTHORITATIVE:** Kick, Jump-Kick, Tag, **Pounce**, Hide(default)
- **LOCAL_ONLY** (+pose sync): Crouch, Lean, Peek, Emote
- **ไม่ใช่ ability (MovementComponent):** Sprint, Jump
- **TigerAbility = {Crouch, Lean, Pounce, Peek}** · HumanAbility = {Kick, Hide, Emote} (+Jump-Kick)

## เปลี่ยนค่า?
แก้ที่ไฟล์นี้ + Change Log + (ถ้ากระทบโค้ด) การ์ด. ค่าในโค้ดควร `@export`/`.tres` (TK-P3-01) เพื่อจูนโดยไม่แตะ logic.
