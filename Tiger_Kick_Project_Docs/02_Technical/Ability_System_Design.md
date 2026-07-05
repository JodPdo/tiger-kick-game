# Ability System — Design (APPROVED)

> **สถานะ:** อนุมัติแล้ว — architect (APPROVE-WITH-CHANGES) + มนุษย์ (project owner) 2026-07-05
> **ที่มา:** การ์ด `TK-P2-16` · บันทึกใน Change Log [0.33]
> **เอกสารนี้คือ source of truth ของ Ability System** (TDD.pdf เป็น binary แก้ยาก — ให้ยึดไฟล์นี้; TDD จะ regen ทีหลังตาม tech-debt)
> เมื่อโค้ดกับเอกสารนี้ขัดกัน = escalate `architect`

## 1. หลักการ (ทำไม)
Kick / Jump / Tag ยังไม่มีในโค้ดจริง — Player ปัจจุบันมีแค่ movement + camera + sync. `TK-P2-16` คือ "แตก Player monolith เป็น component + วางถาดให้ของใหม่เกิดเป็น ability ตั้งแต่แรก" ก่อนจะเขียน Kick/Tag/Jump-Kick ทับ.

## 2. Component Architecture (scene tree ใหม่ของ Player)
```
Player (CharacterBody3D)  — PlayerRoot (Player.gd เดิม ผอมลง)
├── CollisionShape3D
├── MeshInstance3D
├── MovementComponent (Node)     characters/components/MovementComponent.gd
├── CameraComponent  (Node)      characters/components/CameraComponent.gd
├── CameraRig → SpringArm3D → Camera3D   (transform ยังอยู่ใต้ Player; CameraComponent ถือ logic)
├── AbilityController (Node)     characters/abilities/AbilityController.gd
│   └── [ability nodes — สร้าง/ลบ runtime ตาม role จาก AbilityCatalog]
└── MultiplayerSynchronizer      (เดิม + property ใหม่ ดู §4 ช่อง A)
```
- **component = child Node** (ไม่ใช่ Resource) — ต้องมี lifecycle + ถือ scene node ได้ (เช่น KickHitbox Area3D อยู่ใต้ ability node เอง → เพิ่ม ability = 1 ไฟล์). ค่าจูนเป็น `@export` วันนี้ → อัปเกรดเป็น `.tres` ใน TK-P3-01 ได้โดยไม่แตะโครง.

**ความรับผิดชอบ / อะไรย้ายจาก Player.gd เดิม**
| ส่วน | รับผิดชอบ |
|---|---|
| **PlayerRoot** (Player.gd) | `_enter_tree` authority-from-name (**INVARIANT — fix TK-BUG-P1-01, ห้ามย้าย**), naming contract, `get_view_camera()` (delegate — รักษา contract กับ PlayerSpawner), ถือ `role: StringName` + replicated pose props (`stance`, `lean`), `set_role()` กระจายให้ components |
| **MovementComponent** | `_physics_process`: input→velocity, gravity, sprint, **Jump** (TK-P2-10), **non-authority early-return (INVARIANT — fix jitter TK-P1-06)**, pure statics `compute_velocity`/`camera_relative_dir`/`apply_gravity`, **speed profile ต่อ role** (§6 balance) |
| **CameraComponent** | mouse-look, pitch clamp, mouse capture + **ESC gate/consume (load-bearing ต่อ ESC-ESC Leave — ย้ายทั้ง logic+comment)**, sensitivity จาก ConfigManager, **FP/TP mode** (TK-P2-05: tiger=first-person, outer=third-person) |
| **AbilityController** | registry ability ตาม role, input→try_activate, **RPC ทั้งระบบ 3 ตัว (§4)**, cooldown (host จริง + owner ทำนาย), ล็อก input ตาม match state |
| **AbilityCatalog** (pure static) | `role → [ability]` ลำดับ deterministic เท่ากันทุก peer — จุดเดียวที่แตะเมื่อเพิ่ม ability |

