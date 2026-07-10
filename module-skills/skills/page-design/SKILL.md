---
name: page-design
description: >
  Author Proteos Pages — the typed PageLayout tree (rows, columns, sections,
  tabs, fields, dividers, text, components, related lists) for entity-detail
  screens and platform (dashboard/board) pages. Covers element semantics, the
  current FieldElement control registry (incl. entity-picker, user-picker,
  currency, knowledge-text, file, datetime-picker), sizing/responsive rules,
  conditional visibility/read-only, and proven layout patterns for CRM-style
  screens — previewed live via `pro module serve`. Use whenever you design,
  refactor, or debug a Page's layout tree. Triggers — "design a page", "detail
  page", "page layout", "PageLayout", "FieldElement", "tabs in a page", "side
  panel", "visible_when", "read_only_when", "platform page", "dashboard page".
---

# Page design

Pages are the detail screens of the Proteos UI. An **entity-detail page**
binds to one entity and renders one record; a **platform page**
(`"type": "platform"`, no `entity_slug`) is a standalone screen — dashboard,
board, explorer — usually built from `component` elements. The `layout` is a
typed tree of elements.

> **The authoritative wire reference is
> [page-reference.md](page-reference.md)** — every
> element and prop, the control registry, FilterGroup predicates, sizing
> grammar, sample-data shapes, and layout best practices. Validate each
> `pages/<slug>.json` against
> [platform.schema.json](platform.schema.json) →
> `#/$defs/createPageRequest`. This skill is the design discipline on top.

Wire format is **snake_case** throughout (`entity_slug`, `visible_when`,
`read_only_when`, `empty_display`, `default_tab_id`, `component_slug`,
`side_panel`); attribute bindings are snake_case attribute names, dot-paths
into `object` attributes (`shipping_address.postal_code`), leaf-only.

## Cardinal rules

1. **`entity_slug` is immutable** — a page is bound to one entity for life.
2. **Layout updates replace the whole tree** — edit `pages/<slug>.json` and
   re-deploy; there is no element-level patch. Keep element `id`s stable when
   refactoring (they're render keys); keep tab ids stable and update
   `default_tab_id` together with them.
3. **Bind only to real attribute names** — a wrong/miscased `attribute`
   renders `Unknown attribute · <name>`. Platform attributes (`created_at`,
   `created_by`, …) are valid bindings.
4. **Preview is the truth** — a schema-valid layout can still read badly. Look
   at it in the `pro module serve` preview before calling it done.

## The element catalogue (summary — depth in page-reference)

- **`row` / `column`** — flex containers (`gap` xs/sm/md/lg, `align`,
  `justify`; row also `allows_wrap`). The page `main` is conventionally a
  `column` gap `md`. Don't nest rows >2 deep.
- **`section`** — titled block; `is_collapsible` + `default_collapsed` for
  secondary info. Title-less section = invisible grouping wrapper.
- **`tabs`** — equal-weight facets (Overview / Activity / Files). Stable tab
  ids. Don't use tabs to hide what a collapsible section handles.
- **`field`** — bound attribute (the workhorse; below).
- **`related_list`** — embedded live table of related records:
  `related_entity_slug` + `via_attribute` (the relation attr ON THE RELATED
  entity pointing back) + optional `list_slug` pin.
- **`component`** — custom React block: `component_slug` + `props` (Liquid
  templates against `{record, entity, params}` — **bind scalar leaves**;
  passing a whole object stringifies to `[object Object]`). →
  component-engineer.
- **`divider`**, **`text`** (`variant`: heading/subheading/body/caption/
  callout; non-empty `content`).
- **`side_panel`** — optional sticky right rail. Use sparingly: tools and
  context (a component widget, a related-list summary, a callout) — never a
  dump of plain fields, never system/audit fields. Most pages need none.

## FieldElement essentials

```jsonc
{ "type": "field", "id": "f-stage", "attribute": "stage",
  "label": null,                 // null hides; absent → attribute label
  "empty_display": "hide",       // "dash" (default) | "hide" | literal string
  "is_read_only": false,         // 3-state: absent = inherit from attribute
  "control": "chip-group",       // only when the default is wrong
  "control_props": { } }
```

- `read_only_when` / `visible_when` are FilterGroup predicates (`field` =
  snake_case attribute, `value` ALWAYS a string — `"true"`, `"a|b|c"` for
  `in`). `visible_when` works on every element in view mode; `read_only_when`
  is honored on fields only.
- Use `is_read_only` for static intent, `read_only_when` for state gating
  ("lock price once `status == "shipped"`").
- `empty_display: "hide"` for optional metadata whose absence means nothing;
  a literal (`"Not set"`) when absence is meaningful.

## Control registry — current defaults (set `control` only to deviate)

| Attribute | Default control | Alternatives |
|---|---|---|
| `string` | `text` | `textarea` (prose; `control_props: {rows}`), `password` |
| `string` + `email` / `uri` | `email` / `url` | `text` |
| `number` / `integer` | `number` (`control_props: {step,min,max}`) | — |
| `boolean` | `switch` | `checkbox` (consent semantics) |
| `enum` | `select` | `radio-group` (≤4, all visible), `chip-group` (short, equal-weight) |
| `array<string>` | `tag-input` | — |
| `array<enum>` | `multi-select` | — |
| `datetime` `date` | `date-picker` | — |
| `datetime` `date-time` | `datetime-picker` | — |
| `datetime` `time` | `time-picker` | — |
| `datetime` `duration` | none — read-only display | — |
| `relation` | `entity-picker` (searches the related entity, shows `title_template`) | — |
| `user` | `user-picker` (org people picker) | — |
| `currency` | `currency` (decimal amount + ISO-4217 picker) | — |
| `knowledge-text` | `knowledge-text` | — |
| `file` | `file` | — |
| `object` | none — bind to leaf children instead | — |

Reserved-but-unimplemented slugs (fall back to read-only display — don't ship
pages relying on them): `markdown`, `json-editor`, `slider`, `stepper`,
`percent`, `user-card`. Source of truth:
`packages/sdk-ts/src/meta/layout/control-registry.json`.

When you change `control`, drop `control_props` — keys are slug-specific.

## Design discipline

1. **Get the entity schema first** — attribute names, types, formats, object
   leaves. In a module: read `entities/<slug>.json`; for a deployed entity:
   `proteos-admin` MCP `get_entity` (fallback: `pro meta entities get <slug>
   -o json`).
2. **Sketch the tree in pseudo-code** before JSON: what's identity (top,
   never collapsed), what's supporting (sections), what's equal-weight facets
   (tabs), what's secondary (collapsed sections), what's related
   (related_list), what's custom (component).
