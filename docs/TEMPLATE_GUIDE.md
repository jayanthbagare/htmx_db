# Template Guide

This guide explains how the HTMX DB template system works and how to create and modify templates.

## Overview

The template system uses a Mustache-like syntax implemented in PostgreSQL. Templates are stored in the `htmx_templates` table and rendered by the `render_template()` function.

## Template Syntax

### Simple Placeholders

Replace with field values:

```html
<div>{{field_name}}</div>
```

**Input Data:**
```json
{"field_name": "Hello World"}
```

**Output:**
```html
<div>Hello World</div>
```

---

### Nested Paths

Access nested object properties:

```html
<span>{{supplier.supplier_name}}</span>
<span>{{supplier.contact.email}}</span>
```

**Input Data:**
```json
{
  "supplier": {
    "supplier_name": "Acme Corp",
    "contact": {"email": "info@acme.com"}
  }
}
```

---

### HTML Escaping

By default, values are HTML-escaped to prevent XSS:

```html
{{user_input}}
```

**Input:** `<script>alert('XSS')</script>`
**Output:** `&lt;script&gt;alert('XSS')&lt;/script&gt;`

For raw HTML (use with caution):
```html
{{{raw_html}}}
```

---

### Conditionals

#### Simple If

```html
{{#if status}}
<span>Status: {{status}}</span>
{{/if}}
```

#### If-Else

```html
{{#if is_active}}
<span class="active">Active</span>
{{#else}}
<span class="inactive">Inactive</span>
{{/if}}
```

#### Comparison Operators

```html
{{#if status == 'approved'}}
<span class="approved">Approved</span>
{{/if}}

{{#if total_amount > 1000}}
<span class="high-value">High Value Order</span>
{{/if}}

{{#if quantity_received < quantity_ordered}}
<span class="partial">Partially Received</span>
{{/if}}
```

**Supported Operators:** `==`, `!=`, `>`, `<`, `>=`, `<=`

---

### Loops

#### Array Iteration

```html
{{#each lines}}
<tr>
    <td>{{line_number}}</td>
    <td>{{item_code}}</td>
    <td>{{quantity_ordered}}</td>
    <td>{{unit_price}}</td>
</tr>
{{/each}}
```

**Input Data:**
```json
{
  "lines": [
    {"line_number": 1, "item_code": "A001", "quantity_ordered": 10, "unit_price": 25.00},
    {"line_number": 2, "item_code": "B002", "quantity_ordered": 5, "unit_price": 50.00}
  ]
}
```

#### Empty Array Handling

```html
{{#each lines}}
<tr>{{item_code}}</tr>
{{#else}}
<tr><td colspan="4">No items found</td></tr>
{{/each}}
```

#### Loop Index

```html
{{#each items}}
<li data-index="{{@index}}">{{name}}</li>
{{/each}}
```

---

### Partials

Include reusable template fragments:

```html
{{> pagination}}
{{> field_input}}
{{> action_buttons}}
```

Partials are defined separately and included at render time.

---

### HTMX Attributes

Templates frequently include HTMX attributes:

```html
<button
    hx-get="/ui/purchase_order/form/edit?id={{po_id}}"
    hx-target="#modal"
    hx-swap="innerHTML">
    Edit
</button>

<form
    hx-post="/api/purchase_order"
    hx-target="#main-content"
    hx-swap="outerHTML">
    ...
</form>

<tr
    hx-get="/ui/purchase_order/form/view?id={{po_id}}"
    hx-target="#modal"
    hx-trigger="click">
    ...
</tr>
```

---

## Template Types

### List Template

Displays a table of records with filtering and pagination.

