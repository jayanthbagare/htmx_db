# Adding New Entities Guide

This guide explains how to add new business entities to the HTMX DB system.

## Overview

Adding a new entity involves these steps:

1. Create the database table(s)
2. Register the entity type
3. Define field metadata
4. Create templates
5. Set up permissions
6. Add business logic functions (optional)
7. Test the new entity

## Step-by-Step Guide

### Step 1: Create Database Table(s)

Create a migration file in `database/migrations/`:

```sql
-- XXX_create_contracts.sql

CREATE TABLE contracts (
    contract_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_number VARCHAR(50) UNIQUE NOT NULL,
    supplier_id UUID REFERENCES suppliers(supplier_id),
    title VARCHAR(200) NOT NULL,
    description TEXT,
    start_date DATE NOT NULL,
    end_date DATE,
    total_value DECIMAL(15,2),
    status VARCHAR(30) DEFAULT 'draft',
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES users(user_id)
);

-- Add indexes
CREATE INDEX idx_contracts_supplier ON contracts(supplier_id);
CREATE INDEX idx_contracts_status ON contracts(status) WHERE is_deleted = FALSE;
CREATE INDEX idx_contracts_dates ON contracts(start_date, end_date);

-- Add updated_at trigger
CREATE TRIGGER set_contracts_updated_at
    BEFORE UPDATE ON contracts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

**Conventions:**
- Use UUID for primary key
- Include `is_deleted`, `created_at`, `updated_at`, `created_by`
- Add status field with CHECK constraint if needed
- Create indexes for foreign keys and filter fields

---

### Step 2: Register Entity Type

Insert the entity definition:

```sql
INSERT INTO ui_entity_types (
    entity_name,
    display_name,
    primary_table,
    primary_key_field,
    icon,
    description
) VALUES (
    'contract',
    'Contracts',
    'contracts',
    'contract_id',
    'file-contract',
    'Vendor contracts and agreements'
);
```

---

### Step 3: Define Field Metadata

Define each field for UI generation:

```sql
-- Get entity type ID
DO $$
DECLARE
    v_entity_id UUID;
BEGIN
    SELECT entity_type_id INTO v_entity_id
    FROM ui_entity_types
    WHERE entity_name = 'contract';

    -- Contract Number
    INSERT INTO ui_field_definitions (
        entity_type_id, field_name, display_label, data_type,
        field_order, is_required, validation_rule
    ) VALUES (
        v_entity_id, 'contract_number', 'Contract Number', 'text',
        1, true, '{"pattern": "^CON-[0-9]{6}$"}'
    );

    -- Supplier (lookup)
    INSERT INTO ui_field_definitions (
        entity_type_id, field_name, display_label, data_type,
        field_order, is_required, lookup_entity, lookup_display_field
    ) VALUES (
        v_entity_id, 'supplier_id', 'Supplier', 'lookup',
        2, true, 'supplier', 'supplier_name'
    );

    -- Title
    INSERT INTO ui_field_definitions (
        entity_type_id, field_name, display_label, data_type,
        field_order, is_required
    ) VALUES (
        v_entity_id, 'title', 'Title', 'text',
        3, true
    );

    -- Description
    INSERT INTO ui_field_definitions (
        entity_type_id, field_name, display_label, data_type,
        field_order
    ) VALUES (
        v_entity_id, 'description', 'Description', 'textarea',
        4
    );

    -- Start Date
    INSERT INTO ui_field_definitions (
        entity_type_id, field_name, display_label, data_type,
        field_order, is_required
    ) VALUES (
        v_entity_id, 'start_date', 'Start Date', 'date',
        5, true
    );

    -- End Date
    INSERT INTO ui_field_definitions (
        entity_type_id, field_name, display_label, data_type,
        field_order
    ) VALUES (
        v_entity_id, 'end_date', 'End Date', 'date',
        6
    );

    -- Total Value
    INSERT INTO ui_field_definitions (
        entity_type_id, field_name, display_label, data_type,
        field_order
    ) VALUES (
        v_entity_id, 'total_value', 'Total Value', 'decimal',
        7
    );

    -- Status
    INSERT INTO ui_field_definitions (
        entity_type_id, field_name, display_label, data_type,
        field_order, default_value
    ) VALUES (
        v_entity_id, 'status', 'Status', 'select',
        8, 'draft'
    );
END $$;
```

**Data Types:**
| Type | Description | HTML Input |
|------|-------------|------------|
| text | Single line text | `<input type="text">` |
| textarea | Multi-line text | `<textarea>` |
| number | Integer | `<input type="number">` |
| decimal | Decimal number | `<input type="number" step="0.01">` |
| date | Date | `<input type="date">` |
| datetime | Date and time | `<input type="datetime-local">` |
| select | Dropdown | `<select>` |
| lookup | Related entity | `<select>` with HTMX lookup |
| boolean | Checkbox | `<input type="checkbox">` |

---

### Step 4: Create Templates

Create HTML templates for each view type:

```sql
DO $$
DECLARE
    v_entity_id UUID;
