# Database-Driven HTMX UI Generation System - Implementation Prompt

## Project Overview
Build a complete database-centric HTMX generation system using Supabase (PostgreSQL) that demonstrates dynamic UI generation directly from the database layer. The system should handle a procurement workflow: Purchase Order → Goods Receipt → Invoice Receipt → Payment → Clearing.

## Core Architecture Requirements

### 1. Database Schema Design

#### A. Business Domain Tables
Create tables for the procurement workflow with the following entities:

**suppliers table:**
- supplier_id (UUID, PK)
- supplier_code (VARCHAR(50), UNIQUE)
- supplier_name (VARCHAR(200))
- contact_email (VARCHAR(100))
- contact_phone (VARCHAR(20))
- payment_terms_days (INTEGER)
- is_active (BOOLEAN)
- created_at (TIMESTAMPTZ)
- updated_at (TIMESTAMPTZ)
- created_by (UUID, FK to users)

**purchase_orders table:**
- po_id (UUID, PK)
- po_number (VARCHAR(50), UNIQUE)
- supplier_id (UUID, FK to suppliers)
- po_date (DATE)
- expected_delivery_date (DATE)
- total_amount (DECIMAL(15,2))
- currency (VARCHAR(3))
- status (VARCHAR(20)) -- 'draft', 'submitted', 'approved', 'partially_received', 'fully_received', 'cancelled'
- notes (TEXT)
- is_deleted (BOOLEAN, default FALSE)
- created_at (TIMESTAMPTZ)
- updated_at (TIMESTAMPTZ)
- created_by (UUID, FK to users)
- approved_by (UUID, FK to users, nullable)
- approved_at (TIMESTAMPTZ, nullable)

**purchase_order_lines table:**
- po_line_id (UUID, PK)
- po_id (UUID, FK to purchase_orders)
- line_number (INTEGER)
- item_code (VARCHAR(100))
- item_description (TEXT)
- quantity_ordered (DECIMAL(10,2))
- unit_price (DECIMAL(15,2))
- line_total (DECIMAL(15,2))
- quantity_received (DECIMAL(10,2), default 0)
- quantity_invoiced (DECIMAL(10,2), default 0)
- uom (VARCHAR(20)) -- unit of measure
- is_deleted (BOOLEAN, default FALSE)

**goods_receipts table:**
- gr_id (UUID, PK)
- gr_number (VARCHAR(50), UNIQUE)
- po_id (UUID, FK to purchase_orders)
- receipt_date (DATE)
- received_by (UUID, FK to users)
- warehouse_location (VARCHAR(100))
- status (VARCHAR(20)) -- 'draft', 'confirmed', 'cancelled'
- notes (TEXT)
- is_deleted (BOOLEAN, default FALSE)
- created_at (TIMESTAMPTZ)
- updated_at (TIMESTAMPTZ)

**goods_receipt_lines table:**
- gr_line_id (UUID, PK)
- gr_id (UUID, FK to goods_receipts)
- po_line_id (UUID, FK to purchase_order_lines)
- quantity_received (DECIMAL(10,2))
- quality_status (VARCHAR(20)) -- 'accepted', 'rejected', 'pending_inspection'
- notes (TEXT)

**invoice_receipts table:**
- invoice_id (UUID, PK)
- invoice_number (VARCHAR(50), UNIQUE)
- supplier_invoice_number (VARCHAR(50))
- po_id (UUID, FK to purchase_orders)
- invoice_date (DATE)
- due_date (DATE)
- total_amount (DECIMAL(15,2))
- tax_amount (DECIMAL(15,2))
- status (VARCHAR(20)) -- 'received', 'verified', 'approved', 'disputed', 'cancelled'
- matching_status (VARCHAR(20)) -- 'pending', 'matched', 'variance'
- is_deleted (BOOLEAN, default FALSE)
- created_at (TIMESTAMPTZ)
- updated_at (TIMESTAMPTZ)
- verified_by (UUID, FK to users, nullable)
- approved_by (UUID, FK to users, nullable)

**invoice_lines table:**
- invoice_line_id (UUID, PK)
- invoice_id (UUID, FK to invoice_receipts)
- po_line_id (UUID, FK to purchase_order_lines)
- gr_line_id (UUID, FK to goods_receipt_lines, nullable)
- quantity_invoiced (DECIMAL(10,2))
- unit_price (DECIMAL(15,2))
- line_total (DECIMAL(15,2))
- variance_amount (DECIMAL(15,2))

**payments table:**
- payment_id (UUID, PK)
- payment_number (VARCHAR(50), UNIQUE)
- invoice_id (UUID, FK to invoice_receipts)
- payment_date (DATE)
- payment_method (VARCHAR(50)) -- 'bank_transfer', 'check', 'wire', 'credit_card'
- payment_amount (DECIMAL(15,2))
- reference_number (VARCHAR(100))
- status (VARCHAR(20)) -- 'pending', 'processed', 'cleared', 'failed', 'cancelled'
- is_deleted (BOOLEAN, default FALSE)
- created_at (TIMESTAMPTZ)
- updated_at (TIMESTAMPTZ)
- processed_by (UUID, FK to users)

**clearing_entries table:**
- clearing_id (UUID, PK)
- payment_id (UUID, FK to payments)
- invoice_id (UUID, FK to invoice_receipts)
- cleared_amount (DECIMAL(15,2))
- clearing_date (DATE)
- status (VARCHAR(20)) -- 'pending', 'cleared', 'reconciled'
- reconciliation_reference (VARCHAR(100))
- notes (TEXT)
- is_deleted (BOOLEAN, default FALSE)
- created_at (TIMESTAMPTZ)

#### B. UI Generation Framework Tables

