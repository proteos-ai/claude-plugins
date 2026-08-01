---
name: domain-modeling
description: >
  Model a business domain as Proteos entities. Applies DDD (aggregates, value
  objects, ubiquitous language) to Proteos's metadata model and treats rich
  business-context descriptions on every entity, attribute, and enum value as a
  hard requirement — the schema is read by AI agents, so the *why* must live in
  the data. Covers all 13 attribute types (incl. user, currency,
  knowledge-text, file), relation cardinality, the server-managed platform
  attributes, naming conventions, and the platform invariants (slug-is-PK,
  full-replacement attribute updates, enforced relation on_delete). Use when
  designing a new domain, refactoring a schema, or deciding "is this one entity
  or three?".
  Triggers — "model my domain", "design entities", "what entities should I
  have", "value object vs entity", "aggregate root", "schema design", "data
  model", "entity relationships", "how should I model X".
---

# Domain modeling

Design (or refactor) the **entities** of a Proteos module. This skill is
opinionated: apply Domain-Driven Design at the modeling stage, then map the
result onto Proteos's entity/attribute schema.

Scope: this skill = *what entities exist and what shape they take*, expressed
as `entities/<slug>.json` files in a module (or one-off `pro meta entities
apply` payloads). The module lifecycle is **module-builder**; the interview
that precedes modeling is **module-discovery**; pages/lists over the entities
are **page-design**.

> **The authoritative wire reference is
> [entity-reference.md](entity-reference.md)** —
> naming/casing rules (§0), the server-managed platform attributes (§2), every
> attribute type + `meta` shape (§4), and modeling patterns. Validate each file
> against [platform.schema.json](platform.schema.json)
> → `#/$defs/createEntityRequest`. This skill teaches the *thinking*; the
> reference is the *shape*.

## How to run this skill

1. **Start from the signed-off discovery.** module-discovery produced the
   ubiquitous language, the entity shortlist, lifecycles, and invariants — with
   sign-off. If that doesn't exist, go back; never model on an un-signed-off
   understanding. Keep asking until you can write a one-paragraph description
   of every entity and a one-sentence description of every attribute and enum
   value **without making anything up**.
2. **Read what already exists.** Prefer the `proteos` MCP server —
   `list_entities`, then `get_entity` on anything you'll extend (fallback:
   `pro meta entities list -o json`). Avoid org-wide slug collisions and
   reuse the conventions in place (relation predicate style, enum casing,
   description depth).
3. **Propose the model in chat first.** Entities, attributes, relations,
   aggregates vs value objects — as a compact table per entity with draft
   descriptions. Get buy-in on shape AND descriptions before writing files.
4. **Write the files.** One `entities/<slug>.json` per entity. Every
   description filled. Validate against the schema.
5. **Show, then iterate.** In a module build, the entities render in the
   `pro module serve` preview (schema view) — let the user see them there.
6. **Surface trade-offs explicitly.** Embed vs relate, enum vs lookup entity,
   one entity vs two — say what you chose and why. Domain models live with the
   business for years.

Attribute removal is destructive (full-replacement `attributes`) — confirm
with the user before dropping anything from a deployed entity.

## Descriptions are non-negotiable

Every `description` — entity, attribute, enum value, relation — carries
concrete business context. The schema is consumed by AI agents with no other
source of truth; the schema IS the documentation.

- **1–3 sentences**; business words, not platform words.
- **The why and the lifecycle**: when is it set, when does it change, what
  depends on it, who touches it.
- **Never restate the label.** `first_name` described as "the first name" is
  worse than nothing — ask the user for real context instead.
- Enum values: what the state MEANS, what triggers entry/exit, what's
  allowed/blocked while in it.
- If the user says "just make something up" — don't. Ask one more round.

## Platform attributes — server-managed, never declared

Every entity automatically carries **`id`**, **`created_at`**, **`updated_at`**,
**`created_by`**, **`updated_by`** (the `*_by` pair typed `user`,
auto-stamped; system writes carry the `platform` sentinel). The server injects
the canonical definitions on create AND update and **drops any client-supplied
redefinition**. Consequences:

