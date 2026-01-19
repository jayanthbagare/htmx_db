# Permissions Guide

This guide explains the HTMX DB permission system, including how to configure and extend permissions.

## Overview

The permission system operates on three levels:

1. **Action Permissions** - What actions can a user perform on an entity?
2. **Field Permissions** - Which fields can a user see/edit in each view?
3. **Row-Level Security (RLS)** - Which records can a user access?

## Permission Hierarchy

```
User
  └── Role
        ├── Action Permissions (per entity)
        │     └── Can create, edit, delete, approve, etc.
        │
        └── Field Permissions (per field per view)
              └── Visible? Editable?

Record
  └── RLS Policy
        └── Can user access this specific record?
```

---

## Action Permissions

### Definition

Action permissions are stored in `ui_action_permissions`:

```sql
CREATE TABLE ui_action_permissions (
    role_id UUID,
    entity_type_id UUID,
    action_name VARCHAR(50),
    is_allowed BOOLEAN,
    condition_rule JSONB
);
```

### Standard Actions

| Action | Description |
|--------|-------------|
| `read` | View list and individual records |
| `create` | Create new records |
| `edit` | Modify existing records |
| `delete` | Soft delete records |
| `approve` | Approve submitted items |
| `submit` | Submit for approval |
| `cancel` | Cancel records |

### Setting Action Permissions

```sql
-- Allow admin to do everything
INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed)
SELECT
    r.role_id,
    e.entity_type_id,
    action,
    true
FROM roles r
CROSS JOIN ui_entity_types e
CROSS JOIN (VALUES ('read'), ('create'), ('edit'), ('delete'), ('approve')) AS actions(action)
WHERE r.role_name = 'admin';

-- Allow viewer to read only
INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed)
SELECT
    r.role_id,
    e.entity_type_id,
    'read',
    true
FROM roles r
CROSS JOIN ui_entity_types e
WHERE r.role_name = 'viewer';
```

### Conditional Permissions

Use `condition_rule` for context-dependent permissions:

```sql
-- Manager can only edit their own draft POs
INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed, condition_rule)
VALUES (
    (SELECT role_id FROM roles WHERE role_name = 'purchase_manager'),
    (SELECT entity_type_id FROM ui_entity_types WHERE entity_name = 'purchase_order'),
    'edit',
    true,
    '{
        "conditions": [
            {"field": "status", "operator": "=", "value": "draft"},
            {"field": "created_by", "operator": "=", "value": "$user_id"}
        ],
        "logic": "AND"
    }'
);
```

### Checking Action Permissions

```sql
-- Check if user can perform action
SELECT can_user_perform_action(
    '00000000-0000-0000-0000-000000000101',  -- user_id
    'purchase_order',                          -- entity_type
    'approve'                                  -- action_name
);
-- Returns: true/false

-- Check with record context (for conditional rules)
SELECT can_user_perform_action(
    '00000000-0000-0000-0000-000000000101',
    'purchase_order',
    'edit',
    '{"status": "draft", "created_by": "00000000-0000-0000-0000-000000000101"}'::JSONB
);
```

---

## Field Permissions

### Definition

Field permissions are stored in `field_permissions`:

```sql
CREATE TABLE field_permissions (
    role_id UUID,
    field_id UUID,
    list_visible BOOLEAN DEFAULT TRUE,
    list_editable BOOLEAN DEFAULT FALSE,
    form_create_visible BOOLEAN DEFAULT TRUE,
    form_create_editable BOOLEAN DEFAULT TRUE,
    form_edit_visible BOOLEAN DEFAULT TRUE,
    form_edit_editable BOOLEAN DEFAULT TRUE,
    form_view_visible BOOLEAN DEFAULT TRUE
);
```

### Permission Flags

| Flag | View | Description |
|------|------|-------------|
| `list_visible` | List | Show field in list/table |
| `list_editable` | List | Allow inline edit in list (rarely used) |
| `form_create_visible` | Create Form | Show field in create form |
| `form_create_editable` | Create Form | Allow editing in create form |
| `form_edit_visible` | Edit Form | Show field in edit form |
| `form_edit_editable` | Edit Form | Allow editing in edit form |
| `form_view_visible` | View Form | Show field in view form |

### Setting Field Permissions

```sql
-- Get entity and role IDs
DO $$
DECLARE
    v_entity_id UUID;
    v_admin_role UUID;
    v_viewer_role UUID;
    v_field RECORD;
BEGIN
    SELECT entity_type_id INTO v_entity_id
    FROM ui_entity_types WHERE entity_name = 'purchase_order';

    SELECT role_id INTO v_admin_role FROM roles WHERE role_name = 'admin';
    SELECT role_id INTO v_viewer_role FROM roles WHERE role_name = 'viewer';

    -- Admin: Full access to all fields
    FOR v_field IN
        SELECT field_id FROM ui_field_definitions WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_admin_role, v_field.field_id,
            true, true,
            true, true,
            true, true,
            true
        );
    END LOOP;

    -- Viewer: See all fields, edit nothing
    FOR v_field IN
        SELECT field_id FROM ui_field_definitions WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_viewer_role, v_field.field_id,
            true, false,
            false, false,  -- Can't see create form
            false, false,  -- Can't see edit form
            true           -- Can see view form
        );
    END LOOP;
END $$;
```

### Hiding Sensitive Fields

```sql
-- Hide total_amount from warehouse staff
INSERT INTO field_permissions (role_id, field_id, list_visible, form_view_visible)
SELECT
    r.role_id,
    f.field_id,
    false,  -- Not visible in list
    false   -- Not visible in view
FROM roles r
JOIN ui_field_definitions f ON f.field_name = 'total_amount'
WHERE r.role_name = 'warehouse_staff';
```

