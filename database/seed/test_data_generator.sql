-- =============================================================================
-- TEST DATA GENERATOR
-- Generates realistic test data at various scales for the P2P workflow
-- =============================================================================

-- Usage:
-- Small (100 POs):   SELECT generate_test_data('small');
-- Medium (1k POs):   SELECT generate_test_data('medium');
-- Large (10k POs):   SELECT generate_test_data('large');
-- Stress (100k POs): SELECT generate_test_data('stress');

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Generate random date within range
CREATE OR REPLACE FUNCTION random_date(start_date DATE, end_date DATE)
RETURNS DATE AS $$
BEGIN
    RETURN start_date + (random() * (end_date - start_date))::INTEGER;
END;
$$ LANGUAGE plpgsql;

-- Generate random decimal
CREATE OR REPLACE FUNCTION random_decimal(min_val NUMERIC, max_val NUMERIC, decimals INTEGER DEFAULT 2)
RETURNS NUMERIC AS $$
BEGIN
    RETURN ROUND((min_val + random() * (max_val - min_val))::NUMERIC, decimals);
END;
$$ LANGUAGE plpgsql;

-- Generate random item code
CREATE OR REPLACE FUNCTION random_item_code()
RETURNS VARCHAR AS $$
BEGIN
    RETURN 'ITEM-' || UPPER(SUBSTRING(MD5(random()::TEXT) FROM 1 FOR 8));
END;
$$ LANGUAGE plpgsql;

-- Generate random supplier code
CREATE OR REPLACE FUNCTION random_supplier_code()
RETURNS VARCHAR AS $$
BEGIN
    RETURN 'SUP-' || UPPER(SUBSTRING(MD5(random()::TEXT) FROM 1 FOR 6));
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- MAIN GENERATOR FUNCTION
-- =============================================================================

CREATE OR REPLACE FUNCTION generate_test_data(
    p_scale VARCHAR DEFAULT 'small'  -- 'small', 'medium', 'large', 'stress'
) RETURNS JSONB AS $$
DECLARE
    v_num_suppliers INTEGER;
    v_num_pos INTEGER;
    v_lines_per_po INTEGER;
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
    v_start_time TIMESTAMP;
    v_supplier_ids UUID[];
    v_po_ids UUID[];
    v_supplier_id UUID;
    v_po_id UUID;
    v_gr_id UUID;
    v_invoice_id UUID;
    v_i INTEGER;
    v_j INTEGER;
    v_line_num INTEGER;
    v_total NUMERIC;
    v_result JSONB;
