# Page reference

The exact shape of a Proteos **page** — a screen. Its `layout` is a typed tree
of elements bound to an entity's attributes. This is the deepest reference;
keep it open while designing a record-detail screen.


> **Casing** (full rules in entity-reference §0 (domain-modeling skill)):
> slugs kebab-case · attribute references snake_case · enum values kebab-case ·
> icons lucide PascalCase · everything else snake_case.
>
> **Validate:** `pages/<slug>.json` → `#/$defs/createPageRequest` in
> [`platform.schema.json`](platform.schema.json).

---

## 1. Page kinds

- **Record page** (`type: "record"`, has `entity_slug`) — the detail view for a
  single record. Fields bind to that record's attributes. ~90% of pages.
- **Platform page** (`type: "platform"`, **no** `entity_slug`) — a standalone
  screen with no record context: a dashboard, a Kanban board, a report. Built
  from `text`, `divider`, and especially `component` elements that fetch their
  own data. Reached from a menu with `{ "type": "page", "reference": "<slug>" }`.
- **Kiosk page** (`type: "kiosk"`, no `entity_slug`) — a platform page served
  with **no app chrome** (no sidebar/topbar) at `/k/<orgId>/<pageSlug>`, but
  still **authenticated** (login redirect). For wallboards, TVs, embeds.
  Components run with the full authed sdk, exactly like on a platform page.
- **Public page** (`type: "public"`, no `entity_slug`) — no chrome AND
  **no authentication**: anyone on the internet with the URL
  `/p/<orgId>/<pageSlug>` can open it. See the warning below.

> ⚠️ **`type: "public"` publishes the page to the internet — never set it
> unless the user explicitly asked for a public page.** "Make me a dashboard"
> means `platform`. Making a page public means:
> - The **entire layout is world-readable**: every `text` element and every
>   literal component `props` value ships to anonymous visitors. Never bake
>   secrets, internal notes, or personal data into a public page's layout.
> - Every referenced component must set `is_public: true` in its
>   `manifest.json` (its compiled bundle becomes world-downloadable; deploy
>   rejects a public page referencing a non-public component).
> - Components on a public page get a **restricted sdk** with exactly three
>   platform reaches, all unauthenticated:
>   - `sdk.functions.actions.invokePublic(orgId, slug, params)` calling an
>     `is_public` **global action** (runs server-side as the action's
>     creator) — the only path for writes or computed/aggregated data;
>   - **read-only records** of entities with `public_record_access: ["read"]` via
>     `sdk.data.records.list/listPage/get` (org bound automatically; create/
>     update/delete throw) plus their definitions via `sdk.meta.entities.get`;
>   - downloads of `public_access: ["read"]` files via `sdk.storage.files.download` /
>     `publicDownloadUrl` (e.g. images embedded on the page).
>   Everything else (`account`, `agents`, `knowledge`, authed `data`/`meta`/
>   `storage`) throws.
> - `field` / `related_list` elements are forbidden (as on all non-record
>   pages) — there is no record context and no authed query path.
>
> Confirm the public-exposure intent with the user before authoring
> `type: "public"` or `is_public: true` anywhere; repeat what will become
> publicly reachable when you do.

```json
{
  "slug": "customer-detail",
  "entity_slug": "customer",
  "module_slug": "sales",
  "name": "Customer detail",
  "type": "record",
  "actions": [ { "label": "Log a call", "icon": "PhoneCall", "action": "log-call" } ],
  "layout": { "version": 1, "main": { /* LayoutElement */ }, "side_panel": { /* optional */ } }
}
```

| key | notes |
|---|---|
| `slug` | kebab-case, unique. |
| `name` | display name in the page picker (`"Customer detail"`, not `"Page for customers"`). |
| `type` | `record` (default), `platform`, `kiosk`, or `public` (⚠ world-readable — only on explicit user request). |
| `entity_slug` | **required for `record`, absent for all other types.** Immutable after create. |
| `module_slug` | owning module. |
| `actions[]` | toolbar buttons `{ label, icon (lucide PascalCase), action }`. `action` is a free string the route resolves — usually a module-action slug. |
| `layout` | the typed element tree (§2). **Full-tree replacement** on every update — no element-level patch. Preserve element `id`s when refactoring. |

