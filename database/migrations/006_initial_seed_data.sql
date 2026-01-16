-- Migration 006: Initial Seed Data
-- Description: Seeds initial roles and UI entity configurations
-- Dependencies: 005_create_rls_policies.sql
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- SEED ROLES
-- =============================================================================

INSERT INTO roles (role_id, role_name, description, is_active) VALUES
    ('00000000-0000-0000-0000-000000000001'::UUID, 'admin', 'System administrator with full access', TRUE),
    ('00000000-0000-0000-0000-000000000002'::UUID, 'purchase_manager', 'Manages purchase orders and procurement', TRUE),
    ('00000000-0000-0000-0000-000000000003'::UUID, 'warehouse_staff', 'Handles goods receipts and inventory', TRUE),
    ('00000000-0000-0000-0000-000000000004'::UUID, 'accountant', 'Processes invoices and payments', TRUE),
    ('00000000-0000-0000-0000-000000000005'::UUID, 'viewer', 'Read-only access to approved documents', TRUE);

-- =============================================================================
-- SEED ADMIN USER
-- =============================================================================
-- Create default admin user (password should be changed immediately)

INSERT INTO users (user_id, username, email, full_name, role_id, is_active) VALUES
    ('00000000-0000-0000-0000-000000000100'::UUID,
     'admin',
     'admin@example.com',
     'System Administrator',
     '00000000-0000-0000-0000-000000000001'::UUID,
     TRUE);

-- =============================================================================
-- SEED UI ENTITY TYPES
-- =============================================================================

INSERT INTO ui_entity_types (entity_type_id, entity_name, display_name, primary_table, icon_class, description) VALUES
    -- Purchase Order
    ('10000000-0000-0000-0000-000000000001'::UUID,
     'purchase_order',
     'Purchase Orders',
     'purchase_orders',
     'fa-shopping-cart',
     'Purchase orders for procuring goods and services'),

    -- Goods Receipt
    ('10000000-0000-0000-0000-000000000002'::UUID,
     'goods_receipt',
     'Goods Receipts',
     'goods_receipts',
     'fa-truck-loading',
     'Documents for receiving goods against purchase orders'),

    -- Invoice Receipt
    ('10000000-0000-0000-0000-000000000003'::UUID,
     'invoice_receipt',
     'Invoice Receipts',
     'invoice_receipts',
     'fa-file-invoice',
     'Vendor invoices with 3-way matching'),

    -- Payment
    ('10000000-0000-0000-0000-000000000004'::UUID,
     'payment',
     'Payments',
     'payments',
     'fa-money-check',
     'Payment processing for invoices'),

    -- Supplier
    ('10000000-0000-0000-0000-000000000005'::UUID,
     'supplier',
     'Suppliers',
     'suppliers',
     'fa-building',
     'Supplier and vendor master data');

-- =============================================================================
-- SEED FIELD DEFINITIONS FOR PURCHASE ORDERS
-- =============================================================================

INSERT INTO ui_field_definitions (
    entity_type_id, field_name, display_label, data_type, field_order,
    is_required, validation_rule, help_text
) VALUES
    -- Header Fields
    ('10000000-0000-0000-0000-000000000001'::UUID, 'po_number', 'PO Number', 'text', 1, FALSE, NULL, 'Auto-generated'),
    ('10000000-0000-0000-0000-000000000001'::UUID, 'supplier_id', 'Supplier', 'lookup', 2, TRUE,
     '{"entity": "supplier", "display_field": "supplier_name"}', 'Select supplier'),
    ('10000000-0000-0000-0000-000000000001'::UUID, 'po_date', 'PO Date', 'date', 3, TRUE, NULL, 'Date of purchase order'),
    ('10000000-0000-0000-0000-000000000001'::UUID, 'expected_delivery_date', 'Expected Delivery', 'date', 4, FALSE, NULL, 'Expected delivery date'),
    ('10000000-0000-0000-0000-000000000001'::UUID, 'total_amount', 'Total Amount', 'decimal', 5, FALSE, '{"min": 0}', 'Total PO value'),
    ('10000000-0000-0000-0000-000000000001'::UUID, 'currency', 'Currency', 'select', 6, TRUE, NULL, 'Currency code'),
    ('10000000-0000-0000-0000-000000000001'::UUID, 'status', 'Status', 'select', 7, TRUE, NULL, 'PO status'),
    ('10000000-0000-0000-0000-000000000001'::UUID, 'notes', 'Notes', 'textarea', 8, FALSE, NULL, 'Additional notes'),
    ('10000000-0000-0000-0000-000000000001'::UUID, 'created_at', 'Created Date', 'datetime', 9, FALSE, NULL, 'Creation timestamp'),
    ('10000000-0000-0000-0000-000000000001'::UUID, 'approved_by', 'Approved By', 'lookup', 10, FALSE,
     '{"entity": "users", "display_field": "full_name"}', 'Approver name'),
    ('10000000-0000-0000-0000-000000000001'::UUID, 'approved_at', 'Approved Date', 'datetime', 11, FALSE, NULL, 'Approval timestamp');

-- =============================================================================
-- SEED FIELD DEFINITIONS FOR SUPPLIERS
-- =============================================================================