- Your `attributes` array = user-defined fields only.
- No hook is needed to stamp `created_by`/`updated_by`.
- Pages/lists/filters/relations bind to platform names freely
  (`created_at` column, `related_attribute: "id"`).

## The 13 attribute types — choosing well

Full `meta` shapes in [entity-reference §4](entity-reference.md).
Choosing guidance:

| Type | Reach for it when |
|---|---|
| `string` | names, codes, free text. Use `format` (`email`/`uri`/`uuid`/…) for free validation. |
| `number` / `integer` | quantities, rates, counts. |
| `boolean` | flags — name them `is_`/`has_`/`can_`. No `meta`. |
| `datetime` | `meta.format` REQUIRED: `date-time` timestamps, `date` calendar dates, `time`, `duration`. |
| `enum` | a closed set of states. Values **kebab-case** (`payment-pending`) unless a canonical code exists (`USD`, `DE`). Every value described. |
| `object` | embedded value object (address, dimensions) — no identity, replaced wholesale. |
| `array` | list of values; `items` is a nested Attribute. `array<string>` tags, `array<enum>` multi-select. |
| `relation` | many-to-one reference to another entity. FK name `<related_slug>_id`. |
| `user` | a platform person/agent — owner, assignee, approver. Value is a UserRef `{type, id}`. Prefer this over a string email or a relation to a custom people entity. |
| `currency` | money. Value is `{amount, currency_code}` — **amount is a decimal STRING** on the wire. Prefer this over integer cents unless you have a hard reason. `meta`: `default_currency_code`, `allowed_currency_codes`. |
| `knowledge-text` | long-form rich text that agents should also reach through the knowledge graph (notes, briefs, meeting bodies). Record stores `{id}` of a knowledge node; reads are enriched. |
| `file` | an uploaded document/image. Record stores `{id, name}` (storage-service). |

Recurring shapes:

- **Money** → `currency`. Integer minor units (`total_cents`) only when the
  domain computes in a single fixed currency and needs integer math.
- **External IDs** → `string` + `is_unique: true`, named `external_id` (never
  reuse the `id` slot).
- **Status / lifecycle** → `enum`, closed set, transitions documented in the
  entity description.
- **Owner / assignee** → `user`.
- **Tags** → `array<string>` + `items_must_be_unique`.
- **Soft delete** → don't; a `status` enum or `deleted_at` datetime if truly
  needed.

## Relations — the rules that bite

```json
{ "name": "customer_id", "type": "relation", "label": "Customer",
  "description": "The customer who placed this order. Set at creation, never reassigned.",
  "is_required": true,
  "meta": { "related_entity_slug": "customer", "related_attribute": "id",
            "predicate": "is placed by", "on_delete": "restrict" } }
```

- Cardinality is always **many-to-one** (FK on the host). Many-to-many = an
  explicit join entity (which is a first-class entity — give it grants and
  attributes like `assigned_at`).
- `related_attribute` must be `id` or an `is_unique: true` attribute.
- `predicate` reads host → target ("order *is placed by* customer").
- **`on_delete` is enforced** — data-service applies it on every record delete,
  so choose it per relation:
  - `restrict` — the delete is blocked while referencing rows exist (409
    `relation_restrict`, listing the blocking `entity.attribute`). Also the
    fallback for an absent/unknown value.
  - `cascade` — referencing rows are deleted too, walked transitively.
  - `set-null` — the referencing attribute is nulled (those rows are not walked
    further). Incompatible with `is_required: true`.

  The whole plan commits in ONE transaction, capped at 10 000 records (400
  `cascade_too_large` above it). Cascaded rows fire their own `before_delete`
  hooks and `record.deleted` events; set-null rows fire `before_update` /
  `record.updated`. There is still no Postgres FK — enforcement is
  application-level over the inbound-relation graph, so direct SQL bypasses it.
- You cannot delete an entity that is the target of another entity's relation
  — repoint/remove inbound relations first.

## Platform invariants

1. **Slug is the PK and immutable** — kebab-case, singular, org-wide unique
   (modules do NOT namespace slugs).