**ui_entity_types table:**
- entity_type_id (UUID, PK)
- entity_name (VARCHAR(100), UNIQUE) -- 'purchase_order', 'goods_receipt', etc.
- display_name (VARCHAR(200))
- primary_table (VARCHAR(100))
- icon_class (VARCHAR(100)) -- for UI icons
- description (TEXT)

**ui_field_definitions table:**
- field_id (UUID, PK)
- entity_type_id (UUID, FK to ui_entity_types)
- field_name (VARCHAR(100))
- display_label (VARCHAR(200))
- data_type (VARCHAR(50)) -- 'text', 'number', 'date', 'select', 'textarea', 'lookup'
- field_order (INTEGER)
- is_required (BOOLEAN)
- validation_rule (TEXT) -- JSON string with validation rules
- lookup_entity (VARCHAR(100), nullable) -- for foreign key fields
- lookup_display_field (VARCHAR(100), nullable)
- default_value (TEXT)
- help_text (TEXT)

**htmx_templates table:**
- template_id (UUID, PK)
- entity_type_id (UUID, FK to ui_entity_types)
- view_type (VARCHAR(50)) -- 'list', 'form_create', 'form_edit', 'form_view', 'filter_panel'
- template_name (VARCHAR(200))
- base_template (TEXT) -- HTMX/HTML template with placeholders
- version (INTEGER)
- is_active (BOOLEAN)
- created_at (TIMESTAMPTZ)
- updated_at (TIMESTAMPTZ)

**roles table:**
- role_id (UUID, PK)
- role_name (VARCHAR(100), UNIQUE)
- description (TEXT)
- is_active (BOOLEAN)

**users table:**
- user_id (UUID, PK)
- username (VARCHAR(100), UNIQUE)
- email (VARCHAR(200), UNIQUE)
- full_name (VARCHAR(200))
- role_id (UUID, FK to roles)
- is_active (BOOLEAN)
- created_at (TIMESTAMPTZ)

**field_permissions table:**
- permission_id (UUID, PK)
- role_id (UUID, FK to roles)
- entity_type_id (UUID, FK to ui_entity_types)
- field_id (UUID, FK to ui_field_definitions)
- list_visible (BOOLEAN, default TRUE)
- list_editable (BOOLEAN, default FALSE)
- form_create_visible (BOOLEAN, default TRUE)
- form_create_editable (BOOLEAN, default TRUE)
- form_edit_visible (BOOLEAN, default TRUE)
- form_edit_editable (BOOLEAN, default TRUE)
- form_view_visible (BOOLEAN, default TRUE)
- UNIQUE(role_id, field_id)

**ui_action_permissions table:**
- action_permission_id (UUID, PK)
- role_id (UUID, FK to roles)
- entity_type_id (UUID, FK to ui_entity_types)
- action_name (VARCHAR(50)) -- 'create', 'edit', 'delete', 'approve', 'submit', 'cancel'
- is_allowed (BOOLEAN)
- condition_rule (TEXT) -- JSON with conditional logic (e.g., can only edit own records)
- UNIQUE(role_id, entity_type_id, action_name)

#### C. Audit and Performance Tables

**ui_generation_logs table:**
- log_id (UUID, PK)
- request_id (UUID)
- user_id (UUID, FK to users)
- entity_type (VARCHAR(100))
- view_type (VARCHAR(50))
- generation_start_time (TIMESTAMPTZ)
- generation_end_time (TIMESTAMPTZ)
- duration_ms (INTEGER)
- template_cache_hit (BOOLEAN)
- permission_cache_hit (BOOLEAN)
- data_row_count (INTEGER)
- output_size_bytes (INTEGER)
- error_message (TEXT, nullable)

**performance_metrics table:**
- metric_id (UUID, PK)
- metric_timestamp (TIMESTAMPTZ)
- endpoint_name (VARCHAR(200))
- avg_response_time_ms (DECIMAL(10,2))
- p95_response_time_ms (DECIMAL(10,2))
- p99_response_time_ms (DECIMAL(10,2))
- request_count (INTEGER)
- error_count (INTEGER)

### 2. Core Database Functions

#### A. Template Rendering Engine
```sql
CREATE OR REPLACE FUNCTION render_template(
    p_template TEXT,
    p_data JSONB
) RETURNS TEXT AS $$
-- Function to replace {{field_name}} placeholders with actual values
-- Supports nested JSON paths like {{supplier.name}}
-- Returns rendered HTML/HTMX string
$$;

CREATE OR REPLACE FUNCTION apply_field_permissions(
    p_template TEXT,
    p_visible_fields TEXT[],
    p_editable_fields TEXT[]
) RETURNS TEXT AS $$
-- Removes fields from template that user doesn't have permission to see
-- Adds 'disabled' attribute to non-editable fields
-- Returns modified template
$$;
```

#### B. Permission Resolution Functions
```sql
CREATE OR REPLACE FUNCTION get_user_field_permissions(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_view_type VARCHAR -- 'list', 'form_create', 'form_edit', 'form_view'
) RETURNS TABLE (
    field_name VARCHAR,
    is_visible BOOLEAN,
    is_editable BOOLEAN
) AS $$
-- Joins user -> role -> field_permissions
-- Returns which fields are visible/editable for this user and view type
-- Should use aggressive caching
$$;

CREATE OR REPLACE FUNCTION can_user_perform_action(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_action_name VARCHAR,
    p_record_data JSONB DEFAULT NULL
) RETURNS BOOLEAN AS $$
-- Checks ui_action_permissions
-- Evaluates condition_rule if present (e.g., user can only edit own records)
-- Returns TRUE/FALSE
$$;
```

