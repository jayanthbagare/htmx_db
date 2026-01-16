-- Data Layer Indexes
-- Description: Additional composite indexes for common query patterns
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- PURCHASE ORDERS - Additional Indexes
-- =============================================================================

-- Index for amount range queries (common in reporting)
CREATE INDEX IF NOT EXISTS idx_po_total_amount
ON purchase_orders (total_amount)
WHERE is_deleted = FALSE;

-- Index for date range + status (common filter combination)
CREATE INDEX IF NOT EXISTS idx_po_date_status_amount
ON purchase_orders (po_date, status, total_amount)
WHERE is_deleted = FALSE;

-- Index for supplier + status (common in supplier analysis)
CREATE INDEX IF NOT EXISTS idx_po_supplier_status
ON purchase_orders (supplier_id, status)
WHERE is_deleted = FALSE;

-- =============================================================================
-- SUPPLIERS - Additional Indexes
-- =============================================================================

-- Index for name search (ILIKE queries benefit from pg_trgm)
-- Note: Requires pg_trgm extension
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
        CREATE EXTENSION IF NOT EXISTS pg_trgm;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_supplier_name_trgm
ON suppliers USING gin (supplier_name gin_trgm_ops);

-- =============================================================================
-- GOODS RECEIPTS - Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_gr_po_id
ON goods_receipts (po_id)
WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_gr_receipt_date
ON goods_receipts (receipt_date)
WHERE is_deleted = FALSE;

-- =============================================================================
-- INVOICE RECEIPTS - Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_invoice_po_id
ON invoice_receipts (po_id)
WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_invoice_status
ON invoice_receipts (status)
WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_invoice_due_date
ON invoice_receipts (due_date)
WHERE is_deleted = FALSE;

-- =============================================================================
-- PAYMENTS - Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_payment_date
ON payments (payment_date)
WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_payment_status
ON payments (status)
WHERE is_deleted = FALSE;

-- =============================================================================
-- UI/PERMISSION TABLES - Indexes for faster permission lookups
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_field_perms_role_entity
ON field_permissions (role_id, entity_type_id);

CREATE INDEX IF NOT EXISTS idx_action_perms_role_entity
ON ui_action_permissions (role_id, entity_type_id);

CREATE INDEX IF NOT EXISTS idx_users_role
ON users (role_id)
WHERE is_active = TRUE;

-- =============================================================================
-- ANALYZE TABLES
-- =============================================================================
-- Update statistics for query planner

ANALYZE purchase_orders;
ANALYZE suppliers;
ANALYZE goods_receipts;
ANALYZE invoice_receipts;
ANALYZE payments;
ANALYZE field_permissions;
ANALYZE ui_action_permissions;
ANALYZE users;

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Phase 3 indexes created successfully';
    RAISE NOTICE 'Tables analyzed for optimal query planning';
END $$;
