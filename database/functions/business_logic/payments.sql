-- Business Logic Functions
-- Module: Payments
-- Description: Payment creation, processing, and clearing
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- HELPER FUNCTION: Validate Payment Status Transition
-- =============================================================================

CREATE OR REPLACE FUNCTION validate_payment_status_transition(
    p_current_status VARCHAR,
    p_new_status VARCHAR
)
RETURNS BOOLEAN AS $$
DECLARE
    v_valid_transitions JSONB := '{
        "pending": ["processed", "cancelled", "failed"],
        "processed": ["cleared", "failed", "reversed"],
        "cleared": ["reversed"],
        "failed": ["pending"],
        "cancelled": [],
        "reversed": []
    }'::JSONB;
    v_allowed TEXT[];
BEGIN
    SELECT ARRAY(SELECT jsonb_array_elements_text(v_valid_transitions -> p_current_status))
    INTO v_allowed;

    RETURN p_new_status = ANY(v_allowed);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION validate_payment_status_transition(VARCHAR, VARCHAR) IS 'Validates payment status transitions';

-- =============================================================================
-- HELPER FUNCTION: Get Invoice Payment Info
-- =============================================================================

CREATE OR REPLACE FUNCTION get_invoice_payment_info(
    p_invoice_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_invoice RECORD;
    v_total_paid DECIMAL;
    v_remaining DECIMAL;
BEGIN
    SELECT
        ir.invoice_id,
        ir.invoice_number,
        ir.total_amount,
        ir.currency,
        ir.payment_status,
        ir.due_date
    INTO v_invoice
    FROM invoice_receipts ir
    WHERE ir.invoice_id = p_invoice_id
      AND ir.is_deleted = FALSE;

    IF v_invoice IS NULL THEN
        RETURN jsonb_build_object('error', 'Invoice not found');
    END IF;

    -- Calculate total paid
    SELECT COALESCE(SUM(amount), 0)
    INTO v_total_paid
    FROM payments
    WHERE invoice_id = p_invoice_id
      AND status IN ('processed', 'cleared')
      AND is_deleted = FALSE;

    v_remaining := v_invoice.total_amount - v_total_paid;

    RETURN jsonb_build_object(
        'invoice_id', v_invoice.invoice_id,
        'invoice_number', v_invoice.invoice_number,
        'total_amount', v_invoice.total_amount,
        'currency', v_invoice.currency,
        'total_paid', v_total_paid,
        'remaining_amount', v_remaining,
        'payment_status', v_invoice.payment_status,
        'due_date', v_invoice.due_date,
        'is_overdue', v_invoice.due_date < CURRENT_DATE AND v_remaining > 0
    );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_invoice_payment_info(UUID) IS 'Gets payment information for an invoice';

-- =============================================================================
-- FUNCTION: Create Payment
-- =============================================================================
-- Creates a payment for an invoice

CREATE OR REPLACE FUNCTION create_payment(
    p_user_id UUID,
    p_invoice_id UUID,
    p_amount DECIMAL,
    p_payment_method VARCHAR DEFAULT 'bank_transfer',
    p_payment_date DATE DEFAULT CURRENT_DATE,
    p_reference_number VARCHAR DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_payment_id UUID;
    v_payment_number VARCHAR;
    v_invoice_info JSONB;
    v_remaining DECIMAL;
    v_new_payment_status VARCHAR;
BEGIN
    -- Validate user has create permission
    IF NOT can_user_perform_action(p_user_id, 'payment', 'create') THEN
        RAISE EXCEPTION 'User does not have permission to create payments';
    END IF;

    -- Get invoice payment info
    v_invoice_info := get_invoice_payment_info(p_invoice_id);

    IF v_invoice_info ? 'error' THEN
        RAISE EXCEPTION '%', v_invoice_info->>'error';
    END IF;

    -- Validate invoice is payable
    IF (v_invoice_info->>'payment_status') = 'paid' THEN
        RAISE EXCEPTION 'Invoice is already fully paid';
    END IF;

    v_remaining := (v_invoice_info->>'remaining_amount')::DECIMAL;

    -- Validate payment amount
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be positive';
    END IF;

    IF p_amount > v_remaining THEN
        RAISE EXCEPTION 'Payment amount (%) exceeds remaining balance (%)',
            p_amount, v_remaining;
    END IF;

    -- Generate payment ID
    v_payment_id := gen_random_uuid();

    -- Create the payment
    INSERT INTO payments (
        payment_id,
        invoice_id,
        payment_date,
        amount,
        currency,
        payment_method,
        reference_number,
        status,
        notes,
        created_by,
        created_at
    ) VALUES (
        v_payment_id,
        p_invoice_id,
        p_payment_date,
        p_amount,
        v_invoice_info->>'currency',
        p_payment_method,
        p_reference_number,
        'pending',
        p_notes,
        p_user_id,
        NOW()
    )
    RETURNING payment_number INTO v_payment_number;

    -- Update invoice payment status
    IF p_amount = v_remaining THEN
        v_new_payment_status := 'paid';
    ELSE
        v_new_payment_status := 'partial';
    END IF;

    -- Note: Invoice status will be updated when payment is processed

    RETURN jsonb_build_object(
        'success', TRUE,
        'payment_id', v_payment_id,
        'payment_number', v_payment_number,
        'invoice_number', v_invoice_info->>'invoice_number',
        'amount', p_amount,
        'remaining_after', v_remaining - p_amount,
        'status', 'pending',
        'message', 'Payment created. Pending processing.'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION create_payment(UUID, UUID, DECIMAL, VARCHAR, DATE, VARCHAR, TEXT) IS 'Creates a payment for an invoice';

-- =============================================================================
-- FUNCTION: Process Payment
-- =============================================================================
-- Marks a payment as processed (funds transferred)

CREATE OR REPLACE FUNCTION process_payment(
    p_user_id UUID,
    p_payment_id UUID,
    p_transaction_id VARCHAR DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_payment_record RECORD;
    v_invoice_info JSONB;
    v_total_paid DECIMAL;
    v_new_invoice_status VARCHAR;
BEGIN
    -- Validate user has process permission
    IF NOT can_user_perform_action(p_user_id, 'payment', 'process') THEN
        RAISE EXCEPTION 'User does not have permission to process payments';
    END IF;

    -- Get payment info
    SELECT
        p.payment_id,
        p.payment_number,
        p.invoice_id,
        p.amount,
        p.status
    INTO v_payment_record
    FROM payments p
    WHERE p.payment_id = p_payment_id
      AND p.is_deleted = FALSE;

    IF v_payment_record IS NULL THEN
        RAISE EXCEPTION 'Payment not found: %', p_payment_id;
    END IF;

    -- Validate status transition
    IF NOT validate_payment_status_transition(v_payment_record.status, 'processed') THEN
        RAISE EXCEPTION 'Cannot process payment with status: %', v_payment_record.status;
    END IF;

    -- Update payment status
    UPDATE payments
    SET status = 'processed',
        processed_at = NOW(),
        processed_by = p_user_id,
        transaction_id = p_transaction_id,
        updated_at = NOW(),
        updated_by = p_user_id
    WHERE payment_id = p_payment_id;

    -- Calculate new total paid for invoice
    SELECT COALESCE(SUM(amount), 0)
    INTO v_total_paid
    FROM payments
    WHERE invoice_id = v_payment_record.invoice_id
      AND status IN ('processed', 'cleared')
      AND is_deleted = FALSE;

    -- Get invoice info
    v_invoice_info := get_invoice_payment_info(v_payment_record.invoice_id);

    -- Determine new invoice payment status
    IF v_total_paid >= (v_invoice_info->>'total_amount')::DECIMAL THEN
        v_new_invoice_status := 'paid';
    ELSIF v_total_paid > 0 THEN
        v_new_invoice_status := 'partial';
    ELSE
        v_new_invoice_status := 'unpaid';
    END IF;

    -- Update invoice payment status
    UPDATE invoice_receipts
    SET payment_status = v_new_invoice_status,
        updated_at = NOW()
    WHERE invoice_id = v_payment_record.invoice_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'payment_id', p_payment_id,
        'payment_number', v_payment_record.payment_number,
        'old_status', v_payment_record.status,
        'new_status', 'processed',
        'invoice_status', v_new_invoice_status,
        'message', 'Payment processed successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION process_payment(UUID, UUID, VARCHAR) IS 'Processes a pending payment';

-- =============================================================================
-- FUNCTION: Clear Payment
-- =============================================================================
-- Marks a payment as cleared (bank reconciliation complete)

CREATE OR REPLACE FUNCTION clear_payment(
    p_user_id UUID,
    p_payment_id UUID,
    p_cleared_date DATE DEFAULT CURRENT_DATE,
    p_bank_reference VARCHAR DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_payment_record RECORD;
    v_clearing_id UUID;
BEGIN
    -- Validate user has clear permission
    IF NOT can_user_perform_action(p_user_id, 'payment', 'clear') THEN
        RAISE EXCEPTION 'User does not have permission to clear payments';
    END IF;

    -- Get payment info
    SELECT
        p.payment_id,
        p.payment_number,
        p.invoice_id,
        p.amount,
        p.status
    INTO v_payment_record
    FROM payments p
    WHERE p.payment_id = p_payment_id
      AND p.is_deleted = FALSE;

    IF v_payment_record IS NULL THEN
        RAISE EXCEPTION 'Payment not found: %', p_payment_id;
    END IF;

    -- Validate status transition
    IF NOT validate_payment_status_transition(v_payment_record.status, 'cleared') THEN
        RAISE EXCEPTION 'Cannot clear payment with status: %. Must be processed first.',
            v_payment_record.status;
    END IF;

    -- Update payment status
    UPDATE payments
    SET status = 'cleared',
        cleared_at = NOW(),
        cleared_by = p_user_id,
        bank_reference = p_bank_reference,
        updated_at = NOW(),
        updated_by = p_user_id
    WHERE payment_id = p_payment_id;

    -- Create clearing entry for audit trail
    v_clearing_id := gen_random_uuid();

    INSERT INTO clearing_entries (
        clearing_id,
        payment_id,
        invoice_id,
        clearing_date,
        amount,
        clearing_type,
        bank_reference,
        status,
        created_by,
        created_at
    ) VALUES (
        v_clearing_id,
        p_payment_id,
        v_payment_record.invoice_id,
        p_cleared_date,
        v_payment_record.amount,
        'payment',
        p_bank_reference,
        'completed',
        p_user_id,
        NOW()
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'payment_id', p_payment_id,
        'payment_number', v_payment_record.payment_number,
        'clearing_id', v_clearing_id,
        'old_status', v_payment_record.status,
        'new_status', 'cleared',
        'message', 'Payment cleared and reconciled'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION clear_payment(UUID, UUID, DATE, VARCHAR) IS 'Clears a processed payment';

-- =============================================================================
-- FUNCTION: Cancel Payment
-- =============================================================================
-- Cancels a pending payment

CREATE OR REPLACE FUNCTION cancel_payment(
    p_user_id UUID,
    p_payment_id UUID,
    p_cancellation_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_payment_record RECORD;
BEGIN
    -- Validate user has cancel permission
    IF NOT can_user_perform_action(p_user_id, 'payment', 'delete') THEN
        RAISE EXCEPTION 'User does not have permission to cancel payments';
    END IF;

    -- Validate reason
    IF p_cancellation_reason IS NULL OR TRIM(p_cancellation_reason) = '' THEN
        RAISE EXCEPTION 'Cancellation reason is required';
    END IF;

    -- Get payment info
    SELECT payment_id, payment_number, status
    INTO v_payment_record
    FROM payments
    WHERE payment_id = p_payment_id
      AND is_deleted = FALSE;

    IF v_payment_record IS NULL THEN
        RAISE EXCEPTION 'Payment not found: %', p_payment_id;
    END IF;

    -- Validate status transition
    IF NOT validate_payment_status_transition(v_payment_record.status, 'cancelled') THEN
        RAISE EXCEPTION 'Cannot cancel payment with status: %. Only pending payments can be cancelled.',
            v_payment_record.status;
    END IF;

    -- Update payment status
    UPDATE payments
    SET status = 'cancelled',
        cancelled_at = NOW(),
        cancelled_by = p_user_id,
        cancellation_reason = p_cancellation_reason,
        updated_at = NOW(),
        updated_by = p_user_id
    WHERE payment_id = p_payment_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'payment_id', p_payment_id,
        'payment_number', v_payment_record.payment_number,
        'old_status', v_payment_record.status,
        'new_status', 'cancelled',
        'message', 'Payment cancelled'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION cancel_payment(UUID, UUID, TEXT) IS 'Cancels a pending payment';

-- =============================================================================
-- FUNCTION: Reverse Payment
-- =============================================================================
-- Reverses a processed or cleared payment

CREATE OR REPLACE FUNCTION reverse_payment(
    p_user_id UUID,
    p_payment_id UUID,
    p_reversal_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_payment_record RECORD;
    v_invoice_info JSONB;
    v_total_paid DECIMAL;
    v_new_invoice_status VARCHAR;
BEGIN
    -- Validate user has reverse permission
    IF NOT can_user_perform_action(p_user_id, 'payment', 'reverse') THEN
        RAISE EXCEPTION 'User does not have permission to reverse payments';
    END IF;

    -- Validate reason
    IF p_reversal_reason IS NULL OR TRIM(p_reversal_reason) = '' THEN
        RAISE EXCEPTION 'Reversal reason is required';
    END IF;

    -- Get payment info
    SELECT payment_id, payment_number, invoice_id, amount, status
    INTO v_payment_record
    FROM payments
    WHERE payment_id = p_payment_id
      AND is_deleted = FALSE;

    IF v_payment_record IS NULL THEN
        RAISE EXCEPTION 'Payment not found: %', p_payment_id;
    END IF;

    -- Validate status transition
    IF NOT validate_payment_status_transition(v_payment_record.status, 'reversed') THEN
        RAISE EXCEPTION 'Cannot reverse payment with status: %. Only processed or cleared payments can be reversed.',
            v_payment_record.status;
    END IF;

    -- Update payment status
    UPDATE payments
    SET status = 'reversed',
        reversed_at = NOW(),
        reversed_by = p_user_id,
        reversal_reason = p_reversal_reason,
        updated_at = NOW(),
        updated_by = p_user_id
    WHERE payment_id = p_payment_id;

    -- Update any clearing entries
    UPDATE clearing_entries
    SET status = 'reversed',
        reversed_at = NOW(),
        reversed_by = p_user_id
    WHERE payment_id = p_payment_id;

    -- Recalculate invoice payment status
    SELECT COALESCE(SUM(amount), 0)
    INTO v_total_paid
    FROM payments
    WHERE invoice_id = v_payment_record.invoice_id
      AND status IN ('processed', 'cleared')
      AND is_deleted = FALSE;

    v_invoice_info := get_invoice_payment_info(v_payment_record.invoice_id);

    IF v_total_paid >= (v_invoice_info->>'total_amount')::DECIMAL THEN
        v_new_invoice_status := 'paid';
    ELSIF v_total_paid > 0 THEN
        v_new_invoice_status := 'partial';
    ELSE
        v_new_invoice_status := 'unpaid';
    END IF;

    UPDATE invoice_receipts
    SET payment_status = v_new_invoice_status,
        updated_at = NOW()
    WHERE invoice_id = v_payment_record.invoice_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'payment_id', p_payment_id,
        'payment_number', v_payment_record.payment_number,
        'old_status', v_payment_record.status,
        'new_status', 'reversed',
        'invoice_status', v_new_invoice_status,
        'message', 'Payment reversed'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION reverse_payment(UUID, UUID, TEXT) IS 'Reverses a processed or cleared payment';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Create a payment
SELECT create_payment(
    '00000000-0000-0000-0000-000000000100'::UUID,
    (SELECT invoice_id FROM invoice_receipts WHERE payment_status = 'unpaid' LIMIT 1),
    1000.00,
    'bank_transfer',
    CURRENT_DATE,
    'REF-12345',
    'Payment for Q1 supplies'
);

-- Process the payment
SELECT process_payment(
    '00000000-0000-0000-0000-000000000100'::UUID,
    (SELECT payment_id FROM payments WHERE status = 'pending' ORDER BY created_at DESC LIMIT 1),
    'TXN-987654'
);

-- Clear the payment
SELECT clear_payment(
    '00000000-0000-0000-0000-000000000100'::UUID,
    (SELECT payment_id FROM payments WHERE status = 'processed' ORDER BY created_at DESC LIMIT 1),
    CURRENT_DATE,
    'BANK-REF-123'
);

-- Get invoice payment info
SELECT get_invoice_payment_info(
    (SELECT invoice_id FROM invoice_receipts LIMIT 1)
);
*/