BEGIN
    v_start_time := clock_timestamp();

    -- Set scale parameters
    CASE p_scale
        WHEN 'small' THEN
            v_num_suppliers := 10;
            v_num_pos := 100;
            v_lines_per_po := 3;
        WHEN 'medium' THEN
            v_num_suppliers := 50;
            v_num_pos := 1000;
            v_lines_per_po := 4;
        WHEN 'large' THEN
            v_num_suppliers := 200;
            v_num_pos := 10000;
            v_lines_per_po := 5;
        WHEN 'stress' THEN
            v_num_suppliers := 500;
            v_num_pos := 100000;
            v_lines_per_po := 5;
        ELSE
            RAISE EXCEPTION 'Invalid scale: %. Use small, medium, large, or stress', p_scale;
    END CASE;

    RAISE NOTICE 'Generating % test data: % suppliers, % POs', p_scale, v_num_suppliers, v_num_pos;

    -- ==========================================================================
    -- GENERATE SUPPLIERS
    -- ==========================================================================
    RAISE NOTICE 'Generating suppliers...';

    FOR v_i IN 1..v_num_suppliers LOOP
        INSERT INTO suppliers (
            supplier_id, supplier_code, supplier_name, contact_name,
            email, phone, address, city, country,
            payment_terms_days, is_active, created_by, created_at
        ) VALUES (
            gen_random_uuid(),
            random_supplier_code() || v_i,
            'Test Supplier ' || v_i || ' - ' ||
                CASE (v_i % 5)
                    WHEN 0 THEN 'Industrial Supply Co'
                    WHEN 1 THEN 'Tech Parts Inc'
                    WHEN 2 THEN 'Manufacturing Ltd'
                    WHEN 3 THEN 'Global Traders'
                    ELSE 'Premium Goods LLC'
                END,
            'Contact Person ' || v_i,
            'supplier' || v_i || '@testdata.com',
            '+1-555-' || LPAD(v_i::TEXT, 4, '0'),
            v_i || ' Test Street',
            CASE (v_i % 10)
                WHEN 0 THEN 'New York'
                WHEN 1 THEN 'Los Angeles'
                WHEN 2 THEN 'Chicago'
                WHEN 3 THEN 'Houston'
                WHEN 4 THEN 'Phoenix'
                WHEN 5 THEN 'Philadelphia'
                WHEN 6 THEN 'San Antonio'
                WHEN 7 THEN 'San Diego'
                WHEN 8 THEN 'Dallas'
                ELSE 'Seattle'
            END,
            'USA',
            CASE (v_i % 4) WHEN 0 THEN 15 WHEN 1 THEN 30 WHEN 2 THEN 45 ELSE 60 END,
            TRUE,
            v_admin_id,
            NOW()
        )
        RETURNING supplier_id INTO v_supplier_id;

        v_supplier_ids := array_append(v_supplier_ids, v_supplier_id);
    END LOOP;

    RAISE NOTICE 'Created % suppliers', array_length(v_supplier_ids, 1);

    -- ==========================================================================
    -- GENERATE PURCHASE ORDERS WITH LINES
    -- ==========================================================================
    RAISE NOTICE 'Generating purchase orders...';

    FOR v_i IN 1..v_num_pos LOOP
        -- Select random supplier
        v_supplier_id := v_supplier_ids[1 + (random() * (array_length(v_supplier_ids, 1) - 1))::INTEGER];

        -- Create PO
        INSERT INTO purchase_orders (
            po_id, po_number, supplier_id, po_date, expected_delivery_date,
            total_amount, currency, status, notes, is_deleted,
            created_by, created_at
        ) VALUES (
            gen_random_uuid(),
            'PO-' || LPAD(v_i::TEXT, 8, '0'),
            v_supplier_id,
            random_date(CURRENT_DATE - INTERVAL '1 year', CURRENT_DATE),
            random_date(CURRENT_DATE, CURRENT_DATE + INTERVAL '3 months'),
            0,  -- Will update after lines
            CASE (random() * 2)::INTEGER WHEN 0 THEN 'USD' WHEN 1 THEN 'EUR' ELSE 'GBP' END,
            CASE (random() * 5)::INTEGER
                WHEN 0 THEN 'draft'
                WHEN 1 THEN 'submitted'
                WHEN 2 THEN 'approved'
                WHEN 3 THEN 'partially_received'
                ELSE 'fully_received'
            END,
            'Test PO ' || v_i,
            FALSE,
            v_admin_id,
            NOW()
        )
        RETURNING po_id INTO v_po_id;

        v_po_ids := array_append(v_po_ids, v_po_id);
        v_total := 0;

        -- Create lines
        FOR v_j IN 1..v_lines_per_po LOOP
            DECLARE
                v_qty INTEGER := (10 + random() * 90)::INTEGER;
                v_price NUMERIC := random_decimal(10, 500);
                v_line_total NUMERIC := v_qty * v_price;
            BEGIN
                INSERT INTO purchase_order_lines (
                    line_id, po_id, line_number, item_code, item_description,
                    quantity_ordered, unit_price, line_total, uom,
                    quantity_received, quantity_invoiced, is_deleted
                ) VALUES (
                    gen_random_uuid(),
                    v_po_id,
                    v_j,
                    random_item_code(),
                    'Test Item ' || v_i || '-' || v_j || ' ' ||
                        CASE (v_j % 5)
                            WHEN 0 THEN 'Widget'
                            WHEN 1 THEN 'Component'
                            WHEN 2 THEN 'Assembly'
                            WHEN 3 THEN 'Part'
                            ELSE 'Material'
                        END,
                    v_qty,
                    v_price,
                    v_line_total,
                    CASE (random() * 4)::INTEGER
                        WHEN 0 THEN 'EA'
                        WHEN 1 THEN 'PC'
                        WHEN 2 THEN 'BOX'
                        WHEN 3 THEN 'KG'
                        ELSE 'LT'
                    END,
                    CASE WHEN random() > 0.3 THEN v_qty ELSE (v_qty * random())::INTEGER END,
                    0,
                    FALSE
                );

                v_total := v_total + v_line_total;
            END;
        END LOOP;

        -- Update PO total
        UPDATE purchase_orders SET total_amount = v_total WHERE po_id = v_po_id;

        -- Progress indicator
        IF v_i % 1000 = 0 THEN
            RAISE NOTICE 'Created % / % POs...', v_i, v_num_pos;
        END IF;
    END LOOP;

    RAISE NOTICE 'Created % purchase orders', array_length(v_po_ids, 1);

    -- ==========================================================================
    -- GENERATE GOODS RECEIPTS (for approved/received POs)
    -- ==========================================================================
    RAISE NOTICE 'Generating goods receipts...';

    DECLARE
        v_gr_count INTEGER := 0;
        v_po_rec RECORD;
    BEGIN
        FOR v_po_rec IN
            SELECT po_id, po_date
            FROM purchase_orders
            WHERE status IN ('approved', 'partially_received', 'fully_received')
            AND is_deleted = FALSE
        LOOP
            INSERT INTO goods_receipts (
                gr_id, gr_number, po_id, receipt_date, delivery_note_number,
                quality_status, notes, is_deleted, created_by, created_at
            ) VALUES (
                gen_random_uuid(),
                'GR-' || LPAD((v_gr_count + 1)::TEXT, 8, '0'),
                v_po_rec.po_id,
                v_po_rec.po_date + (random() * 30)::INTEGER,
                'DN-' || UPPER(SUBSTRING(MD5(random()::TEXT) FROM 1 FOR 8)),
                CASE (random() * 2)::INTEGER
                    WHEN 0 THEN 'accepted'
                    WHEN 1 THEN 'pending'
                    ELSE 'rejected'
                END,
                'Test goods receipt',
                FALSE,
                v_admin_id,
                NOW()
            )
            RETURNING gr_id INTO v_gr_id;

            v_gr_count := v_gr_count + 1;

            -- Progress indicator
            IF v_gr_count % 1000 = 0 THEN
                RAISE NOTICE 'Created % goods receipts...', v_gr_count;
            END IF;
        END LOOP;

        RAISE NOTICE 'Created % goods receipts', v_gr_count;
    END;

    -- ==========================================================================
    -- GENERATE INVOICES (for fully received POs)
    -- ==========================================================================
    RAISE NOTICE 'Generating invoices...';

    DECLARE
        v_inv_count INTEGER := 0;
        v_po_rec RECORD;
    BEGIN
        FOR v_po_rec IN
            SELECT po_id, po_date, total_amount, currency
            FROM purchase_orders
            WHERE status = 'fully_received'
            AND is_deleted = FALSE
        LOOP
            INSERT INTO invoice_receipts (
                invoice_id, invoice_number, po_id, vendor_invoice_number,
                invoice_date, due_date, total_amount, currency,
                matching_status, notes, is_deleted, created_by, created_at
            ) VALUES (
                gen_random_uuid(),
                'INV-' || LPAD((v_inv_count + 1)::TEXT, 8, '0'),
                v_po_rec.po_id,
                'VINV-' || UPPER(SUBSTRING(MD5(random()::TEXT) FROM 1 FOR 8)),
                v_po_rec.po_date + (random() * 45)::INTEGER,
                v_po_rec.po_date + (random() * 45)::INTEGER + 30,
                v_po_rec.total_amount,
                v_po_rec.currency,
                CASE (random() * 2)::INTEGER
                    WHEN 0 THEN 'matched'
                    WHEN 1 THEN 'pending'
                    ELSE 'variance'
                END,
                'Test invoice',
                FALSE,
                v_admin_id,
                NOW()
            )
            RETURNING invoice_id INTO v_invoice_id;

            v_inv_count := v_inv_count + 1;

            -- Progress indicator
            IF v_inv_count % 1000 = 0 THEN
                RAISE NOTICE 'Created % invoices...', v_inv_count;
            END IF;
        END LOOP;

        RAISE NOTICE 'Created % invoices', v_inv_count;
    END;

    -- ==========================================================================
    -- GENERATE PAYMENTS (for matched invoices)
    -- ==========================================================================
    RAISE NOTICE 'Generating payments...';

    DECLARE
        v_pay_count INTEGER := 0;
        v_inv_rec RECORD;
    BEGIN
        FOR v_inv_rec IN
            SELECT invoice_id, invoice_date, total_amount
            FROM invoice_receipts
            WHERE matching_status = 'matched'
            AND is_deleted = FALSE
        LOOP
            INSERT INTO payments (
                payment_id, payment_number, invoice_id, amount,
                payment_method, payment_date, reference_number,
                status, notes, is_deleted, created_by, created_at
            ) VALUES (
                gen_random_uuid(),
                'PAY-' || LPAD((v_pay_count + 1)::TEXT, 8, '0'),
                v_inv_rec.invoice_id,
                v_inv_rec.total_amount,
                CASE (random() * 3)::INTEGER
                    WHEN 0 THEN 'bank_transfer'
                    WHEN 1 THEN 'check'
                    WHEN 2 THEN 'wire'
                    ELSE 'credit_card'
                END,
                v_inv_rec.invoice_date + (random() * 30)::INTEGER,
                'REF-' || UPPER(SUBSTRING(MD5(random()::TEXT) FROM 1 FOR 10)),
                CASE (random() * 2)::INTEGER
                    WHEN 0 THEN 'cleared'
                    WHEN 1 THEN 'processed'
                    ELSE 'pending'
                END,
                'Test payment',
                FALSE,
                v_admin_id,
                NOW()
            );

            v_pay_count := v_pay_count + 1;

            -- Progress indicator
            IF v_pay_count % 1000 = 0 THEN
                RAISE NOTICE 'Created % payments...', v_pay_count;
            END IF;
        END LOOP;

        RAISE NOTICE 'Created % payments', v_pay_count;
    END;

    -- ==========================================================================
    -- SUMMARY
    -- ==========================================================================
    v_result := jsonb_build_object(
        'scale', p_scale,
        'suppliers_created', array_length(v_supplier_ids, 1),
        'purchase_orders_created', array_length(v_po_ids, 1),
        'duration_seconds', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)),
        'completed_at', NOW()
    );

    RAISE NOTICE 'Test data generation complete!';
    RAISE NOTICE 'Duration: % seconds', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time));

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- CLEANUP FUNCTION
-- =============================================================================

