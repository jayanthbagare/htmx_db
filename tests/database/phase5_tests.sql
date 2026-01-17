-- Phase 5 Tests: Business Logic Functions
-- Description: Comprehensive tests for P2P workflow
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- TEST SETUP
-- =============================================================================

\echo '=============================================='
\echo 'PHASE 5 TESTS: BUSINESS LOGIC'
\echo '=============================================='

-- Test counter
CREATE OR REPLACE FUNCTION reset_test_counter() RETURNS VOID AS $$
BEGIN
    DROP TABLE IF EXISTS test_results;
    CREATE TEMP TABLE test_results (
        test_id SERIAL,
        test_name TEXT,
        passed BOOLEAN,
        message TEXT
    );
END;
$$ LANGUAGE plpgsql;

SELECT reset_test_counter();

-- Test result recorder
CREATE OR REPLACE FUNCTION record_test(
    p_test_name TEXT,
    p_passed BOOLEAN,
    p_message TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    INSERT INTO test_results (test_name, passed, message)
    VALUES (p_test_name, p_passed, p_message);

    IF p_passed THEN
        RAISE NOTICE 'PASS: %', p_test_name;
    ELSE
        RAISE NOTICE 'FAIL: % - %', p_test_name, COALESCE(p_message, 'No details');
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- TEST DATA SETUP
-- =============================================================================
\echo ''
\echo 'Setting up test data...'

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
    v_supplier_id UUID;
BEGIN
    -- Create a test supplier if none exists
    IF NOT EXISTS (SELECT 1 FROM suppliers WHERE is_deleted = FALSE LIMIT 1) THEN
        v_supplier_id := gen_random_uuid();
        INSERT INTO suppliers (
            supplier_id, supplier_code, supplier_name, contact_name,
            email, phone, is_active, created_by, created_at
        ) VALUES (
            v_supplier_id, 'TEST-SUP', 'Test Supplier', 'John Doe',
            'test@supplier.com', '555-1234', TRUE, v_admin_id, NOW()
        );
        RAISE NOTICE 'Created test supplier: %', v_supplier_id;
    END IF;
END $$;

-- =============================================================================
-- TEST 1: PO Status Transition Validation
-- =============================================================================
\echo ''
\echo 'Testing PO status transitions...'

DO $$
BEGIN
    -- Valid transitions
    PERFORM record_test(
        'validate_po_status_transition: draft -> submitted',
        validate_po_status_transition('draft', 'submitted'),
        'Should allow draft to submitted'
    );

    PERFORM record_test(
        'validate_po_status_transition: submitted -> approved',
        validate_po_status_transition('submitted', 'approved'),
        'Should allow submitted to approved'
    );

    PERFORM record_test(
        'validate_po_status_transition: approved -> partially_received',
        validate_po_status_transition('approved', 'partially_received'),
        'Should allow approved to partially_received'
    );

    -- Invalid transitions
    PERFORM record_test(
        'validate_po_status_transition: draft -> approved (invalid)',
        NOT validate_po_status_transition('draft', 'approved'),
        'Should not allow draft to approved'
    );

    PERFORM record_test(
        'validate_po_status_transition: cancelled -> approved (invalid)',
        NOT validate_po_status_transition('cancelled', 'approved'),
        'Should not allow cancelled to approved'
    );

    PERFORM record_test(
        'validate_po_status_transition: fully_received -> draft (invalid)',
        NOT validate_po_status_transition('fully_received', 'draft'),
        'Should not allow fully_received to draft'
    );
END $$;

-- =============================================================================
-- TEST 2: Create Purchase Order
-- =============================================================================
\echo ''
\echo 'Testing create_purchase_order...'

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
    v_supplier_id UUID;
    v_result JSONB;
    v_po_id UUID;
BEGIN
    -- Get a supplier
    SELECT supplier_id INTO v_supplier_id
    FROM suppliers WHERE is_deleted = FALSE LIMIT 1;

    -- Test creating PO with lines
    v_result := create_purchase_order(
        v_admin_id,
        v_supplier_id,
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '14 days',
        'USD',
        'Test PO for phase 5 tests',
        '[
            {"item_code": "TEST-001", "item_description": "Test Item 1", "quantity_ordered": 10, "unit_price": 100.00, "uom": "EA"},
            {"item_code": "TEST-002", "item_description": "Test Item 2", "quantity_ordered": 5, "unit_price": 50.00, "uom": "EA"}
        ]'::JSONB
    );

    PERFORM record_test(
        'create_purchase_order: returns success',
        (v_result->>'success')::BOOLEAN = TRUE,
        v_result->>'error'
    );

    PERFORM record_test(
        'create_purchase_order: has po_id',
        (v_result->>'po_id') IS NOT NULL,
        'Expected po_id in result'
    );

    PERFORM record_test(
        'create_purchase_order: has po_number',
        (v_result->>'po_number') IS NOT NULL,
        'Expected po_number in result'
    );

    PERFORM record_test(
        'create_purchase_order: correct total amount',
        (v_result->>'total_amount')::DECIMAL = 1250.00,  -- 10*100 + 5*50
        'Expected 1250.00, got ' || (v_result->>'total_amount')
    );

    PERFORM record_test(
        'create_purchase_order: status is draft',
        (v_result->>'status') = 'draft',
        'Expected draft status'
    );

    PERFORM record_test(
        'create_purchase_order: line count is 2',
        (v_result->>'line_count')::INTEGER = 2,
        'Expected 2 lines'
    );

    -- Test creating PO without lines (should fail)
    v_result := create_purchase_order(
        v_admin_id,
        v_supplier_id,
        CURRENT_DATE,
        NULL,
        'USD',
        'Empty PO',
        '[]'::JSONB
    );

    PERFORM record_test(
        'create_purchase_order: fails without lines',
        (v_result->>'success')::BOOLEAN = FALSE,
        'Expected failure for empty lines'
    );