## 3. Base Ability API
```gdscript
class_name Ability extends Node
enum Resolution { HOST_AUTHORITATIVE, LOCAL_ONLY }
@export var ability_id: StringName
@export var input_action: StringName
@export var cooldown_sec: float = 0.0
var resolution := Resolution.HOST_AUTHORITATIVE      # DEFAULT = ปลอดภัยสุด (ลืมประกาศ = ผ่าน host)

func can_activate(ctx) -> bool                        # owner precheck (cooldown/grounded/state)
func on_activate_local(ctx) -> void                  # owner feedback ทันที (cosmetic เท่านั้น)
func host_validate(ctx) -> Dictionary                # HOST เท่านั้น: {ok, reason, result}
func host_apply(result) -> void                      # HOST: แก้ authoritative state / แจ้ง GameManager
func on_confirmed(result) -> void                    # ทุก peer หลัง broadcast — จุดเดียวที่ "ผล" เกิด
func on_rejected(reason) -> void                     # owner ยกเลิก windup
```
`class_name HumanAbility extends Ability` · `class_name TigerAbility extends Ability`
**ability subclass ห้ามมี `@rpc` เอง** — network surface อยู่ที่ AbilityController ไฟล์เดียว.
**เกณฑ์ resolution:** *"โกงแล้วชนะเกมได้ = HOST; โกงแล้วแค่ภาพ/เสียงเพี้ยน = LOCAL_ONLY"*

| Ability | Resolution |
|---|---|
| Kick, Jump-Kick, Tag, Pounce | **HOST** (ตัดสินเกม) |
| Hide | HOST (default — รอ designer นิยามกลไก Phase 3) |
| Crouch, Lean, Peek, Emote | **LOCAL_ONLY** + pose replication (ช่อง A) |
| **Sprint, Jump** | **ไม่ใช่ ability** — MovementComponent (movement primitive) |

**testability:** logic ตัดสินใจเป็น pure static แยกไฟล์ (pattern เดียวกับ `TigerSelector`/`SpawnPointUtil`) เช่น `KickRules.is_in_range()`, `CooldownLedger.can_fire()`, `AbilityCatalog.abilities_for_role()` → `host_validate` เป็นเปลือกบาง.

## 4. Networking — 2 ช่องทาง (จารึกถาวร)
- **ช่อง A — owner-sync (MultiplayerSynchronizer เดิม):** สิ่งที่เจ้าของประกาศเกี่ยวกับตัวเอง + โกงแล้วได้แค่ภาพเพี้ยน — `position`, `rotation` (เดิม) + `stance:int`, `lean:float`, `emote_id:int` (ON_CHANGE, path จาก Player root `.:stance`). remote เห็นเสือหมอบ/ชะโงกผ่านช่องนี้.
- **ช่อง B — host-RPC เท่านั้น:** ผล ability ที่ตัดสินเกม + **`role`**. **role มาจาก GameManager broadcast (`apply_role_switch`) เท่านั้น — ห้ามใส่ใน synchronizer** เพราะ synchronizer ไหลจาก authority (peer เจ้าของ Player) ไปทางเดียว → ถ้า role อยู่ในนั้น client ประกาศตัวเป็นเสือได้ = ทะลุ server authority.

**RPC 3 ตัว ที่ AbilityController** (node static ใน Player.tscn → NodePath ตรงกันทุก pear เสมอ):
```gdscript
@rpc("any_peer","reliable")   func rpc_request_activate(ability_id, payload)  # host เช็ค sender == authority ของ Player นี้
@rpc("authority","call_local","reliable") func rpc_confirm(ability_id, result)  # host → ทุกคน
@rpc("authority","reliable")  func rpc_reject(ability_id, reason)               # host → ผู้ขอ
```
**เดินจริง Kick:** client กด → can_activate → on_activate_local(windup) → `rpc_request_activate.rpc_id(1,...)` → host: เช็ค sender-owns-player + state==Playing + `host_validate` (ระยะจากตำแหน่งฝั่ง host, cooldown ledger ฝั่ง host) → ผ่าน `host_apply`+`rpc_confirm`(call_local) → ทุก peer `on_confirmed`; ไม่ผ่าน `rpc_reject` → owner `on_rejected`.
- LOCAL_ONLY (Crouch): ไม่ยิง RPC — set `stance` บน root → synchronizer พาไป.
- **หมายเหตุ latency:** host เห็น client ช้ากว่าจอ client เล็กน้อย → "จอฉันโดนแต่ host บอกไม่โดน" เกิดได้ → รับได้สำหรับ party game, จูนระยะให้ใจดี Phase 3.