INSERT INTO ui_field_definitions (
    entity_type_id, field_name, display_label, data_type, field_order,
    is_required, validation_rule, help_text
) VALUES
    ('10000000-0000-0000-0000-000000000005'::UUID, 'supplier_code', 'Supplier Code', 'text', 1, TRUE,
     '{"pattern": "^[A-Z0-9-]+$"}', 'Uppercase alphanumeric code'),
    ('10000000-0000-0000-0000-000000000005'::UUID, 'supplier_name', 'Supplier Name', 'text', 2, TRUE, NULL, 'Company name'),
    ('10000000-0000-0000-0000-000000000005'::UUID, 'contact_email', 'Email', 'email', 3, FALSE, NULL, 'Contact email'),
    ('10000000-0000-0000-0000-000000000005'::UUID, 'contact_phone', 'Phone', 'phone', 4, FALSE, NULL, 'Contact phone'),
    ('10000000-0000-0000-0000-000000000005'::UUID, 'payment_terms_days', 'Payment Terms (Days)', 'number', 5, TRUE,
     '{"min": 0, "max": 365}', 'Standard payment terms'),
    ('10000000-0000-0000-0000-000000000005'::UUID, 'is_active', 'Active', 'checkbox', 6, FALSE, NULL, 'Active status');

-- =============================================================================
-- SEED ACTION PERMISSIONS
-- =============================================================================

-- Admin: Full access to everything
INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed) VALUES
    -- Purchase Orders
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'create', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'edit', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'delete', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'approve', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'submit', TRUE),
    -- Goods Receipts
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000002'::UUID, 'create', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000002'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000002'::UUID, 'edit', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000002'::UUID, 'delete', TRUE),
    -- Invoice Receipts
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'create', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'edit', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'delete', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'approve', TRUE),
    -- Payments
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000004'::UUID, 'create', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000004'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000004'::UUID, 'edit', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000004'::UUID, 'delete', TRUE),
    -- Suppliers
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000005'::UUID, 'create', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000005'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000005'::UUID, 'edit', TRUE),
    ('00000000-0000-0000-0000-000000000001'::UUID, '10000000-0000-0000-0000-000000000005'::UUID, 'delete', TRUE);

-- Purchase Manager: Can create/edit/submit POs
INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed) VALUES
    ('00000000-0000-0000-0000-000000000002'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'create', TRUE),
    ('00000000-0000-0000-0000-000000000002'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000002'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'edit', TRUE),
    ('00000000-0000-0000-0000-000000000002'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'submit', TRUE),
    ('00000000-0000-0000-0000-000000000002'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'approve', FALSE),
    ('00000000-0000-0000-0000-000000000002'::UUID, '10000000-0000-0000-0000-000000000002'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000002'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000002'::UUID, '10000000-0000-0000-0000-000000000004'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000002'::UUID, '10000000-0000-0000-0000-000000000005'::UUID, 'read', TRUE);

-- Warehouse Staff: Can create/edit goods receipts
INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed) VALUES
    ('00000000-0000-0000-0000-000000000003'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000003'::UUID, '10000000-0000-0000-0000-000000000002'::UUID, 'create', TRUE),
    ('00000000-0000-0000-0000-000000000003'::UUID, '10000000-0000-0000-0000-000000000002'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000003'::UUID, '10000000-0000-0000-0000-000000000002'::UUID, 'edit', TRUE);

-- Accountant: Can process invoices and payments
INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed) VALUES
    ('00000000-0000-0000-0000-000000000004'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000004'::UUID, '10000000-0000-0000-0000-000000000002'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000004'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'create', TRUE),
    ('00000000-0000-0000-0000-000000000004'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000004'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'edit', TRUE),
    ('00000000-0000-0000-0000-000000000004'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'approve', TRUE),
    ('00000000-0000-0000-0000-000000000004'::UUID, '10000000-0000-0000-0000-000000000004'::UUID, 'create', TRUE),
    ('00000000-0000-0000-0000-000000000004'::UUID, '10000000-0000-0000-0000-000000000004'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000004'::UUID, '10000000-0000-0000-0000-000000000004'::UUID, 'edit', TRUE);

-- Viewer: Read-only access
INSERT INTO ui_action_permissions (role_id, entity_type_id, action_name, is_allowed) VALUES
    ('00000000-0000-0000-0000-000000000005'::UUID, '10000000-0000-0000-0000-000000000001'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000005'::UUID, '10000000-0000-0000-0000-000000000002'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000005'::UUID, '10000000-0000-0000-0000-000000000003'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000005'::UUID, '10000000-0000-0000-0000-000000000004'::UUID, 'read', TRUE),
    ('00000000-0000-0000-0000-000000000005'::UUID, '10000000-0000-0000-0000-000000000005'::UUID, 'read', TRUE);

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 006 completed successfully';
    RAISE NOTICE '';
    RAISE NOTICE 'Seeded data:';
    RAISE NOTICE '  - 5 roles: admin, purchase_manager, warehouse_staff, accountant, viewer';
    RAISE NOTICE '  - 1 admin user (username: admin, email: admin@example.com)';
    RAISE NOTICE '  - 5 UI entity types: purchase_order, goods_receipt, invoice_receipt, payment, supplier';
    RAISE NOTICE '  - Field definitions for purchase_order and supplier entities';
    RAISE NOTICE '  - Action permissions for all roles';
    RAISE NOTICE '';
    RAISE NOTICE 'IMPORTANT SECURITY NOTES:';
    RAISE NOTICE '  1. Change admin password immediately after first login';
    RAISE NOTICE '  2. Do NOT use the seeded admin account in production';
    RAISE NOTICE '  3. Create proper user accounts with Supabase Auth';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Run remaining migrations to add core functions';
    RAISE NOTICE '  2. Add field permissions (coming in future migrations)';
    RAISE NOTICE '  3. Add HTMX templates (coming in future migrations)';
END $$;
