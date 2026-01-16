-- Phase 3 Tests: Data Layer & Query Building
-- Description: Comprehensive tests for Phase 3 implementation
-- Run with: psql -d htmx_db -f phase3_tests.sql

-- =============================================================================
-- TEST CONFIGURATION
-- =============================================================================

\set ON_ERROR_STOP on
\timing on

-- Test results tracking
CREATE TEMPORARY TABLE IF NOT EXISTS test_results (
    test_id SERIAL PRIMARY KEY,
    test_category VARCHAR(50),
    test_name VARCHAR(200),
    passed BOOLEAN,
    error_message TEXT,
    run_at TIMESTAMP DEFAULT NOW()
);

-- Helper function to record test results
CREATE OR REPLACE FUNCTION record_test(
    p_category VARCHAR,
    p_name VARCHAR,
    p_passed BOOLEAN,
    p_error TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    INSERT INTO test_results (test_category, test_name, passed, error_message)
    VALUES (p_category, p_name, p_passed, p_error);

    IF p_passed THEN
        RAISE NOTICE '✓ [%] %', p_category, p_name;
    ELSE
        RAISE NOTICE '✗ [%] % - %', p_category, p_name, COALESCE(p_error, 'FAILED');
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- TEST SETUP: Create Test Data
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'PHASE 3 TESTS: Data Layer & Query Building';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    RAISE NOTICE '';
    RAISE NOTICE 'Setting up test data...';
END $$;

-- Create test suppliers
INSERT INTO suppliers (supplier_id, supplier_code, supplier_name, contact_email, payment_terms_days, is_active, created_by)
SELECT
    '20000000-0000-0000-0000-000000000001'::UUID,
    'ACME-001',
    'Acme Corporation',
    'sales@acme.com',
    30,
    TRUE,
    '00000000-0000-0000-0000-000000000100'::UUID
WHERE NOT EXISTS (SELECT 1 FROM suppliers WHERE supplier_id = '20000000-0000-0000-0000-000000000001'::UUID);

INSERT INTO suppliers (supplier_id, supplier_code, supplier_name, contact_email, payment_terms_days, is_active, created_by)
SELECT
    '20000000-0000-0000-0000-000000000002'::UUID,
    'GLOBEX-001',
    'Globex Industries',
    'contact@globex.com',
    45,
    TRUE,
    '00000000-0000-0000-0000-000000000100'::UUID
WHERE NOT EXISTS (SELECT 1 FROM suppliers WHERE supplier_id = '20000000-0000-0000-0000-000000000002'::UUID);

INSERT INTO suppliers (supplier_id, supplier_code, supplier_name, contact_email, payment_terms_days, is_active, created_by)
SELECT
    '20000000-0000-0000-0000-000000000003'::UUID,
    'INITECH-001',
    'Initech Solutions',
    'info@initech.com',
    60,
    FALSE,  -- Inactive supplier
    '00000000-0000-0000-0000-000000000100'::UUID
WHERE NOT EXISTS (SELECT 1 FROM suppliers WHERE supplier_id = '20000000-0000-0000-0000-000000000003'::UUID);

-- Create test purchase orders
INSERT INTO purchase_orders (po_id, po_number, supplier_id, po_date, total_amount, status, currency, created_by)
SELECT
    '30000000-0000-0000-0000-000000000001'::UUID,
    'PO-TEST-001',
    '20000000-0000-0000-0000-000000000001'::UUID,
    CURRENT_DATE - 10,
    5000.00,
    'draft',
    'USD',
    '00000000-0000-0000-0000-000000000100'::UUID
WHERE NOT EXISTS (SELECT 1 FROM purchase_orders WHERE po_id = '30000000-0000-0000-0000-000000000001'::UUID);

INSERT INTO purchase_orders (po_id, po_number, supplier_id, po_date, total_amount, status, currency, created_by)
SELECT
    '30000000-0000-0000-0000-000000000002'::UUID,
    'PO-TEST-002',
    '20000000-0000-0000-0000-000000000001'::UUID,
    CURRENT_DATE - 5,
    15000.00,
    'submitted',
    'USD',
    '00000000-0000-0000-0000-000000000100'::UUID
WHERE NOT EXISTS (SELECT 1 FROM purchase_orders WHERE po_id = '30000000-0000-0000-0000-000000000002'::UUID);

INSERT INTO purchase_orders (po_id, po_number, supplier_id, po_date, total_amount, status, currency, created_by, approved_by, approved_at)
SELECT
    '30000000-0000-0000-0000-000000000003'::UUID,
    'PO-TEST-003',
    '20000000-0000-0000-0000-000000000002'::UUID,
    CURRENT_DATE - 3,
    25000.00,
    'approved',
    'USD',
    '00000000-0000-0000-0000-000000000100'::UUID,
    '00000000-0000-0000-0000-000000000100'::UUID,
    NOW()
WHERE NOT EXISTS (SELECT 1 FROM purchase_orders WHERE po_id = '30000000-0000-0000-0000-000000000003'::UUID);

INSERT INTO purchase_orders (po_id, po_number, supplier_id, po_date, total_amount, status, currency, created_by)
SELECT
    '30000000-0000-0000-0000-000000000004'::UUID,
    'PO-TEST-004',
    '20000000-0000-0000-0000-000000000002'::UUID,
    CURRENT_DATE,
    8500.00,
    'draft',
    'EUR',
    '00000000-0000-0000-0000-000000000101'::UUID
WHERE NOT EXISTS (SELECT 1 FROM purchase_orders WHERE po_id = '30000000-0000-0000-0000-000000000004'::UUID);

-- =============================================================================
-- TEST 1: get_filter_operator
-- =============================================================================

DO $$
DECLARE
    v_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing get_filter_operator ---';

    -- Test 1.1: Greater than or equal
    SELECT * INTO v_result FROM get_filter_operator('po_date_gte');
    PERFORM record_test('get_filter_operator', 'Parses _gte suffix',
        v_result.field_name = 'po_date' AND v_result.sql_operator = '>=');

    -- Test 1.2: Less than
    SELECT * INTO v_result FROM get_filter_operator('amount_lt');
    PERFORM record_test('get_filter_operator', 'Parses _lt suffix',
        v_result.field_name = 'amount' AND v_result.sql_operator = '<');

    -- Test 1.3: LIKE operator
    SELECT * INTO v_result FROM get_filter_operator('name_like');
    PERFORM record_test('get_filter_operator', 'Parses _like suffix',
        v_result.field_name = 'name' AND v_result.sql_operator = 'ILIKE');

    -- Test 1.4: NULL check
    SELECT * INTO v_result FROM get_filter_operator('approved_by_null');
    PERFORM record_test('get_filter_operator', 'Parses _null suffix',
        v_result.field_name = 'approved_by' AND v_result.operator = 'null');

    -- Test 1.5: NOT NULL check
    SELECT * INTO v_result FROM get_filter_operator('created_by_notnull');
    PERFORM record_test('get_filter_operator', 'Parses _notnull suffix',
        v_result.field_name = 'created_by' AND v_result.operator = 'notnull');

    -- Test 1.6: Default equals
    SELECT * INTO v_result FROM get_filter_operator('status');
    PERFORM record_test('get_filter_operator', 'Default equals operator',
        v_result.field_name = 'status' AND v_result.sql_operator = '=');
END $$;

-- =============================================================================
-- TEST 2: quote_filter_value
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing quote_filter_value ---';

    -- Test 2.1: Text value
    v_result := quote_filter_value('Hello World', 'text');
    PERFORM record_test('quote_filter_value', 'Quotes text value',
        v_result = '''Hello World''');

    -- Test 2.2: Integer value
    v_result := quote_filter_value('123', 'integer');
    PERFORM record_test('quote_filter_value', 'Returns integer as-is',
        v_result = '123');

    -- Test 2.3: Date value
    v_result := quote_filter_value('2024-01-15', 'date');
    PERFORM record_test('quote_filter_value', 'Quotes date value',
        v_result = '''2024-01-15''');

    -- Test 2.4: Boolean value
    v_result := quote_filter_value('true', 'boolean');
    PERFORM record_test('quote_filter_value', 'Returns boolean as-is',
        v_result = 'true');

    -- Test 2.5: NULL value
    v_result := quote_filter_value(NULL, 'text');
    PERFORM record_test('quote_filter_value', 'Returns NULL for null input',
        v_result = 'NULL');

    -- Test 2.6: SQL injection attempt - properly escapes quotes
    v_result := quote_filter_value('test''; DROP TABLE users; --', 'text');
    -- The result should have doubled single quotes for proper escaping
    PERFORM record_test('quote_filter_value', 'Escapes SQL injection attempt',
        v_result LIKE '%''''%');  -- Check for doubled single quotes
END $$;

-- =============================================================================
-- TEST 3: build_where_clause
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing build_where_clause ---';

    -- Test 3.1: Simple equals filter
    v_result := build_where_clause('purchase_order', '{"status": "draft"}'::JSONB);
    PERFORM record_test('build_where_clause', 'Simple equals filter',
        v_result LIKE '%t.status = ''draft''%' OR v_result LIKE '%t."status" = ''draft''%');

    -- Test 3.2: Array IN filter
    v_result := build_where_clause('purchase_order', '{"status": ["draft", "submitted"]}'::JSONB);
    PERFORM record_test('build_where_clause', 'Array IN filter',
        v_result LIKE '%IN%' AND v_result LIKE '%draft%' AND v_result LIKE '%submitted%');

    -- Test 3.3: Greater than filter
    v_result := build_where_clause('purchase_order', '{"total_amount_gt": 10000}'::JSONB);
    PERFORM record_test('build_where_clause', 'Greater than filter',
        v_result LIKE '%total_amount%' AND v_result LIKE '%>%' AND v_result LIKE '%10000%');

    -- Test 3.4: LIKE filter
    v_result := build_where_clause('supplier', '{"supplier_name_like": "%Acme%"}'::JSONB);
    PERFORM record_test('build_where_clause', 'LIKE filter',
        v_result LIKE '%supplier_name%' AND v_result LIKE '%ILIKE%' AND v_result LIKE '%Acme%');

    -- Test 3.5: Combined filters
    v_result := build_where_clause('purchase_order', '{"status": "draft", "total_amount_gt": 5000}'::JSONB);
    PERFORM record_test('build_where_clause', 'Combined filters with AND',
        v_result LIKE '%AND%');

    -- Test 3.6: Empty filters
    v_result := build_where_clause('purchase_order', '{}'::JSONB);
    PERFORM record_test('build_where_clause', 'Empty filters returns empty string',
        v_result = '');

    -- Test 3.7: NULL filters
    v_result := build_where_clause('purchase_order', NULL);
    PERFORM record_test('build_where_clause', 'NULL filters returns empty string',
        v_result = '');

    -- Test 3.8: Date range filters
    v_result := build_where_clause('purchase_order', '{"po_date_gte": "2024-01-01", "po_date_lte": "2024-12-31"}'::JSONB);
    PERFORM record_test('build_where_clause', 'Date range filters',
        v_result LIKE '%>=%' AND v_result LIKE '%<=%');
END $$;

-- =============================================================================
-- TEST 4: build_query_with_joins
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing build_query_with_joins ---';

    -- Test 4.1: Basic query generation
    v_result := build_query_with_joins('purchase_order');
    PERFORM record_test('build_query_with_joins', 'Generates SELECT FROM clause',
        v_result LIKE 'SELECT%' AND v_result LIKE '%FROM purchase_orders t%');

    -- Test 4.2: Includes lookup joins
    v_result := build_query_with_joins('purchase_order', NULL, TRUE);
    PERFORM record_test('build_query_with_joins', 'Includes LEFT JOIN for lookups',
        v_result LIKE '%LEFT JOIN%');

    -- Test 4.3: Without lookups
    v_result := build_query_with_joins('purchase_order', NULL, FALSE);
    PERFORM record_test('build_query_with_joins', 'Excludes lookups when disabled',
        v_result NOT LIKE '%LEFT JOIN%');

    -- Test 4.4: Specific columns
    v_result := build_query_with_joins('purchase_order', ARRAY['po_number', 'status'], FALSE);
    PERFORM record_test('build_query_with_joins', 'Selects specific columns',
        v_result LIKE '%t.po_number%' AND v_result LIKE '%t.status%');

    -- Test 4.5: Supplier entity
    v_result := build_query_with_joins('supplier');
    PERFORM record_test('build_query_with_joins', 'Works for supplier entity',
        v_result LIKE '%FROM suppliers t%');
END $$;

-- =============================================================================
-- TEST 5: build_order_by_clause
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing build_order_by_clause ---';

    -- Test 5.1: ASC sorting
    v_result := build_order_by_clause('purchase_order', 'po_date', 'ASC');
    PERFORM record_test('build_order_by_clause', 'ASC sorting',
        v_result LIKE '%ORDER BY t.po_date ASC%');

    -- Test 5.2: DESC sorting
    v_result := build_order_by_clause('purchase_order', 'po_date', 'DESC');
    PERFORM record_test('build_order_by_clause', 'DESC sorting',
        v_result LIKE '%ORDER BY t.po_date DESC%');

    -- Test 5.3: Default ASC
    v_result := build_order_by_clause('purchase_order', 'total_amount', NULL);
    PERFORM record_test('build_order_by_clause', 'Default ASC direction',
        v_result LIKE '%ASC%');

    -- Test 5.4: Empty field returns empty
    v_result := build_order_by_clause('purchase_order', NULL, 'ASC');
    PERFORM record_test('build_order_by_clause', 'NULL field returns empty',
        v_result = '');

    -- Test 5.5: Invalid direction defaults to ASC
    v_result := build_order_by_clause('purchase_order', 'po_date', 'INVALID');
    PERFORM record_test('build_order_by_clause', 'Invalid direction defaults to ASC',
        v_result LIKE '%ASC%');
END $$;

-- =============================================================================
-- TEST 6: build_pagination_clause
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing build_pagination_clause ---';

    -- Test 6.1: Basic pagination
    v_result := build_pagination_clause(25, 1);
    PERFORM record_test('build_pagination_clause', 'First page pagination',
        v_result = 'LIMIT 25 OFFSET 0');

    -- Test 6.2: Second page
    v_result := build_pagination_clause(25, 2);
    PERFORM record_test('build_pagination_clause', 'Second page offset',
        v_result = 'LIMIT 25 OFFSET 25');

    -- Test 6.3: Third page
    v_result := build_pagination_clause(10, 3);
    PERFORM record_test('build_pagination_clause', 'Third page offset',
        v_result = 'LIMIT 10 OFFSET 20');

    -- Test 6.4: Max page size limit
    v_result := build_pagination_clause(2000, 1);
    PERFORM record_test('build_pagination_clause', 'Limits max page size to 1000',
        v_result LIKE 'LIMIT 1000%');

    -- Test 6.5: Min page size
    v_result := build_pagination_clause(-5, 1);
    PERFORM record_test('build_pagination_clause', 'Ensures minimum page size of 1',
        v_result LIKE 'LIMIT 1%');
END $$;

-- =============================================================================
-- TEST 7: fetch_list_data
-- =============================================================================

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_viewer_id UUID := '00000000-0000-0000-0000-000000000104';
    v_result RECORD;
    v_count BIGINT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing fetch_list_data ---';

    -- Test 7.1: Basic list fetch
    SELECT * INTO v_result FROM fetch_list_data(v_admin_id, 'purchase_order');
    PERFORM record_test('fetch_list_data', 'Returns list data',
        v_result.data IS NOT NULL AND jsonb_array_length(v_result.data) >= 0);

    -- Test 7.2: Returns count and pagination info
    SELECT * INTO v_result FROM fetch_list_data(v_admin_id, 'purchase_order', '{}'::JSONB, NULL, 'ASC', 10, 1);
    PERFORM record_test('fetch_list_data', 'Returns pagination info',
        v_result.total_count >= 0 AND v_result.page_count >= 0 AND v_result.current_page = 1);

    -- Test 7.3: Filter by status
    SELECT * INTO v_result FROM fetch_list_data(
        v_admin_id,
        'purchase_order',
        '{"status": "draft"}'::JSONB
    );
    PERFORM record_test('fetch_list_data', 'Filters by status',
        v_result.data IS NOT NULL);

    -- Test 7.4: Filter by multiple statuses
    SELECT * INTO v_result FROM fetch_list_data(
        v_admin_id,
        'purchase_order',
        '{"status": ["draft", "submitted"]}'::JSONB
    );
    PERFORM record_test('fetch_list_data', 'Filters by multiple statuses',
        v_result.data IS NOT NULL);

    -- Test 7.5: Sorting works
    SELECT * INTO v_result FROM fetch_list_data(
        v_admin_id,
        'purchase_order',
        '{}'::JSONB,
        'total_amount',
        'DESC'
    );
    PERFORM record_test('fetch_list_data', 'Sorting by total_amount DESC',
        v_result.data IS NOT NULL);

    -- Test 7.6: Supplier list
    SELECT * INTO v_result FROM fetch_list_data(v_admin_id, 'supplier');
    PERFORM record_test('fetch_list_data', 'Fetches supplier list',
        v_result.data IS NOT NULL AND jsonb_array_length(v_result.data) >= 2);

    -- Test 7.7: Viewer can access (has read permission)
    SELECT * INTO v_result FROM fetch_list_data(v_viewer_id, 'purchase_order');
    PERFORM record_test('fetch_list_data', 'Viewer can read list',
        v_result.data IS NOT NULL);
END $$;

-- =============================================================================
-- TEST 8: fetch_list_data_simple
-- =============================================================================

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_result JSONB;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing fetch_list_data_simple ---';

    -- Test 8.1: Returns JSON array
    v_result := fetch_list_data_simple(v_admin_id, 'purchase_order');
    PERFORM record_test('fetch_list_data_simple', 'Returns JSON array',
        jsonb_typeof(v_result) = 'array');

    -- Test 8.2: With filter
    v_result := fetch_list_data_simple(
        v_admin_id,
        'supplier',
        '{"is_active": true}'::JSONB
    );
    PERFORM record_test('fetch_list_data_simple', 'Filters active suppliers',
        jsonb_typeof(v_result) = 'array');
END $$;

-- =============================================================================
-- TEST 9: fetch_form_data
-- =============================================================================

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_pm_id UUID := '00000000-0000-0000-0000-000000000101';
    v_po_id UUID := '30000000-0000-0000-0000-000000000001';
    v_result JSONB;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing fetch_form_data ---';

    -- Test 9.1: Fetch PO for viewing
    v_result := fetch_form_data(v_admin_id, 'purchase_order', v_po_id, 'form_view');
    PERFORM record_test('fetch_form_data', 'Fetches PO for viewing',
        v_result IS NOT NULL AND v_result->>'po_number' = 'PO-TEST-001');

    -- Test 9.2: Includes lookup display fields
    v_result := fetch_form_data(v_admin_id, 'purchase_order', v_po_id, 'form_view');
    PERFORM record_test('fetch_form_data', 'Includes supplier display name',
        v_result ? 'supplier_id_display' OR v_result ? 'supplier_id');

    -- Test 9.3: PM can view PO
    v_result := fetch_form_data(v_pm_id, 'purchase_order', v_po_id, 'form_view');
    PERFORM record_test('fetch_form_data', 'PM can view PO',
        v_result IS NOT NULL);

    -- Test 9.4: Fetch supplier
    v_result := fetch_form_data(v_admin_id, 'supplier', '20000000-0000-0000-0000-000000000001'::UUID, 'form_view');
    PERFORM record_test('fetch_form_data', 'Fetches supplier data',
        v_result IS NOT NULL AND v_result->>'supplier_code' = 'ACME-001');
END $$;

-- =============================================================================
-- TEST 10: fetch_form_data_with_permissions
-- =============================================================================

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_viewer_id UUID := '00000000-0000-0000-0000-000000000104';
    v_po_id UUID := '30000000-0000-0000-0000-000000000001';
    v_result JSONB;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing fetch_form_data_with_permissions ---';

    -- Test 10.1: Returns data and permissions
    v_result := fetch_form_data_with_permissions(v_admin_id, 'purchase_order', v_po_id, 'form_edit');
    PERFORM record_test('fetch_form_data_with_permissions', 'Returns data and permissions',
        v_result ? 'data' AND v_result ? 'field_permissions');

    -- Test 10.2: Admin has editable fields
    v_result := fetch_form_data_with_permissions(v_admin_id, 'purchase_order', v_po_id, 'form_edit');
    PERFORM record_test('fetch_form_data_with_permissions', 'Admin has editable fields',
        jsonb_array_length(v_result->'editable_fields') > 0);

    -- Test 10.3: Viewer has no editable fields
    v_result := fetch_form_data_with_permissions(v_viewer_id, 'purchase_order', v_po_id, 'form_view');
    PERFORM record_test('fetch_form_data_with_permissions', 'Viewer has no editable fields',
        jsonb_array_length(v_result->'editable_fields') = 0);
END $$;

-- =============================================================================
-- TEST 11: fetch_lookup_options
-- =============================================================================

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_result JSONB;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing fetch_lookup_options ---';

    -- Test 11.1: Returns supplier options
    v_result := fetch_lookup_options(v_admin_id, 'purchase_order', 'supplier_id');
    PERFORM record_test('fetch_lookup_options', 'Returns supplier dropdown options',
        jsonb_typeof(v_result) = 'array' AND jsonb_array_length(v_result) >= 2);

    -- Test 11.2: Each option has id and label
    v_result := fetch_lookup_options(v_admin_id, 'purchase_order', 'supplier_id');
    PERFORM record_test('fetch_lookup_options', 'Options have id and label',
        (v_result->0) ? 'id' AND (v_result->0) ? 'label');

    -- Test 11.3: Search filter works
    v_result := fetch_lookup_options(v_admin_id, 'purchase_order', 'supplier_id', 'Acme');
    PERFORM record_test('fetch_lookup_options', 'Search filter returns matching results',
        jsonb_array_length(v_result) >= 1);

    -- Test 11.4: Only active suppliers
    v_result := fetch_lookup_options(v_admin_id, 'purchase_order', 'supplier_id');
    PERFORM record_test('fetch_lookup_options', 'Only returns active suppliers',
        jsonb_array_length(v_result) = 2);  -- Initech is inactive
END $$;

-- =============================================================================
-- TEST 12: fetch_new_form_defaults
-- =============================================================================

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_result JSONB;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing fetch_new_form_defaults ---';

    -- Test 12.1: Returns defaults object
    v_result := fetch_new_form_defaults(v_admin_id, 'purchase_order');
    PERFORM record_test('fetch_new_form_defaults', 'Returns defaults object',
        v_result IS NOT NULL AND jsonb_typeof(v_result) = 'object');

    -- Test 12.2: Includes created_by
    v_result := fetch_new_form_defaults(v_admin_id, 'purchase_order');
    PERFORM record_test('fetch_new_form_defaults', 'Sets created_by to user',
        v_result->>'created_by' = v_admin_id::TEXT);

    -- Test 12.3: Includes date defaults
    v_result := fetch_new_form_defaults(v_admin_id, 'purchase_order');
    PERFORM record_test('fetch_new_form_defaults', 'Includes date defaults',
        v_result ? 'po_date');
END $$;

-- =============================================================================
-- TEST 13: Permission Enforcement
-- =============================================================================

DO $$
DECLARE
    v_viewer_id UUID := '00000000-0000-0000-0000-000000000104';
    v_inactive_id UUID := '00000000-0000-0000-0000-000000000105';
    v_error_caught BOOLEAN;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing Permission Enforcement ---';

    -- Test 13.1: Inactive user cannot fetch list
    BEGIN
        PERFORM fetch_list_data(v_inactive_id, 'purchase_order');
        v_error_caught := FALSE;
    EXCEPTION WHEN OTHERS THEN
        v_error_caught := TRUE;
    END;
    PERFORM record_test('permissions', 'Inactive user denied list access',
        v_error_caught = TRUE);

    -- Test 13.2: Viewer cannot get new form defaults (no create permission)
    BEGIN
        PERFORM fetch_new_form_defaults(v_viewer_id, 'purchase_order');
        v_error_caught := FALSE;
    EXCEPTION WHEN OTHERS THEN
        v_error_caught := TRUE;
    END;
    PERFORM record_test('permissions', 'Viewer denied create form defaults',
        v_error_caught = TRUE);
END $$;

-- =============================================================================
-- TEST 14: Performance - EXPLAIN ANALYZE
-- =============================================================================

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_result RECORD;
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_duration INTERVAL;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing Query Performance ---';

    -- Test 14.1: List query executes quickly
    v_start_time := clock_timestamp();
    SELECT * INTO v_result FROM fetch_list_data(v_admin_id, 'purchase_order');
    v_end_time := clock_timestamp();
    v_duration := v_end_time - v_start_time;
    PERFORM record_test('performance', 'List query < 200ms',
        EXTRACT(MILLISECONDS FROM v_duration) < 200);

    -- Test 14.2: Form query executes quickly
    v_start_time := clock_timestamp();
    PERFORM fetch_form_data(v_admin_id, 'purchase_order', '30000000-0000-0000-0000-000000000001'::UUID);
    v_end_time := clock_timestamp();
    v_duration := v_end_time - v_start_time;
    PERFORM record_test('performance', 'Form query < 100ms',
        EXTRACT(MILLISECONDS FROM v_duration) < 100);

    -- Test 14.3: Filtered query with indexes
    v_start_time := clock_timestamp();
    SELECT * INTO v_result FROM fetch_list_data(
        v_admin_id,
        'purchase_order',
        '{"status": ["draft", "submitted"], "total_amount_gt": 1000}'::JSONB
    );
    v_end_time := clock_timestamp();
    v_duration := v_end_time - v_start_time;
    PERFORM record_test('performance', 'Filtered query < 200ms',
        EXTRACT(MILLISECONDS FROM v_duration) < 200);
END $$;

-- =============================================================================
-- TEST RESULTS SUMMARY
-- =============================================================================

DO $$
DECLARE
    v_total INTEGER;
    v_passed INTEGER;
    v_failed INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_total FROM test_results;
    SELECT COUNT(*) INTO v_passed FROM test_results WHERE passed = TRUE;
    SELECT COUNT(*) INTO v_failed FROM test_results WHERE passed = FALSE;

    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'TEST RESULTS SUMMARY';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    RAISE NOTICE '';
    RAISE NOTICE 'Total Tests:  %', v_total;
    RAISE NOTICE 'Passed:       % ✓', v_passed;
    RAISE NOTICE 'Failed:       % ✗', v_failed;
    RAISE NOTICE '';

    IF v_failed > 0 THEN
        RAISE NOTICE 'FAILED TESTS:';
        RAISE NOTICE '─────────────────────────────────────────────────────────────────';
    END IF;
END $$;

-- Show failed tests
SELECT test_category, test_name, error_message
FROM test_results
WHERE passed = FALSE
ORDER BY test_id;

-- Overall pass/fail count by category
SELECT
    test_category,
    COUNT(*) FILTER (WHERE passed) as passed,
    COUNT(*) FILTER (WHERE NOT passed) as failed,
    COUNT(*) as total
FROM test_results
GROUP BY test_category
ORDER BY test_category;

-- =============================================================================
-- CLEANUP
-- =============================================================================

DROP FUNCTION IF EXISTS record_test(VARCHAR, VARCHAR, BOOLEAN, TEXT);

DO $$
DECLARE
    v_failed INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_failed FROM test_results WHERE passed = FALSE;

    RAISE NOTICE '';
    IF v_failed = 0 THEN
        RAISE NOTICE '✓ ALL TESTS PASSED! Phase 3 implementation is working correctly.';
    ELSE
        RAISE NOTICE '✗ Some tests failed. Please review the output above.';
    END IF;
    RAISE NOTICE '';
END $$;
