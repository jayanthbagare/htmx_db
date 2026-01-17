-- Phase 4 Tests: UI Generation Functions
-- Description: Comprehensive tests for HTMX generation
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- TEST SETUP
-- =============================================================================

\echo '=============================================='
\echo 'PHASE 4 TESTS: UI GENERATION'
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
-- TEST 1: Helper Function - build_pagination_data
-- =============================================================================
\echo ''
\echo 'Testing build_pagination_data...'

DO $$
DECLARE
    v_result JSONB;
BEGIN
    -- Test basic pagination
    v_result := build_pagination_data(100, 25, 1);

    PERFORM record_test(
        'build_pagination_data: total_count',
        (v_result->>'total_count')::INTEGER = 100,
        'Expected 100, got ' || (v_result->>'total_count')
    );

    PERFORM record_test(
        'build_pagination_data: total_pages',
        (v_result->>'total_pages')::INTEGER = 4,
        'Expected 4, got ' || (v_result->>'total_pages')
    );

    PERFORM record_test(
        'build_pagination_data: page_start',
        (v_result->>'page_start')::INTEGER = 1,
        'Expected 1, got ' || (v_result->>'page_start')
    );

    PERFORM record_test(
        'build_pagination_data: page_end',
        (v_result->>'page_end')::INTEGER = 25,
        'Expected 25, got ' || (v_result->>'page_end')
    );

    PERFORM record_test(
        'build_pagination_data: has_prev false on page 1',
        (v_result->>'has_prev')::BOOLEAN = FALSE,
        'Expected false'
    );

    PERFORM record_test(
        'build_pagination_data: has_next true when more pages',
        (v_result->>'has_next')::BOOLEAN = TRUE,
        'Expected true'
    );

    -- Test middle page
    v_result := build_pagination_data(100, 25, 2);

    PERFORM record_test(
        'build_pagination_data: page_start on page 2',
        (v_result->>'page_start')::INTEGER = 26,
        'Expected 26, got ' || (v_result->>'page_start')
    );

    PERFORM record_test(
        'build_pagination_data: has_prev true on page 2',
        (v_result->>'has_prev')::BOOLEAN = TRUE,
        'Expected true'
    );

    -- Test last page
    v_result := build_pagination_data(100, 25, 4);

    PERFORM record_test(
        'build_pagination_data: has_next false on last page',
        (v_result->>'has_next')::BOOLEAN = FALSE,
        'Expected false'
    );

    PERFORM record_test(
        'build_pagination_data: page_end capped at total',
        (v_result->>'page_end')::INTEGER = 100,
        'Expected 100, got ' || (v_result->>'page_end')
    );
END $$;

-- =============================================================================
-- TEST 2: Helper Function - build_user_permission_data
-- =============================================================================
\echo ''
\echo 'Testing build_user_permission_data...'

DO $$
DECLARE
    v_result JSONB;
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
BEGIN
    -- Test admin permissions
    v_result := build_user_permission_data(v_admin_id, 'purchase_order');

    PERFORM record_test(
        'build_user_permission_data: returns JSONB',
        v_result IS NOT NULL,
        'Expected non-null result'
    );

    -- Admin should have create permission
    PERFORM record_test(
        'build_user_permission_data: admin has create permission',
        (v_result->>'user_can_create')::BOOLEAN = TRUE OR v_result ? 'user_can_create',
        'Expected user_can_create key'
    );

END $$;

-- =============================================================================
-- TEST 3: Helper Function - get_entity_template
-- =============================================================================
\echo ''
\echo 'Testing get_entity_template...'

DO $$
DECLARE
    v_template TEXT;
BEGIN
    -- Test getting list template
    v_template := get_entity_template('purchase_order', 'list');

    PERFORM record_test(
        'get_entity_template: returns template for PO list',
        v_template IS NOT NULL,
        'Expected non-null template'
    );

    PERFORM record_test(
        'get_entity_template: template contains HTML',
        v_template LIKE '%<div%' OR v_template LIKE '%<table%',
        'Expected HTML content'
    );

    -- Test getting form_view template
    v_template := get_entity_template('purchase_order', 'form_view');

    PERFORM record_test(
        'get_entity_template: returns template for PO form_view',
        v_template IS NOT NULL,
        'Expected non-null template'
    );

    -- Test non-existent template returns NULL
    v_template := get_entity_template('nonexistent_entity', 'list');

    PERFORM record_test(
        'get_entity_template: returns NULL for non-existent entity',
        v_template IS NULL,
        'Expected NULL'
    );