#### C. Data Fetching with Security
```sql
CREATE OR REPLACE FUNCTION fetch_list_data(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_filters JSONB DEFAULT '{}'::JSONB,
    p_sort_field VARCHAR DEFAULT NULL,
    p_sort_direction VARCHAR DEFAULT 'ASC',
    p_page_size INTEGER DEFAULT 50,
    p_page_number INTEGER DEFAULT 1
) RETURNS TABLE (
    total_count BIGINT,
    data JSONB
) AS $$
-- Dynamically builds query based on entity_type
-- Applies filters from p_filters JSON
-- Joins related tables for lookups
-- Applies row-level security if needed
-- Returns paginated results as JSONB array
$$;

CREATE OR REPLACE FUNCTION fetch_form_data(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_id UUID
) RETURNS JSONB AS $$
-- Fetches single record for edit/view form
-- Includes related lookup data
-- Returns full record as JSONB
$$;
```

#### D. Main HTMX Generation Functions
```sql
CREATE OR REPLACE FUNCTION generate_htmx_list(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_filters JSONB DEFAULT '{}'::JSONB,
    p_sort_field VARCHAR DEFAULT NULL,
    p_sort_direction VARCHAR DEFAULT 'ASC',
    p_page INTEGER DEFAULT 1
) RETURNS TEXT AS $$
DECLARE
    v_template TEXT;
    v_permissions RECORD;
    v_data JSONB;
    v_rendered TEXT;
    v_start_time TIMESTAMPTZ;
    v_request_id UUID;
BEGIN
    v_start_time := clock_timestamp();
    v_request_id := gen_random_uuid();
    
    -- 1. Fetch base template
    SELECT base_template INTO v_template
    FROM htmx_templates t
    JOIN ui_entity_types e ON t.entity_type_id = e.entity_type_id
    WHERE e.entity_name = p_entity_type 
    AND t.view_type = 'list'
    AND t.is_active = TRUE
    ORDER BY version DESC
    LIMIT 1;
    
    IF v_template IS NULL THEN
        RAISE EXCEPTION 'No template found for entity: %', p_entity_type;
    END IF;
    
    -- 2. Get user's field permissions
    -- (Build arrays of visible/editable fields)
    
    -- 3. Apply permission filtering to template
    -- v_template := apply_field_permissions(v_template, visible_fields, editable_fields);
    
    -- 4. Fetch data
    SELECT data INTO v_data
    FROM fetch_list_data(
        p_user_id, 
        p_entity_type, 
        p_filters, 
        p_sort_field, 
        p_sort_direction, 
        50, 
        p_page
    );
    
    -- 5. Render template with data
    v_rendered := render_template(v_template, v_data);
    
    -- 6. Log performance
    INSERT INTO ui_generation_logs (
        log_id, request_id, user_id, entity_type, view_type,
        generation_start_time, generation_end_time,
        duration_ms, data_row_count
    ) VALUES (
        gen_random_uuid(), v_request_id, p_user_id, p_entity_type, 'list',
        v_start_time, clock_timestamp(),
        EXTRACT(MILLISECONDS FROM clock_timestamp() - v_start_time),
        jsonb_array_length(v_data)
    );
    
    RETURN v_rendered;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_htmx_form(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_form_type VARCHAR, -- 'create', 'edit', 'view'
    p_record_id UUID DEFAULT NULL
) RETURNS TEXT AS $$
-- Similar structure to generate_htmx_list
-- Fetches form template
-- Applies permissions
-- Loads record data if p_record_id provided
-- Renders form HTML
$$;
```

#### E. Workflow-Specific Business Logic
```sql
CREATE OR REPLACE FUNCTION create_purchase_order(
    p_user_id UUID,
    p_po_data JSONB
) RETURNS UUID AS $$
-- Creates PO header and lines
-- Sets status to 'draft'
-- Returns po_id
$$;

CREATE OR REPLACE FUNCTION submit_purchase_order(
    p_user_id UUID,
    p_po_id UUID
) RETURNS BOOLEAN AS $$
-- Validates PO is complete
-- Changes status to 'submitted'
-- Records submission timestamp
$$;

CREATE OR REPLACE FUNCTION approve_purchase_order(
    p_user_id UUID,
    p_po_id UUID
) RETURNS BOOLEAN AS $$
-- Checks user has approval permission
-- Changes status to 'approved'
-- Records approver and timestamp
$$;

CREATE OR REPLACE FUNCTION create_goods_receipt(
    p_user_id UUID,
    p_po_id UUID,
    p_gr_data JSONB
) RETURNS UUID AS $$
-- Creates GR header and lines
-- Updates purchase_order_lines.quantity_received
-- Updates PO status if fully received
-- Returns gr_id
$$;

CREATE OR REPLACE FUNCTION create_invoice_receipt(
    p_user_id UUID,
    p_invoice_data JSONB
) RETURNS UUID AS $$
-- Creates invoice header and lines
-- Performs 3-way matching (PO, GR, Invoice)
-- Sets matching_status
-- Updates purchase_order_lines.quantity_invoiced
-- Returns invoice_id
$$;

CREATE OR REPLACE FUNCTION create_payment(
    p_user_id UUID,
    p_payment_data JSONB
) RETURNS UUID AS $$
-- Creates payment record
-- Validates against invoice amount
-- Sets status to 'pending'
-- Returns payment_id
$$;

CREATE OR REPLACE FUNCTION process_payment(
    p_user_id UUID,
    p_payment_id UUID
) RETURNS BOOLEAN AS $$
-- Updates payment status to 'processed'
-- Creates clearing entry
-- Returns success
$$;

CREATE OR REPLACE FUNCTION clear_payment(
    p_user_id UUID,
    p_clearing_id UUID
) RETURNS BOOLEAN AS $$
-- Updates clearing status to 'cleared'
-- Updates payment status to 'cleared'
-- Updates invoice status
$$;
```