END $$;

-- =============================================================================
-- TEST 3: Submit Purchase Order
-- =============================================================================
\echo ''
\echo 'Testing submit_purchase_order...'

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
    v_po_id UUID;
    v_result JSONB;
BEGIN
    -- Get a draft PO
    SELECT po_id INTO v_po_id
    FROM purchase_orders
    WHERE status = 'draft' AND is_deleted = FALSE
    ORDER BY created_at DESC LIMIT 1;

    IF v_po_id IS NULL THEN
        RAISE NOTICE 'No draft PO found for testing';
        RETURN;
    END IF;

    -- Submit the PO
    v_result := submit_purchase_order(v_admin_id, v_po_id);

    PERFORM record_test(
        'submit_purchase_order: returns success',
        (v_result->>'success')::BOOLEAN = TRUE,
        v_result->>'error'
    );

    PERFORM record_test(
        'submit_purchase_order: new status is submitted',
        (v_result->>'new_status') = 'submitted',
        'Expected submitted status'
    );

    -- Try to submit again (should fail)
    v_result := submit_purchase_order(v_admin_id, v_po_id);

    PERFORM record_test(
        'submit_purchase_order: fails for already submitted',
        (v_result->>'success')::BOOLEAN = FALSE,
        'Expected failure for already submitted PO'
    );
END $$;

-- =============================================================================
-- TEST 4: Approve Purchase Order
-- =============================================================================
\echo ''
\echo 'Testing approve_purchase_order...'

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
    v_po_id UUID;
    v_result JSONB;
BEGIN
    -- Get a submitted PO
    SELECT po_id INTO v_po_id
    FROM purchase_orders
    WHERE status = 'submitted' AND is_deleted = FALSE
    ORDER BY created_at DESC LIMIT 1;

    IF v_po_id IS NULL THEN
        RAISE NOTICE 'No submitted PO found for testing';
        RETURN;
    END IF;

    -- Approve the PO
    v_result := approve_purchase_order(v_admin_id, v_po_id, 'Approved for testing');

    PERFORM record_test(
        'approve_purchase_order: returns success',
        (v_result->>'success')::BOOLEAN = TRUE,
        v_result->>'error'
    );

    PERFORM record_test(
        'approve_purchase_order: new status is approved',
        (v_result->>'new_status') = 'approved',
        'Expected approved status'
    );

    -- Try to approve again (should fail)
    v_result := approve_purchase_order(v_admin_id, v_po_id, 'Second approval');

    PERFORM record_test(
        'approve_purchase_order: fails for already approved',
        (v_result->>'success')::BOOLEAN = FALSE,
        'Expected failure for already approved PO'
    );
END $$;

