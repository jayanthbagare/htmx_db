# Database Schema Documentation

## Overview

The HTMX DB system uses PostgreSQL as its database layer. The schema is organized into three main categories:

1. **Business Domain Tables** (9 tables) - Core procurement data
2. **UI Framework Tables** (7 tables) - UI generation metadata
3. **Audit & Performance Tables** (2 tables) - Logging and metrics

## Table Summary

| Category | Table | Description |
|----------|-------|-------------|
| Business | suppliers | Vendor master data |
| Business | purchase_orders | Purchase order headers |
| Business | purchase_order_lines | PO line items |
| Business | goods_receipts | Goods receipt headers |
| Business | goods_receipt_lines | GR line items |
| Business | invoice_receipts | Vendor invoice headers |
| Business | invoice_lines | Invoice line items |
| Business | payments | Payment records |
| Business | clearing_entries | Payment-invoice reconciliation |
| UI Framework | ui_entity_types | Entity definitions |
| UI Framework | ui_field_definitions | Field metadata |
| UI Framework | htmx_templates | HTML templates |
| UI Framework | roles | User roles |
| UI Framework | users | User accounts |
| UI Framework | field_permissions | Field-level permissions |
| UI Framework | ui_action_permissions | Action-level permissions |
| Audit | ui_generation_logs | UI generation metrics |
| Audit | performance_metrics | Aggregated performance data |

---

## Business Domain Tables

### suppliers

Vendor/supplier master data.

```sql
CREATE TABLE suppliers (
    supplier_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_code VARCHAR(50) UNIQUE NOT NULL,
    supplier_name VARCHAR(200) NOT NULL,
    contact_name VARCHAR(100),
    email VARCHAR(200),
    phone VARCHAR(50),
    address TEXT,
    city VARCHAR(100),
    country VARCHAR(100),
    payment_terms_days INTEGER DEFAULT 30,
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES users(user_id)
);
```

**Key Fields:**
- `supplier_code`: Unique business identifier (e.g., "SUP-001")
- `payment_terms_days`: Default payment terms for this supplier
- `is_active`: Soft flag for supplier status
- `is_deleted`: Soft delete flag

**Indexes:**
- `idx_suppliers_code` on `supplier_code`
- `idx_suppliers_active` on `is_active` WHERE `is_deleted = FALSE`

---

### purchase_orders

Purchase order header records.

```sql
CREATE TABLE purchase_orders (
    po_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    po_number VARCHAR(50) UNIQUE NOT NULL,
    supplier_id UUID NOT NULL REFERENCES suppliers(supplier_id),
    po_date DATE NOT NULL,
    expected_delivery_date DATE,
    total_amount DECIMAL(15,2) DEFAULT 0,
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(30) DEFAULT 'draft',
    notes TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES users(user_id),
    approved_by UUID REFERENCES users(user_id),
    approved_at TIMESTAMP WITH TIME ZONE
);
```

**Status Values:**
- `draft` - Initial state, can be edited
- `submitted` - Sent for approval
- `approved` - Approved and ready for receiving
- `partially_received` - Some goods received
- `fully_received` - All goods received
- `cancelled` - Cancelled

**Valid Status Transitions:**
```
draft -> submitted -> approved -> partially_received -> fully_received
                  |                |
                  v                v
             cancelled         cancelled
```

**Indexes:**
- `idx_po_supplier` on `supplier_id`
- `idx_po_status` on `status` WHERE `is_deleted = FALSE`
- `idx_po_date` on `po_date`
- `idx_po_created_by` on `created_by`

---

### purchase_order_lines

Line items for purchase orders.