### 3. Implementation Tasks

#### Phase 1: Database Setup
1. Create all tables with proper indexes
2. Set up foreign key constraints
3. Create database roles (app_read, app_write, app_admin)
4. Implement Row Level Security (RLS) policies on Supabase
5. Create database triggers for updated_at timestamps

#### Phase 2: Template System
1. Implement render_template function with placeholder replacement
2. Implement apply_field_permissions function
3. Create sample HTMX templates for each view type
4. Store templates in htmx_templates table
5. Test template rendering with various data scenarios

#### Phase 3: Permission System
1. Implement get_user_field_permissions function
2. Implement can_user_perform_action function
3. Seed sample roles: 'admin', 'purchase_manager', 'warehouse_staff', 'accountant', 'viewer'
4. Seed field permissions for each role
5. Test permission resolution with different user roles

#### Phase 4: Data Layer
1. Implement fetch_list_data with dynamic query building
2. Implement fetch_form_data
3. Add filtering, sorting, and pagination logic
4. Optimize with appropriate indexes
5. Test with various filter combinations

#### Phase 5: HTMX Generation
1. Implement generate_htmx_list function
2. Implement generate_htmx_form function
3. Add caching layer for templates and permissions
4. Implement logging to ui_generation_logs
5. Test end-to-end generation

#### Phase 6: Business Logic
1. Implement all workflow functions (create_purchase_order, etc.)
2. Add validation logic
3. Implement status transitions
4. Add error handling
5. Test complete procurement workflow

#### Phase 7: API Layer
Create minimal Express.js/Fastify API middleware:
```javascript
// server.js
app.get('/ui/:entity_type/list', async (req, res) => {
    const { data, error } = await supabase.rpc('generate_htmx_list', {
        p_user_id: req.user.id,
        p_entity_type: req.params.entity_type,
        p_filters: req.query.filters || {},
        p_page: req.query.page || 1
    });
    
    if (error) return res.status(500).send(error.message);
    res.setHeader('Content-Type', 'text/html');
    res.send(data);
});

app.get('/ui/:entity_type/form/:form_type', async (req, res) => {
    const { data, error } = await supabase.rpc('generate_htmx_form', {
        p_user_id: req.user.id,
        p_entity_type: req.params.entity_type,
        p_form_type: req.params.form_type,
        p_record_id: req.query.id || null
    });
    
    if (error) return res.status(500).send(error.message);
    res.setHeader('Content-Type', 'text/html');
    res.send(data);
});
```

### 4. Test Data Generation

Create comprehensive seed data:

#### A. Master Data (100 records each)
- 100 suppliers
- 5 roles with complete permission matrices
- 50 users across different roles
- UI entity definitions for all 6 entities
- Field definitions (50-100 fields total)
- HTMX templates for all view types
- Complete field_permissions matrix

#### B. Transactional Data (Progressive Volumes)
**Small Dataset (100 records):**
- 100 Purchase Orders with 1-10 lines each
- 80 Goods Receipts (80% of POs)
- 70 Invoice Receipts (70% of POs)
- 50 Payments (50% of invoices)
- 40 Clearing Entries (40% of payments)

**Medium Dataset (1,000 records):**
- 1,000 Purchase Orders
- 800 Goods Receipts
- 700 Invoice Receipts
- 500 Payments
- 400 Clearing Entries

**Large Dataset (10,000 records):**
- 10,000 Purchase Orders
- 8,000 Goods Receipts
- 7,000 Invoice Receipts
- 5,000 Payments
- 4,000 Clearing Entries

**Stress Dataset (100,000 records):**
- 100,000 Purchase Orders
- 80,000 Goods Receipts
- 70,000 Invoice Receipts
- 50,000 Payments
- 40,000 Clearing Entries

### 5. Comprehensive Test Cases

#### A. Functional Tests

**TEST-001: Template Retrieval**
- **Objective**: Verify correct template is fetched based on entity and view type
- **Steps**:
  1. Call generate_htmx_list for 'purchase_order'
  2. Verify correct template is used
  3. Test with non-existent entity (should raise exception)
- **Expected**: Correct template retrieved, errors handled properly

**TEST-002: Permission Filtering - Admin Role**
- **Objective**: Admin sees all fields
- **Setup**: User with 'admin' role
- **Steps**:
  1. Generate list view for purchase_orders
  2. Verify all fields present
  3. Generate create form
  4. Verify all fields are editable
- **Expected**: All fields visible and editable

**TEST-003: Permission Filtering - Viewer Role**
- **Objective**: Viewer has read-only access
- **Setup**: User with 'viewer' role
- **Steps**:
  1. Generate list view
  2. Verify fields are visible but no edit buttons
  3. Attempt to generate create form (should be blocked)
- **Expected**: Read access granted, write access denied

**TEST-004: Permission Filtering - Purchase Manager**
- **Objective**: Purchase manager can create/edit POs but not approve invoices
- **Setup**: User with 'purchase_manager' role
- **Steps**:
  1. Create purchase order
  2. Edit purchase order
  3. Attempt to approve invoice (should fail)
- **Expected**: PO operations succeed, invoice approval denied

**TEST-005: Field-Level Permissions**
- **Objective**: Certain fields hidden based on role
- **Setup**: Configure 'total_amount' field as hidden for 'warehouse_staff'
- **Steps**:
  1. Generate PO list as warehouse_staff user
  2. Verify 'total_amount' column not present
  3. Generate same list as admin
  4. Verify 'total_amount' column present
- **Expected**: Field visibility respects permissions

**TEST-006: List Data Fetching - No Filters**
- **Objective**: Fetch all records with pagination
- **Steps**:
  1. Call fetch_list_data with no filters, page_size=50
  2. Verify 50 records returned
  3. Verify total_count is correct