CREATE OR REPLACE FUNCTION cleanup_test_data()
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
    v_counts RECORD;
BEGIN
    -- Count records before cleanup
    SELECT
        (SELECT COUNT(*) FROM suppliers WHERE supplier_code LIKE 'SUP-%') AS suppliers,
        (SELECT COUNT(*) FROM purchase_orders WHERE po_number LIKE 'PO-%') AS pos,
        (SELECT COUNT(*) FROM goods_receipts WHERE gr_number LIKE 'GR-%') AS grs,
        (SELECT COUNT(*) FROM invoice_receipts WHERE invoice_number LIKE 'INV-%') AS invoices,
        (SELECT COUNT(*) FROM payments WHERE payment_number LIKE 'PAY-%') AS payments
    INTO v_counts;

    RAISE NOTICE 'Cleaning up test data...';
    RAISE NOTICE 'Found: % suppliers, % POs, % GRs, % invoices, % payments',
        v_counts.suppliers, v_counts.pos, v_counts.grs, v_counts.invoices, v_counts.payments;

    -- Delete in reverse order of dependencies
    DELETE FROM payments WHERE payment_number LIKE 'PAY-%';
    DELETE FROM invoice_lines WHERE invoice_id IN (SELECT invoice_id FROM invoice_receipts WHERE invoice_number LIKE 'INV-%');
    DELETE FROM invoice_receipts WHERE invoice_number LIKE 'INV-%';
    DELETE FROM goods_receipt_lines WHERE gr_id IN (SELECT gr_id FROM goods_receipts WHERE gr_number LIKE 'GR-%');
    DELETE FROM goods_receipts WHERE gr_number LIKE 'GR-%';
    DELETE FROM purchase_order_lines WHERE po_id IN (SELECT po_id FROM purchase_orders WHERE po_number LIKE 'PO-%');
    DELETE FROM purchase_orders WHERE po_number LIKE 'PO-%';
    DELETE FROM suppliers WHERE supplier_code LIKE 'SUP-%';

    v_result := jsonb_build_object(
        'suppliers_deleted', v_counts.suppliers,
        'purchase_orders_deleted', v_counts.pos,
        'goods_receipts_deleted', v_counts.grs,
        'invoices_deleted', v_counts.invoices,
        'payments_deleted', v_counts.payments,
        'completed_at', NOW()
    );

    RAISE NOTICE 'Cleanup complete!';

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- USAGE EXAMPLES
-- =============================================================================
COMMENT ON FUNCTION generate_test_data(VARCHAR) IS '
Generates test data at various scales:
  - small:  100 POs, 10 suppliers (~3 lines each)
  - medium: 1,000 POs, 50 suppliers (~4 lines each)
  - large:  10,000 POs, 200 suppliers (~5 lines each)
  - stress: 100,000 POs, 500 suppliers (~5 lines each)

Usage: SELECT generate_test_data(''medium'');

The function generates:
  1. Suppliers with realistic contact information
  2. Purchase orders with random statuses
  3. PO lines with items and quantities
  4. Goods receipts for approved/received POs
  5. Invoices for fully received POs
  6. Payments for matched invoices
';

COMMENT ON FUNCTION cleanup_test_data() IS '
Removes all test data generated by generate_test_data().
Identifies test data by naming convention (SUP-%, PO-%, etc.)
Safe to run multiple times.

Usage: SELECT cleanup_test_data();
';