```html
<div class="entity-list" id="{{entity_type}}-list">
    <!-- Header with title and create button -->
    <div class="list-header">
        <h2>{{display_name}}</h2>
        {{#if can_create}}
        <button
            hx-get="/ui/{{entity_type}}/form/create"
            hx-target="#modal"
            class="btn btn-primary">
            New {{display_name_singular}}
        </button>
        {{/if}}
    </div>

    <!-- Filter panel -->
    {{> filter_panel}}

    <!-- Data table -->
    <table class="data-table">
        <thead>
            <tr>
                {{#each visible_fields}}
                <th hx-get="/ui/{{../entity_type}}/list/table?sort={{field_name}}"
                    hx-target="#{{../entity_type}}-table-body"
                    class="sortable {{#if is_sorted}}sorted-{{sort_direction}}{{/if}}">
                    {{display_label}}
                </th>
                {{/each}}
                <th>Actions</th>
            </tr>
        </thead>
        <tbody id="{{entity_type}}-table-body">
            {{#each records}}
            <tr>
                {{#each ../visible_fields}}
                <td>{{lookup ../this field_name}}</td>
                {{/each}}
                <td class="actions">
                    {{> row_actions}}
                </td>
            </tr>
            {{/each}}
        </tbody>
    </table>

    <!-- Pagination -->
    {{> pagination}}
</div>
```

---

### Create Form Template

Empty form for creating new records.

```html
<div class="form-container">
    <form
        hx-post="/api/{{entity_type}}"
        hx-target="#main-content"
        hx-swap="outerHTML"
        class="entity-form">

        <h2>Create {{display_name_singular}}</h2>

        {{#each fields}}
        {{#if form_create_visible}}
        <div class="form-group">
            <label for="{{field_name}}">
                {{display_label}}
                {{#if is_required}}<span class="required">*</span>{{/if}}
            </label>

            {{#switch data_type}}
            {{#case 'text'}}
            <input type="text"
                   id="{{field_name}}"
                   name="{{field_name}}"
                   {{#if is_required}}required{{/if}}
                   {{#unless form_create_editable}}disabled{{/unless}}
                   value="{{default_value}}">
            {{/case}}

            {{#case 'textarea'}}
            <textarea
                id="{{field_name}}"
                name="{{field_name}}"
                {{#unless form_create_editable}}disabled{{/unless}}>{{default_value}}</textarea>
            {{/case}}

            {{#case 'date'}}
            <input type="date"
                   id="{{field_name}}"
                   name="{{field_name}}"
                   {{#if is_required}}required{{/if}}
                   {{#unless form_create_editable}}disabled{{/unless}}>
            {{/case}}

            {{#case 'lookup'}}
            <select
                id="{{field_name}}"
                name="{{field_name}}"
                hx-get="/ui/{{lookup_entity}}/lookup/{{field_name}}"
                hx-trigger="load"
                {{#if is_required}}required{{/if}}
                {{#unless form_create_editable}}disabled{{/unless}}>
                <option value="">Select {{display_label}}...</option>
            </select>
            {{/case}}
            {{/switch}}

            {{#if help_text}}
            <small class="help-text">{{help_text}}</small>
            {{/if}}
        </div>
        {{/if}}
        {{/each}}

        <div class="form-actions">
            <button type="submit" class="btn btn-primary">Create</button>
            <button type="button" class="btn btn-secondary" onclick="closeModal()">Cancel</button>
        </div>
    </form>
</div>
```

---

### Edit Form Template

Pre-populated form for editing records.

```html
<form
    hx-put="/api/{{entity_type}}/{{record_id}}"
    hx-target="#main-content">

    <h2>Edit {{display_name_singular}}</h2>

    {{#each fields}}
    {{#if form_edit_visible}}
    <div class="form-group">
        <label for="{{field_name}}">{{display_label}}</label>
        <input type="{{input_type}}"
               name="{{field_name}}"
               value="{{lookup ../record field_name}}"
               {{#unless form_edit_editable}}disabled{{/unless}}>
    </div>
    {{/if}}
    {{/each}}

    <div class="form-actions">
        <button type="submit">Save Changes</button>
        <button type="button" onclick="closeModal()">Cancel</button>
    </div>
</form>
```