- **Expected**: Correct pagination and count

**TEST-007: List Data Fetching - Simple Filter**
- **Objective**: Filter by status field
- **Setup**: 100 POs with various statuses
- **Steps**:
  1. Filter for status='approved'
  2. Verify all returned records have status='approved'
  3. Verify count matches filtered dataset
- **Expected**: Accurate filtering

**TEST-008: List Data Fetching - Complex Filter**
- **Objective**: Multiple AND/OR conditions
- **Filters**: 
```json
  {
    "status": ["approved", "submitted"],
    "po_date_gte": "2024-01-01",
    "total_amount_gt": 10000
  }
```
- **Expected**: Records match all conditions

**TEST-009: List Data Fetching - Sorting**
- **Objective**: Sort by different fields
- **Steps**:
  1. Sort by po_date ASC
  2. Verify ascending order
  3. Sort by total_amount DESC
  4. Verify descending order
- **Expected**: Correct sort order

**TEST-010: List Data Fetching - Lookup Join**
- **Objective**: Include supplier name in PO list
- **Steps**:
  1. Fetch PO list
  2. Verify each record includes supplier.supplier_name
- **Expected**: Lookup data properly joined

**TEST-011: Form Data Fetching - New Record**
- **Objective**: Form for creating new record
- **Steps**:
  1. Call generate_htmx_form with p_form_type='create', p_record_id=NULL
  2. Verify form has empty fields
  3. Verify default values are populated
- **Expected**: Empty form with defaults

**TEST-012: Form Data Fetching - Edit Record**
- **Objective**: Form pre-filled with existing data
- **Steps**:
  1. Create a PO with specific data
  2. Call generate_htmx_form with p_form_type='edit', p_record_id=<po_id>
  3. Verify form fields contain saved data
- **Expected**: Form populated with record data

**TEST-013: Template Rendering - Simple Placeholders**
- **Template**: `<div>{{po_number}} - {{supplier_name}}</div>`
- **Data**: `{"po_number": "PO-001", "supplier_name": "Acme Corp"}`
- **Expected**: `<div>PO-001 - Acme Corp</div>`

**TEST-014: Template Rendering - Nested Paths**
- **Template**: `<div>{{supplier.name}} - {{supplier.email}}</div>`
- **Data**: `{"supplier": {"name": "Acme", "email": "info@acme.com"}}`
- **Expected**: Nested data properly resolved

**TEST-015: Template Rendering - Array Iteration**
- **Template**: 
```html
  {{#lines}}
  <tr><td>{{item_code}}</td><td>{{quantity}}</td></tr>
  {{/lines}}
```
- **Data**: Array of line items
- **Expected**: Multiple rows generated

**TEST-016: End-to-End List Generation**
- **Objective**: Complete list generation flow
- **Setup**: User with 'purchase_manager' role, 50 POs in DB
- **Steps**:
  1. Call generate_htmx_list for purchase_orders
  2. Verify HTML is valid
  3. Verify HTMX attributes present (hx-get, hx-target, etc.)
  4. Verify all visible fields rendered
  5. Verify action buttons match user permissions
- **Expected**: Complete, valid HTMX response

**TEST-017: End-to-End Form Generation - Create**
- **Objective**: Create form generation
- **Steps**:
  1. Call generate_htmx_form for purchase_orders, type='create'
  2. Verify form HTML is valid
  3. Verify all createable fields present
  4. Verify HTMX post attributes correct
  5. Verify lookup fields have select/autocomplete
- **Expected**: Functional create form

**TEST-018: End-to-End Form Generation - Edit**
- **Objective**: Edit form with pre-filled data
- **Setup**: Existing PO record
- **Steps**:
  1. Call generate_htmx_form for purchase_orders, type='edit', record_id=<po_id>
  2. Verify form populated
  3. Verify non-editable fields are disabled
  4. Verify HTMX put/patch attributes
- **Expected**: Functional edit form

**TEST-019: Workflow - Complete Procurement Cycle**
- **Objective**: Execute full P2P workflow
- **Steps**:
  1. Create PO (create_purchase_order)
  2. Submit PO (submit_purchase_order)
  3. Approve PO (approve_purchase_order)
  4. Create GR (create_goods_receipt)
  5. Verify PO quantities updated
  6. Create Invoice (create_invoice_receipt)
  7. Verify 3-way matching
  8. Create Payment (create_payment)
  9. Process Payment (process_payment)
  10. Clear Payment (clear_payment)
- **Expected**: All steps succeed, data consistent

**TEST-020: Workflow - Partial Receipt**
- **Objective**: PO with partial goods receipt
- **Steps**:
  1. Create PO with 100 units ordered
  2. Create GR with 60 units received
  3. Verify PO status = 'partially_received'
  4. Create 2nd GR with 40 units
  5. Verify PO status = 'fully_received'
- **Expected**: Status transitions correctly

**TEST-021: Workflow - 3-Way Matching - Perfect Match**
- **Objective**: Invoice matches PO and GR exactly
- **Setup**: PO for 10 units @ $100, GR for 10 units, Invoice for 10 units @ $100
- **Steps**:
  1. Create invoice
  2. Verify matching_status = 'matched'
  3. Verify variance_amount = 0
- **Expected**: Perfect match detected

**TEST-022: Workflow - 3-Way Matching - Price Variance**
- **Objective**: Invoice price differs from PO
- **Setup**: PO for 10 units @ $100, Invoice for 10 units @ $110
- **Steps**:
  1. Create invoice
  2. Verify matching_status = 'variance'
  3. Verify variance_amount = $100 (10 units * $10 difference)
- **Expected**: Variance detected and calculated

