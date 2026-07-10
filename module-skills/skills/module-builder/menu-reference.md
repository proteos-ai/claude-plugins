# Menu reference

A **menu** is the sidebar navigation tree shown under an app — a nested list of
links to lists, pages, and entities.


> **Casing** (full rules in entity-reference §0 (domain-modeling skill)):
> slugs kebab-case · `icon` lucide PascalCase · `reference` = a target slug
> (kebab) · everything else snake_case.
>
> **Validate:** `menus/<slug>.json` → `#/$defs/createMenuConfigurationRequest`
> in [`platform.schema.json`](platform.schema.json).

---

## Structure

```json
{
  "slug": "sales-nav",
  "name": "Sales navigation",
  "module_slug": "crm-sales",
  "app_slug": "sales",
  "is_default": true,
  "items": [
    { "id": "accounts", "order": 0, "label": "Accounts", "type": "group", "icon": "Users", "reference": "", "children": [
      { "id": "customers", "order": 0, "label": "Customers", "type": "list", "icon": "Building2",    "reference": "active-customers", "children": [] },
      { "id": "orders",    "order": 1, "label": "Orders",    "type": "list", "icon": "ShoppingCart", "reference": "open-orders",      "children": [] }
    ] }
  ]
}
```

| key | type | notes |
|---|---|---|
| `slug` | string | **required**, kebab-case, unique. |
| `name` | string | display name. |
| `module_slug` | string | owning module. |
| `app_slug` | string | **required**, the app this menu populates (must exist — author the app first). |
| `is_default` | boolean | the menu shown by default for the app. Have exactly one default per app. |
| `items` | MenuItem[] | the tree — **replaced wholesale** on every deploy. |

## MenuItem

```json
{ "id": "customers", "order": 0, "label": "Customers", "type": "list", "icon": "Building2", "reference": "active-customers", "children": [] }
```

| key | type | notes |
|---|---|---|
| `id` | string | stable within the menu. |
| `order` | integer | sort order among siblings. |
| `label` | string | display text. |
| `type` | enum | `link` · `group` · `entity` · `page` · `list`. |
| `icon` | string | lucide PascalCase (`FolderClosed`, `FileText`, `Users`). kebab-case → placeholder. |
| `reference` | string | the **target slug** — a list slug (`type:list`), page slug (`type:page`), or entity slug (`type:entity`). `""` for a `group`. A `link` uses a URL. |
| `children` | MenuItem[] \| null | nesting. `[]` (or `null`) for a leaf; a `group` holds its items here. |

### Item types

- **`group`** — a non-clickable heading that nests `children`; `reference: ""`.
- **`list`** — opens a records table; `reference` = a list slug.
- **`page`** — opens a **platform** page (dashboard/board); `reference` = the
  page slug. (Record pages are reached by clicking a record, not from the menu.)
- **`entity`** — the entity's default list/records view; `reference` = entity slug.
- **`link`** — an external/internal URL in `reference`.

## Best practices

- Group by the user's mental model (Accounts / Pipeline / Reports), not by
  entity. One or two levels deep — deep menus are hard to scan.
- Lead each group with the object the user reaches for most.
- Icons should be recognizable and consistent (a `list` of customers →
  `Building2`, orders → `ShoppingCart`).

## Checklist

- [ ] Validates against `#/$defs/createMenuConfigurationRequest`.
- [ ] `app_slug` references an existing app; exactly one `is_default` menu per app.
- [ ] Every `reference` points at a real slug of the right kind; `group` items use `""`.
- [ ] Every `icon` is a real lucide name in PascalCase.
- [ ] `items` is the complete tree (it replaces wholesale).