BEGIN
    SELECT entity_type_id INTO v_entity_id
    FROM ui_entity_types
    WHERE entity_name = 'contract';

    -- List template
    INSERT INTO htmx_templates (
        entity_type_id, view_type, template_name, base_template
    ) VALUES (
        v_entity_id,
        'list',
        'contract_list',
        '
<div class="entity-list">
    <div class="list-header">
        <h2>Contracts</h2>
        {{#if can_create}}
        <button hx-get="/ui/contract/form/create" hx-target="#modal">
            New Contract
        </button>
        {{/if}}
    </div>

    <table class="data-table">
        <thead>
            <tr>
                <th>Contract #</th>
                <th>Title</th>
                <th>Supplier</th>
                <th>Start Date</th>
                <th>End Date</th>
                <th>Value</th>
                <th>Status</th>
            </tr>
        </thead>
        <tbody>
            {{#each records}}
            <tr hx-get="/ui/contract/form/view?id={{contract_id}}" hx-target="#modal">
                <td>{{contract_number}}</td>
                <td>{{title}}</td>
                <td>{{supplier.supplier_name}}</td>
                <td>{{start_date}}</td>
                <td>{{end_date}}</td>
                <td>{{total_value}}</td>
                <td><span class="status-badge status-{{status}}">{{status}}</span></td>
            </tr>
            {{/each}}
        </tbody>
    </table>

    {{> pagination}}
</div>
        '
    );

    -- Create form template
    INSERT INTO htmx_templates (
        entity_type_id, view_type, template_name, base_template
    ) VALUES (
        v_entity_id,
        'form_create',
        'contract_form_create',
        '
<form hx-post="/api/contract" hx-target="#main-content">
    <h2>New Contract</h2>

    {{#each fields}}
    <div class="form-field">
        <label for="{{field_name}}">{{display_label}}</label>
        {{> field_input}}
    </div>
    {{/each}}

    <div class="form-actions">
        <button type="submit">Create Contract</button>
        <button type="button" onclick="closeModal()">Cancel</button>
    </div>
</form>
        '
    );

    -- Edit and view templates follow similar pattern...
END $$;
```

See [TEMPLATE_GUIDE.md](TEMPLATE_GUIDE.md) for complete template syntax.

---

### Step 5: Set Up Permissions

Define permissions for each role:

```sql
DO $$
DECLARE
    v_entity_id UUID;
    v_admin_role UUID;
    v_manager_role UUID;
    v_viewer_role UUID;
BEGIN
    SELECT entity_type_id INTO v_entity_id
    FROM ui_entity_types WHERE entity_name = 'contract';

    SELECT role_id INTO v_admin_role FROM roles WHERE role_name = 'admin';
    SELECT role_id INTO v_manager_role FROM roles WHERE role_name = 'purchase_manager';
    SELECT role_id INTO v_viewer_role FROM roles WHERE role_name = 'viewer';

    -- Action permissions for admin
    INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed)
    VALUES
        (v_admin_role, v_entity_id, 'read', true),
        (v_admin_role, v_entity_id, 'create', true),
        (v_admin_role, v_entity_id, 'edit', true),
        (v_admin_role, v_entity_id, 'delete', true),
        (v_admin_role, v_entity_id, 'approve', true);

    -- Action permissions for manager
    INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed)
    VALUES
        (v_manager_role, v_entity_id, 'read', true),
        (v_manager_role, v_entity_id, 'create', true),
        (v_manager_role, v_entity_id, 'edit', true);

    -- Action permissions for viewer
    INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed)
    VALUES
        (v_viewer_role, v_entity_id, 'read', true);

    -- Field permissions (set for each field...)
END $$;
```

See [PERMISSIONS_GUIDE.md](PERMISSIONS_GUIDE.md) for complete permission setup.

---

### Step 6: Add Business Logic (Optional)

Create custom functions for entity-specific logic:

```sql
-- Create contract function
CREATE OR REPLACE FUNCTION create_contract(
    p_user_id UUID,
    p_supplier_id UUID,
    p_title VARCHAR,
    p_description TEXT,
    p_start_date DATE,
    p_end_date DATE,
    p_total_value DECIMAL
) RETURNS JSONB AS $$
DECLARE
    v_contract_id UUID;
    v_contract_number VARCHAR;
BEGIN
    -- Check permissions
    IF NOT can_user_perform_action(p_user_id, 'contract', 'create') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Permission denied');
    END IF;

    -- Generate contract number
    v_contract_number := 'CON-' || LPAD(nextval('contract_number_seq')::TEXT, 6, '0');

    -- Insert record
    INSERT INTO contracts (
        contract_number, supplier_id, title, description,
        start_date, end_date, total_value, created_by
    ) VALUES (
        v_contract_number, p_supplier_id, p_title, p_description,
        p_start_date, p_end_date, p_total_value, p_user_id
    )
    RETURNING contract_id INTO v_contract_id;

    RETURN jsonb_build_object(
        'success', true,
        'contract_id', v_contract_id,
        'contract_number', v_contract_number
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

### Step 7: Test the New Entity

1. **Database Test:**
```sql
-- Test create function
SELECT create_contract(
    '00000000-0000-0000-0000-000000000100',
    (SELECT supplier_id FROM suppliers LIMIT 1),
    'Test Contract',
    'Description',
    CURRENT_DATE,
    CURRENT_DATE + INTERVAL '1 year',
    50000.00
);
```

2. **API Test:**
```bash
curl -X GET "http://localhost:3000/ui/contract/list" \
  -H "x-demo-user: 00000000-0000-0000-0000-000000000100"
```

3. **Add to navigation:**
Update `src/routes/ui.js` to include the new entity in the nav.

---

## Checklist

- [ ] Database table created with all standard columns
- [ ] Indexes created for foreign keys and filter fields
- [ ] Entity type registered in `ui_entity_types`
- [ ] All fields defined in `ui_field_definitions`
- [ ] Templates created for list, create, edit, view
- [ ] Action permissions set for all roles
- [ ] Field permissions set for all roles
- [ ] Business logic functions created (if needed)
- [ ] Tests written and passing
- [ ] Entity added to navigation

---

## Tips

1. **Use existing entities as templates** - Copy and modify existing entity definitions

2. **Start simple** - Begin with basic CRUD, add workflow later

3. **Test incrementally** - Verify each step before proceeding

4. **Follow naming conventions** - Use consistent table/field names

5. **Document special logic** - Add comments for non-obvious behavior
