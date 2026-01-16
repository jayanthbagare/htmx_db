-- Migration 005: Create Row Level Security Policies
-- Description: Implements RLS policies for data access control
-- Dependencies: 004_create_triggers_sequences.sql
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- HELPER FUNCTIONS FOR RLS
-- =============================================================================

-- Get current user's role name
CREATE OR REPLACE FUNCTION current_user_role()
RETURNS VARCHAR AS $$
DECLARE
    v_role_name VARCHAR;
BEGIN
    SELECT r.role_name INTO v_role_name
    FROM users u
    JOIN roles r ON u.role_id = r.role_id
    WHERE u.user_id = get_current_user_id()
      AND u.is_active = TRUE;

    RETURN COALESCE(v_role_name, 'viewer');
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION current_user_role() IS 'Returns current user role name (default: viewer)';

-- Check if current user is admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN current_user_role() = 'admin';
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION is_admin() IS 'Returns TRUE if current user is admin';

-- =============================================================================
-- ENABLE ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on critical business tables
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE goods_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Enable RLS on sensitive framework tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE field_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ui_action_permissions ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- PURCHASE ORDERS - RLS POLICIES
-- =============================================================================

-- SELECT Policy: Users can see submitted/approved POs + their own drafts
CREATE POLICY po_select_policy ON purchase_orders
    FOR SELECT
    USING (
        is_deleted = FALSE AND (
            -- Admins see everything
            is_admin()
            -- Submitted or approved POs visible to all
            OR status IN ('submitted', 'approved', 'partially_received', 'fully_received')
            -- Users can see their own drafts
            OR created_by = get_current_user_id()
        )
    );

-- INSERT Policy: Users with create permission can insert
CREATE POLICY po_insert_policy ON purchase_orders
    FOR INSERT
    WITH CHECK (
        -- Only active users can insert
        EXISTS (
            SELECT 1 FROM users
            WHERE user_id = get_current_user_id()
              AND is_active = TRUE
        )
    );

-- UPDATE Policy: Admins + owners of drafts/submitted POs
CREATE POLICY po_update_policy ON purchase_orders
    FOR UPDATE
    USING (
        is_deleted = FALSE AND (
            is_admin()
            OR (created_by = get_current_user_id() AND status IN ('draft', 'submitted'))
        )
    )
    WITH CHECK (
        is_admin()
        OR (created_by = get_current_user_id() AND status IN ('draft', 'submitted'))
    );

-- DELETE Policy: Only admins can delete (soft delete)
CREATE POLICY po_delete_policy ON purchase_orders
    FOR UPDATE
    USING (is_admin());

COMMENT ON POLICY po_select_policy ON purchase_orders IS 'Users see submitted/approved POs + own drafts';
COMMENT ON POLICY po_update_policy ON purchase_orders IS 'Admins + owners can edit draft/submitted POs';

-- =============================================================================
-- PURCHASE ORDER LINES - RLS POLICIES
-- =============================================================================

-- SELECT Policy: Can see lines if can see the PO
CREATE POLICY po_lines_select_policy ON purchase_order_lines
    FOR SELECT
    USING (
        is_deleted = FALSE AND
        EXISTS (
            SELECT 1 FROM purchase_orders po
            WHERE po.po_id = purchase_order_lines.po_id
              AND po.is_deleted = FALSE
              AND (
                  is_admin()
                  OR po.status IN ('submitted', 'approved', 'partially_received', 'fully_received')
                  OR po.created_by = get_current_user_id()
              )
        )
    );

-- INSERT Policy: Can insert if can edit the PO
CREATE POLICY po_lines_insert_policy ON purchase_order_lines
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM purchase_orders po
            WHERE po.po_id = purchase_order_lines.po_id
              AND po.is_deleted = FALSE
              AND (
                  is_admin()
                  OR (po.created_by = get_current_user_id() AND po.status = 'draft')
              )
        )
    );

-- UPDATE Policy: Can update if can edit the PO
CREATE POLICY po_lines_update_policy ON purchase_order_lines
    FOR UPDATE
    USING (
        is_deleted = FALSE AND
        EXISTS (
            SELECT 1 FROM purchase_orders po
            WHERE po.po_id = purchase_order_lines.po_id
              AND (
                  is_admin()
                  OR (po.created_by = get_current_user_id() AND po.status IN ('draft', 'submitted'))
              )
        )
    );

-- =============================================================================
-- GOODS RECEIPTS - RLS POLICIES
-- =============================================================================

-- SELECT Policy: Warehouse staff + admins can see all GRs
CREATE POLICY gr_select_policy ON goods_receipts
    FOR SELECT
    USING (
        is_deleted = FALSE AND (
            is_admin()
            OR current_user_role() IN ('warehouse_staff', 'purchase_manager')
            OR received_by = get_current_user_id()
        )
    );

-- INSERT Policy: Warehouse staff can create GRs
CREATE POLICY gr_insert_policy ON goods_receipts
    FOR INSERT
    WITH CHECK (
        is_admin()
        OR current_user_role() IN ('warehouse_staff', 'purchase_manager')
    );

