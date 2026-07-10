# Entity reference

The exact shape of a Proteos **entity** — the record type that everything else
(pages, lists, relations) binds to. This is the file to read first; the sibling
references build on the naming rules established here.


> **Validate** an `entities/<slug>.json` file against
> [`platform.schema.json`](platform.schema.json) →
> `#/$defs/createEntityRequest`.

---

## 0. Naming & casing — the rules that bite (read once, apply everywhere)

Four distinct things get cased, and conflating them is the single most common
cause of a design that validates locally but renders wrong or is rejected on
deploy. **These rules apply across every reference file**, not just entities.

| Thing | Casing | Examples | Why |
|---|---|---|---|
| **Slugs** — entity / page / list / list-view / app / menu `slug`, and `entity_slug`, `list_slug`, `app_slug`, `related_entity_slug`, menu `reference` | **kebab-case** | `customer`, `purchase-order`, `customer-detail`, `active-customers` | Slug is the immutable primary key; lowercase, hyphen-separated, singular for entities. |
| **Attribute names** — `attribute.name`, and every reference (`field.attribute`, `column.attribute`, `sorting[].attribute`, `filter.field`, `via_attribute`, `related_attribute`) | **snake_case** | `first_name`, `customer_id`, `is_signed`, `shipping_address.postal_code` | These become the record's data keys. Booleans carry an `is_`/`has_`/`can_` prefix. |
| **Enum values** — `meta.values[].value` (and the compared `value` in a filter/`visible_when` on an enum) | **kebab-case** | `payment-pending`, `in-transit`, `active`, `churned` | Stable machine token, stored verbatim. Canonical external codes (`DE`, `USD`, `INVOICE`) are the deliberate exception — keep them as the business writes them. |
| **Icons** — `icon`, `icon_slug` on menus/apps/actions | **lucide PascalCase** | `FileText`, `Users`, `TrendingUp`, `PenLine` | kebab-case silently renders a placeholder. |
| **All other structural JSON keys** | **snake_case** | `is_required`, `module_slug`, `title_template`, `visible_when`, `default_tab_id`, `logical_operator` | Map 1:1 onto Go request structs; a camelCase key is dropped or rejected. |

**Two hard rules:**

1. **A camelCase structural key is a bug.** `entitySlug`, `isRequired`,
   `relatedEntitySlug` are dropped or rejected. Everything is snake_case except
   the slug / enum-value / icon exceptions above.
2. **Attribute-name references must match the entity exactly.** A `field` whose
   `attribute` doesn't match a real attribute name renders as
   `Unknown attribute · <name>` — the #1 cause is snake-vs-kebab drift
   (`customer-id` will not resolve `customer_id`).

**Descriptions are non-negotiable.** Every entity, attribute, enum value, and
relation carries a substantive `description`. The schema is read by AI agents
that have no other source of business context — the *why* must live in the
data. "The customer's name" is worse than nothing; write what it captures, who
sets it, when it changes, what depends on it. The validator requires a non-empty
`description` on attributes and enum values for exactly this reason.

---

## 1. Entity structure

An entity is a table of business records — the root of everything. Pages, lists,
and relations bind to it by its slug.

```json
{
  "slug": "customer",
  "name": "Customer",
  "description": "A company that buys freight-forwarding services from us. Created when sales qualifies an inbound lead; lives through the full account lifecycle (prospect → active → churned). One customer places many orders.",
  "is_remote": false,
  "module_slug": "sales",
  "title_template": "{{ name }}",
  "attributes": [ /* Attribute[] — see §3 */ ]
}
```