**TEST-023: Workflow - 3-Way Matching - Quantity Variance**
- **Objective**: Invoice quantity exceeds received quantity
- **Setup**: PO for 10 units, GR for 8 units, Invoice for 10 units
- **Steps**:
  1. Create invoice
  2. Verify matching_status = 'variance'
  3. Verify variance captured
- **Expected**: Over-billing detected

**TEST-024: Workflow - Payment Exceeds Invoice**
- **Objective**: Prevent overpayment
- **Setup**: Invoice for $1000
- **Steps**:
  1. Attempt to create payment for $1200
  2. Verify operation fails with validation error
- **Expected**: Overpayment prevented

**TEST-025: Workflow - Multiple Payments for One Invoice**
- **Objective**: Split payments
- **Setup**: Invoice for $1000
- **Steps**:
  1. Create payment for $600
  2. Create payment for $400
  3. Verify both payments link to invoice
  4. Verify clearing totals $1000
- **Expected**: Partial payments supported

**TEST-026: Logical Delete - Purchase Order**
- **Objective**: Soft delete instead of hard delete
- **Steps**:
  1. Create PO
  2. Mark as deleted (is_deleted=TRUE)
  3. Verify PO doesn't appear in list queries
  4. Verify PO still exists in database
- **Expected**: Soft delete working

**TEST-027: Audit Trail - Who Created**
- **Objective**: Track record creators
- **Steps**:
  1. Create PO as user A
  2. Verify created_by = user A's ID
  3. Verify created_at timestamp
- **Expected**: Audit fields populated

**TEST-028: Audit Trail - Who Approved**
- **Objective**: Track approvals
- **Steps**:
  1. Approve PO as user B
  2. Verify approved_by = user B's ID
  3. Verify approved_at timestamp
- **Expected**: Approval audit trail

#### B. Performance Tests

**PERF-001: List Generation - Small Dataset (100 records)**
- **Setup**: 100 POs in database
- **Measurement**: Time to execute generate_htmx_list
- **Success Criteria**: < 100ms average, < 200ms p95

**PERF-002: List Generation - Medium Dataset (1,000 records)**
- **Setup**: 1,000 POs in database, fetch 50 per page
- **Success Criteria**: < 150ms average, < 300ms p95

**PERF-003: List Generation - Large Dataset (10,000 records)**
- **Setup**: 10,000 POs in database, fetch 50 per page
- **Success Criteria**: < 200ms average, < 400ms p95

**PERF-004: List Generation - Stress Dataset (100,000 records)**
- **Setup**: 100,000 POs in database
- **Success Criteria**: < 300ms average, < 600ms p95

**PERF-005: Form Generation - Simple**
- **Measurement**: Time to generate create form
- **Success Criteria**: < 50ms average

**PERF-006: Form Generation - With Lookups**
- **Setup**: Form with 5 lookup fields (each requiring join)
- **Success Criteria**: < 100ms average

**PERF-007: Permission Resolution - Cold Cache**
- **Measurement**: First call to get_user_field_permissions
- **Success Criteria**: < 50ms

**PERF-008: Permission Resolution - Warm Cache**
- **Setup**: Implement caching, make repeated calls
- **Success Criteria**: < 5ms for cached results

**PERF-009: Template Rendering - Small Template**
- **Setup**: Template with 10 placeholders, single record
- **Success Criteria**: < 10ms

**PERF-010: Template Rendering - Large Template**
- **Setup**: Template with 100 placeholders, 50 records
- **Success Criteria**: < 100ms

**PERF-011: Complex Query - Multi-Join List**
- **Setup**: List query requiring 5 table joins
- **Success Criteria**: < 200ms with proper indexes

**PERF-012: Concurrent Users - 10 Users**
- **Setup**: Simulate 10 users requesting lists simultaneously
- **Success Criteria**: No significant degradation, < 500ms p95

**PERF-013: Concurrent Users - 50 Users**
- **Setup**: Simulate 50 concurrent users
- **Success Criteria**: < 1000ms p95, no timeouts

**PERF-014: Concurrent Users - 100 Users**
- **Setup**: Simulate 100 concurrent users
- **Success Criteria**: < 2000ms p95, < 1% error rate

**PERF-015: Write Performance - Batch Insert**
- **Setup**: Insert 1000 PO records with lines
- **Success Criteria**: < 5 seconds total

**PERF-016: Index Effectiveness**
- **Objective**: Verify queries use indexes
- **Steps**:
  1. Run EXPLAIN ANALYZE on all major queries
  2. Verify index scans, not sequential scans
  3. Check index hit ratio
- **Success Criteria**: > 95% index usage

**PERF-017: Database Connection Pool**
- **Setup**: Configure connection pool, run 100 concurrent requests
- **Success Criteria**: No connection exhaustion, < 100ms wait time

**PERF-018: Memory Usage - Large Result Set**
- **Setup**: Fetch 1000 records
- **Measurement**: Memory consumption
- **Success Criteria**: < 100MB per request

**PERF-019: Template Cache Hit Rate**
- **Setup**: Make 100 list requests for same entity
- **Measurement**: Template cache hit ratio
- **Success Criteria**: > 90% cache hit rate after first request

**PERF-020: End-to-End Latency - API to Response**
- **Setup**: Complete HTTP request through API layer
- **Success Criteria**: < 300ms for list, < 200ms for form

#### C. Load Tests

**LOAD-001: Sustained Load - 10 req/sec for 5 minutes**
- **Setup**: Constant 10 requests/second for 5 minutes
- **Success Criteria**: 
  - < 500ms average response time
  - < 0.1% error rate
  - No memory leaks

**LOAD-002: Sustained Load - 50 req/sec for 5 minutes**
- **Success Criteria**:
  - < 1000ms average response time
  - < 1% error rate

