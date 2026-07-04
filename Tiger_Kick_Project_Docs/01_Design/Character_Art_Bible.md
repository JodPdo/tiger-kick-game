# Character & Art Bible — Tiger Kick

เอกสารกำหนด "หน้าตา / โทน" ของตัวละครและเกม — เป็นกติกาที่ `polish-agent` ต้องทำตาม และ `designer` เป็นเจ้าของ
(เหมือนที่ TDD คุม programmer — ไฟล์นี้คุม visual)

> ช่องที่เป็น `____` = การตัดสินใจเชิงศิลป์ของ **คุณ (มนุษย์)** เติมให้ครบก่อนเข้า Phase 4
> ตราบใดที่ยังว่าง = ยังไม่ล็อก agent ห้ามเดาเอง ต้องถามก่อน

## 1. Art Direction (โทนรวม)
- สไตล์: ☐ Realistic  ☐ Stylized / Toon  ☐ Low-poly  ☐ Pixel/อื่น: `____`
- อารมณ์ที่ต้องการ (เลือก/เขียน): ฮา · น่ารัก · ดุ · การ์ตูน · `____`
- อ้างอิง (mood board / เกมที่ชอบสไตล์): `____`

## 2. Color Palette
- สีหลัก: `____`   สีรอง: `____`   สีเน้น (accent): `____`
- **สีของ "เสือ" ต้องเด่นและอ่านง่ายในทุกฉาก** (กันสับสนว่าใครเป็นเสือ)

## 3. Tiger (ตัวเสือ)
- Silhouette / รูปทรง: `____`
- บุคลิก: `____`
- เป้าหมายด้านความรู้สึก: ดู "เป็นเป้าให้เตะ" แต่ก็ "น่ากลัวนิด ๆ" ตอนไล่จับ

## 4. Player (ผู้เล่นทั่วไป)
- รูปทรง / ชุด: `____`
- ต้องแยกออกจากเสือได้ชัดในระยะไกลและในที่แสงน้อย

## 5. Tiger Indicator (สำคัญที่สุด)
"ใครเป็นเสือคนใหม่" ต้องรู้ได้ทันทีทุกเครื่อง (โยงกับ Tag Sequence + Round Flow)
- วิธีบ่งชี้: ☐ สีตัว  ☐ ขนาด  ☐ เอฟเฟกต์รอบตัว  ☐ ไอคอนเหนือหัว  ☐ อื่น: `____`
- ต้องชัดทั้งมุม First Person (เสือมองตัวเอง/มือ) และ Third Person (คนอื่นมอง)

## 6. Silhouette & Readability
- ดูเงา (silhouette) แล้วต้องแยก "เสือ vs คน" ออกทันที
- อ่านออกได้ในระยะไกลสุดของสนาม (ผูกกับ Safe Circle radius ใน TDD)

## 7. Animation Set ที่ต้องมี (ผูกกับ TDD §8 + Phase 4)
Idle · Walk · Run/Sprint · Kick · **Tag Sequence: Grab → Throw → Transform (เสือ↔คน)** · Caught/โดนเตะ
- งบเวลา Tag Sequence ตาม GDD: รวม ≤ 1.5 วินาที (Grab 0.2–0.3 / Throw 0.3–0.5 / Transform 0.5–0.7)

## 8. VFX / Feedback (Phase 4)
- Transform VFX ตอนกลายร่าง · Camera shake ตอนทุ่ม · เสียงคำรามของเสือ · feedback ตอนเตะโดน

## 9. Asset Sourcing (คุณเป็นคนจัดหา — agent สร้างงานศิลป์ต้นฉบับไม่ได้)
- แหล่ง: ☐ Mixamo  ☐ Asset store  ☐ จ้างศิลปิน  ☐ AI-generated  ☐ อื่น: `____`
- ฟอร์แมต import: glTF / FBX → Godot (polish-agent เป็นคน import + ตั้ง AnimationTree)

## 10. Do / Don't (กติกาที่ agent ห้ามข้าม)
- **DO** — ทำตามสไตล์ / สี / Tiger Indicator ที่ระบุไว้ในไฟล์นี้เท่านั้น
- **DON'T** — `polish-agent` ห้ามเปลี่ยน design intent เอง ต้องให้ `designer` เซ็น + บันทึกใน `04_Management/03_Change_Log.md`
- ถ้าช่อง `____` ยังว่าง = ห้ามเดา ให้ escalate หา `designer` → คุณ

## สถานะเอกสาร
- เจ้าของ (R): `designer` · อนุมัติสุดท้าย (A): คุณ (มนุษย์) · ผู้ทำตาม: `polish-agent`
- ทุกการเปลี่ยนแปลง → บันทึกใน Change Log · ล็อกให้ครบก่อนเริ่ม Phase 4
