-- Migration 004: Create Triggers and Sequences
-- Description: Creates auto-update triggers and numbering sequences
-- Dependencies: 003_create_audit_tables.sql
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- SEQUENCES FOR AUTO-NUMBERING
-- =============================================================================
-- These sequences generate sequential numbers for document numbering

CREATE SEQUENCE po_number_seq START 1000;
CREATE SEQUENCE gr_number_seq START 1000;
CREATE SEQUENCE invoice_number_seq START 1000;
CREATE SEQUENCE payment_number_seq START 1000;

COMMENT ON SEQUENCE po_number_seq IS 'Sequence for purchase order numbering';
COMMENT ON SEQUENCE gr_number_seq IS 'Sequence for goods receipt numbering';
COMMENT ON SEQUENCE invoice_number_seq IS 'Sequence for invoice numbering';
COMMENT ON SEQUENCE payment_number_seq IS 'Sequence for payment numbering';

-- =============================================================================
-- TRIGGER FUNCTION: Update Timestamp
-- =============================================================================
-- Automatically updates the updated_at column on record modification

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_updated_at_column() IS 'Trigger function to auto-update updated_at timestamp';

-- =============================================================================
-- CREATE TRIGGERS FOR updated_at
-- =============================================================================
-- Apply the update timestamp trigger to all relevant tables

-- Business Domain Tables
CREATE TRIGGER tr_suppliers_updated_at
    BEFORE UPDATE ON suppliers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER tr_purchase_orders_updated_at
    BEFORE UPDATE ON purchase_orders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER tr_goods_receipts_updated_at
    BEFORE UPDATE ON goods_receipts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER tr_invoice_receipts_updated_at
    BEFORE UPDATE ON invoice_receipts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER tr_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- UI Framework Tables
CREATE TRIGGER tr_htmx_templates_updated_at
    BEFORE UPDATE ON htmx_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- NUMBER GENERATION FUNCTIONS
-- =============================================================================

-- Generate Purchase Order Number
CREATE OR REPLACE FUNCTION generate_po_number()
RETURNS VARCHAR AS $$
DECLARE
    v_sequence_num INTEGER;
    v_po_number VARCHAR(50);
BEGIN
    v_sequence_num := nextval('po_number_seq');
    v_po_number := 'PO-' || TO_CHAR(CURRENT_DATE, 'YYYYMM') || '-' ||
                   LPAD(v_sequence_num::TEXT, 5, '0');
    RETURN v_po_number;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generate_po_number() IS 'Generates PO number in format: PO-YYYYMM-00001';

-- Generate Goods Receipt Number
CREATE OR REPLACE FUNCTION generate_gr_number()
RETURNS VARCHAR AS $$
DECLARE
    v_sequence_num INTEGER;
    v_gr_number VARCHAR(50);
BEGIN
    v_sequence_num := nextval('gr_number_seq');
    v_gr_number := 'GR-' || TO_CHAR(CURRENT_DATE, 'YYYYMM') || '-' ||
                   LPAD(v_sequence_num::TEXT, 5, '0');
    RETURN v_gr_number;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generate_gr_number() IS 'Generates GR number in format: GR-YYYYMM-00001';

-- Generate Invoice Number
CREATE OR REPLACE FUNCTION generate_invoice_number()
RETURNS VARCHAR AS $$
DECLARE
    v_sequence_num INTEGER;
    v_invoice_number VARCHAR(50);
BEGIN
    v_sequence_num := nextval('invoice_number_seq');
    v_invoice_number := 'INV-' || TO_CHAR(CURRENT_DATE, 'YYYYMM') || '-' ||
                        LPAD(v_sequence_num::TEXT, 5, '0');
    RETURN v_invoice_number;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generate_invoice_number() IS 'Generates invoice number in format: INV-YYYYMM-00001';

-- Generate Payment Number
CREATE OR REPLACE FUNCTION generate_payment_number()
RETURNS VARCHAR AS $$
DECLARE
    v_sequence_num INTEGER;
    v_payment_number VARCHAR(50);
BEGIN
    v_sequence_num := nextval('payment_number_seq');
    v_payment_number := 'PAY-' || TO_CHAR(CURRENT_DATE, 'YYYYMM') || '-' ||
                        LPAD(v_sequence_num::TEXT, 5, '0');
    RETURN v_payment_number;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generate_payment_number() IS 'Generates payment number in format: PAY-YYYYMM-00001';

-- =============================================================================
-- TRIGGER FUNCTION: Calculate PO Line Total
-- =============================================================================
-- Automatically calculates line_total when quantity or unit_price changes

CREATE OR REPLACE FUNCTION calculate_po_line_total()
RETURNS TRIGGER AS $$
BEGIN
    NEW.line_total := NEW.quantity_ordered * NEW.unit_price;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_po_line_total() IS 'Auto-calculates line_total = quantity * unit_price';

CREATE TRIGGER tr_po_lines_calculate_total
    BEFORE INSERT OR UPDATE OF quantity_ordered, unit_price ON purchase_order_lines
    FOR EACH ROW
    EXECUTE FUNCTION calculate_po_line_total();