**LOAD-003: Spike Test - 0 to 100 req/sec**
- **Setup**: Sudden spike from 0 to 100 req/sec
- **Success Criteria**:
  - System handles spike gracefully
  - < 5% error rate during spike
  - Recovery to normal performance within 30 seconds

**LOAD-004: Gradual Ramp - 1 to 100 req/sec over 10 minutes**
- **Setup**: Linear increase in load
- **Success Criteria**:
  - Identify breaking point
  - Response time degrades gracefully

**LOAD-005: Mixed Workload**
- **Setup**: 60% list requests, 30% form requests, 10% write operations
- **Duration**: 10 minutes at 50 req/sec
- **Success Criteria**: All operation types perform within SLA

#### D. Security Tests

**SEC-001: Row-Level Security - User Isolation**
- **Setup**: User A and User B
- **Steps**:
  1. User A creates PO
  2. User B attempts to fetch User A's PO
  3. If RLS configured, User B should not see it
- **Expected**: Data isolation enforced

**SEC-002: SQL Injection - Filter Input**
- **Setup**: Malicious filter input
- **Input**: `{"status": "'; DROP TABLE purchase_orders; --"}`
- **Expected**: Parameterized queries prevent injection

**SEC-003: Permission Bypass Attempt**
- **Setup**: User with 'viewer' role
- **Steps**:
  1. Attempt to call create_purchase_order directly
  2. Verify permission check blocks execution
- **Expected**: Access denied

**SEC-004: Field Permission Bypass**
- **Setup**: Field marked as hidden for user's role
- **Steps**:
  1. Attempt to request field in filter/sort
  2. Verify field is not exposed
- **Expected**: Hidden fields remain hidden

**SEC-005: Action Permission - Status Transition**
- **Setup**: User without approval permission
- **Steps**:
  1. Attempt to call approve_purchase_order
  2. Verify can_user_perform_action returns FALSE
- **Expected**: Unauthorized action prevented

#### E. Data Integrity Tests

**DATA-001: Referential Integrity**
- **Steps**:
  1. Attempt to create PO with non-existent supplier_id
  2. Verify foreign key constraint violation
- **Expected**: Invalid reference rejected

**DATA-002: Cascade Behavior**
- **Setup**: PO with lines
- **Steps**:
  1. Delete (soft) PO header
  2. Verify lines are also marked deleted (or handle appropriately)
- **Expected**: Cascade delete/update working

**DATA-003: Quantity Reconciliation**
- **Setup**: PO with quantity_ordered = 100
- **Steps**:
  1. Create multiple GRs totaling 120 units
  2. Verify system prevents over-receipt or flags it
- **Expected**: Quantity validation enforced

**DATA-004: Amount Reconciliation**
- **Setup**: Invoice for $1000
- **Steps**:
  1. Create payments totaling $1200
  2. Verify system prevents overpayment
- **Expected**: Amount validation enforced

**DATA-005: Status Consistency**
- **Setup**: PO with all lines fully received
- **Steps**:
  1. Verify PO status updates to 'fully_received'
  2. Create another GR
  3. Verify system prevents additional receipt
- **Expected**: Status reflects reality

**DATA-006: Concurrent Updates**
- **Setup**: Same PO, two users editing simultaneously
- **Steps**:
  1. User A fetches PO (version 1)
  2. User B fetches PO (version 1)
  3. User A updates and saves (version 2)
  4. User B updates and attempts to save
  5. Verify optimistic locking or last-write-wins
- **Expected**: Concurrent update handled gracefully

#### F. Edge Cases

**EDGE-001: Empty Result Set**
- **Setup**: Filter that matches no records
- **Expected**: Empty list returned, no errors

**EDGE-002: Single Record**
- **Setup**: Only 1 record in database
- **Expected**: Pagination works, displays correctly

**EDGE-003: Exact Page Boundary**
- **Setup**: 100 records, page_size=50
- **Expected**: Page 1 has 50, page 2 has 50, page 3 is empty

**EDGE-004: Very Long Text Field**
- **Setup**: Notes field with 10,000 characters
- **Expected**: Handles without truncation or error

**EDGE-005: Null/Empty Values**
- **Setup**: Record with many NULL fields
- **Expected**: Template renders gracefully, no "null" strings shown

**EDGE-006: Special Characters in Data**
- **Setup**: Supplier name with quotes, ampersands: `"Acme & Co's Supplies"`
- **Expected**: HTML-escaped properly, no XSS

**EDGE-007: Unicode Data**
- **Setup**: Supplier name in Chinese, Arabic, emoji
- **Expected**: Displays correctly, no encoding issues

**EDGE-008: Very Large Decimal**
- **Setup**: Amount = 999999999999.99
- **Expected**: Stored and displayed correctly

**EDGE-009: Date Boundaries**
- **Setup**: Date = 1900-01-01, 2099-12-31
- **Expected**: Dates handled correctly

**EDGE-010: Lookup with No Match**
- **Setup**: Foreign key points to soft-deleted record
- **Expected**: Handles gracefully, shows ID or "(deleted)"

### 6. Performance Monitoring Implementation

Create real-time monitoring:
```sql
-- Function to capture performance metrics
CREATE OR REPLACE FUNCTION log_request_metrics(
    p_endpoint VARCHAR,
    p_response_time_ms INTEGER,
    p_was_error BOOLEAN
) RETURNS VOID AS $$
BEGIN
    -- Insert into time-series table or update aggregates
    -- Can be called from application layer
END;
$$ LANGUAGE plpgsql;

-- Materialized view for dashboard
CREATE MATERIALIZED VIEW performance_dashboard AS
SELECT 
    entity_type,
    view_type,
    COUNT(*) as request_count,
    AVG(duration_ms) as avg_duration_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms) as p95_duration_ms,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) as p99_duration_ms,
    AVG(data_row_count) as avg_row_count,
    SUM(CASE WHEN error_message IS NOT NULL THEN 1 ELSE 0 END) as error_count
FROM ui_generation_logs
WHERE generation_start_time > NOW() - INTERVAL '1 hour'
GROUP BY entity_type, view_type;
```