### 4a. Authority ของ node ใน Player (จารึกเพิ่ม 2026-07-05 — แก้ defect ที่ review TK-P2-16 Step 3 พบ; architect APPROVE, Change Log [0.35])
- **Player (root), MultiplayerSynchronizer, MovementComponent, CameraComponent:** authority = **peer เจ้าของ** (จาก recursive set ใน `Player._enter_tree()` — INVARIANT TK-BUG-P1-01 คงเดิม ห้ามย้าย)
- **AbilityController + ability children ทั้งหมด:** authority = **1 (server) เสมอ** — AbilityController เรียก `set_multiplayer_authority(1)` ใน `_enter_tree()` ของตัวเอง ซึ่งวิ่ง**หลัง** recursive set ของ Player เสมอ (parent-ก่อน-child, ยืนยัน empirically บน Godot 4.7) และ override เฉพาะ subtree ตัวเอง — sibling synchronizer ยังเป็นของ owner → position/spawn sync ไม่กระทบ. ability node ที่สร้าง runtime ได้ default authority = 1 ตรงกันอยู่แล้ว
- **เหตุผล:** Godot ตรวจ `@rpc("authority")` ฝั่งรับด้วย `sender == authority ของ node นั้น`. ถ้า AbilityController เป็นของ owner: confirm/reject จาก host โดน drop และ client เจ้าของ forge `rpc_confirm` ได้เอง = server authority พลิกกลับ (S1). ตั้ง authority=1 ให้ engine drop RPC ปลอมก่อนถึงโค้ดเรา (fail-closed)
- **กฎถาวร:** ห้ามตีความ `@rpc("authority")` ว่า "host-only" บน node ใดที่ authority ไม่ใช่ server — annotation ผูกกับ authority ของ node เสมอ. guard `is_server()` + `sender == authority ของ Player` ใน `rpc_request_activate` คงไว้ (defense in depth). ในโค้ด ability: **owner check = `_body.is_multiplayer_authority()` (Player root)** · **host check = `multiplayer.is_server()`** — ห้ามใช้ `is_multiplayer_authority()` ของ AbilityController เอง (หลัง fix = "am I host" ไม่ใช่ "am I owner")
- **walkthrough Kick (host/offline ที่เป็นเจ้าของ Player เอง):** `try_activate` ห้ามยิง `rpc_id(1)` หาตัวเอง (Godot ห้าม self-RPC) — เรียก `_host_process_request(...)` (method ธรรมดา ตัวเดียวกับที่ `rpc_request_activate` เรียก) ตรง ๆ; reject ให้ host ผู้ขอ = `on_rejected` local ไม่ยิง `rpc_reject.rpc_id(1)`. client ทางไกลเดินเส้นเดิมผ่าน sender==authority guard ครบ

## 5. Role-swap
1. GameManager (host) เดิน Tag Sequence ถึง transform → `apply_role_switch.rpc(old, new)` (`authority, call_local, reliable`)
2. ทุก peer หา Player จาก `Players/str(peer_id)` → `player.set_role(&"tiger"/&"outer")`
3. `PlayerRoot.set_role()` (idempotent) กระจาย: AbilityController free+rebuild จาก catalog · CameraComponent set FP/TP (จริงเฉพาะเครื่องเจ้าของ) · MovementComponent apply role speed profile
4. ระหว่าง Tag Sequence match state ≠ Playing → try_activate ปฏิเสธต้นทาง + host เช็ค state ซ้ำใน validate (2 ชั้น)

## 6. Balance — per-role speed (ตัดสินโดยมนุษย์ 2026-07-05, จูน Phase 3)
**Sprint = movement primitive ที่ทุกคนมี แต่ค่าความเร็วเป็น per-role:**
- **Human:** walk 4.0 / sprint 6.0 m/s
- **Tiger:** max (รวม sprint) **≤ 4.0 m/s** = "เดินคน" — เสือกด sprint ได้แต่เพดานต่ำ
- **เจตนา:** เสือ = นักล่าซุ่ม ไม่ใช่นักวิ่งไล่ → จับด้วย **Pounce + จังหวะคนเข้ามาเตะ** ไม่ใช่วิ่งไล่
- ค่าเดิม TK-P1-02 (walk 5.0 / sprint ×1.4) ใช้ต่อจนกว่า role profile จะ wire (ไม่ใช่ Step 1); ค่าใหม่นี้เป็นเป้า
- **TigerAbility catalog (หลังตัด Sprint):** {Crouch, Lean, Pounce, Peek} · HumanAbility: {Kick, Hide, Emote} (+Jump-Kick)