```sql
CREATE TABLE purchase_order_lines (
    line_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    po_id UUID NOT NULL REFERENCES purchase_orders(po_id),
    line_number INTEGER NOT NULL,
    item_code VARCHAR(50) NOT NULL,
    item_description TEXT,
    quantity_ordered INTEGER NOT NULL,
    unit_price DECIMAL(15,2) NOT NULL,
    line_total DECIMAL(15,2) GENERATED ALWAYS AS (quantity_ordered * unit_price) STORED,
    uom VARCHAR(20) DEFAULT 'EA',
    quantity_received INTEGER DEFAULT 0,
    quantity_invoiced INTEGER DEFAULT 0,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Key Fields:**
- `line_total`: Auto-calculated from quantity * price
- `quantity_received`: Updated by goods receipts
- `quantity_invoiced`: Updated by invoice receipts
- `uom`: Unit of measure (EA, PC, BOX, KG, LT, etc.)

**Indexes:**
- `idx_po_lines_po` on `po_id` WHERE `is_deleted = FALSE`
- `idx_po_lines_item` on `item_code`

---

### goods_receipts

Goods receipt header records.

```sql
CREATE TABLE goods_receipts (
    gr_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gr_number VARCHAR(50) UNIQUE NOT NULL,
    po_id UUID NOT NULL REFERENCES purchase_orders(po_id),
    receipt_date DATE NOT NULL,
    delivery_note_number VARCHAR(100),
    quality_status VARCHAR(30) DEFAULT 'pending',
    notes TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES users(user_id)
);
```

**Quality Status Values:**
- `pending` - Awaiting QC inspection
- `accepted` - Passed QC
- `rejected` - Failed QC

---

### invoice_receipts

Vendor invoice records with 3-way matching.

```sql
CREATE TABLE invoice_receipts (
    invoice_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    po_id UUID NOT NULL REFERENCES purchase_orders(po_id),
    vendor_invoice_number VARCHAR(100) NOT NULL,
    invoice_date DATE NOT NULL,
    due_date DATE,
    total_amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    matching_status VARCHAR(30) DEFAULT 'pending',
    variance_amount DECIMAL(15,2),
    notes TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES users(user_id)
);
```

**Matching Status Values:**
- `pending` - Awaiting matching
- `matched` - PO-GR-Invoice match within tolerance
- `variance` - Variance detected, requires approval

---

### payments

Payment records.

```sql
CREATE TABLE payments (
    payment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_number VARCHAR(50) UNIQUE NOT NULL,
    invoice_id UUID NOT NULL REFERENCES invoice_receipts(invoice_id),
    amount DECIMAL(15,2) NOT NULL,
    payment_method VARCHAR(50) NOT NULL,
    payment_date DATE NOT NULL,
    reference_number VARCHAR(100),
    status VARCHAR(30) DEFAULT 'pending',
    transaction_id VARCHAR(200),
    cleared_date DATE,
    bank_reference VARCHAR(200),
    notes TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES users(user_id)
);
```

**Payment Methods:**
- `bank_transfer`
- `check`
- `wire`
- `credit_card`

**Payment Status Values:**
- `pending` - Created, awaiting processing
- `processed` - Sent to bank/payment processor
- `cleared` - Confirmed by bank
- `failed` - Payment failed
- `cancelled` - Cancelled by user

---

## UI Framework Tables

### roles

User role definitions.

```sql
CREATE TABLE roles (
    role_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Standard Roles:**

| Role | Description | Typical Permissions |
|------|-------------|---------------------|
| admin | System administrator | Full access to all entities |
| purchase_manager | Procurement manager | Create, edit, submit POs |
| warehouse_staff | Warehouse personnel | Create goods receipts |
| accountant | Finance team | Create invoices, payments |
| viewer | Read-only access | View all entities |

---

### users

User accounts.

```sql
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(200) UNIQUE NOT NULL,
    full_name VARCHAR(200) NOT NULL,
    role_id UUID REFERENCES roles(role_id),
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

### ui_entity_types

Entity type definitions for UI generation.

```sql
CREATE TABLE ui_entity_types (
    entity_type_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_name VARCHAR(100) UNIQUE NOT NULL,
    display_name VARCHAR(200) NOT NULL,
    primary_table VARCHAR(100) NOT NULL,
    primary_key_field VARCHAR(100) DEFAULT 'id',
    icon VARCHAR(50),
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

### ui_field_definitions

Field metadata for dynamic form/list generation.

```sql
CREATE TABLE ui_field_definitions (
    field_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type_id UUID REFERENCES ui_entity_types(entity_type_id),
    field_name VARCHAR(100) NOT NULL,
    display_label VARCHAR(200),
    data_type VARCHAR(50) NOT NULL,
    field_order INTEGER DEFAULT 0,
    is_required BOOLEAN DEFAULT FALSE,
    validation_rule JSONB,
    lookup_entity VARCHAR(100),
    lookup_display_field VARCHAR(100),
    default_value TEXT,
    help_text TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(entity_type_id, field_name)
);
```

**Data Types:**
- `text` - Single line text input
- `textarea` - Multi-line text
- `number` - Numeric input
- `decimal` - Decimal number
- `date` - Date picker
- `datetime` - Date and time
- `select` - Dropdown selection
- `lookup` - Related entity lookup
- `boolean` - Checkbox

---

### htmx_templates

HTML templates for UI generation.

```sql
CREATE TABLE htmx_templates (
    template_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type_id UUID REFERENCES ui_entity_types(entity_type_id),
    view_type VARCHAR(50) NOT NULL,
    template_name VARCHAR(100) NOT NULL,
    base_template TEXT NOT NULL,
    version INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(entity_type_id, view_type, version)
);
```

**View Types:**
- `list` - Table/list view
- `form_create` - Create form
- `form_edit` - Edit form
- `form_view` - View-only form
- `filter_panel` - Filter controls

---

### field_permissions

Field-level access control.

```sql
CREATE TABLE field_permissions (
    permission_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID REFERENCES roles(role_id),
    field_id UUID REFERENCES ui_field_definitions(field_id),
    list_visible BOOLEAN DEFAULT TRUE,
    list_editable BOOLEAN DEFAULT FALSE,
    form_create_visible BOOLEAN DEFAULT TRUE,
    form_create_editable BOOLEAN DEFAULT TRUE,
    form_edit_visible BOOLEAN DEFAULT TRUE,
    form_edit_editable BOOLEAN DEFAULT TRUE,
    form_view_visible BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(role_id, field_id)
);
```

---

### ui_action_permissions

Action-level access control.

```sql
CREATE TABLE ui_action_permissions (
    action_permission_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID REFERENCES roles(role_id),
    entity_type_id UUID REFERENCES ui_entity_types(entity_type_id),
    action_name VARCHAR(50) NOT NULL,
    is_allowed BOOLEAN DEFAULT FALSE,
    condition_rule JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(role_id, entity_type_id, action_name)
);
```

**Standard Actions:**
- `read` - View records
- `create` - Create new records
- `edit` - Modify existing records
- `delete` - Soft delete records
- `approve` - Approve submissions
- `submit` - Submit for approval
- `cancel` - Cancel records

---

## Audit & Performance Tables

### ui_generation_logs

Logs every UI generation request for performance analysis.

```sql
CREATE TABLE ui_generation_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    entity_type VARCHAR(100),
    view_type VARCHAR(50),
    duration_ms INTEGER,
    cache_hit BOOLEAN,
    data_row_count INTEGER,
    error_message TEXT,
    request_params JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

### performance_metrics

Aggregated performance metrics.

```sql
CREATE TABLE performance_metrics (
    metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type VARCHAR(100),
    view_type VARCHAR(50),
    time_bucket TIMESTAMP WITH TIME ZONE,
    request_count INTEGER DEFAULT 0,
    avg_response_time_ms NUMERIC(10,2),
    p95_response_time_ms NUMERIC(10,2),
    p99_response_time_ms NUMERIC(10,2),
    error_count INTEGER DEFAULT 0,
    cache_hit_rate NUMERIC(5,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

## Relationships

```
suppliers
    └── purchase_orders (1:N)
            ├── purchase_order_lines (1:N)
            ├── goods_receipts (1:N)
            │       └── goods_receipt_lines (1:N)
            └── invoice_receipts (1:N)
                    ├── invoice_lines (1:N)
                    └── payments (1:N)
                            └── clearing_entries (1:N)

roles
    ├── users (1:N)
    ├── field_permissions (1:N)
    └── ui_action_permissions (1:N)

ui_entity_types
    ├── ui_field_definitions (1:N)
    │       └── field_permissions (1:N)
    ├── htmx_templates (1:N)
    └── ui_action_permissions (1:N)
```

---

## Conventions

### Naming Conventions

- Tables: lowercase, underscore-separated plurals (`purchase_orders`)
- Primary keys: `<singular_entity>_id` (`po_id`, `supplier_id`)
- Foreign keys: Same as referenced primary key
- Indexes: `idx_<table>_<column(s)>`
- Unique constraints: Inline or named `uq_<table>_<column(s)>`

### Standard Columns

All business tables include:
- `is_deleted` - Soft delete flag (BOOLEAN)
- `created_at` - Creation timestamp (TIMESTAMP WITH TIME ZONE)
- `updated_at` - Last update timestamp (TIMESTAMP WITH TIME ZONE)
- `created_by` - User who created the record (UUID FK)

### Data Types

- Primary Keys: UUID (using `gen_random_uuid()`)
- Money: DECIMAL(15,2)
- Dates: DATE or TIMESTAMP WITH TIME ZONE
- Status: VARCHAR(30) with CHECK constraint
- Codes: VARCHAR with UNIQUE constraint

---

## Migrations

Migration files are located in `database/migrations/`:

1. `001_create_business_domain.sql` - Business tables
2. `002_create_ui_framework.sql` - UI framework tables
3. `003_create_audit_tables.sql` - Logging tables
4. `004_create_triggers_sequences.sql` - Triggers and sequences
5. `005_create_rls_policies.sql` - Row-level security
6. `006_initial_seed_data.sql` - Initial data

Run migrations in order to set up the database.