| key | type | notes |
|---|---|---|
| `slug` | string | **required**, kebab-case, singular, org-wide unique, **immutable** — there is no rename. |
| `name` | string | Human label, freeform Title Case. |
| `description` | string | **required**, business context (2–4 sentences). |
| `is_remote` | boolean | `true` → records are sourced from an external system. Almost always `false`. |
| `module_slug` | string | The owning module's slug; equals the module you're authoring in. |
| `title_template` | string | Liquid template rendering a one-line human title for a record — `"{{ first_name }} {{ last_name }}"`, `"{{ number }}"`. Empty = fall back to the record id. **Set this** — it's what relation pickers, related-lists, and breadcrumbs display. |
| `attributes` | Attribute[] | **required**, non-empty. **Fully replaced** on every deploy — never send a partial list (an omitted attribute is deleted along with its data). |

---

## 2. The five platform attributes (server-managed — do NOT declare them)

Every entity **automatically** carries five canonical, platform-managed
attributes. The server injects them — first in the list — on create AND on
every update, and **drops any client-supplied attribute whose name collides**
(the canonical definition is authoritative; source:
`packages/go/model/meta/platform-attributes.go`, `EnsurePlatformAttributes`):

| name | type | notes |
|---|---|---|
| `id` | `string` | primary key; unique, read-only; the default relation target |
| `created_at` | `datetime` (`date-time`) | server-set on first persist |
| `updated_at` | `datetime` (`date-time`) | server-set on every write |
| `created_by` | `user` | auto-stamped UserRef `{type, id}`; system writes carry the `platform` sentinel |
| `updated_by` | `user` | auto-stamped on every write |

Consequences:

- Your `attributes` array contains **only the user-defined fields**. Never
  declare `id` / `created_at` / `updated_at` / `created_by` / `updated_by` —
  it's a silent no-op at best.
- Pages, lists, filters, and relations may freely **bind** to the platform
  names (`created_at` column, `created_by` field, relation
  `related_attribute: "id"`).
- No hook is needed to stamp `created_by`/`updated_by` — the platform does it.

---

## 3. Attribute

The atom of the model. The same shape is used for entity attributes, `object`
value-object children, and `array` items.

```json
{
  "name": "customer_id",
  "type": "relation",
  "label": "Customer",
  "description": "The customer this order was placed by. Set at order creation and never changed; re-assigning an order to a different customer means voiding and re-issuing.",
  "is_required": true,
  "is_nullable": false,
  "is_unique": false,
  "is_read_only": false,
  "default_value": null,
  "meta": { /* type-specific — see §4 */ }
}
```

| key | type | notes |
|---|---|---|
| `name` | string | **required**, snake_case, unique within the entity. |
| `type` | enum | **required** — one of the 13 types in §4. |
| `label` | string | **required**, UI label (Title Case). |
| `description` | string | **required**, business meaning. |
| `is_required` | boolean | **required** — must be supplied on create. |
| `is_unique` | boolean | **required** — unique constraint. |
| `is_nullable` | boolean | Can be set to `null` after create. Independent of `is_required` (`is_required:false, is_nullable:false` = "optional on create, but once set can't be cleared"). |
| `is_read_only` | boolean | Server-managed; hidden from create/patch flows. |
| `default_value` | any | Optional default applied on create. |
| `meta` | object | Type-specific config (§4). Omit for `boolean`. |

---

## 4. Attribute types & their `meta`

| type | stores | `meta` | when to use |
|---|---|---|---|
| `string` | text | `StringAttributeMeta` (optional) | names, free text, codes. Use `format` for validation. |
| `number` | float | `NumberAttributeMeta` (optional) | decimals, rates, quantities. |
| `integer` | int | `NumberAttributeMeta` (optional) | counts, minor-unit money (`total_cents`). |
| `boolean` | bool | — (none) | flags. Name it `is_*`/`has_*`/`can_*`. |
| `datetime` | timestamp | `DatetimeAttributeMeta` (**required**) | dates, timestamps, times, durations. |
| `enum` | text | `EnumAttributeMeta` (**required**) | a closed set of states. Prefer over a free-string status. |
| `array` | jsonb | `ArrayAttributeMeta` (**required**) | lists of scalars (tags) or of objects. |
| `object` | jsonb | `ObjectAttributeMeta` (**required**) | embedded value object (address, coordinates). |
| `relation` | FK ref | `RelationAttributeMeta` (**required**) | many-to-one link to another entity. |
| `user` | `{type,id}` | `UserAttributeMeta` (optional) | a person — owner, assignee, `created_by`. |
| `currency` | `{amount,currency_code}` | `CurrencyAttributeMeta` (optional) | monetary amounts with a currency. |
| `file` | `{id,name}` | `FileAttributeMeta` (optional) | an uploaded document/image. |
| `knowledge-text` | `{id,content?}` | `KnowledgeTextAttributeMeta` (optional) | long rich body backed by a knowledge node. |