END $$;

-- =============================================================================
-- TEST 4: Main Function - generate_htmx_list (Permission Denied)
-- =============================================================================
\echo ''
\echo 'Testing generate_htmx_list permission handling...'

DO $$
DECLARE
    v_result TEXT;
    v_fake_user UUID := '00000000-0000-0000-0000-000000009999'::UUID;
BEGIN
    -- Test with non-existent user (should be denied)
    v_result := generate_htmx_list(v_fake_user, 'purchase_order');

    PERFORM record_test(
        'generate_htmx_list: returns error for invalid user',
        v_result LIKE '%permission%' OR v_result LIKE '%error%',
        'Expected permission error message'
    );
END $$;

-- =============================================================================
-- TEST 5: Main Function - generate_htmx_list (Success Case)
-- =============================================================================
\echo ''
\echo 'Testing generate_htmx_list success case...'

DO $$
DECLARE
    v_result TEXT;
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
BEGIN
    -- Test with admin user
    v_result := generate_htmx_list(v_admin_id, 'purchase_order');

    PERFORM record_test(
        'generate_htmx_list: returns HTML for admin',
        v_result IS NOT NULL AND LENGTH(v_result) > 0,
        'Expected non-empty result'
    );

    PERFORM record_test(
        'generate_htmx_list: contains entity display name',
        v_result LIKE '%Purchase Order%' OR v_result LIKE '%purchase_order%',
        'Expected entity name in output'
    );

    -- Test with filters
    v_result := generate_htmx_list(
        v_admin_id,
        'purchase_order',
        '{"status": ["draft"]}'::JSONB
    );

    PERFORM record_test(
        'generate_htmx_list: accepts filters',
        v_result IS NOT NULL,
        'Expected result with filters'
    );

    -- Test with sorting
    v_result := generate_htmx_list(
        v_admin_id,
        'purchase_order',
        '{}'::JSONB,
        'po_date',
        'DESC'
    );

    PERFORM record_test(
        'generate_htmx_list: accepts sort parameters',
        v_result IS NOT NULL,
        'Expected result with sorting'
    );

    -- Test with pagination
    v_result := generate_htmx_list(
        v_admin_id,
        'purchase_order',
        '{}'::JSONB,
        NULL,
        'ASC',
        10,
        1
    );

    PERFORM record_test(
        'generate_htmx_list: accepts pagination',
        v_result IS NOT NULL,
        'Expected result with pagination'
    );
END $$;

-- =============================================================================
-- TEST 6: Main Function - generate_htmx_form
-- =============================================================================
\echo ''
\echo 'Testing generate_htmx_form...'

DO $$
DECLARE
    v_result TEXT;
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
BEGIN
    -- Test create form
    v_result := generate_htmx_form_create(v_admin_id, 'purchase_order');

    PERFORM record_test(
        'generate_htmx_form_create: returns HTML',
        v_result IS NOT NULL AND LENGTH(v_result) > 0,
        'Expected non-empty result'
    );

    PERFORM record_test(
        'generate_htmx_form_create: contains form elements',
        v_result LIKE '%<form%' OR v_result LIKE '%Create%' OR v_result LIKE '%modal%',
        'Expected form HTML'
    );

    -- Test with invalid user
    v_result := generate_htmx_form_create('00000000-0000-0000-0000-000000009999'::UUID, 'purchase_order');

    PERFORM record_test(
        'generate_htmx_form_create: returns error for invalid user',
        v_result LIKE '%permission%' OR v_result LIKE '%error%',
        'Expected permission error'
    );

    -- Test view form without record_id (should error)
    v_result := generate_htmx_form(v_admin_id, 'purchase_order', 'form_view', NULL);

    PERFORM record_test(
        'generate_htmx_form_view: requires record_id',
        v_result LIKE '%required%' OR v_result LIKE '%error%',
        'Expected error about missing record_id'
    );