2. **`attributes` is fully replaced** on every apply/deploy — an omitted
   attribute is deleted with its data. Always edit the full list.
3. **Enum values are stored verbatim** — renaming a `value` is a data
   migration; renaming a `label` is free.
4. **`title_template` matters** — it's what relation pickers, related lists,
   and breadcrumbs display. Always set it (`"{{ first_name }} {{ last_name }}"`).

## Applying DDD to Proteos

| DDD concept | Proteos expression |
|---|---|
| Ubiquitous language | slugs/names/labels/descriptions — the business's words |
| Aggregate root | a top-level entity |
| Value object | an `object` attribute (embedded, no identity) |
| Aggregate boundary | embed (`object`) inside; relate (`relation`) across |
| Domain event | an enum state transition, or a dedicated event entity |
| Bounded context | NO direct primitive — modules don't namespace slugs; use slug prefixes (`sales-order`) |

**The aggregate-vs-relation decision** — *can this thing exist or be referenced
on its own?* Embed when it has no independent lifecycle/identity/references
(`shipping_address` snapshot on an order). Relate when it's referenced from
elsewhere, queried independently, or unbounded in cardinality.

### Patterns

1. **One aggregate, value objects inside** — customer with embedded
   `shipping_address` object.
2. **Two aggregates, one relation** — `order.customer_id` → customer; the FK
   lives on the many side.
3. **Many-to-many via join entity** — `customer-tag` with `customer_id` +
   `tag_id` (+ its own permissions grant!).
4. **Hierarchy** — self-relation `parent_id` (`is_required: false` so roots
   exist).
5. **Event log** — `order-status-change` entity with `order_id`,
   `from_status`, `to_status`, rather than freeform notes on the parent.

## Anti-patterns to push back on

- **One big entity with 50 attributes** → prefix clusters (`shipping_*`) are
  value objects or separate aggregates.
- **Free-string status** → `enum` with described values.
- **"Skip the descriptions"** → they're part of the model. Push back.
- **Denormalized display fields** (`customer_name` on order) → use
  `title_template` + the relation; denormalize only deliberately via a hook.
- **Reusing `id` for an external identifier** → `external_id`, unique.
- **Declaring `id`/`created_at`/`created_by`/…** → platform-managed; the
  server drops your copy anyway.
- **Picking `on_delete` by reflex** → it really fires. `cascade` on a shared
  lookup deletes live data; `restrict` on owned children makes the parent
  undeletable. Decide per relation.
- **Non-snake_case attribute names** → `customer_id`, `is_signed`; no
  exceptions.
- **`public_record_access: ["read"]` as a convenience** → it makes EVERY record of
  the entity world-readable unauthenticated (plus the entity definition). Only
  with the user's explicit ask (e.g. data shown on a public page); `read` is
  the only accepted value today (`write`/`delete` reserved), empty `[]` =
  private, and full-replacement means omitting it on a later deploy resets it.
  Details: entity-reference.md §1.

## Skeleton payload

```json
{
  "slug": "REPLACE-ME",
  "name": "Replace Me",
  "is_remote": false,
  "module_slug": "<this-module>",
  "description": "REPLACE — what this represents in the business, who creates records, the lifecycle to terminal state, why it exists separately from neighbours. 2–4 sentences.",
  "title_template": "{{ REPLACE_ME }}",
  "attributes": [
    {
      "name": "REPLACE_ME",
      "type": "string",
      "label": "Replace Me",
      "description": "REPLACE — what it captures, who sets it, when it changes, what depends on it.",
      "is_required": false,
      "is_unique": false,
      "is_nullable": false
    }
  ]
}
```

No platform attributes. Every added attribute: snake_case `name`, substantive
`description`.

## When NOT to use this skill

- Changing one attribute on an existing entity → edit the file (full list!)
  and redeploy; no ceremony.
- The whole module lifecycle → **module-builder**.
- Pages/lists over the entities → **page-design**.
- Reading/writing records → the `proteos` MCP server (CLI `pro data`
  as fallback), not modeling.