3. **Standard CRM shape**: Identity section (row of key fields) → supporting
   sections → tabs (Overview / related lists / comments component) →
   collapsed secondary sections. Two-column rows: two fields at
   `width: "1/2"`.
4. **Add conditions late** — get the unconditional layout right first.
5. **Responsive**: design for `lg`; add `sm` overrides collapsing multi-column
   rows to `100%`. Only when the layout *shape* must change.
6. **Preview and iterate** — save the file; the `pro module serve` preview
   re-renders in place (pages render against a deterministic sample record;
   relation/user values show inline labels). Look at it before showing the
   user; then let the user react.

Page-level `actions[]` (`{label, icon, action}`) render as toolbar buttons —
`action` is typically a module action slug (→ action-engineer); icons lucide
PascalCase. In the preview they show as buttons with a "runs in the live app"
note; they execute only after deploy.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| `json: unknown field` | camelCase key | snake_case everything |
| `Unknown attribute · X` | binding doesn't match entity attribute name | match snake_case exactly; check the entity file |
| Field shows read-only fallback | control slug unimplemented or incompatible | use the registry table above |
| Object bound directly | `attribute: "shipping_address"` | bind leaves: `shipping_address.postal_code` |
| Component prop is `[object Object]` | Liquid-bound a whole object | bind scalar leaves per prop |
| `visible_when` ignored | empty FilterGroup is vacuously true | add at least one element |
| Boolean condition fails | `value: true` (boolean) | `value: "true"` (string) |
| Tab content vanished after rename | tab id changed without `default_tab_id` | keep ids stable; update both together |

## What this skill does NOT cover

- Entity shape → **domain-modeling**. Lists/menus/apps + lifecycle →
  **module-builder**. Action logic → **action-engineer**. Component internals
  → **component-engineer**. Validation/invariants → a `before_*` hook
  (**hook-engineer**), never `visible_when`.