### `meta` by type — verbatim shapes

**string** — all optional. `format` ∈ `email` `uri` `uuid` `hostname` `ipv4` `ipv6`.
```json
{ "min_length": 1, "max_length": 200, "pattern": "^[A-Z]", "format": "email" }
```

**number / integer** — all optional.
```json
{ "minimum": 0, "maximum": 100, "exclusive_minimum": 0, "exclusive_maximum": 100, "multiple_of": 0.01 }
```

**datetime** — `format` **required**. `format` ∈ `date-time` `date` `time` `duration`.
```json
{ "format": "date-time", "minimum": "2020-01-01T00:00:00Z", "maximum": "2030-12-31T23:59:59Z" }
```

**enum** — `value` is a kebab-case token; `label` + `description` required per value.
```json
{ "values": [
  { "value": "prospect", "label": "Prospect", "description": "Qualified by sales but has not yet paid a first invoice. Appears in the pipeline, excluded from revenue reporting." },
  { "value": "active",   "label": "Active",   "description": "Has at least one paid invoice and no churn signal. Counts toward MRR." },
  { "value": "churned",  "label": "Churned",  "description": "No active contract and flagged lost by the account owner. Read-only in most flows; retained for history." }
] }
```

**object** — embedded value object (no independent identity); recursive `attributes[]`.
```json
{ "attributes": [
  { "name": "address_line_1", "type": "string", "label": "Address line 1", "description": "Street and number.", "is_required": false, "is_unique": false, "is_nullable": false },
  { "name": "postal_code",    "type": "string", "label": "Postal code",    "description": "ZIP / postcode.",     "is_required": false, "is_unique": false, "is_nullable": false },
  { "name": "country",        "type": "string", "label": "Country",        "description": "ISO-3166 alpha-2 code.", "is_required": false, "is_unique": false, "is_nullable": false }
] }
```
On a page, bind fields to the **leaves** (`shipping_address.postal_code`), never the object itself.

**array** — `items` is a nested Attribute (recursive).
```json
{ "items": { "name": "tag", "type": "string", "label": "Tag", "description": "A free-form label for segmentation.", "is_required": false, "is_unique": false, "is_nullable": false },
  "min_items": 0, "max_items": 20, "items_must_be_unique": true }
```

**relation** — many-to-one; FK-style reference lives on the host entity.
```json
{ "related_entity_slug": "customer",
  "related_attribute": "id",
  "predicate": "is placed by",
  "description": "The customer who placed this order.",
  "on_delete": "restrict" }
```
- `related_attribute` must be `id` or an `is_unique: true` attribute on the target.
- `predicate` reads host → target so the sentence flows ("order *is placed by* customer").
- `on_delete` ∈ `cascade` `restrict` `set-null`. **`set-null` is incompatible with `is_required: true`.**
- FK naming convention: `<related_slug>_id` → `customer_id`.
- **Cardinality is always many-to-one.** For many-to-many, model a join entity (§6).
- ⚠️ **`on_delete` is advisory metadata — there is NO database foreign key and NO cascade.** Deleting the referenced record does nothing to the referrer at the DB level. If a delete must propagate, a `before_delete` hook does it. Treat `on_delete` as documented intent.