Platform-page skeleton:
```json
{ "slug": "sales-dashboard", "type": "platform", "name": "Sales dashboard", "actions": [],
  "layout": { "version": 1, "main": { "type": "column", "id": "main", "gap": "md",
    "children": [ { "type": "component", "id": "cmp", "component_slug": "pipeline-chart", "props": {} } ] } } }
```

---

## 2. PageLayout

```json
{
  "version": 1,
  "main": { "type": "column", "id": "main", "gap": "md", "children": [ /* … */ ] },
  "side_panel": {
    "width": "320px",
    "is_sticky": true,
    "content": { "type": "column", "id": "side", "gap": "md", "children": [ /* … */ ] }
  },
  "style": { /* public/kiosk only — see §2.1 */ }
}
```

- `version` is always `1`.
- `main` is one `LayoutElement` — conventionally a `column` with `gap: "md"`.
- `side_panel` is optional; **omit it unless a tool/widget earns the rail** (§7).
- `style` is optional and **only honored on `public` + `kiosk` pages** (§2.1).

### 2.1 Page style — background & full-bleed (public / kiosk only)

A `public` or `kiosk` page's shell hard-codes three constants: a `bg`-token
background, a `1200px` centered content cap, and `24px`/`32px` side/top padding.
`layout.style` overrides any of them — set a background color, and/or widen the
content and drop the padding so a component runs **edge-to-edge**.

```json
"layout": {
  "version": 1,
  "main": { "type": "component", "id": "cmp-hero", "component_slug": "landing-hero", "props": {} },
  "style": {
    "background": "#0a0a0a",
    "max_width": "fill",
    "padding_x": "0px",
    "padding_y": "0px"
  }
}
```

| key | value | default | notes |
|---|---|---|---|
| `background` | design-token key **or** raw CSS color | `bg` token | token keys: `bg` `bg-2` `bg-3` `ink` `ink-2..4` `rule` `rule-2` `accent` `accent-2` `accent-ink` `success` `warning` `danger` `info` → resolve to `var(--color-<key>)`. Raw colors: `#hex`, `rgb()/rgba()`, `hsl()/hsla()`, `oklch()/oklab()`. No `;{}`/`url(` (server rejects). |
| `max_width` | `"Npx"` · `"N%"` · `"auto"` · `"fill"` | `1200px` | `"fill"`/`"auto"` remove the cap → content spans the full viewport width. |
| `padding_x` | `"Npx"` · `"N%"` · `"auto"` · `"fill"` | `24px` | horizontal padding of the content container. `"0px"` = flush to the sides. |
| `padding_y` | same grammar | `32px` | top/bottom padding. |

- **Full-bleed recipe:** `max_width: "fill"` + `padding_x: "0px"` + `padding_y: "0px"`.
  The component then fills the page; give it its own internal padding.
- **Fractions are rejected here** (unlike element `width`/`height` §6) — a page
  container takes `px`/`%`/`auto`/`fill` only.
- **Type gate:** the metadata-service **rejects** `style` on `record` and
  `platform` pages (`page_style_unsupported_for_type`). Omit it on those types.
- `background` paints the whole viewport (`min-h-dvh`); `max_width`/`padding`
  only reshape the content container inside it.

---

## 3. The element catalogue

Discriminated union on `type`: `row` · `column` · `section` · `tabs` · `field`
· `related_list` · `component` · `divider` · `text`.

**Every element carries CommonProps** (all optional): `id`, `visible_when`,
`read_only_when`, `width`, `height`, `grow`, `shrink`, `align`, `responsive`.
Always give containers, fields, and tabs a stable, semantic `id`
(`sec-overview`, `f-email`, `tab-orders`) — the renderer uses ids as React keys
and `default_tab_id` references tab ids.

### Containers

| element | key props | use for |
|---|---|---|
| `row` | `gap` (`xs`/`sm`/`md`/`lg`), `allows_wrap` (default true), `align`, `justify`, `children[]` | inline groups of fields (first + last name), label-value pairs. Don't nest > 2 deep. |
| `column` | `gap`, `align`, `justify`, `children[]` | the page body; stacked fields inside a section. |
| `section` | `title`, `description`, `is_collapsible`, `default_collapsed`, `content` (one child) | a titled block. No title *and* no description → renders bare (a grouping wrapper). Collapse **secondary** info only, never the primary section. |
| `tabs` | `tabs[]` (`{id,label,icon?,visible_when?,content}`), `default_tab_id` | 3+ equal-weight facets (Overview / Orders / Activity / Files). Keep tab ids stable; ids must be unique within the element. |

