-- Business Logic Functions
-- Module: Invoice Receipts
-- Description: Invoice processing with 3-way matching
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- HELPER FUNCTION: Perform 3-Way Match
-- =============================================================================
-- Compares invoice line to PO and GR data

CREATE OR REPLACE FUNCTION perform_three_way_match(
    p_po_line_id UUID,
    p_invoice_quantity DECIMAL,
    p_invoice_unit_price DECIMAL,
    p_tolerance_percent DECIMAL DEFAULT 0.05  -- 5% tolerance
)
RETURNS JSONB AS $$
DECLARE
    v_po_line RECORD;
    v_qty_received DECIMAL;
    v_price_variance DECIMAL;
    v_qty_variance DECIMAL;
    v_match_status VARCHAR;
    v_issues TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Get PO line data
    SELECT
        pol.quantity_ordered,
        pol.quantity_received,
        pol.unit_price
    INTO v_po_line
    FROM purchase_order_lines pol
    WHERE pol.line_id = p_po_line_id
      AND pol.is_deleted = FALSE;

    IF v_po_line IS NULL THEN
        RETURN jsonb_build_object(
            'match_status', 'error',
            'issues', ARRAY['PO line not found']
        );
    END IF;

    v_qty_received := v_po_line.quantity_received;

    -- Check 1: Quantity vs PO (can't invoice more than ordered)
    IF p_invoice_quantity > v_po_line.quantity_ordered THEN
        v_issues := array_append(v_issues,
            format('Invoice quantity (%s) exceeds PO quantity (%s)',
                   p_invoice_quantity, v_po_line.quantity_ordered));
    END IF;

    -- Check 2: Quantity vs GR (can't invoice more than received)
    IF p_invoice_quantity > v_qty_received THEN
        v_issues := array_append(v_issues,
            format('Invoice quantity (%s) exceeds received quantity (%s)',
                   p_invoice_quantity, v_qty_received));
    END IF;

    -- Check 3: Price variance
    IF v_po_line.unit_price > 0 THEN
        v_price_variance := ABS(p_invoice_unit_price - v_po_line.unit_price) / v_po_line.unit_price;

        IF v_price_variance > p_tolerance_percent THEN
            v_issues := array_append(v_issues,
                format('Price variance: Invoice %s vs PO %s (%.1f%% difference)',
                       p_invoice_unit_price, v_po_line.unit_price, v_price_variance * 100));
        END IF;
    END IF;

    -- Determine match status
    IF array_length(v_issues, 1) IS NULL OR array_length(v_issues, 1) = 0 THEN
        v_match_status := 'matched';
    ELSIF array_length(v_issues, 1) = 1 AND v_issues[1] LIKE 'Price variance%' THEN
        v_match_status := 'variance';  -- Price variance only
    ELSE
        v_match_status := 'mismatch';  -- Quantity issues
    END IF;

    RETURN jsonb_build_object(
        'match_status', v_match_status,
        'po_quantity', v_po_line.quantity_ordered,
        'received_quantity', v_qty_received,
        'invoice_quantity', p_invoice_quantity,
        'po_unit_price', v_po_line.unit_price,
        'invoice_unit_price', p_invoice_unit_price,
        'price_variance_percent', ROUND(COALESCE(v_price_variance, 0) * 100, 2),
        'issues', v_issues
    );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION perform_three_way_match(UUID, DECIMAL, DECIMAL, DECIMAL) IS 'Performs 3-way match on invoice line';

-- =============================================================================
-- FUNCTION: Create Invoice Receipt
-- =============================================================================
-- Creates an invoice receipt with automatic 3-way matching

CREATE OR REPLACE FUNCTION create_invoice_receipt(
    p_user_id UUID,
    p_po_id UUID,
    p_vendor_invoice_number VARCHAR,
    p_invoice_date DATE DEFAULT CURRENT_DATE,
    p_due_date DATE DEFAULT NULL,
    p_currency VARCHAR DEFAULT 'USD',
    p_notes TEXT DEFAULT NULL,
    p_lines JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB AS $$
DECLARE
    v_invoice_id UUID;
    v_invoice_number VARCHAR;
    v_po_record RECORD;
    v_line JSONB;
    v_line_id UUID;
    v_po_line RECORD;
    v_line_number INTEGER := 0;
    v_line_total DECIMAL(15,2);
    v_total_amount DECIMAL(15,2) := 0;
    v_match_result JSONB;
    v_overall_status VARCHAR := 'matched';
    v_has_variance BOOLEAN := FALSE;
    v_has_mismatch BOOLEAN := FALSE;
    v_lines_created INTEGER := 0;
BEGIN
    -- Validate user has create permission
    IF NOT can_user_perform_action(p_user_id, 'invoice_receipt', 'create') THEN
        RAISE EXCEPTION 'User does not have permission to create invoices';
    END IF;

    -- Validate PO exists and is in receivable status
    SELECT po_id, po_number, status, currency, supplier_id
    INTO v_po_record
    FROM purchase_orders
    WHERE po_id = p_po_id
      AND is_deleted = FALSE;

    IF v_po_record IS NULL THEN
        RAISE EXCEPTION 'Purchase order not found: %', p_po_id;
    END IF;

    IF v_po_record.status NOT IN ('approved', 'partially_received', 'fully_received') THEN
        RAISE EXCEPTION 'Cannot invoice PO with status: %. Must be approved/received.', v_po_record.status;
    END IF;

    -- Validate currency matches PO
    IF p_currency != v_po_record.currency THEN
        RAISE EXCEPTION 'Invoice currency (%) must match PO currency (%)',
            p_currency, v_po_record.currency;
    END IF;

    -- Default due date to 30 days from invoice date
    IF p_due_date IS NULL THEN
        p_due_date := p_invoice_date + INTERVAL '30 days';
    END IF;

    -- Generate invoice ID
    v_invoice_id := gen_random_uuid();

    -- Create the invoice (invoice_number will be auto-generated by trigger)
    INSERT INTO invoice_receipts (
        invoice_id,
        po_id,
        vendor_invoice_number,
        invoice_date,
        due_date,
        currency,
        total_amount,
        matching_status,
        payment_status,
        notes,
        created_by,
        created_at
    ) VALUES (
        v_invoice_id,
        p_po_id,
        p_vendor_invoice_number,
        p_invoice_date,
        p_due_date,
        p_currency,
        0,  -- Will be updated after lines
        'pending',
        'unpaid',
        p_notes,
        p_user_id,
        NOW()
    )
    RETURNING invoice_number INTO v_invoice_number;

    -- Create line items with matching
    IF jsonb_array_length(p_lines) = 0 THEN
        -- Auto-create lines from PO lines (for received quantities)
        FOR v_po_line IN
            SELECT
                pol.line_id,
                pol.line_number,
                pol.item_code,
                pol.item_description,
                pol.quantity_ordered,
                pol.quantity_received,
                pol.quantity_invoiced,
                pol.unit_price,
                pol.uom
            FROM purchase_order_lines pol
            WHERE pol.po_id = p_po_id
              AND pol.is_deleted = FALSE
              AND pol.quantity_received > pol.quantity_invoiced
            ORDER BY pol.line_number
        LOOP
            v_line_number := v_line_number + 1;
            v_line_id := gen_random_uuid();

            -- Invoice for received but not yet invoiced quantity
            v_line_total := (v_po_line.quantity_received - v_po_line.quantity_invoiced) * v_po_line.unit_price;

            -- Perform 3-way match
            v_match_result := perform_three_way_match(
                v_po_line.line_id,
                v_po_line.quantity_received - v_po_line.quantity_invoiced,
                v_po_line.unit_price
            );

            INSERT INTO invoice_lines (
                invoice_line_id,
                invoice_id,
                po_line_id,
                line_number,
                item_code,
                item_description,
                quantity,
                unit_price,
                line_total,
                matching_status,
                matching_details,
                created_at
            ) VALUES (
                v_line_id,
                v_invoice_id,
                v_po_line.line_id,
                v_line_number,
                v_po_line.item_code,
                v_po_line.item_description,
                v_po_line.quantity_received - v_po_line.quantity_invoiced,
                v_po_line.unit_price,
                v_line_total,
                v_match_result->>'match_status',
                v_match_result,
                NOW()
            );

            v_total_amount := v_total_amount + v_line_total;
            v_lines_created := v_lines_created + 1;

            -- Track overall status
            IF (v_match_result->>'match_status') = 'mismatch' THEN
                v_has_mismatch := TRUE;
            ELSIF (v_match_result->>'match_status') = 'variance' THEN
                v_has_variance := TRUE;
            END IF;
        END LOOP;
    ELSE
        -- Create lines from provided data
        FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
        LOOP
            v_line_number := v_line_number + 1;
            v_line_id := gen_random_uuid();

            -- Get PO line
            SELECT line_id, item_code, item_description, unit_price
            INTO v_po_line
            FROM purchase_order_lines
            WHERE line_id = (v_line->>'po_line_id')::UUID
              AND po_id = p_po_id
              AND is_deleted = FALSE;

            IF v_po_line IS NULL THEN
                RAISE EXCEPTION 'Invalid PO line: %', v_line->>'po_line_id';
            END IF;

            v_line_total := COALESCE((v_line->>'quantity')::DECIMAL, 0) *
                           COALESCE((v_line->>'unit_price')::DECIMAL, v_po_line.unit_price);

            -- Perform 3-way match
            v_match_result := perform_three_way_match(
                v_po_line.line_id,
                COALESCE((v_line->>'quantity')::DECIMAL, 0),
                COALESCE((v_line->>'unit_price')::DECIMAL, v_po_line.unit_price)
            );

            INSERT INTO invoice_lines (
                invoice_line_id,
                invoice_id,
                po_line_id,
                line_number,
                item_code,
                item_description,
                quantity,
                unit_price,
                line_total,
                matching_status,
                matching_details,
                created_at
            ) VALUES (
                v_line_id,
                v_invoice_id,
                v_po_line.line_id,
                v_line_number,
                COALESCE(v_line->>'item_code', v_po_line.item_code),
                COALESCE(v_line->>'item_description', v_po_line.item_description),
                COALESCE((v_line->>'quantity')::DECIMAL, 0),
                COALESCE((v_line->>'unit_price')::DECIMAL, v_po_line.unit_price),
                v_line_total,
                v_match_result->>'match_status',
                v_match_result,
                NOW()
            );

            v_total_amount := v_total_amount + v_line_total;
            v_lines_created := v_lines_created + 1;

            -- Track overall status
            IF (v_match_result->>'match_status') = 'mismatch' THEN
                v_has_mismatch := TRUE;
            ELSIF (v_match_result->>'match_status') = 'variance' THEN
                v_has_variance := TRUE;
            END IF;
        END LOOP;
    END IF;

    IF v_lines_created = 0 THEN
        DELETE FROM invoice_receipts WHERE invoice_id = v_invoice_id;
        RAISE EXCEPTION 'No items to invoice - all quantities already invoiced';
    END IF;

    -- Determine overall matching status
    IF v_has_mismatch THEN
        v_overall_status := 'mismatch';
    ELSIF v_has_variance THEN
        v_overall_status := 'variance';
    ELSE
        v_overall_status := 'matched';
    END IF;

    -- Update invoice totals and status
    UPDATE invoice_receipts
    SET total_amount = v_total_amount,
        matching_status = v_overall_status,
        updated_at = NOW()
    WHERE invoice_id = v_invoice_id;

    -- Update PO line invoiced quantities
    PERFORM update_po_line_quantities(p_po_id, 'invoiced');

    RETURN jsonb_build_object(
        'success', TRUE,
        'invoice_id', v_invoice_id,
        'invoice_number', v_invoice_number,
        'vendor_invoice_number', p_vendor_invoice_number,
        'po_number', v_po_record.po_number,
        'total_amount', v_total_amount,
        'line_count', v_lines_created,
        'matching_status', v_overall_status,
        'has_variance', v_has_variance,
        'has_mismatch', v_has_mismatch,
        'message', CASE
            WHEN v_has_mismatch THEN 'Invoice created with matching issues. Review required.'
            WHEN v_has_variance THEN 'Invoice created with price variances. Approval may be required.'
            ELSE 'Invoice created and matched successfully.'
        END
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION create_invoice_receipt(UUID, UUID, VARCHAR, DATE, DATE, VARCHAR, TEXT, JSONB) IS 'Creates an invoice with automatic 3-way matching';

-- =============================================================================
-- FUNCTION: Approve Invoice Variance
-- =============================================================================
-- Approves an invoice with variances

CREATE OR REPLACE FUNCTION approve_invoice_variance(
    p_user_id UUID,
    p_invoice_id UUID,
    p_approval_notes TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_invoice_record RECORD;
BEGIN
    -- Validate user has approve permission
    IF NOT can_user_perform_action(p_user_id, 'invoice_receipt', 'approve') THEN
        RAISE EXCEPTION 'User does not have permission to approve invoice variances';
    END IF;

    -- Get invoice info
    SELECT invoice_id, invoice_number, matching_status
    INTO v_invoice_record
    FROM invoice_receipts
    WHERE invoice_id = p_invoice_id
      AND is_deleted = FALSE;

    IF v_invoice_record IS NULL THEN
        RAISE EXCEPTION 'Invoice not found: %', p_invoice_id;
    END IF;

    IF v_invoice_record.matching_status NOT IN ('variance', 'mismatch') THEN
        RAISE EXCEPTION 'Invoice does not have variances to approve. Status: %',
            v_invoice_record.matching_status;
    END IF;

    -- Update status to approved
    UPDATE invoice_receipts
    SET matching_status = 'approved',
        variance_approved_by = p_user_id,
        variance_approved_at = NOW(),
        variance_approval_notes = p_approval_notes,
        updated_at = NOW(),
        updated_by = p_user_id
    WHERE invoice_id = p_invoice_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'invoice_id', p_invoice_id,
        'invoice_number', v_invoice_record.invoice_number,
        'old_status', v_invoice_record.matching_status,
        'new_status', 'approved',
        'message', 'Invoice variances approved'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION approve_invoice_variance(UUID, UUID, TEXT) IS 'Approves an invoice with variances';

-- =============================================================================
-- FUNCTION: Get Invoice Matching Summary
-- =============================================================================
-- Returns detailed matching information for an invoice

CREATE OR REPLACE FUNCTION get_invoice_matching_summary(
    p_invoice_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_invoice_record RECORD;
    v_lines JSONB;
    v_summary JSONB;
BEGIN
    -- Get invoice header
    SELECT
        ir.invoice_id,
        ir.invoice_number,
        ir.vendor_invoice_number,
        ir.total_amount,
        ir.matching_status,
        po.po_number,
        po.total_amount AS po_total
    INTO v_invoice_record
    FROM invoice_receipts ir
    JOIN purchase_orders po ON ir.po_id = po.po_id
    WHERE ir.invoice_id = p_invoice_id
      AND ir.is_deleted = FALSE;

    IF v_invoice_record IS NULL THEN
        RETURN jsonb_build_object('error', 'Invoice not found');
    END IF;

    -- Get line details
    SELECT jsonb_agg(
        jsonb_build_object(
            'line_number', il.line_number,
            'item_code', il.item_code,
            'invoice_qty', il.quantity,
            'invoice_price', il.unit_price,
            'po_qty', pol.quantity_ordered,
            'po_price', pol.unit_price,
            'received_qty', pol.quantity_received,
            'match_status', il.matching_status,
            'issues', il.matching_details->'issues'
        ) ORDER BY il.line_number
    ) INTO v_lines
    FROM invoice_lines il
    JOIN purchase_order_lines pol ON il.po_line_id = pol.line_id
    WHERE il.invoice_id = p_invoice_id
      AND il.is_deleted = FALSE;

    -- Build summary
    v_summary := jsonb_build_object(
        'invoice_number', v_invoice_record.invoice_number,
        'vendor_invoice_number', v_invoice_record.vendor_invoice_number,
        'po_number', v_invoice_record.po_number,
        'invoice_total', v_invoice_record.total_amount,
        'po_total', v_invoice_record.po_total,
        'total_difference', v_invoice_record.total_amount - v_invoice_record.po_total,
        'matching_status', v_invoice_record.matching_status,
        'lines', v_lines,
        'matched_count', (
            SELECT COUNT(*) FROM invoice_lines
            WHERE invoice_id = p_invoice_id AND matching_status = 'matched'
        ),
        'variance_count', (
            SELECT COUNT(*) FROM invoice_lines
            WHERE invoice_id = p_invoice_id AND matching_status = 'variance'
        ),
        'mismatch_count', (
            SELECT COUNT(*) FROM invoice_lines
            WHERE invoice_id = p_invoice_id AND matching_status = 'mismatch'
        )
    );

    RETURN v_summary;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_invoice_matching_summary(UUID) IS 'Returns detailed matching summary for an invoice';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Create an invoice for a received PO
SELECT create_invoice_receipt(
    '00000000-0000-0000-0000-000000000100'::UUID,  -- user_id
    (SELECT po_id FROM purchase_orders WHERE status = 'fully_received' LIMIT 1),
    'VND-INV-001',  -- vendor invoice number
    CURRENT_DATE,
    CURRENT_DATE + INTERVAL '30 days',
    'USD',
    'Monthly supplies invoice'
);

-- Get matching summary
SELECT get_invoice_matching_summary(
    (SELECT invoice_id FROM invoice_receipts ORDER BY created_at DESC LIMIT 1)
);

-- Approve variance
SELECT approve_invoice_variance(
    '00000000-0000-0000-0000-000000000100'::UUID,
    (SELECT invoice_id FROM invoice_receipts WHERE matching_status = 'variance' LIMIT 1),
    'Price increase approved per contract amendment'
);
*/
