# List & list-view reference

The exact shape of a Proteos **list** (a table configuration over one entity)
and a **list-view** (a saved filter/sort on top of a list). This file also
documents the shared **FilterGroup** predicate, which pages reuse for
`visible_when` / `read_only_when`.


> **Casing** (full rules in entity-reference §0 (domain-modeling skill)):
> slugs kebab-case · attribute references snake_case · enum values kebab-case ·
> everything else snake_case.
>
> **Validate:** `lists/<slug>.json` → `#/$defs/createListRequest`;
> `list-views/<slug>.json` → `#/$defs/createListViewRequest` in
> [`platform.schema.json`](platform.schema.json).

---

## 1. List

A list is the model behind every records table and behind a `related_list` on a
page: which columns, in what order, sorted and filtered how.

```json
{
  "slug": "active-customers",
  "entity_slug": "customer",
  "module_slug": "sales",
  "name": "Customers",
  "columns": [
    { "attribute": "name",           "label": "Name",           "width": 240 },
    { "attribute": "status",         "label": "Status",         "width": 120 },
    { "attribute": "industry",       "label": "Industry",       "width": 180 },
    { "attribute": "annual_revenue", "label": "Annual revenue", "width": 160 },
    { "attribute": "owner",          "label": "Owner",          "width": 160 },
    { "attribute": "created_at",     "label": "Created",        "width": 160 }
  ],
  "sorting": [ { "attribute": "created_at", "direction": "desc" } ],
  "filters": []
}
```

| key | type | notes |
|---|---|---|
| `slug` | string | **required**, kebab-case, unique. |
| `entity_slug` | string | **required**, the entity whose records the list shows. Immutable. |
| `module_slug` | string | owning module. |
| `name` | string | display name. |
| `columns` | Column[] | `{ attribute, label, width }`. `attribute` = snake_case entity attribute name; `width` in px (a hint). |
| `sorting` | SortConfig[] | `{ attribute, direction }`, `direction` ∈ `asc` `desc`. Empty = default order. |
| `filters` | FilterGroup[] | rows that don't match are excluded (§3). Empty = all rows. |

### Column

```json
{ "attribute": "annual_revenue", "label": "Annual revenue", "width": 160 }
```

- `attribute` — must match a real snake_case attribute on the entity (a
  mismatch renders `Unknown attribute`).
- `relation` / `user` columns show the related record's title / the person's
  name automatically in the product (and the inline label you supply in a
  preview — see page-reference §preview (page-design skill)).

---

## 2. List-view

A saved filter/sort layered on a list (like a Salesforce "My open
opportunities"). References a `list_slug`; overrides its `filters` / `sorting` /
`columns`.

```json
{
  "slug": "my-active-customers",
  "list_slug": "active-customers",
  "module_slug": "sales",
  "name": "Active accounts",
  "columns": [],
  "sorting": [ { "attribute": "annual_revenue", "direction": "desc" } ],
  "filters": [
    { "logical_operator": "and",
      "elements": [ { "field": "status", "operator": "eq", "value": "active" } ],
      "groups": [] }
  ]
}
```

- `list_slug` — the list this view refines. Immutable.
- Empty `columns` = inherit the list's columns.
- Use list-views for the daily segments a user reaches for (Mine / Open /
  Overdue / This quarter) rather than one giant unfiltered table.

---

## 3. FilterGroup — the shared predicate

Used by list/list-view `filters` **and** by page `visible_when` /
`read_only_when`.

```json
{
  "logical_operator": "and",
  "elements": [
    { "field": "status", "operator": "eq", "value": "active" }
  ],
  "groups": [
    { "logical_operator": "or",
      "elements": [
        { "field": "is_priority",    "operator": "eq", "value": "true" },
        { "field": "annual_revenue", "operator": "gt", "value": "1000000" }
      ] }
  ]
}
```

- `logical_operator` ∈ `and` `or`. `elements` are atomic predicates; `groups` nest.
- `field` — a snake_case attribute name.
- **`value` is ALWAYS a string** — the runtime coerces. Booleans →
  `"true"`/`"false"`; `in`/`not_in` → pipe-joined `"a|b|c"`; ignored for
  `empty`/`not_empty`. Enum comparisons use the kebab-case value (`"in-transit"`).
- `operator` ∈ `eq` `ne` `gt` `gte` `lt` `lte` `in` `not_in` `contains`
  `starts_with` `ends_with` `empty` `not_empty`.
- An **empty** FilterGroup (no elements, no groups) is **vacuously true**.

---

## 4. CRM / ERP column best practices

- **6–7 columns max.** A table is not a detail page. If you need more, that's a
  page.
- **Order:** lead with the **title** column (widest, ~220–280px), then the
  **status/stage** enum (~120px), then 2–4 defining business attributes, then an
  **owner/user** (~160px), then a **date** last (~160px). Narrow booleans ~90px.
- **Never lead with `id` or `created_at`.** System columns go last or are
  omitted.
- **Default-sort by what the user scans for** — usually `created_at desc` or a
  due-date `asc`.
- **Provide list-views for the common segments** instead of expecting users to
  filter a raw table each time.
- **Header + lines (ERP):** the line entity (`order-line`) gets its own list
  (`number`, `qty`, `unit_price`, `line_total`) that drives the `related_list`
  on the header's page.

---

## 5. List checklist

- [ ] List validates against `#/$defs/createListRequest`; list-view against `#/$defs/createListViewRequest`.
- [ ] `entity_slug` (list) / `list_slug` (list-view) reference a real slug.
- [ ] Every `columns[].attribute` and `sorting[].attribute` matches a real snake_case attribute.
- [ ] ≤ 6–7 columns; title first, system fields last or omitted.
- [ ] Filter `value`s are strings; enum comparisons use kebab-case values.
- [ ] A default `sorting` is set to something meaningful.
