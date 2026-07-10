# App reference

An **app** is a top-level container in the Proteos product switcher — the
grouping a menu (and its entities/pages/lists) lives under.


> **Casing** (full rules in entity-reference §0 (domain-modeling skill)):
> `slug` kebab-case · `icon_slug` lucide PascalCase · everything else snake_case.
>
> **Validate:** `apps/<slug>.json` → `#/$defs/createAppRequest` in
> [`platform.schema.json`](platform.schema.json).

---

## Structure

```json
{
  "slug": "sales",
  "name": "Sales",
  "description": "Manage the customer pipeline and the orders customers place.",
  "module_slug": "crm-sales",
  "icon_slug": "TrendingUp"
}
```

| key | type | notes |
|---|---|---|
| `slug` | string | **required**, kebab-case, org-wide unique, immutable. |
| `name` | string | **required**, display name in the switcher. |
| `description` | string | one line — what this app is for. |
| `module_slug` | string | owning module. |
| `icon_slug` | string | **required**, lucide icon in PascalCase (`TrendingUp`, `Users`, `FileText`). kebab-case renders a placeholder. |

An app is a thin container: it carries no layout of its own. What shows up
inside it is defined by a **menu** whose `app_slug` points here (see
[menu-reference.md](menu-reference.md)). Author the app **before** the menu that
references it.

## Checklist

- [ ] Validates against `#/$defs/createAppRequest`.
- [ ] `slug` kebab-case; `icon_slug` a real lucide name in PascalCase.
- [ ] A menu with `is_default: true` and this `app_slug` exists to populate the sidebar.