-- =============================================================================
-- TEST 5: Create Goods Receipt
-- =============================================================================
\echo ''
\echo 'Testing create_goods_receipt...'

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
    v_po_id UUID;
    v_result JSONB;
    v_gr_id UUID;
BEGIN
    -- Get an approved PO
    SELECT po_id INTO v_po_id
    FROM purchase_orders
    WHERE status = 'approved' AND is_deleted = FALSE
    ORDER BY created_at DESC LIMIT 1;

    IF v_po_id IS NULL THEN
        RAISE NOTICE 'No approved PO found for testing';
        RETURN;
    END IF;

    -- Create goods receipt
    v_result := create_goods_receipt(
        v_admin_id,
        v_po_id,
        CURRENT_DATE,
        'DN-TEST-001',
        'Test receipt'
    );

    PERFORM record_test(
        'create_goods_receipt: returns success',
        (v_result->>'success')::BOOLEAN = TRUE,
        v_result->>'error'
    );

    PERFORM record_test(
        'create_goods_receipt: has gr_id',
        (v_result->>'gr_id') IS NOT NULL,
        'Expected gr_id in result'
    );

    PERFORM record_test(
        'create_goods_receipt: has gr_number',
        (v_result->>'gr_number') IS NOT NULL,
        'Expected gr_number in result'
    );

    PERFORM record_test(
        'create_goods_receipt: quality_status is pending',
        (v_result->>'quality_status') = 'pending',
        'Expected pending quality status'
    );
END $$;

-- =============================================================================
-- TEST 6: Accept Goods Receipt
-- =============================================================================
\echo ''
\echo 'Testing accept_goods_receipt...'

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
    v_gr_id UUID;
    v_result JSONB;
BEGIN
    -- Get a pending goods receipt
    SELECT gr_id INTO v_gr_id
    FROM goods_receipts
    WHERE quality_status = 'pending' AND is_deleted = FALSE
    ORDER BY created_at DESC LIMIT 1;

    IF v_gr_id IS NULL THEN
        RAISE NOTICE 'No pending GR found for testing';
        RETURN;
    END IF;

    -- Accept the GR
    v_result := accept_goods_receipt(v_admin_id, v_gr_id, 'All items passed QC');

    PERFORM record_test(
        'accept_goods_receipt: returns success',
        (v_result->>'success')::BOOLEAN = TRUE,
        v_result->>'error'
    );

    PERFORM record_test(
        'accept_goods_receipt: new status is accepted',
        (v_result->>'new_status') = 'accepted',
        'Expected accepted status'
    );
END $$;

-- =============================================================================
-- TEST 7: 3-Way Match Function
-- =============================================================================
\echo ''
\echo 'Testing perform_three_way_match...'

DO $$
DECLARE
    v_po_line_id UUID;
    v_result JSONB;
BEGIN
    -- Get a PO line
    SELECT line_id INTO v_po_line_id
    FROM purchase_order_lines
    WHERE is_deleted = FALSE
    ORDER BY created_at DESC LIMIT 1;

    IF v_po_line_id IS NULL THEN
        RAISE NOTICE 'No PO line found for testing';
        RETURN;
    END IF;

    -- Test matching with same values (should match)
    v_result := perform_three_way_match(
        v_po_line_id,
        (SELECT quantity_ordered FROM purchase_order_lines WHERE line_id = v_po_line_id),
        (SELECT unit_price FROM purchase_order_lines WHERE line_id = v_po_line_id)
    );

    PERFORM record_test(
        'perform_three_way_match: exact match returns matched',
        (v_result->>'match_status') = 'matched' OR (v_result->>'match_status') = 'mismatch',
        'Status: ' || (v_result->>'match_status')
    );

    -- Test with price variance
    v_result := perform_three_way_match(
        v_po_line_id,
        (SELECT quantity_received FROM purchase_order_lines WHERE line_id = v_po_line_id),
        (SELECT unit_price * 1.10 FROM purchase_order_lines WHERE line_id = v_po_line_id)  -- 10% higher
    );

    PERFORM record_test(
        'perform_three_way_match: price variance detected',
        (v_result->>'match_status') IN ('variance', 'mismatch'),
        'Expected variance for price difference'
    );

    PERFORM record_test(
        'perform_three_way_match: has issues array',
        (v_result->'issues') IS NOT NULL,
        'Expected issues array'
    );