---

### View Form Template

Read-only display of a record.

```html
<div class="view-form">
    <h2>{{display_name_singular}} Details</h2>

    <dl class="details-list">
        {{#each fields}}
        {{#if form_view_visible}}
        <dt>{{display_label}}</dt>
        <dd>{{lookup ../record field_name}}</dd>
        {{/if}}
        {{/each}}
    </dl>

    <div class="form-actions">
        {{#if can_edit}}
        <button
            hx-get="/ui/{{entity_type}}/form/edit?id={{record_id}}"
            hx-target="#modal">
            Edit
        </button>
        {{/if}}
        <button type="button" onclick="closeModal()">Close</button>
    </div>
</div>
```

---

## Permission Integration

Templates automatically receive permission data:

```html
{{#if can_create}}
<!-- Show create button -->
{{/if}}

{{#if can_edit}}
<!-- Show edit button -->
{{/if}}

{{#if can_delete}}
<!-- Show delete button -->
{{/if}}

{{#if can_approve}}
<!-- Show approve button -->
{{/if}}
```

Field-level permissions control visibility and editability:

```html
{{#each fields}}
    {{#if list_visible}}
        <!-- Field shown in list -->
    {{/if}}

    {{#if form_edit_editable}}
        <input ...>
    {{#else}}
        <input ... disabled>
    {{/if}}
{{/each}}
```

---

## Common Partials

### pagination

```html
<div class="pagination">
    <span>Showing {{start_row}} - {{end_row}} of {{total_count}}</span>

    {{#if has_prev_page}}
    <button
        hx-get="/ui/{{entity_type}}/list/table?page={{prev_page}}"
        hx-target="#{{entity_type}}-table-body">
        Previous
    </button>
    {{/if}}

    <span>Page {{current_page}} of {{total_pages}}</span>

    {{#if has_next_page}}
    <button
        hx-get="/ui/{{entity_type}}/list/table?page={{next_page}}"
        hx-target="#{{entity_type}}-table-body">
        Next
    </button>
    {{/if}}
</div>
```

### row_actions

```html
<div class="row-actions">
    {{#if can_edit}}
    <button
        hx-get="/ui/{{entity_type}}/form/edit?id={{id}}"
        hx-target="#modal"
        class="btn-icon">
        Edit
    </button>
    {{/if}}

    {{#if can_delete}}
    <button
        hx-delete="/api/{{entity_type}}/{{id}}"
        hx-confirm="Are you sure?"
        class="btn-icon btn-danger">
        Delete
    </button>
    {{/if}}
</div>
```

---

## Best Practices

1. **Use semantic HTML** - Use appropriate elements (`<table>`, `<form>`, `<button>`)

2. **Include HTMX targets** - Always specify `hx-target` for predictable behavior

3. **Handle empty states** - Use `{{#else}}` blocks for empty lists

4. **Apply permission checks** - Wrap actions in permission conditionals

5. **Escape user input** - Use `{{}}` (not `{{{}}}`) for user-provided content

6. **Use consistent IDs** - Include entity type in IDs for uniqueness

7. **Add loading indicators** - Use `hx-indicator` for better UX

8. **Test with all roles** - Verify templates work for each user role

---

## Debugging Templates

1. **View raw template:**
```sql
SELECT base_template
FROM htmx_templates
WHERE entity_type_id = (SELECT entity_type_id FROM ui_entity_types WHERE entity_name = 'purchase_order')
AND view_type = 'list';
```

2. **Test rendering:**
```sql
SELECT render_template(
    '<div>{{name}}</div>',
    '{"name": "Test"}'::JSONB
);
```

3. **Check field permissions:**
```sql
SELECT * FROM get_user_field_permissions(
    '00000000-0000-0000-0000-000000000100',
    'purchase_order',
    'list'
);
```