-- =============================================================================
-- TRIGGER FUNCTION: Calculate Invoice Line Total
-- =============================================================================
-- Automatically calculates line_total when quantity or unit_price changes

CREATE OR REPLACE FUNCTION calculate_invoice_line_total()
RETURNS TRIGGER AS $$
BEGIN
    NEW.line_total := NEW.quantity_invoiced * NEW.unit_price;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_invoice_line_total() IS 'Auto-calculates invoice line_total';

CREATE TRIGGER tr_invoice_lines_calculate_total
    BEFORE INSERT OR UPDATE OF quantity_invoiced, unit_price ON invoice_lines
    FOR EACH ROW
    EXECUTE FUNCTION calculate_invoice_line_total();

-- =============================================================================
-- TRIGGER FUNCTION: Deactivate Old Templates
-- =============================================================================
-- When a new template is marked as active, deactivate old versions

CREATE OR REPLACE FUNCTION deactivate_old_templates()
RETURNS TRIGGER AS $$
BEGIN
    -- Only run if new template is being marked as active
    IF NEW.is_active = TRUE THEN
        -- Deactivate all other active templates for the same entity and view type
        UPDATE htmx_templates
        SET is_active = FALSE
        WHERE entity_type_id = NEW.entity_type_id
          AND view_type = NEW.view_type
          AND template_id != NEW.template_id
          AND is_active = TRUE;

        RAISE NOTICE 'Deactivated old templates for entity % view %',
            NEW.entity_type_id, NEW.view_type;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION deactivate_old_templates() IS 'Auto-deactivates old template versions when new one is activated';

CREATE TRIGGER tr_templates_deactivate_old
    AFTER INSERT OR UPDATE OF is_active ON htmx_templates
    FOR EACH ROW
    WHEN (NEW.is_active = TRUE)
    EXECUTE FUNCTION deactivate_old_templates();

-- =============================================================================
-- TRIGGER FUNCTION: Audit Trail Logging
-- =============================================================================
-- Generic trigger to log changes to audit_trail table

CREATE OR REPLACE FUNCTION log_audit_trail()
RETURNS TRIGGER AS $$
DECLARE
    v_operation VARCHAR(10);
    v_old_values JSONB;
    v_new_values JSONB;
    v_record_id UUID;
BEGIN
    -- Determine operation type
    IF TG_OP = 'DELETE' THEN
        v_operation := 'DELETE';
        v_old_values := to_jsonb(OLD);
        v_new_values := NULL;
        v_record_id := (to_jsonb(OLD)->>'id')::UUID; -- Assumes primary key named 'id'
    ELSIF TG_OP = 'UPDATE' THEN
        v_operation := 'UPDATE';
        v_old_values := to_jsonb(OLD);
        v_new_values := to_jsonb(NEW);
        v_record_id := (to_jsonb(NEW)->>'id')::UUID;
    ELSIF TG_OP = 'INSERT' THEN
        v_operation := 'INSERT';
        v_old_values := NULL;
        v_new_values := to_jsonb(NEW);
        v_record_id := (to_jsonb(NEW)->>'id')::UUID;
    END IF;

    -- Insert audit record
    INSERT INTO audit_trail (
        table_name,
        record_id,
        operation,
        old_values,
        new_values,
        changed_by
    ) VALUES (
        TG_TABLE_NAME,
        v_record_id,
        v_operation,
        v_old_values,
        v_new_values,
        current_setting('app.current_user_id', TRUE)::UUID
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION log_audit_trail() IS 'Generic audit trail logging function for all table changes';

-- Note: Audit triggers can be added selectively to specific tables
-- Example (commented out - enable as needed):
-- CREATE TRIGGER tr_purchase_orders_audit
--     AFTER INSERT OR UPDATE OR DELETE ON purchase_orders
--     FOR EACH ROW
--     EXECUTE FUNCTION log_audit_trail();

-- =============================================================================
-- HELPER FUNCTION: Set Current User ID
-- =============================================================================
-- Sets the current user ID in session for audit trail

CREATE OR REPLACE FUNCTION set_current_user_id(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_user_id', p_user_id::TEXT, FALSE);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION set_current_user_id(UUID) IS 'Sets current user ID in session for audit logging';

-- =============================================================================
-- HELPER FUNCTION: Get Current User ID
-- =============================================================================
-- Gets the current user ID from session

CREATE OR REPLACE FUNCTION get_current_user_id()
RETURNS UUID AS $$
BEGIN
    RETURN current_setting('app.current_user_id', TRUE)::UUID;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_current_user_id() IS 'Gets current user ID from session';

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 004 completed successfully';
    RAISE NOTICE 'Created 4 sequences: po_number_seq, gr_number_seq, invoice_number_seq, payment_number_seq';
    RAISE NOTICE 'Created triggers for auto-updating updated_at columns';
    RAISE NOTICE 'Created triggers for auto-calculating line totals';
    RAISE NOTICE 'Created number generation functions';
    RAISE NOTICE 'Created audit trail logging infrastructure';
END $$;