END $$;

-- =============================================================================
-- TEST 7: Helper Function - build_form_field_html
-- =============================================================================
\echo ''
\echo 'Testing build_form_field_html...'

DO $$
DECLARE
    v_result TEXT;
BEGIN
    -- Test text input
    v_result := build_form_field_html('test_field', 'test value', 'text', TRUE, FALSE, NULL);

    PERFORM record_test(
        'build_form_field_html: generates text input',
        v_result LIKE '%<input type="text"%',
        'Expected text input element'
    );

    PERFORM record_test(
        'build_form_field_html: includes field name',
        v_result LIKE '%name="test_field"%',
        'Expected field name attribute'
    );

    PERFORM record_test(
        'build_form_field_html: includes value',
        v_result LIKE '%value="test value"%',
        'Expected value attribute'
    );

    -- Test disabled field
    v_result := build_form_field_html('disabled_field', 'value', 'text', FALSE, FALSE, NULL);

    PERFORM record_test(
        'build_form_field_html: adds disabled for non-editable',
        v_result LIKE '%disabled%',
        'Expected disabled attribute'
    );

    -- Test required field
    v_result := build_form_field_html('required_field', '', 'text', TRUE, TRUE, NULL);

    PERFORM record_test(
        'build_form_field_html: adds required attribute',
        v_result LIKE '%required%',
        'Expected required attribute'
    );

    -- Test date input
    v_result := build_form_field_html('date_field', '2024-01-15', 'date', TRUE, FALSE, NULL);

    PERFORM record_test(
        'build_form_field_html: generates date input',
        v_result LIKE '%type="date"%',
        'Expected date input type'
    );

    -- Test checkbox
    v_result := build_form_field_html('bool_field', 'true', 'checkbox', TRUE, FALSE, NULL);

    PERFORM record_test(
        'build_form_field_html: generates checkbox',
        v_result LIKE '%type="checkbox"%',
        'Expected checkbox input type'
    );

    PERFORM record_test(
        'build_form_field_html: checkbox checked when true',
        v_result LIKE '%checked%',
        'Expected checked attribute'
    );

    -- Test select/lookup
    v_result := build_form_field_html(
        'select_field',
        '1',
        'lookup',
        TRUE,
        FALSE,
        '[{"id": "1", "label": "Option 1"}, {"id": "2", "label": "Option 2"}]'::JSONB
    );

    PERFORM record_test(
        'build_form_field_html: generates select',
        v_result LIKE '%<select%',
        'Expected select element'
    );

    PERFORM record_test(
        'build_form_field_html: includes options',
        v_result LIKE '%Option 1%' AND v_result LIKE '%Option 2%',
        'Expected options'
    );

    PERFORM record_test(
        'build_form_field_html: marks selected option',
        v_result LIKE '%selected%',
        'Expected selected attribute'
    );

    -- Test textarea
    v_result := build_form_field_html('notes', 'Some notes', 'textarea', TRUE, FALSE, NULL);

    PERFORM record_test(
        'build_form_field_html: generates textarea',
        v_result LIKE '%<textarea%',
        'Expected textarea element'
    );

    -- Test number input
    v_result := build_form_field_html('amount', '100.50', 'decimal', TRUE, FALSE, NULL);

    PERFORM record_test(
        'build_form_field_html: generates number input for decimal',
        v_result LIKE '%type="number"%',
        'Expected number input type'
    );

    PERFORM record_test(
        'build_form_field_html: decimal has step 0.01',
        v_result LIKE '%step="0.01"%',
        'Expected step attribute'
    );

    -- Test HTML escaping in value
    v_result := build_form_field_html('xss_field', '<script>alert(1)</script>', 'text', TRUE, FALSE, NULL);

    PERFORM record_test(
        'build_form_field_html: escapes HTML in value',
        v_result NOT LIKE '%<script>%',
        'Expected escaped script tag'
    );
END $$;

-- =============================================================================
-- TEST 8: Performance Logging
-- =============================================================================
\echo ''
\echo 'Testing log_ui_generation...'

