# Change Log — Tiger Kick

บันทึกการเปลี่ยนแปลงสำคัญของโปรเจกต์และเอกสาร (รูปแบบ Keep a Changelog)
เวอร์ชันล่าสุดอยู่บนสุด

## [0.37] — 2026-07-07 — TK-P2-10 Jump: code-complete, REVIEW-PENDING (1 review round, S2 fixed)
- **Jump = movement primitive** (characters/components/MovementComponent.gd + new characters/components/JumpRules.gd pure helper), NOT a new characters/abilities/*Ability.gd. This is a re-confirmation, not a new decision -- Ability_System_Design.md §2/§3 and [0.34] below ("Jump=primitive") already ruled this explicitly; CURRENT_PHASE.md's looser "Jump re-slot as abilities" sprint-summary line is stale phrasing from before that detail, superseded by the dated design doc per CLAUDE.md/DOCUMENT_ROUTING precedence. No new architect escalation was needed.
- **Implementation:** `jump_speed` @export tunable (5.0 m/s placeholder, see Game_Balance.md below) · `JumpRules.can_jump(is_on_floor, is_jumping)`/`jump_velocity(jump_speed)` pure statics (GUT-tested) · new `_is_jumping` flag on MovementComponent (own authoritative "did I jump and not land yet" tracking, independent of `is_on_floor()` which is not live on non-authority copies) mirrored onto a new `Player.is_jumping` replicated property (channel A, ON_CHANGE, same pattern as `stance`/`lean`) · new InputMap action `jump` = spacebar (device -1/all) · jump trigger gated on `Input.mouse_mode == MOUSE_MODE_CAPTURED` (same UI/ESC-ESC guard Kick's input uses)
- **Sync:** `.:position` already replicated the full Vector3 (X/Y/Z) before this card -- no change needed there. New: `.:is_jumping` added to Player.tscn's SceneReplicationConfig so remote peers/host can see "this Player has jumped and not landed yet" for animation/feel, since non-authority copies never run physics locally (TK-P1-06 invariant) and so cannot derive it from their own `is_on_floor()`.
- **code-review round 1: CHANGES-REQUIRED → fixed.** Blocking [S2]: the landing-clear branch cleared `_is_jumping` on `is_grounded` alone, keyed off the SAME read the jump-trigger gate used, reducing `JumpRules.can_jump()`'s own is_jumping guard to dead code -- a stale `is_on_floor()`-true tick while still RISING (a known CharacterBody3D lag on slopes/moving floors, never reproducing on the flat TestArena) could silently clear the flag and permit an illegal mid-air re-jump. **Fix:** landing now requires `is_grounded AND velocity.y <= 0.0` (non-upward motion), and the whole landing-clear + jump-trigger decision was extracted into a new `MovementComponent.step_jump(is_grounded, current_velocity_y, jump_input_pressed) -> float` instance method specifically so the ORDERING itself (not just the pure `can_jump()`/`jump_velocity()` statics it wraps) is GUT-reachable without a live physics tick -- added `tests/test_jump_rules.gd` glue coverage (`test_step_jump_no_double_jump_mid_air_even_with_stale_grounded_true` etc.) exercising the exact regression scenario the review caught.
- **nits fixed:** JumpRules.gd Change Log citation corrected to [0.34]/[0.33] (was [0.36]) · renamed `_airborne`/`is_airborne()`/`Player.airborne` → `_is_jumping`/`is_jumping()`/`Player.is_jumping` (review nit: the old name over-promised -- it is only ever true from an actual jump impulse to landing, NOT general "not on the ground", e.g. a ledge-fall never sets it; the TK-P2-11 hook doc now explicitly flags that scope gap) · Player.gd doc corrected ("mirrored every tick, but the underlying flag/value only changes at 2 transitions", was wrongly "every tick") · `jump` InputMap event now `device -1` (all devices, matching editor-authored convention), `kick`'s pre-existing `device 32` left untouched (out of scope) · confirmed both new `.uid` files exist for commit (`characters/components/JumpRules.gd.uid`, `tests/test_jump_rules.gd.uid`)
- **TK-P2-11 hook left:** `MovementComponent.is_jumping()` getter, documented as owner-side PREDICTION only -- explicitly flagged NOT authoritative (the mirrored `Player.is_jumping` is channel-A/spoofable, same "cheat = wrong pose only" class as `stance`/`lean`) AND explicitly scoped to "jumped, not landed yet" (does NOT cover falling off a ledge); Jump-Kick's host_validate() must independently decide how to authoritatively verify jumping/airborne-ness, and must decide whether "Jump Kick" also covers ledge-falls. Left as open questions for that card, not resolved here.
- **Balance:** added `jump_speed` placeholder (5.0 m/s) to Game_Balance.md §4 -- not yet in GDD, tune Phase 3 per this card's own DoD note.

## [0.36] — 2026-07-06 — TK-P2-16 ปิด (มนุษย์เทส 2 หน้าต่างผ่าน) → เริ่ม Kick
- **TK-P2-16 (Ability scaffold) เสร็จสมบูรณ์** — มนุษย์ยืนยัน 2-window: spawn slot/sprint sync/mouse-look/ESC-2-step/host-quit ครบ (refactor 3 step ไม่พังเกม)
- เริ่ม **TK-P2-01 Kick** = ability HOST_AUTHORITATIVE ตัวแรกบน scaffold; เพิ่ม InputMap action `kick` = left mouse button (project.godot)
- nits ที่ผูกกับ Kick: set_role early-guard, ability_id collision assert, `on_confirmed` ต้องไม่ authoritative (forger self-echo เป็น cosmetic)

## [0.35] — 2026-07-05 — แก้ authority model ของ Ability RPC (§4a) — review จับ + architect เคาะ
- **defect:** review TK-P2-16 Step 3 (Fable 5) จับว่า TK-BUG-P1-01 (recursive authority) ทำให้ AbilityController ได้ authority = client เจ้าของ ไม่ใช่ server → `@rpc("authority")` = "owner" → (1) confirm/reject จาก host โดน drop (2) **client forge rpc_confirm ข้าม host_validate ได้ = server-authority พลิกกลับ (S1)** (3) host กด ability ตัวเองไม่ได้ (self-RPC) — เป็น interaction ข้ามการ์ดที่ per-card review มองไม่เห็น, จับได้ตอน scaffold ว่าง (ก่อน Kick)
- **architect ruling (option a, พร้อม probe พิสูจน์ empirically):** AbilityController เรียก `set_multiplayer_authority(1)` ใน `_enter_tree` ตัวเอง (วิ่งหลัง recursive set, override เฉพาะ subtree ตัวเอง; sibling synchronizer/position ไม่กระทบ) → `@rpc("authority")` กลับมาหมายถึง host, engine drop RPC ปลอม (fail-closed) · + host-local activation path (`_host_process_request` เรียกตรงเมื่อ is_server, reject local เลี่ยง self-RPC)
- บันทึกใน `Ability_System_Design.md` **§4a** (authority ของแต่ละ node); TK-P2-01 Kick ต้องยึด: owner=`_body.is_multiplayer_authority()`, host=`multiplayer.is_server()`
- implement: `network-engineer` (RPC/authority domain) แก้ `AbilityController.gd` อย่างเดียว + tripwire test (authority==1)

## [0.34] — 2026-07-05 — บันทึก Game Balance / Physics + การ์ด Pounce/Kick-Stagger
- สร้าง **`01_Design/Game_Balance.md`** = balance/physics source of truth (แทน GDD §Balance / TDD §Physics ที่เป็น PDF) + เดินสาย DOCUMENT_ROUTING (`design.game_balance`)
- **บันทึกค่า (ค่าเสนอ จูน P3):** Kinematic CharacterBody3D server-auth · Human walk 4.0/sprint 6.0 · Tiger ≤4.0 (cap รวม sprint) · Pounce burst ~8 · Safe Circle radius 5.0m (locked — reconcile marker P0-05 ~6.0 ตอน TK-P2-06) · Kick range 1.5 · Sprint=primitive per-role
- **กฎ locked:** เสือ = นักล่าซุ่ม จับด้วย Pounce+จังหวะคนเข้าเตะ ไม่วิ่งไล่
- **การ์ดใหม่:** `TK-P2-17` Kick Stagger (เสือเซ ~0.3s + ดันถอยเล็กน้อย, host-auth, ห้าม stun เต็ม; dep TK-P2-01) · `TK-P2-18` Pounce (ดึงมา Phase 2, TigerAbility burst ~8 m/s = กลไกจับหลัก, host validate; dep TK-P2-16) — backlog 55→57
- อัปเดต notes `TK-P2-16` ยืนยันทิศ architect (Jump=primitive, Tag=GameManager, Sprint ออกจาก Tiger)

## [0.33] — 2026-07-05 — อนุมัติ Ability System (architecture + design + balance) → เริ่ม Phase 2
- **architect เคาะ + มนุษย์อนุมัติ** design Ability System (`TK-P2-16`) — บันทึกเต็มใน `02_Technical/Ability_System_Design.md` (source of truth; TDD.pdf เป็น binary → regen ทีหลัง)
- **โครง:** Player → MovementComponent / CameraComponent / AbilityController → [abilities]; base `Ability`/`HumanAbility`/`TigerAbility`; component = child Node
- **server-authority:** แกน `HOST_AUTHORITATIVE` vs `LOCAL_ONLY` (default HOST); RPC รวมศูนย์ที่ AbilityController ไฟล์เดียว (ability subclass ห้ามมี @rpc); role มาจาก host RPC ห้ามเข้า synchronizer; 2-channel replication (owner-sync pose vs host-RPC result)
- **architect ปรับทิศ (มนุษย์ยืนยัน):** Jump = movement primitive (ไม่ใช่ ability) · Tag Sequence 7 ขั้น = GameManager ไม่ใช่ ability · TagAbility จบแค่ "host ตัดสินว่าจับโดน"
- **BALANCE (มนุษย์ตัดสิน — design/balance change):** Sprint = primitive ทุกคนมี **แต่ความเร็ว per-role**: Human walk 4.0/sprint 6.0, **Tiger รวม sprint ≤ 4.0** (เสือซุ่มไม่วิ่งไล่ จับด้วย Pounce+จังหวะคนเข้าเตะ) → TigerAbility เหลือ {Crouch, Lean, Pounce, Peek}. ค่าเดิม 5.0/×1.4 ใช้ต่อจน role profile wire (จูนจริง Phase 3)
- **migration:** TK-P2-16 = Step1 แยก Movement → Step2 แยก Camera → Step3 AbilityController เปล่า (แต่ละ step no-regress: GUT+net_smoke+spawn probe); Kick = Step4 (TK-P2-01)
- **doc impact ค้าง (มอบ documentation-manager/regen):** TDD §4/§6/§8.1/§9.1 + routing §10 conflict (แก้ให้ชี้ design doc แล้ว) + KickHitbox/TagArea ย้ายไปใต้ ability node

## [0.32] — 2026-07-05 — Phase 1 (M1 Movement) CLOSED ✅
- Exit Gate ผ่านครบ: **มนุษย์เทส 2 หน้าต่างผ่าน** (spawn ไม่ทับ, ESC-ESC Leave, host ปิด→client กลับเมนู, เดิน/กล้อง sync) + CI เขียว (GUT 119/119 + net_smoke + spawn probe เป็น gate แล้ว)
- `TK-P1-07` done (CI wiring). การ์ด Phase 1 ครบ: TK-P1-01..07 + TK-BUG-P1-01/02
- **บทเรียน:** "116/116 เขียว แต่เกมพัง" → เทส pure-function ล้วนมองไม่เห็น glue bug; แก้เชิงระบบด้วยการเพิ่ม 2-instance spawn probe เข้า CI (ไม่ให้เกิดซ้ำ)
- เหลือ: merge PR #3 (มนุษย์) · **gate ก่อน Phase 2 = architect อนุมัติ design Ability System (TK-P2-16)**

## [0.31] — 2026-07-05 — แก้บั๊ก Phase 1 reopen เสร็จ (ผ่าน review 2 รอบ + qa)
- `TK-BUG-P1-01` (S1): authority ย้ายไป `Player._enter_tree()` (จาก name contract + tripwire) และ spawner เปลี่ยนเป็น `MultiplayerSpawner.spawn_function` ส่ง `{id, position}` ถึงทุก peer โดยไม่พึ่ง authority-gated sync (`spawn=false` บน position/rotation; `_spawnable_scenes` ถอดออกกัน footgun) — spawn probe: client ลง slot ตัวเอง ไม่ทับ host ไม่ (0,0,0) ไม่มี pending-spawn error
- `TK-BUG-P1-02` (S2): signal `NetworkManager.server_disconnected` → `world/TestArena.gd` (ใหม่) พากลับ MainMenu + คืนเมาส์; Leave = ESC-ESC (ESC แรก consume ใน Player ตอน CAPTURED — แก้ single-ESC race ที่ reviewer จับได้จากการยิง key จริง); guard `host()/join()` = ERR_ALREADY_IN_USE
- เทสใหม่: NetworkManager 3 เคส + `tests/net/spawn_probe_peer.gd`/`run_spawn_probe.sh` (เช็ค XZ-tolerance กัน false-pass จาก gravity settle) — GUT 119/119, net_smoke + spawn probe + windowed ESC probe ผ่านหมด
- late-join ตรวจแล้ว**ไม่ใช่ปัญหา** (reviewer ทดลอง 3-instance: late joiner เห็นตำแหน่งปัจจุบันทันที)
- เหลือ: `TK-P1-07` (net smoke + spawn probe เข้า ci.yml) + **มนุษย์เทส 2 หน้าต่าง** = เงื่อนไขปิด Phase 1

## [0.30] — 2026-07-05 — ปรับ model ทีม AI agent
- `producer` / `architect` / `code-reviewer`: opus → **claude-fable-5** · `designer`: sonnet → **claude-opus-4-8** (7 ตัวที่เหลือคง sonnet) — แก้ทั้ง frontmatter `.claude/agents/*.md` และตาราง AGENT_INDEX.md
- ตัดสินโดย: มนุษย์ (project owner)

## [0.29] — 2026-07-05 — ทิศทางสถาปัตย์ใหม่: Ability System (รอ architect อนุมัติ design) + การ์ดใหม่ 8 ใบ
- **adopt Ability System** — `TK-P2-16` scaffold: refactor PlayerController → Movement / Camera / Ability (+ base HumanAbility/TigerAbility) เป็น **งานแรกของ Phase 2** หลังปิด Phase 1; ของเดิม (Kick/Jump/Tag) re-slot เป็น ability — **ต้องให้ `architect` อนุมัติ design ก่อนลงมือ**
- `TK-P3-05` Tiger Body-Language (Crouch → Lean L/R → Peek) = สกิลตัวอย่างพิสูจน์ระบบ (hunt-not-chase)
- Ability catalog (แผน Phase 3-5): Tiger{Crouch, Lean, Sprint, Pounce, Peek} · Human{Kick, Hide, Emote}
- การ์ดใหม่จาก Cowork 8 ใบ: `TK-P2-10/11` (Jump, Jump Kick), `TK-P2-12..15` (Waiting Room → Start Match → Countdown → Match state machine), `TK-P2-16`, `TK-P3-05` — backlog รวม 52→55 ใบ (รวม bug cards ด้านล่าง)
- เสนอ/ตัดสินโดย: มนุษย์ (project owner)

## [0.28] — 2026-07-05 — Audit อิสระ Phase 0-X-1 → REOPEN Phase 1 (แก้บั๊กก่อนเข้า Phase 2)
- producer (Fable 5) ตรวจงานใหม่ทั้งหมดแบบ adversarial + มนุษย์ยืนยันด้วยการเทส 2 หน้าต่างจริง
- **S1-A "เดินไม่ได้ (device:16)" = FALSE ALARM** — มนุษย์เทสจริง: WASD เดินได้ปกติ device:16 ไม่กระทบคีย์บอร์ด (ไม่แก้ project.godot)
- **บั๊กจริงที่ยืนยัน → REOPEN Phase 1:**
  - `TK-BUG-P1-01` (S1, blocker): client spawn ทับหัว host / โผล่ (0,0,0) + engine error "unable to process the pending spawn" ทุก join — สาเหตุ: `PlayerSpawner._on_spawned()` เซ็ต authority หลัง `_ready()` → แก้โดยย้ายไป `Player._enter_tree()`/spawn_function
  - `TK-BUG-P1-02` (S2): host ปิดเกม → client ค้างในสนามว่าง ไม่มีทางออก — แก้: signal `server_disconnected` → กลับ MainMenu + ปุ่ม Leave (`disconnect_from_game()` ยังไม่มี caller เลย)
  - `TK-P1-07`: net smoke เข้า `ci.yml` + 2-instance integration probe (เกณฑ์ no-ERROR + client ไม่ทับ host) — อุดช่องที่เทส pure-function ล้วนมองไม่เห็น glue bugs
- ลำดับที่ตกลง: แก้บั๊ก → มนุษย์เทส 2 หน้าต่าง → ปิด Phase 1 / PR #3 → architect เคาะ Ability System → เริ่ม Phase 2 ที่ TK-P2-16

## [0.27] — 2026-07-05 — Phase 1 code ครบ: synchronizer tuning + remote-physics guard
- `TK-P1-06`: MultiplayerSynchronizer sync เฉพาะ position+rotation, mode ALWAYS→ON_CHANGE (ไม่ส่ง packet ตอนนิ่ง, spawn=true คง seed แรก), non-authority peer skip move_and_slide/gravity (puppet ขับด้วย sync ล้วน กัน jitter), guard is_valid_int ใน _on_spawned
- **Phase 1 (M1 Movement) code ครบ 6/6** — เหลือ Exit Gate: มนุษย์ทดสอบ GUI 2 หน้าต่าง (เดิน/กล้อง/no-jitter) + merge PR #3

## [0.26] — 2026-07-05 — Phase 1: spawner + camera rig + per-player authority
- `TK-P1-04` MultiplayerSpawner: spawn Player ต่อ peer id (host-authoritative), despawn on disconnect, กล้อง current เฉพาะ local (host-local path + client replicated)
- `TK-P1-03` third-person camera rig: `Player→CameraRig→SpringArm3D→Camera3D`, mouse-look (yaw/pitch clamp -60..+30), camera-relative movement, contract `get_view_camera()`
- `TK-P1-05` per-player authority: `set_multiplayer_authority(peer_id)` (host+client path), synchronizer follows recursive → แต่ละ peer คุม player ตัวเอง
- ค้าง (TK-P1-06): skip move_and_slide/gravity บน non-authority peer (กัน jitter) + synchronizer property tuning + guard `int(node.name)` ใน _on_spawned

## [0.25] — 2026-07-05 — Phase 1: movement + InputMap actions
- `TK-P1-02` movement: WASD + gravity + Sprint (Shift) ใน `characters/Player.gd`, ค่า walk 5.0 m/s / sprint ×1.4 จาก TDD §11 (export ปรับได้), input gate `is_multiplayer_authority()`
- เพิ่ม **InputMap actions** ใน `project.godot` `[input]`: `move_forward`(W)/`move_back`(S)/`move_left`(A)/`move_right`(D)/`sprint`(Shift) — ปลดล็อกงาน Controls-rebind ที่ค้างจาก TK-PX-05 ด้วย (ชื่อ action ตรงกับ REBIND_KEYS)
- ค้าง (ผูกไว้ TK-P1-05/06): non-authority peer ยังรัน move_and_slide → ต้อง skip บน remote กัน jitter ตอน authority per-player + synchronizer active

## [0.24] — 2026-07-04 — Phase X ครบ: Settings menu + PerfOverlay (จบ MX Dev Infra)
- `SettingsMenu` (`ui/SettingsMenu.gd/.tscn`, TK-PX-05): Graphics/Audio/Controls tabs → ConfigManager (get/set/save), apply DisplayServer/AudioServer แบบ guard headless + missing-bus; เข้าถึงจากปุ่ม Settings ใหม่ใน MainMenu (แก้ TK-P0-03 แบบ additive — NET SMOKE ยืนยันไม่ regress Host/Join)
- `PerfOverlay` (`ui/PerfOverlay.gd`, TK-PX-03): overlay กด F4 ใช้ Performance singleton (memory/draw/objects/primitives/nodes/process/physics), แยกจาก DebugOverlay (F3, layer 100 vs 101)
- Autoload set: GameLog, ConfigManager, NetworkManager, ErrorHandler, DebugOverlay, PerfOverlay
- **Follow-ups (non-blocking, ยกไป Phase ถัดไป):** (1) Controls rebind รอ InputMap actions ของ Phase 1 (ตอนนี้ placeholder + เก็บใน config) + reconcile รูปแบบ string ("W"→"w"); (2) audio bus layout (Music/SFX) ยังไม่ตั้ง — slider warn+no-op จนกว่าจะเพิ่ม
- verified: GUT 88/88 (1135 asserts) exit 0, ไม่มี rp_logger/leak, NET SMOKE PASS
- **Phase X (MX Dev Infra) เสร็จครบ 7 การ์ด**

## [0.23] — 2026-07-04 — Phase X: เพิ่ม DebugOverlay + ErrorHandler autoloads
- `DebugOverlay` (`ui/DebugOverlay.gd`, TK-PX-02): overlay กด F3 เปิด/ปิด แสดง FPS/ping/scene/role/peers, refresh 0.25s, ไม่ crash ตอน offline
- `ErrorHandler` (`managers/ErrorHandler.gd`, TK-PX-06): `report()/report_if()` route ผ่าน GameLog.error — convention จับ error สำคัญแทน bare push_error (ไม่ hook engine logger เลี่ยงชน GUT error_tracker)
- Autoload set ปัจจุบัน: GameLog, ConfigManager, NetworkManager, ErrorHandler, DebugOverlay
- verified: GUT 52/52 (1083 asserts) exit 0, ไม่มี rp_logger/leak

## [0.22] — 2026-07-04 — Logger autoload ตั้งชื่อ `GameLog` (เลี่ยงชนกับ engine class `Logger`)
- Phase X: เพิ่ม autoload `GameLog` (ไฟล์ `managers/Logger.gd`) และ `ConfigManager` (`managers/ConfigManager.gd`)
- **บั๊กที่จับได้ตอน integration:** ตั้งชื่อ autoload ว่า `Logger` **ชนกับ Godot built-in class `Logger`** ที่ GUT `error_tracker.gd` ใช้ (`extends Logger` + `OS.add_logger`) → GUT error-tracking พังเงียบ (`rp_logger is null`) + ObjectDB leak. เปลี่ยนชื่อ singleton เป็น `GameLog` แก้หมด (GUT 37/37 clean, ไม่มี leak). ไฟล์คง `Logger.gd`; โค้ดเรียกผ่านชื่อ singleton `GameLog.info()/warn()/error()` — **ห้ามตั้ง autoload ชื่อ `Logger` อีก**
- ConfigManager: method `load()` เดิมชนกับ builtin `load(path)` → เปลี่ยนเป็น `load_config()` (API: `get_value/set_value/save/load_config` + static `resolve_value/apply_defaults` + `DEFAULTS`)
- ตัดสินโดย: producer (integration fix); code identifiers ตรวจโดย code-reviewer/qa

## [0.21] — 2026-07-04 — เพิ่ม guard ตรวจ _backlog.json ใน CI
- เพิ่ม `tools/validate_backlog.py` — ตรวจ JSON valid + id ไม่ซ้ำ + depends_on ชี้ id ที่มีจริง + ฟิลด์ id/status ครบ + status อยู่ในชุดที่อนุญาต
- เพิ่ม step ใน `ci.yml` (รันก่อนโหลด Godot, fail เร็ว) → ถ้า backlog เสีย/ถูกตัด build แดงทันที รู้ตัวก่อน agent หยิบงานผิด
- ไม่กระทบเกม/บิลด์ (เป็น dev tool ล้วน) · รันเองในเครื่องได้: `python3 tools/validate_backlog.py`
- ทดสอบแล้ว: ไฟล์ปกติ→ผ่าน, ไฟล์ถูกตัด→exit 1 (แดง)

## [0.20] — 2026-07-04 — ติดตั้ง GUT + ต่อ CI ให้รันเทสจริง (TK-PX-07 → review)
- vendored **GUT 9.7.0** ที่ `addons/gut/` (commit เข้า repo; .gitignore อนุญาตอยู่แล้ว)
- แก้ `.github/workflows/ci.yml`: เอา branch "skip if GUT missing" ออก → GUT รันทุก push/PR และ **fail build ถ้าเทสตก** (-gexit)
- เทสที่จะรันจริง: `tests/test_network_manager.gd` (เดิม) + `tests/test_tiger_assignment.gd` (ใหม่, 10 เคส) บน `managers/TigerSelector.gd`
- verify: รัน Godot ในแซนด์บ็อกซ์ไม่ได้ (network allowlist บล็อก CDN binary ของ Godot) → พิสูจน์ logic ด้วย Python port (9/9 ผ่าน) + static review (tab ล้วน) · green จริงมาจาก CI ตอน push
- TK-PX-07 → status **review** (handoff ครบ)
- ⚠️ **เหตุการณ์:** พบ `_backlog.json` โดนตัดหาย (truncate) ครั้งที่ 2 ระหว่าง agent เขียนไฟล์พร้อมกัน — กู้คืนครบ 44 การ์ด (คงสถานะ review ของ TK-P0-06 ไว้) · แนะนำเพิ่ม guard ตรวจ JSON valid (ดูข้อเสนอ)

## [0.19] — 2026-07-04 — เพิ่ม unit test spec สำหรับสุ่มเสือตัวแรก (TK-P2-09)
- เพิ่ม `managers/TigerSelector.gd` — pure helper (static, node-independent, inject RNG) แยก logic การสุ่ม/แจกบทบาทออกจาก multiplayer เพื่อให้ unit-test ได้
- เพิ่ม `tests/test_tiger_assignment.gd` (GUT) 10 เคส: mock 4 peers → เสือ 1 ตัวเสมอ, เสืออยู่ในลิสต์จริง, fairness (ทุกคนถูกสุ่มได้), single/empty/stale-id edge, anti-repeat, determinism (seed เดียวกันได้ผลเดียวกัน)
- indentation เป็น tab ล้วน (ตรวจแล้ว) · รันได้เมื่อ GUT ลง (TK-PX-07) · integration เข้า GameManager/RPC ยังทำตามการ์ด TK-P2-09 ผ่าน review

## [0.18] — 2026-07-04 — เพิ่มการ์ดสุ่มเสือตัวแรก (TK-P2-09)
- เพิ่ม `_backlog.json`: **TK-P2-09** สุ่มเสือตัวแรกตอนเริ่มรอบ (host-authoritative + broadcast)
- กติกาสถาปัตย์: HOST สุ่มคนเดียว (randomize() ครั้งเดียว) แล้ว broadcast ผ่าน @rpc(authority, call_local, reliable) — client ห้ามสุ่มเอง กัน desync (S1)
- ผูก: depends_on [TK-P2-04 Role state machine] · เรียกโดย RoundManager (TK-P2-07) ตอนสถานะ Random Tiger · pair กับ network-engineer
- edge cases: รวม host ในการสุ่ม, สุ่มใหม่ถ้าคนถูกเลือกหลุด, ทุกรอบใหม่สุ่มใหม่ · optional anti-repeat = Phase 3
- Backlog รวม 44 การ์ด (Phase 2 = 9 ใบ)

## [0.17] — 2026-07-04 — เพิ่มการ์ด backlog Phase 4 (Art/Character) 4 ใบ
- เพิ่มใน `_backlog.json`: **TK-P4-05** (โมเดล+rig เสือ), **TK-P4-06** (โมเดล+rig ผู้เล่น base เปล่า + material slot), **TK-P4-07** (Toon Shader + Rim Light pipeline), **TK-P4-08** (ระบบแต่งตัว Lobby + network sync)
- ผูก dependency: P4-07 ← [P4-05, P4-06] · P4-08 ← [P4-06] · owner: polish-agent (05/06/07), gameplay-engineer (08, handoff network sync ให้ network-engineer)
- ทุกใบมี `notes` ชี้ ref → Character_Art_Bible.md + refs/*.png และระบุ DoD ย่อ
- Backlog รวมเป็น 43 การ์ด (Phase 4 = 8 ใบ) · หมายเหตุ: 05_Backlog.md/.csv/.xlsx (human view) ยังไม่ regen — รอทำรอบเดียวพร้อมกันได้

## [0.16] — 2026-07-04 — ล็อกสเปกผู้เล่น (ไม่ใช่เสือ) จาก character sheet + แก้ขนาดเสือ/ผู้เล่น
- รับ **character sheet ผู้เล่น** จากคุณเป็นมาตรฐาน → อัปเดต Art Bible §4, §4B, §7
- **ขนาด (แก้ conflict):** เสือ **~2.0m** (ใหญ่กว่า) · ผู้เล่น **1.2–1.4m** — แก้ §3 เดิมที่เขียนว่าเสือเตี้ยกว่าผู้เล่น (ขัดกับ sheet) ให้ถูกต้อง
- **สเปกผู้เล่น:** low-poly toon ทรงเรียบ สีขาวเปล่า = ผ้าใบ · ~1K–2K tris · Toon Shader + Rim Light · turnaround 4 มุม
- **Customization (Cosmetic Only, ที่ Lobby):** สีพื้น 8 สี · decal (หน้ายิ้ม/ดาว/มงกุฎ/"สู้ๆ"/"KICK ME!" ฯลฯ) · accessory 4 หมวด (หมวก/กระเป๋า/ผ้าพันคอ/แว่น)
- **Animation:** เพิ่ม Jump เข้า set · ยืนยันตัวหลักผู้เล่น: วิ่ง/กระโดด/เตะ/โดนเตะ-ล้ม · ใช้ rig ร่วมกับเสือได้
- ที่วางไฟล์: `01_Design/refs/player_style_ref.png`

## [0.15] — 2026-07-04 — ล็อกสเปกผลิตตัวเสือจาก character sheet
- รับ **character sheet เสือ (turnaround 6 มุม)** จากคุณเป็นมาตรฐานหน้าตา → อัปเดต Art Bible §3, §9
- **สเปกที่ล็อก:** ทรงง่าย/อ่านชัด · โทนสีสด · **Toon Shader + Rim Light** · โพลีต่ำ **~1K–2K tris**
- **มาร์กกิ้ง:** เสือส้ม+ลายดำ+พุงครีม + **รอยเท้าแมวกลางพุง** (signature) · Turnaround: Front/3-4/Side/Back
- **ยืนยันแล้ว:** เสือขาวใน sheet = **palette variant เฉย ๆ** (ไม่ใช่สกิน/บทบาท) — เสือมาตรฐาน = ส้ม+ลายดำ+พุงครีม
- ที่วางไฟล์: `01_Design/refs/tiger_style_ref.png` (Art Bible ชี้ path นี้แล้ว)

## [0.14] — 2026-07-04 — ล็อกสไตล์ Art = Toon/Low-poly (อ้างอิง MECCHA CHAMELEON) + เพิ่มระบบแต่งตัวที่ Lobby
- **Art Direction ล็อก:** Stylized/Toon + Low-poly (cel-shaded, รันบน integrated GPU ได้) อ้างอิงหลัก = MECCHA CHAMELEON — บันทึกใน `01_Design/Character_Art_Bible.md` §1
- **ตัวเสือ:** low-poly toon เสือ ทรงป้อมน่ารักแต่ดุนิด ๆ, **สีตัวตายตัว (ผู้เล่นแก้ไม่ได้)** เพื่อ readability
- **ผู้เล่น (ไม่ใช่เสือ):** โมเดลฐานเรียบ/เป็นผ้าใบ **ทาสี/แต่งตัวเองได้** — feature ใหม่ §4B
- **ขอบเขต feature "แต่งตัว":** เป็น **COSMETIC ล้วน ทำที่หน้า Lobby ก่อนแมตช์เท่านั้น** ไม่ใช่กลไกพรางตัว (ต่างจาก MECCHA) และ **ไม่กระทบ Core Loop เดิม** (แอบ→เตะ→หนี) — ตัดสินโดยคุณ (มนุษย์) 2026-07-04
- **ผลต่อ Tiger Indicator (§5):** ห้ามพึ่ง "สีตัว" อย่างเดียวชี้เสืออีกต่อไป เพราะผู้เล่นเลือกสีเองได้ → ต้องซ้อนหลายชั้น (โมเดลเสือแยก + เอฟเฟกต์/ไอคอน)
- **Phase placement:** ระบบแต่งตัววางไว้ **Phase 4 (Polish) ขั้นต่ำ / เต็มรูปแบบก่อน Ship** — ยังไม่แตะ Phase 0–2 (พิสูจน์ความสนุกก่อน) — ทีมยืนยัน scope + เพิ่มการ์ด backlog ก่อนลงมือ
- ผู้เสนอ/อนุมัติ: คุณ (มนุษย์) · ต้องให้ `designer` เซ็นก่อน `polish-agent` ลงมือ (ตามกติกา Art Bible §10)

## [0.13] — 2026-07-04 — แก้ path NetworkManager ให้ตรง TDD §3 (managers/ → networking/)
- ย้าย `NetworkManager.gd` จาก `res://managers/` ไป `res://networking/` เพื่อให้ตรงกับ TDD §3 (Folder Structure) ที่กำหนด `networking/` เป็นที่อยู่ของ NetworkManager/RPC/sync ส่วน `managers/` สงวนให้ GameManager/RoundManager/ConfigManager/Logger
- เหตุ: การ์ด TK-P0-04 ระบุ path `managers/` ซึ่งขัดกับ TDD; TDD คือ source of truth ด้านสถาปัตย์ (ตาม DOCUMENT_ROUTING) จึงทำโค้ดให้ตรง TDD — ถือเป็นการ *conform* ไม่ใช่ *เปลี่ยน* สถาปัตย์
- อัปเดต: `project.godot` [autoload] → `res://networking/NetworkManager.gd`, preload path ใน `tests/test_network_manager.gd`
- อนุมัติโดย: producer (ไม่ต้องขอ architect เพราะเป็นการทำตาม TDD เดิม ไม่ได้แก้ TDD)

## [0.12] — 2026-07-04 — อัปเกรด Engine Godot 4.6 → 4.7
- เปลี่ยนเวอร์ชัน Engine จาก Godot 4.6 เป็น Godot 4.7 (เป็น stable build ใหม่กว่า ไม่มี breaking change ต่อ High-Level Multiplayer/ENet ที่ใช้ใน Phase 0 และตรงกับ build ที่ติดตั้งจริงบนเครื่อง — `Godot_v4.7-stable_win64_console.exe`, verified `4.7.stable.official`)
- อนุมัติโดย: producer
- อัปเดตทุกจุดที่อ้างอิงเวอร์ชัน Engine: CLAUDE.md, WORKSPACE_SETUP.md, _backlog.json (TK-P0-01), 05_Backlog.md/.csv, _AGENT_CONTRACT_TEMPLATE.md, .claude/agents/{gameplay-engineer, network-engineer, tools-devops}.md
- หมายเหตุ: รายการ [0.2] ด้านล่างเป็นบันทึกประวัติศาสตร์ (Unity → Godot 4.6 ตอนนั้น) คงไว้ตามเดิมเพื่อความถูกต้องของประวัติ ไม่แก้ไขย้อนหลัง

## [0.11] — เพิ่ม Character & Art Bible
- เพิ่ม 01_Design/Character_Art_Bible.md (สไตล์/สี/Tiger indicator/animation set) — designer เป็นเจ้าของ, polish-agent ต้องทำตาม
- เดินสาย: DOCUMENT_ROUTING (design.character_art_bible) + Required Reading ของ designer และ polish-agent
- ซ่อม _backlog.json ที่เสีย (กู้ 26 การ์ดเดิม + สร้างส่วนที่ขาด ครบ 39 การ์ด valid)

## [0.10] — README: ลำดับภายในโฟลเดอร์
- เพิ่มหัวข้อ "Reading Order within Each Folder" (Sequential vs Reference/Living)
- อธิบายว่าไฟล์ชุดไหนอ่านเรียง ชุดไหนเปิดเฉพาะตอนใช้ และเหตุผล

## [0.9] — จัดโครงรวม + ยกระดับ README เป็น Onboarding Guide
- รวมเอกสารทั้งหมดเป็นโครงเดียว Tiger_Kick_Project_Docs (01_Design / 02_Technical / 03_QA / 04_Management)
- README เพิ่ม: Current Status, How to Read the Diagrams, If you are…, Project Mental Model
- เพิ่มไดอะแกรม Mental Model และ Dev/QA Workflow (diagrams/)

## [0.8] — เพิ่ม Backlog รายเฟส
- เพิ่ม Management/05_Backlog (md/pdf) + 05_Backlog.csv + 05_Backlog.xlsx
- ดึงงานย่อยทุกเฟสเป็น backlog 39 การ์ด พร้อม ID (TK-P#-##), priority, label, milestone
- ไฟล์ csv/xlsx import เข้า GitHub Projects / Trello / Notion ได้ทันที

## [0.7] — Team Workflow (ทีม 2 คน)
- เพิ่ม Management/04_Team_Workflow: Kanban Board, Issue Tracker, Milestones
- แนะนำใช้ GitHub Projects + Issues + Milestones (ครบในที่เดียว)
- นิยาม label (type/severity/priority/phase) และผูกกับ QA/RTM/Milestone Plan

## [0.6] — เพิ่ม Technical Design Document (TDD)
- สร้าง TDD พร้อมไดอะแกรมจริง: Architecture, Scene Tree, Class Diagram, Round Flow, State (Player/Tag), Network Flow
- เพิ่ม Round Flow (Lobby → Random Tiger → Countdown → Playing → Tag Sequence → Round End → Score → Next Round)
- กำหนด Safe Circle Specification (รัศมี, ผู้เล่นเข้าวง, เสือออกนอกวง)
- เพิ่มตาราง Game Balance (ค่าเริ่มต้นเสนอ, ปรับใน Phase 3) และตาราง RPC/Signals

## [0.5] — เปลี่ยน Tag เป็น Tag Sequence
- Phase 2 GDD: เปลี่ยน "Tag จับทันที" เป็น Tag Sequence 7 ขั้น (จับ → ทุ่ม → กลายร่าง → สลับบทบาท → เสือเดิมออกนอกวง → Playing)
- กำหนดงบเวลา Tag Sequence ≤ 1.2–1.5 วินาที (Grab 0.2–0.3s, Throw 0.3–0.5s, Transform 0.5–0.7s)
- เพิ่ม signal: tag_sequence_started / tag_sequence_finished
- Phase 4 GDD: เพิ่ม Grab/Throw Animation, Transform VFX, Camera Shake, เสียงคำรามเสือ
- อัปเดต GDD หลัก (หัวข้อ Core Loop / Role Switching) ให้ตรงกัน

## [0.4] — เพิ่มชุดเอกสาร PM และ QA เสริม
- เพิ่ม Management/: Milestone Plan, Risk Register, Change Log
- เพิ่มใน _shared/: RTM, Test Data, Automation Matrix, Risk Matrix, Metrics Dashboard, Release Readiness

## [0.3] — QA Package
- สร้าง QA Package แบบ Hybrid (เอกสารกลาง + รายเฟส 7 เฟส)
- กำหนด QA Architecture: Regression อยู่ก่อน DoD ก่อน Exit Gate
- เพิ่ม Severity S0–S4 และ Bug Lifecycle

## [0.2] — เปลี่ยน Engine และเพิ่ม Phase X
- เปลี่ยนจาก Unity เป็น Godot 4.6 (High-Level Multiplayer)
- เพิ่ม Phase X — Development Infrastructure
- เสริมทุกเฟสด้วยข้อเสนอระดับ Senior/TD

## [0.1] — เอกสารเริ่มต้น
- สร้าง GDD (Game Design Document)
- แบ่งแผนพัฒนาเป็น Phase 0–5

## วิธีใช้
- ทุกการเปลี่ยนแปลง scope, ค่าปรับจูน, หรือโครงสร้างเอกสาร ให้เพิ่มรายการที่นี่
- ก่อน Release ให้สรุปเป็นหัวข้อเวอร์ชันที่จะปล่อย