## 7. Migration — TK-P2-16 = Step 1→3 (แต่ละ step 1 PR, ผ่าน reviewer+qa, ห้ามผสมย้ายโค้ดกับเปลี่ยนพฤติกรรม)
**เกณฑ์ no-regress ทุก step:** GUT เขียว (baseline 119) · net_smoke PASS · spawn probe PASS (CI gate) · manual 2 หน้าต่าง: spawn ตรง slot, ขยับ/sprint sync ไม่ jitter, mouse-look ปกติ, **ESC 2 จังหวะ**, host quit→client กลับ MainMenu.
- **Step 1** — แยก `MovementComponent` (พฤติกรรมเดิม 100%, ค่าเดิม). invariant: non-authority early-return + `_enter_tree` authority คงที่, ไม่แตะ SceneReplicationConfig.
- **Step 2** — แยก `CameraComponent` (TP โหมดเดียวเท่าเดิม). **จุดเสี่ยง #1: ESC gate+consume ต้องย้ายทั้ง logic+comment** (พลาด = single-ESC ดีดออกทั้ง session, บั๊กที่เคย ship มาแล้ว). `get_view_camera()` คงอยู่ PlayerRoot → **ไม่แตะ PlayerSpawner**.
- **Step 3** — `AbilityController` เปล่า + role plumbing + เพิ่ม `stance`/`lean` เข้า SceneReplicationConfig (ค่าไม่เปลี่ยน=ไม่มี traffic; **แยกเดี่ยว + เกณฑ์ no-ERROR in log** เพราะโซนนี้กัดคน — บทเรียน TK-BUG-P1-01).
- **Step 4 (= การ์ด TK-P2-01 Kick, นอก TK-P2-16)** — ability HOST ตัวแรกวิ่งครบ pipeline; ต้องนิยาม InputMap action `kick` ก่อน. DoD: "เพิ่ม ability = 1 ไฟล์ + 1 บรรทัด catalog" ผ่านจริง.
- **Step 5 (TK-P2-04/05)** — FP mode + role-swap wiring จริง.
> TK-P2-16 ถือว่าเสร็จที่จบ Step 3.

## 8. New ownership boundaries
- **AbilityController** = เจ้าของ network surface ของ ability ทั้งหมด (RPC)
- **GameManager** (TK-P2-15) = เจ้าของ role + Tag Sequence 7 ขั้น (ability ไม่กลืน match flow)
- **MovementComponent** = เจ้าของ physics primitives (Sprint, Jump)
- **ability subclass** = logic + visuals เท่านั้น

## 9. ความเสี่ยง / open (ตรง ๆ)
- Host-view fairness: "จอฉันโดนแต่ระบบบอกไม่โดน" ตามธรรมชาติ — เลือกถูกต้อง (no desync) เหนือแม่น; แก้ด้วยขยาย range ก่อน lag-comp
- Crouch LOCAL_ONLY มีช่องโกงเบา (ประกาศหมอบทั้งที่วิ่ง) — host sanity-check pose-vs-speed ก่อน Steam (Phase 5)
- เพิ่ม property เข้า SceneReplicationConfig (Step 3): มั่นใจ 90% ไม่กวน pending-spawn (spawn=false อยู่แล้ว) → บังคับ Step 3 แยกเดี่ยว + probe no-ERROR
- Late-join/reconnect: role/ability สร้างจาก broadcast ณ เวลาเกิด — Phase 5 ต้อง state snapshot ตอนเข้า (`set_role` idempotent รอไว้แล้ว ยังไม่พิสูจน์)
- Hide HOST-or-LOCAL: รอ designer นิยามกลไก (default HOST ตามหลัก fail-safe)