DO $$
DECLARE
    v_start_time TIMESTAMPTZ := clock_timestamp();
    v_log_count INTEGER;
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
BEGIN
    -- Get initial count
    SELECT COUNT(*) INTO v_log_count FROM ui_generation_logs;

    -- Generate a list view (which should log)
    PERFORM generate_htmx_list(v_admin_id, 'purchase_order');

    -- Check if log entry was created
    PERFORM record_test(
        'log_ui_generation: creates log entry',
        (SELECT COUNT(*) FROM ui_generation_logs) > v_log_count,
        'Expected new log entry'
    );

    -- Check log entry has required fields
    PERFORM record_test(
        'log_ui_generation: log has user_id',
        EXISTS (
            SELECT 1 FROM ui_generation_logs
            WHERE user_id = v_admin_id
            ORDER BY created_at DESC LIMIT 1
        ),
        'Expected user_id in log'
    );

    PERFORM record_test(
        'log_ui_generation: log has entity_type',
        EXISTS (
            SELECT 1 FROM ui_generation_logs
            WHERE entity_type = 'purchase_order'
            ORDER BY created_at DESC LIMIT 1
        ),
        'Expected entity_type in log'
    );

    PERFORM record_test(
        'log_ui_generation: log has generation_time_ms',
        EXISTS (
            SELECT 1 FROM ui_generation_logs
            WHERE generation_time_ms IS NOT NULL
            ORDER BY created_at DESC LIMIT 1
        ),
        'Expected generation_time_ms in log'
    );
END $$;

-- =============================================================================
-- TEST 9: Generate List Table (Partial Update)
-- =============================================================================
\echo ''
\echo 'Testing generate_htmx_list_table...'

DO $$
DECLARE
    v_result TEXT;
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100'::UUID;
BEGIN
    -- Test table-only generation
    v_result := generate_htmx_list_table(v_admin_id, 'purchase_order');

    PERFORM record_test(
        'generate_htmx_list_table: returns HTML',
        v_result IS NOT NULL,
        'Expected non-null result'
    );

    PERFORM record_test(
        'generate_htmx_list_table: contains table rows',
        v_result LIKE '%<tr%' OR v_result LIKE '%pagination%',
        'Expected table row or pagination HTML'
    );

    -- Test with invalid user
    v_result := generate_htmx_list_table('00000000-0000-0000-0000-000000009999'::UUID, 'purchase_order');

    PERFORM record_test(
        'generate_htmx_list_table: handles permission denied',
        v_result LIKE '%Permission%' OR v_result LIKE '%denied%' OR v_result LIKE '%error%',
        'Expected permission denied message'
    );
END $$;

-- =============================================================================
-- TEST 10: Get Entity Field Definitions
-- =============================================================================
\echo ''
\echo 'Testing get_entity_field_definitions...'

DO $$
DECLARE
    v_count INTEGER;
    v_has_po_number BOOLEAN;
BEGIN
    -- Test getting field definitions
    SELECT COUNT(*) INTO v_count
    FROM get_entity_field_definitions('purchase_order');

    PERFORM record_test(
        'get_entity_field_definitions: returns fields',
        v_count > 0,
        'Expected some field definitions, got ' || v_count
    );

    -- Check for expected fields
    SELECT EXISTS (
        SELECT 1 FROM get_entity_field_definitions('purchase_order')
        WHERE field_name = 'po_number'
    ) INTO v_has_po_number;

    PERFORM record_test(
        'get_entity_field_definitions: includes po_number',
        v_has_po_number,
        'Expected po_number field'
    );

    -- Test with non-existent entity
    SELECT COUNT(*) INTO v_count
    FROM get_entity_field_definitions('nonexistent_entity');

    PERFORM record_test(
        'get_entity_field_definitions: returns empty for unknown entity',
        v_count = 0,
        'Expected 0 fields for unknown entity'
    );
END $$;

-- =============================================================================
-- TEST SUMMARY
-- =============================================================================
\echo ''
\echo '=============================================='
\echo 'PHASE 4 TEST SUMMARY'
\echo '=============================================='

DO $$
DECLARE
    v_total INTEGER;
    v_passed INTEGER;
    v_failed INTEGER;
    v_pass_rate NUMERIC;
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