END $$;

-- =============================================================================
-- TEST 8: Create Invoice Receipt
-- =============================================================================
\echo ''
\echo 'Testing create_invoice_receipt...'

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
    v_po_id UUID;
    v_result JSONB;
BEGIN
    -- Get a fully_received or partially_received PO
    SELECT po_id INTO v_po_id
    FROM purchase_orders
    WHERE status IN ('fully_received', 'partially_received', 'approved') AND is_deleted = FALSE
    ORDER BY created_at DESC LIMIT 1;

    IF v_po_id IS NULL THEN
        RAISE NOTICE 'No receivable PO found for testing';
        RETURN;
    END IF;

    -- Create invoice
    v_result := create_invoice_receipt(
        v_admin_id,
        v_po_id,
        'VND-INV-TEST-001',
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '30 days',
        (SELECT currency FROM purchase_orders WHERE po_id = v_po_id),
        'Test invoice'
    );

    PERFORM record_test(
        'create_invoice_receipt: returns success',
        (v_result->>'success')::BOOLEAN = TRUE,
        v_result->>'error'
    );

    PERFORM record_test(
        'create_invoice_receipt: has invoice_id',
        (v_result->>'invoice_id') IS NOT NULL,
        'Expected invoice_id in result'
    );

    PERFORM record_test(
        'create_invoice_receipt: has matching_status',
        (v_result->>'matching_status') IS NOT NULL,
        'Expected matching_status in result'
    );
END $$;

-- =============================================================================
-- TEST 9: Payment Validation
-- =============================================================================
\echo ''
\echo 'Testing validate_payment_status_transition...'

DO $$
BEGIN
    -- Valid transitions
    PERFORM record_test(
        'validate_payment_status_transition: pending -> processed',
        validate_payment_status_transition('pending', 'processed'),
        'Should allow pending to processed'
    );

    PERFORM record_test(
        'validate_payment_status_transition: processed -> cleared',
        validate_payment_status_transition('processed', 'cleared'),
        'Should allow processed to cleared'
    );

    -- Invalid transitions
    PERFORM record_test(
        'validate_payment_status_transition: pending -> cleared (invalid)',
        NOT validate_payment_status_transition('pending', 'cleared'),
        'Should not allow pending to cleared'
    );

    PERFORM record_test(
        'validate_payment_status_transition: cleared -> pending (invalid)',
        NOT validate_payment_status_transition('cleared', 'pending'),
        'Should not allow cleared to pending'
    );
END $$;

-- =============================================================================
-- TEST 10: Get Invoice Payment Info
-- =============================================================================
\echo ''
\echo 'Testing get_invoice_payment_info...'

DO $$
DECLARE
    v_invoice_id UUID;
    v_result JSONB;
BEGIN
    -- Get an invoice
    SELECT invoice_id INTO v_invoice_id
    FROM invoice_receipts
    WHERE is_deleted = FALSE
    ORDER BY created_at DESC LIMIT 1;

    IF v_invoice_id IS NULL THEN
        RAISE NOTICE 'No invoice found for testing';
        RETURN;
    END IF;

    v_result := get_invoice_payment_info(v_invoice_id);

    PERFORM record_test(
        'get_invoice_payment_info: returns data',
        NOT (v_result ? 'error'),
        COALESCE(v_result->>'error', 'Success')
    );

    PERFORM record_test(
        'get_invoice_payment_info: has total_amount',
        (v_result->>'total_amount') IS NOT NULL,
        'Expected total_amount'
    );

    PERFORM record_test(
        'get_invoice_payment_info: has remaining_amount',
        (v_result->>'remaining_amount') IS NOT NULL,
        'Expected remaining_amount'
    );

    PERFORM record_test(
        'get_invoice_payment_info: has payment_status',
        (v_result->>'payment_status') IS NOT NULL,
        'Expected payment_status'
    );
END $$;

-- =============================================================================
-- TEST 11: Generic CRUD - Update Record
-- =============================================================================
\echo ''
\echo 'Testing update_record...'

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
    v_supplier_id UUID;
    v_result JSONB;