### 7. Optimization Strategies to Implement

1. **Template Caching**
   - Cache compiled templates in application memory
   - Invalidate on template updates
   - Target: 90%+ cache hit rate

2. **Permission Caching**
   - Cache user permissions for 5 minutes
   - Use Redis or in-memory cache
   - Invalidate on role changes

3. **Prepared Statements**
   - Use prepared statements for all queries
   - Reduces parsing overhead

4. **Connection Pooling**
   - Configure Supabase connection pool
   - Min: 10, Max: 100 connections
   - Monitor pool utilization

5. **Index Optimization**
   - Create indexes on:
     - All foreign keys
     - Frequently filtered fields (status, dates)
     - Sort fields
   - Monitor index usage, remove unused indexes

6. **Pagination Strategy**
   - Use cursor-based pagination for large datasets
   - Implement "load more" rather than page numbers for better UX

7. **Materialized Views**
   - For complex aggregations (e.g., PO summary with counts)
   - Refresh strategy: on-demand or scheduled

8. **Partial Template Rendering**
   - For very large lists, render in chunks
   - Use HTMX's infinite scroll pattern

### 8. Deliverables

Your implementation should produce:

1. **Complete SQL Scripts**
   - Schema creation (tables, indexes, constraints)
   - Function implementations
   - Seed data scripts
   - Test data generation scripts

2. **API Server Code**
   - Express/Fastify minimal middleware
   - Authentication integration with Supabase Auth
   - Error handling
   - Logging

3. **Sample HTMX Templates**
   - At least one complete template for each view type
   - Demonstrating: filters, sorting, forms, lookups, actions

4. **Test Suite**
   - Automated tests for all test cases listed above
   - Performance test scripts (using tools like k6, Artillery, or Apache Bench)
   - Test result reporting

5. **Performance Report**
   - Baseline performance metrics
   - Bottleneck analysis
   - Optimization recommendations
   - Before/after comparisons

6. **Documentation**
   - Database schema documentation
   - API endpoint documentation
   - How to add new entities
   - How to modify templates
   - How to add new roles/permissions

7. **Dashboard**
   - Simple admin UI showing:
     - Performance metrics from ui_generation_logs
     - Recent errors
     - Template cache hit rates
     - Slow queries

### 9. Success Metrics

The implementation is considered successful if:

- ✅ All functional tests pass (100%)
- ✅ List generation < 300ms p95 for 10k records
- ✅ Form generation < 200ms p95
- ✅ System handles 50 concurrent users with < 1s p95 latency
- ✅ Complete procurement workflow executes correctly
- ✅ Permission system enforces all rules
- ✅ No SQL injection vulnerabilities
- ✅ Template cache hit rate > 85%
- ✅ Zero data integrity violations in tests

### 10. Bonus Challenges

If time permits, implement:

1. **Template versioning** - Support A/B testing different UI templates
2. **Real-time updates** - Use Supabase Realtime to push updates to open lists
3. **Audit log UI** - Generate HTMX views of change history
4. **Export functionality** - Generate CSV/Excel from same data functions
5. **Advanced filters** - Saved filter presets, shared filters
6. **Bulk operations** - Approve multiple POs at once
7. **Workflow engine** - Configurable approval workflows
8. **Notification system** - Alert users when actions require attention

### 11. Testing Tools and Approach

Use the following tools:

- **Database Testing**: pgTAP or custom PL/pgSQL test functions
- **Load Testing**: k6 or Artillery for HTTP load tests
- **Performance Profiling**: 
  - PostgreSQL: EXPLAIN ANALYZE, pg_stat_statements
  - Application: Node.js built-in profiler or clinic.js
- **Assertion Library**: Jest or Mocha + Chai for API tests
- **Data Generation**: Faker.js for realistic test data

Example test structure:
```javascript
// test/functional/list-generation.test.js
describe('List Generation', () => {
    test('TEST-016: End-to-End List Generation', async () => {
        // Setup: Create user with purchase_manager role
        const user = await createTestUser('purchase_manager');
        
        // Create 50 test POs
        await seedPurchaseOrders(50);
        
        // Execute
        const response = await request(app)
            .get('/ui/purchase_order/list')
            .set('Authorization', `Bearer ${user.token}`);
        
        // Assert
        expect(response.status).toBe(200);
        expect(response.headers['content-type']).toContain('text/html');
        
        const $ = cheerio.load(response.text);
        
        // Verify HTMX attributes
        expect($('[hx-get]').length).toBeGreaterThan(0);
        
        // Verify fields rendered
        expect($('table thead th').length).toBeGreaterThanOrEqual(5);
        
        // Verify action buttons match permissions
        expect($('button[data-action="create"]').length).toBe(1);
        expect($('button[data-action="approve"]').length).toBe(0); // PM can't approve
    });
});
```

### 12. Final Notes

- Prioritize **correctness** over performance initially
- Add comprehensive logging at each layer
- Use transactions for all multi-step operations
- Handle errors gracefully with meaningful messages
- Document any assumptions or design decisions
- Keep functions focused and testable
- Use consistent naming conventions
- Add comments for complex logic
- Run EXPLAIN ANALYZE on all major queries
- Monitor actual vs expected cardinality in query plans

This prompt should give your coding agent everything needed to build a production-grade, database-centric HTMX generation system with comprehensive testing and performance validation.