`align`/`justify` values — `align` ∈ `start` `center` `end` `stretch`;
`justify` ∈ `start` `center` `end` `between` `around`.

### Leaves

| element | key props | notes |
|---|---|---|
| `field` | `attribute`, `label`, `control`, … (§4) | bound input/display. The center of gravity. |
| `related_list` | `related_entity_slug`, `via_attribute`, `list_slug?` | a live table of related records — every record whose `via_attribute` FK points back at this one. `list_slug` pins the column model (else the related entity's first list). Rows click through. |
| `component` | `component_slug`, `props?` | mounts a registered custom React component (map, chart, board). Author it with **component-engineer**. |
| `divider` | — | a horizontal rule. Use sparingly; sections already separate. |
| `text` | `variant` (`heading`/`subheading`/`body`/`caption`/`callout`), `content` | static prose. `callout` for one-line context ("All amounts in USD"); `caption` for eyebrow labels. `content` must be non-empty. |

---

## 4. FieldElement — the deep dive

```json
{
  "type": "field",
  "id": "f-email",
  "attribute": "email",
  "label": "Work email",
  "description": "help text shown under the field",
  "placeholder": "name@company.com",
  "is_read_only": false,
  "is_required": false,
  "empty_display": "dash",
  "control": "email",
  "control_props": {}
}
```

- **`attribute`** — snake_case data key. **Dot-path into object attributes**
  (`shipping_address.country`); binding the object itself is rejected. Must
  resolve to a leaf. Unknown name → `Unknown attribute · X` placeholder (a bug —
  fix the casing).
- **`label`** — omit → inherit the attribute label (the default). A string →
  override for this page only. `null` → hide the label (only when surrounding
  chrome makes the field obvious; the control still gets an `aria-label`).
- **`empty_display`** — `undefined`/`"dash"` → em-dash `—`; `"hide"` → the row
  disappears in view mode when empty; any other string → that literal
  (`"Not set"`). Empty = null/undefined/""/[].
- **`is_required` / `is_read_only`** — three-state: omit (inherit from the
  attribute), `true`, `false`. Use `is_read_only` for static intent (`id`);
  use `read_only_when` (§5) for state-dependent locking.

### Controls — the registry

The renderer picks `field.control ?? default(attribute)`. Only set `control` to
override the default. Defaults resolve automatically:

| attribute (type → format/items) | default control |
|---|---|
| `string` | `text` |
| `string` + `email` | `email` |
| `string` + `uri` | `url` |
| `string` + `uuid`/`hostname`/`ipv4`/`ipv6` | `text` |
| `number` / `integer` | `number` |
| `boolean` | `switch` |
| `enum` | `select` |
| `array<string>` | `tag-input` |
| `array<enum>` | `multi-select` |
| `datetime` + `date` | `date-picker` |
| `datetime` + `date-time` | `datetime-picker` |
| `datetime` + `time` | `time-picker` |
| `relation` | `entity-picker` |
| `user` | `user-picker` |
| `currency` | `currency` |
| `file` | `file` |
| `knowledge-text` | `knowledge-text` |
| `object` / `datetime` + `duration` | (none — read-only fallback; bind to leaves) |

**Compatible alternatives** (set `control` explicitly to switch within a bucket):

| attribute | compatible controls |
|---|---|
| `string` | `text` · `textarea` · `password` |
| `string + email` | `email` · `text` |
| `string + uri` | `url` · `text` |
| `boolean` | `switch` · `checkbox` |
| `enum` | `select` · `radio-group` · `chip-group` |
| everything else | only the primary |

**`control_props`** are per-control:
```json
{ "rows": 5 }                          // textarea (default 4)
{ "step": 0.01, "min": 0, "max": 100 } // number
```
When you change `control`, **drop `control_props`** — keys are slug-specific.

**Control heuristics:** `textarea` for prose/addresses/notes (`rows` 5–6 for
paragraphs, 3 for short notes); `password` for secret-like strings; `switch` for
on/off, `checkbox` for consent/inclusion; `select` for enums by default,
`radio-group` when ≤4 options all worth showing, `chip-group` for short
equal-weight states (New / Packing / Shipped); `tag-input` for free-text arrays,
`multi-select` for a fixed enum list.

---

## 5. Conditions — `visible_when` / `read_only_when`

Both are **FilterGroup** predicates (the same shape lists use — full spec in
list-reference §3 (module-builder skill)):

```json
{
  "logical_operator": "and",
  "elements": [ { "field": "status", "operator": "eq", "value": "cancelled" } ],
  "groups": []
}
```

- **`value` is always a string** — booleans `"true"`/`"false"`, enums the
  kebab-case value, `in`/`not_in` pipe-joined.
- **`visible_when`** is honored by every element in view mode. An empty
  FilterGroup is vacuously true (shows always).
- **`read_only_when`** is acted on only by `field` (OR-combined with
  `is_read_only`; any truthy condition wins). To lock a whole section, mirror
  the predicate onto each child field.

**Use them for:** revealing a "Reason for cancellation" field only when
`status = cancelled` (`visible_when` on the field); locking commercial fields
once `status = in-transit` (`read_only_when` on each). **Don't** put real
invariants here — those enforce nothing on submit; validation belongs in a
`before_*` hook (**hook-engineer**).

---

## 6. Sizing — width / height / grow / shrink / responsive

`SizeValue` is polymorphic: `0.5` (fraction ∈ [0,1]), `"1/2"`/`"2/3"`, `"240px"`,
`"50%"`, `"auto"` (size to content), `"fill"` (grow to remaining).

- In a **row** parent, `width` drives flex sizing (a `1/3` child takes a third).
- In a **column** parent, `width` is the cross-axis (`100%` default; `"auto"`
  shrinks to content).
- `grow`/`shrink` pass through to flex.

**Recipes:** two-column field row → `row gap:"md"` with two fields each
`width:"1/2"`; fixed sidebar in a row → first child `"260px"`, second `"fill"`.
**Most fields need no sizing** — let flex handle it; over-specifying is the
common mistake.

**Responsive** overrides carry only `SizingProps`
(`width`/`height`/`grow`/`shrink`/`align`) at breakpoints `sm` (≥640), `md`
(≥768), `lg` (≥1024):
```json
{ "type": "row", "id": "r-name", "gap": "md",
  "responsive": { "sm": { "width": "100%" } },
  "children": [ /* … */ ] }
```
Design for `lg`, then add `sm` overrides that collapse multi-column rows to full
width. Only reach for responsive when the layout *shape* must change.

---

## 7. CRM / ERP layout best practices

How good CRM (Salesforce, HubSpot, Attio) and ERP (NetSuite, SAP) record screens
are shaped — the heuristics that keep dense business data scannable.

### 7.1 The standard record-detail skeleton

```
column (main, gap: md)
├─ section "Overview"                 ← identity + the 4–6 fields you came for; NEVER collapsible
│   └─ column (gap: sm)
│       ├─ row: name · status(enum)
│       ├─ row: email · phone
│       └─ row: owner(user) · annual_revenue(currency)
├─ tabs                               ← equal-weight facets
│   ├─ "Orders"     → related_list (related_entity_slug:"order", via_attribute:"customer_id")
│   ├─ "Details"    → the long tail of attributes, grouped in sections
│   └─ "Activity"   → component (timeline) or text
└─ section "Addresses"                ← secondary; is_collapsible + default_collapsed
    └─ column (gap: sm) with the object leaves
```

**Principles:**

- **Overview first, above the fold, never collapsible.** The 4–6 attributes a
  user opened the record to see: title, status/stage, owner, the one or two
  numbers that matter. Two fields per row (`width: "1/2"`) reads well.
- **Group by cohesion, not by type.** "Billing", "Shipping", "Commercial terms"
  — put fields where a domain expert expects them, not all strings together.
- **Tabs for facets, collapsible sections for secondary detail.** Reach for
  `tabs` when a record has 3+ equal-weight areas; reach for a collapsed
  `section` for one block of rarely-needed fields. Don't use tabs to hide a
  single small group — heavier than it earns.
- **Related records go in a `related_list`, never re-typed as fields.** A
  customer's orders, an order's line items, a project's tasks: `related_list`
  with the child's back-reference `via_attribute`. Give it its own tab or
  section.
- **Lifecycle/status is a first-class enum, shown high and often gated.** Use
  `read_only_when` to lock commercial fields once a record is `shipped` /
  `signed` / `closed-won`; use `visible_when` to reveal fields per state.
- **System/audit fields belong low or nowhere.** `id`, `created_at`,
  `updated_at`, `created_by` go in a collapsed "Record details" section or are
  omitted. Never in the Overview, never in the side panel.

### 7.2 The side panel — earn it or omit it

A sticky right rail (default 340px) for **glanceable context and tools**, not a
second form. Fill it with a `component` (health score, map, mini-chart), a
summarizing `related_list`, a status pill, or a primary CTA — **not** plain
entity fields, and never system/audit fields. If nothing earns the space, omit
`side_panel` entirely (the right default for most pages).

### 7.3 ERP-flavored patterns

- **Header + lines** (order + line-items, invoice + entries): the header is the
  page's Overview; the lines are a `related_list` in a prominent tab. The line
  entity is a real entity with its own FK back to the header.
- **Documents** (`file` attributes): a "Documents" tab/section with `file`
  fields; a `related_list` if documents are their own entity.
- **Money**: `currency` type (amounts are decimal **strings** on records), or
  `integer` minor units (`total_cents`) when you need exactness — document the
  unit in the description.
- **Status pipelines**: an `enum` with a `chip-group` control reads as a
  pipeline; gate downstream fields with `read_only_when` per stage.

---

## 8. Preview / sample data shapes

The preview surfaces (`pro module serve` → the module-preview app, and the
agent workspace's `present_page`) render pages offline: omitted attributes are
auto-sampled deterministically, and any sample record you supply overrides
them. The entity is always resolved by `entity_slug` from the module/store —
never embedded in the page. Offline renderer value shapes:

- **keys = snake_case attribute names.**
- **relation / user** values carry an inline label (no fetch):
  `{ "id": "usr_dana", "label": "Dana Reyes" }` (`label`/`name`/`title`/
  `display_name` or a bare string all work).
- **currency**: `{ "amount": "2840000.00", "currency_code": "USD" }` — amount a string.
- **datetime**: ISO-8601 string (`"2026-05-04T14:32:00Z"`).
- **enum**: the kebab-case value (`"active"`).
- **file**: `{ "id": "file_123", "name": "contract.pdf" }`.

```json
{
  "id": "rec_8842",
  "name": "North Star Logistics",
  "email": "ops@northstar.io",
  "status": "active",
  "annual_revenue": { "amount": "2840000.00", "currency_code": "USD" },
  "owner": { "id": "usr_dana", "label": "Dana Reyes" },
  "created_at": "2026-05-04T14:32:00Z"
}
```

---

## 9. Page checklist

- [ ] Validates against `#/$defs/createPageRequest`.
- [ ] Record page has `entity_slug`; platform/kiosk/public pages set their `type` and omit it.
- [ ] `type:"public"` ONLY on the user's explicit request (world-readable layout!); every component it references sets `is_public: true` and fetches data solely via `is_public` global actions, read-only records of `public_record_access: ["read"]` entities, or `public_access: ["read"]` file downloads — each of those flags also requires the user's express permission.
- [ ] Every `field.attribute` matches a real snake_case attribute; object binds are dot-paths to leaves.
- [ ] Every element has a stable `id`; tab ids are unique and match `default_tab_id`.
- [ ] Overview is first and not collapsible; system/audit fields are low or omitted.
- [ ] Related records use a `related_list` with the correct back-reference `via_attribute`.
- [ ] `control` only set when overriding the default; `control_props` dropped when the control changes.
- [ ] Condition `value`s are strings; `read_only_when` is on fields (mirror onto children for a section).
- [ ] `side_panel` omitted unless a tool/widget earns it.
- [ ] `layout.style` only on `public`/`kiosk` pages; `background` is a token key or safe CSS color; `max_width`/`padding_x`/`padding_y` are `px`/`%`/`auto`/`fill` (no fractions). Full-bleed = `max_width:"fill"` + zero padding.