### Getting Field Permissions

```sql
-- Get all field permissions for a user in a specific view
SELECT * FROM get_user_field_permissions(
    '00000000-0000-0000-0000-000000000102',  -- user_id
    'purchase_order',                          -- entity_type
    'list'                                     -- view_type
);

-- Returns:
-- field_name | is_visible | is_editable
-- -----------+------------+-------------
-- po_number  | true       | false
-- supplier   | true       | false
-- status     | true       | false
-- total      | false      | false  <-- Hidden for this user
```

---

## Row-Level Security (RLS)

### Enabling RLS

```sql
-- Enable RLS on table
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;

-- Force RLS for table owner too
ALTER TABLE purchase_orders FORCE ROW LEVEL SECURITY;
```

### Creating Policies

```sql
-- Users can see their own records
CREATE POLICY po_select_own ON purchase_orders
    FOR SELECT
    USING (created_by = current_setting('app.user_id')::UUID);

-- Admins can see all records
CREATE POLICY po_select_admin ON purchase_orders
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN roles r ON u.role_id = r.role_id
            WHERE u.user_id = current_setting('app.user_id')::UUID
            AND r.role_name = 'admin'
        )
    );

-- Users can only update their own draft records
CREATE POLICY po_update_own ON purchase_orders
    FOR UPDATE
    USING (
        created_by = current_setting('app.user_id')::UUID
        AND status = 'draft'
    );
```

### Common RLS Patterns

#### Own Records Only
```sql
CREATE POLICY user_own_records ON table_name
    FOR ALL
    USING (created_by = current_setting('app.user_id')::UUID);
```

#### Role-Based Access
```sql
CREATE POLICY role_based_access ON table_name
    FOR SELECT
    USING (
        (SELECT role_name FROM roles r
         JOIN users u ON u.role_id = r.role_id
         WHERE u.user_id = current_setting('app.user_id')::UUID)
        IN ('admin', 'manager')
    );
```

#### Status-Based Access
```sql
CREATE POLICY status_access ON table_name
    FOR SELECT
    USING (
        status IN ('approved', 'published')
        OR created_by = current_setting('app.user_id')::UUID
    );
```

---

## Standard Role Configuration

### Admin

Full access to all entities and actions:

```sql
-- All action permissions
INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed)
SELECT r.role_id, e.entity_type_id, a.action, true
FROM roles r
CROSS JOIN ui_entity_types e
CROSS JOIN (VALUES ('read'), ('create'), ('edit'), ('delete'), ('approve'), ('submit'), ('cancel')) AS a(action)
WHERE r.role_name = 'admin';

-- All field permissions (full access)
-- ... (as shown above)
```

### Purchase Manager

Can manage purchase orders:

| Entity | Actions |
|--------|---------|
| Suppliers | read |
| Purchase Orders | read, create, edit, submit |
| Goods Receipts | read |
| Invoices | read |
| Payments | read |

### Warehouse Staff

Can manage goods receipts:

| Entity | Actions |
|--------|---------|
| Suppliers | read |
| Purchase Orders | read |
| Goods Receipts | read, create, edit |
| Invoices | - |
| Payments | - |

**Field Restrictions:**
- Cannot see `total_amount`, `unit_price` fields

### Accountant

Can manage invoices and payments:

| Entity | Actions |
|--------|---------|
| Suppliers | read |
| Purchase Orders | read |
| Goods Receipts | read |
| Invoices | read, create, edit, approve |
| Payments | read, create, edit |

### Viewer

Read-only access:

| Entity | Actions |
|--------|---------|
| All | read |

---

## Permission Functions

### can_user_perform_action

```sql
CREATE OR REPLACE FUNCTION can_user_perform_action(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_action_name VARCHAR,
    p_record_data JSONB DEFAULT NULL
) RETURNS BOOLEAN
```

### get_user_field_permissions

```sql
CREATE OR REPLACE FUNCTION get_user_field_permissions(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_view_type VARCHAR
) RETURNS TABLE (
    field_name VARCHAR,
    is_visible BOOLEAN,
    is_editable BOOLEAN
)
```

### apply_field_permissions

```sql
CREATE OR REPLACE FUNCTION apply_field_permissions(
    p_template TEXT,
    p_visible_fields TEXT[],
    p_editable_fields TEXT[]
) RETURNS TEXT
```

---

## Best Practices

1. **Default Deny** - Start with no permissions, grant explicitly

2. **Use Roles** - Assign permissions to roles, not individual users

3. **Test All Roles** - Verify each role sees/does what's expected

4. **Document Exceptions** - Note any special permission rules

5. **Audit Changes** - Track permission modifications

6. **Review Regularly** - Periodically review permission assignments

---

## Troubleshooting

### User Can't See Records

1. Check action permissions:
```sql
SELECT * FROM ui_action_permissions
WHERE role_id = (SELECT role_id FROM users WHERE user_id = 'user-uuid')
AND action_name = 'read';
```

2. Check RLS policies:
```sql
SELECT * FROM pg_policies WHERE tablename = 'purchase_orders';
```

### User Can't Edit Fields

1. Check field permissions:
```sql
SELECT * FROM field_permissions fp
JOIN ui_field_definitions fd ON fp.field_id = fd.field_id
WHERE fp.role_id = (SELECT role_id FROM users WHERE user_id = 'user-uuid')
AND fd.field_name = 'status';
```

### Permission Changes Not Taking Effect

1. Clear permission cache (if implemented)
2. Check for overlapping policies
3. Verify user-role assignment