-- UPDATE Policy: Warehouse staff can edit draft GRs
CREATE POLICY gr_update_policy ON goods_receipts
    FOR UPDATE
    USING (
        is_deleted = FALSE AND status = 'draft' AND (
            is_admin()
            OR current_user_role() IN ('warehouse_staff', 'purchase_manager')
            OR received_by = get_current_user_id()
        )
    );

-- =============================================================================
-- INVOICE RECEIPTS - RLS POLICIES
-- =============================================================================

-- SELECT Policy: Accountants + admins can see invoices
CREATE POLICY invoice_select_policy ON invoice_receipts
    FOR SELECT
    USING (
        is_deleted = FALSE AND (
            is_admin()
            OR current_user_role() = 'accountant'
            OR current_user_role() = 'purchase_manager'
        )
    );

-- INSERT Policy: Accountants can create invoices
CREATE POLICY invoice_insert_policy ON invoice_receipts
    FOR INSERT
    WITH CHECK (
        is_admin()
        OR current_user_role() = 'accountant'
    );

-- UPDATE Policy: Accountants can edit received invoices
CREATE POLICY invoice_update_policy ON invoice_receipts
    FOR UPDATE
    USING (
        is_deleted = FALSE AND (
            is_admin()
            OR (current_user_role() = 'accountant' AND status = 'received')
        )
    );

-- =============================================================================
-- PAYMENTS - RLS POLICIES
-- =============================================================================

-- SELECT Policy: Accountants + admins can see payments
CREATE POLICY payment_select_policy ON payments
    FOR SELECT
    USING (
        is_deleted = FALSE AND (
            is_admin()
            OR current_user_role() = 'accountant'
        )
    );

-- INSERT Policy: Accountants can create payments
CREATE POLICY payment_insert_policy ON payments
    FOR INSERT
    WITH CHECK (
        is_admin()
        OR current_user_role() = 'accountant'
    );

-- UPDATE Policy: Accountants can update pending payments
CREATE POLICY payment_update_policy ON payments
    FOR UPDATE
    USING (
        is_deleted = FALSE AND status = 'pending' AND (
            is_admin()
            OR current_user_role() = 'accountant'
        )
    );

-- =============================================================================
-- USERS - RLS POLICIES
-- =============================================================================

-- SELECT Policy: Users can see active users, own record always visible
CREATE POLICY users_select_policy ON users
    FOR SELECT
    USING (
        is_admin()
        OR user_id = get_current_user_id()
        OR is_active = TRUE
    );

-- INSERT Policy: Only admins can create users
CREATE POLICY users_insert_policy ON users
    FOR INSERT
    WITH CHECK (is_admin());

-- UPDATE Policy: Admins can edit all, users can edit own profile
CREATE POLICY users_update_policy ON users
    FOR UPDATE
    USING (
        is_admin()
        OR user_id = get_current_user_id()
    )
    WITH CHECK (
        is_admin()
        -- Users cannot change their own role
        OR (user_id = get_current_user_id() AND role_id = (SELECT role_id FROM users WHERE user_id = get_current_user_id()))
    );

-- =============================================================================
-- PERMISSIONS TABLES - RLS POLICIES
-- =============================================================================

-- Field Permissions: All authenticated users can read, only admins modify
CREATE POLICY field_perm_select_policy ON field_permissions
    FOR SELECT
    USING (TRUE); -- All can read permissions

CREATE POLICY field_perm_modify_policy ON field_permissions
    FOR ALL
    USING (is_admin())
    WITH CHECK (is_admin());

-- Action Permissions: All authenticated users can read, only admins modify
CREATE POLICY action_perm_select_policy ON ui_action_permissions
    FOR SELECT
    USING (TRUE); -- All can read permissions

CREATE POLICY action_perm_modify_policy ON ui_action_permissions
    FOR ALL
    USING (is_admin())
    WITH CHECK (is_admin());

-- =============================================================================
-- BYPASS POLICIES FOR SERVICE ROLE
-- =============================================================================
-- For API/service role that needs full access (e.g., Supabase service role)
-- Note: This assumes you'll set app.current_user_id in the application layer

-- Grant bypass for service operations
-- The application should set app.current_user_id even when using service role

-- =============================================================================
-- GRANT PERMISSIONS TO ROLES
-- =============================================================================

-- Create database roles if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_admin') THEN
        CREATE ROLE app_admin;
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_readonly') THEN
        CREATE ROLE app_readonly;
    END IF;
END $$;

-- Grant appropriate permissions to app_user role
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_user;

-- Grant all permissions to app_admin role
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO app_admin;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_admin;

-- Grant read-only access to app_readonly role
GRANT USAGE ON SCHEMA public TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_readonly;

-- Ensure future objects get same permissions
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE ON TABLES TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL PRIVILEGES ON TABLES TO app_admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO app_readonly;

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 005 completed successfully';
    RAISE NOTICE 'Enabled RLS on critical tables';
    RAISE NOTICE 'Created RLS policies for purchase_orders, goods_receipts, invoices, payments, users';
    RAISE NOTICE 'Created database roles: app_user, app_admin, app_readonly';
    RAISE NOTICE 'Granted appropriate permissions to each role';
    RAISE NOTICE '';
    RAISE NOTICE 'IMPORTANT: Application must call set_current_user_id(user_id) at session start';
    RAISE NOTICE 'Example: SELECT set_current_user_id(''user-uuid-here''::UUID);';
END $$;