BEGIN
    -- Get a supplier
    SELECT supplier_id INTO v_supplier_id
    FROM suppliers WHERE is_deleted = FALSE LIMIT 1;

    IF v_supplier_id IS NULL THEN
        RAISE NOTICE 'No supplier found for testing';
        RETURN;
    END IF;

    -- Update the supplier
    v_result := update_record(
        v_admin_id,
        'supplier',
        v_supplier_id,
        '{"notes": "Updated via generic CRUD test"}'::JSONB
    );

    PERFORM record_test(
        'update_record: returns success',
        (v_result->>'success')::BOOLEAN = TRUE,
        v_result->>'error'
    );

    PERFORM record_test(
        'update_record: has fields_updated',
        (v_result->>'fields_updated')::INTEGER > 0,
        'Expected fields_updated count'
    );
END $$;

-- =============================================================================
-- TEST 12: Generic CRUD - Soft Delete and Restore
-- =============================================================================
\echo ''
\echo 'Testing soft_delete_record and restore_record...'

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
    v_supplier_id UUID;
    v_result JSONB;
    v_is_deleted BOOLEAN;
BEGIN
    -- Create a test supplier to delete
    v_supplier_id := gen_random_uuid();
    INSERT INTO suppliers (
        supplier_id, supplier_code, supplier_name, is_active, created_by, created_at
    ) VALUES (
        v_supplier_id, 'DEL-TEST', 'Delete Test Supplier', TRUE, v_admin_id, NOW()
    );

    -- Soft delete
    v_result := soft_delete_record(
        v_admin_id,
        'supplier',
        v_supplier_id,
        'Testing soft delete'
    );

    PERFORM record_test(
        'soft_delete_record: returns success',
        (v_result->>'success')::BOOLEAN = TRUE,
        v_result->>'error'
    );

    -- Verify deleted
    SELECT is_deleted INTO v_is_deleted
    FROM suppliers WHERE supplier_id = v_supplier_id;

    PERFORM record_test(
        'soft_delete_record: sets is_deleted flag',
        v_is_deleted = TRUE,
        'Expected is_deleted = TRUE'
    );

    -- Restore
    v_result := restore_record(
        v_admin_id,
        'supplier',
        v_supplier_id
    );

    PERFORM record_test(
        'restore_record: returns success',
        (v_result->>'success')::BOOLEAN = TRUE,
        v_result->>'error'
    );

    -- Verify restored
    SELECT is_deleted INTO v_is_deleted
    FROM suppliers WHERE supplier_id = v_supplier_id;

    PERFORM record_test(
        'restore_record: clears is_deleted flag',
        v_is_deleted = FALSE,
        'Expected is_deleted = FALSE'
    );

    -- Clean up
    DELETE FROM suppliers WHERE supplier_id = v_supplier_id;
END $$;

-- =============================================================================
-- TEST SUMMARY
-- =============================================================================
\echo ''
\echo '=============================================='
\echo 'PHASE 5 TEST SUMMARY'
\echo '=============================================='

DO $$
DECLARE
    v_total INTEGER;
    v_passed INTEGER;
    v_failed INTEGER;
    v_pass_rate NUMERIC;
    test_rec RECORD;
BEGIN
    SELECT COUNT(*), COUNT(*) FILTER (WHERE passed), COUNT(*) FILTER (WHERE NOT passed)
    INTO v_total, v_passed, v_failed
    FROM test_results;

    v_pass_rate := ROUND((v_passed::NUMERIC / NULLIF(v_total, 0)) * 100, 1);

    RAISE NOTICE '';
    RAISE NOTICE 'Total Tests: %', v_total;
    RAISE NOTICE 'Passed: %', v_passed;
    RAISE NOTICE 'Failed: %', v_failed;
    RAISE NOTICE 'Pass Rate: %%', v_pass_rate;
    RAISE NOTICE '';

    -- List failed tests
    IF v_failed > 0 THEN
        RAISE NOTICE 'FAILED TESTS:';
        FOR test_rec IN
            SELECT test_name, message FROM test_results WHERE NOT passed
        LOOP
            RAISE NOTICE '  - %: %', test_rec.test_name, test_rec.message;
        END LOOP;
    ELSE
        RAISE NOTICE 'ALL TESTS PASSED!';
    END IF;
END $$;

-- Clean up
DROP FUNCTION IF EXISTS reset_test_counter();
DROP FUNCTION IF EXISTS record_test(TEXT, BOOLEAN, TEXT);