**currency** — record value is `{ "amount": "2840000.00", "currency_code": "USD" }`; **`amount` is a decimal STRING** (a number is rejected).
```json
{ "default_currency_code": "USD", "allowed_currency_codes": ["USD", "EUR", "GBP"] }
```
Both fields optional; empty `allowed_currency_codes` = any ISO-4217 code.

**user** / **file** / **knowledge-text** — `meta` is optional and usually absent (`{}` or omitted). Record value shapes:
- `user` → `{ "type": "person", "id": "<user-id>" }` (client may send a bare id; the domain fills `type`).
- `file` → `{ "id": "<storage-file-id>", "name": "contract.pdf" }`.
- `knowledge-text` → `{ "content": "# markdown…" }` on write; `{ "id": "<node-id>", "content": "…" }` on read.

---

## 5. Platform invariants (the rules that will bite you)

1. **Slug is the PK and immutable.** Pick well; no rename.
2. **`attributes` is fully replaced on deploy.** Always model the full list; an omitted attribute is dropped with its data.
3. **`id` is the implicit PK** and a valid relation target even without `is_unique`. You still declare it explicitly.
4. **You cannot delete an entity that is the target of another entity's relation.** Repoint or remove inbound relations first.
5. **No many-to-many primitive** — model a join entity.
6. **Enum values are stored as the `value` string.** Renaming a `value` is a data migration; renaming a `label` is free.

---

## 6. Modeling patterns (battle-tested)

**Value object embedded** — `customer.shipping_address` as an `object`. The
address has no lifecycle of its own → embed. (An address referenced from
elsewhere → a separate entity + relation.)

**Two aggregates, one relation** — `customer ◄── order`. Orders have their own
lifecycle → separate entity; the FK (`customer_id`) lives on the many side.

**Many-to-many via join entity:**
```
customer ◄── customer-tag ──► tag
             ├─ id, created_at, updated_at
             ├─ customer_id (relation → customer.id)
             └─ tag_id      (relation → tag.id)
```

**Self-reference / hierarchy** — `category.parent_id` (relation → `category.id`,
`on_delete: set-null`, `is_required: false` so roots exist).

**Event log** — audit trails (status changes, price history) are their own
entity (`order-status-change`), not a `notes` blob on the parent.

**Header + lines** (ERP) — `order` + `order-line`. The line is a real entity
with a relation back to the header; the page shows the lines as a `related_list`
(see page-reference.md (page-design skill)).

---

## 7. Anti-patterns to reject

- **One 50-attribute mega-entity.** Look for prefix clusters (`shipping_*`,
  `billing_*`) → an `object` value object or a separate entity.
- **Free-string status.** Use an `enum` and describe every value.
- **`customer_name` copied onto `order`.** Use `title_template` on `customer` +
  the relation; don't denormalize in the schema (do it deliberately in a hook if
  query performance truly needs it).
- **Reusing the `id` slot for an external id.** Add `external_id`, `is_unique: true`.
- **Any attribute name not in snake_case** — including FKs (`customer_id`) and
  booleans (`is_signed`).

---

## 8. Entity checklist

- [ ] Validates against `#/$defs/createEntityRequest`.
- [ ] `slug` kebab-case, singular; `attributes` is the FULL list.
- [ ] Declares `id`, `created_at`, `updated_at`.
- [ ] Every attribute name snake_case; booleans prefixed `is_`/`has_`/`can_`.
- [ ] Every enum `value` kebab-case (or a canonical external code); every enum value has a `description`.
- [ ] `datetime` has `meta.format`; `enum`/`array`/`object`/`relation` have their required `meta`.
- [ ] Relations are many-to-one; `related_attribute` = `id` or a unique attr; `set-null` not paired with `is_required: true`.
- [ ] Every entity, attribute, and relation has a substantive `description`.
- [ ] `title_template` set to a meaningful record title.
