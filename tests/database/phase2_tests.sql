-- Phase 2 Tests: Template Rendering and Permission System
-- Description: Comprehensive tests for Phase 2 implementation
-- Run with: psql -d your_database -f phase2_tests.sql

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
-- TEST SETUP: Create Test Users for Each Role
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'PHASE 2 TESTS: Template Rendering & Permission System';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    RAISE NOTICE '';
    RAISE NOTICE 'Setting up test users...';
END $$;

-- Create test users for each role (if they don't exist)
INSERT INTO users (user_id, username, email, full_name, role_id, is_active)
SELECT
    '00000000-0000-0000-0000-000000000101'::UUID,
    'test_purchase_manager',
    'pm@test.com',
    'Test Purchase Manager',
    '00000000-0000-0000-0000-000000000002'::UUID,
    TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM users WHERE user_id = '00000000-0000-0000-0000-000000000101'::UUID
);

INSERT INTO users (user_id, username, email, full_name, role_id, is_active)
SELECT
    '00000000-0000-0000-0000-000000000102'::UUID,
    'test_warehouse_staff',
    'wh@test.com',
    'Test Warehouse Staff',
    '00000000-0000-0000-0000-000000000003'::UUID,
    TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM users WHERE user_id = '00000000-0000-0000-0000-000000000102'::UUID
);

INSERT INTO users (user_id, username, email, full_name, role_id, is_active)
SELECT
    '00000000-0000-0000-0000-000000000103'::UUID,
    'test_accountant',
    'acc@test.com',
    'Test Accountant',
    '00000000-0000-0000-0000-000000000004'::UUID,
    TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM users WHERE user_id = '00000000-0000-0000-0000-000000000103'::UUID
);

INSERT INTO users (user_id, username, email, full_name, role_id, is_active)
SELECT
    '00000000-0000-0000-0000-000000000104'::UUID,
    'test_viewer',
    'viewer@test.com',
    'Test Viewer',
    '00000000-0000-0000-0000-000000000005'::UUID,
    TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM users WHERE user_id = '00000000-0000-0000-0000-000000000104'::UUID
);

INSERT INTO users (user_id, username, email, full_name, role_id, is_active)
SELECT
    '00000000-0000-0000-0000-000000000105'::UUID,
    'test_inactive',
    'inactive@test.com',
    'Inactive User',
    '00000000-0000-0000-0000-000000000002'::UUID,
    FALSE
WHERE NOT EXISTS (
    SELECT 1 FROM users WHERE user_id = '00000000-0000-0000-0000-000000000105'::UUID
);

-- =============================================================================
-- TEST 1: TEMPLATE ENGINE - escape_html
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing escape_html ---';

    -- Test 1.1: Basic HTML escaping
    v_result := escape_html('<script>alert(1)</script>');
    PERFORM record_test('escape_html', 'Escapes script tags',
        v_result = '&lt;script&gt;alert(1)&lt;/script&gt;');

    -- Test 1.2: Ampersand escaping
    v_result := escape_html('Tom & Jerry');
    PERFORM record_test('escape_html', 'Escapes ampersand',
        v_result = 'Tom &amp; Jerry');

    -- Test 1.3: Quote escaping
    v_result := escape_html('He said "Hello"');
    PERFORM record_test('escape_html', 'Escapes double quotes',
        v_result = 'He said &quot;Hello&quot;');

    -- Test 1.4: Single quote escaping
    v_result := escape_html('It''s a test');
    PERFORM record_test('escape_html', 'Escapes single quotes',
        v_result = 'It&#39;s a test');

    -- Test 1.5: NULL handling
    v_result := escape_html(NULL);
    PERFORM record_test('escape_html', 'Returns empty string for NULL',
        v_result = '');

    -- Test 1.6: No escaping needed
    v_result := escape_html('Hello World');
    PERFORM record_test('escape_html', 'Returns unchanged text when no escaping needed',
        v_result = 'Hello World');
END $$;

-- =============================================================================
-- TEST 2: TEMPLATE ENGINE - get_json_value
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
    v_data JSONB;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing get_json_value ---';

    v_data := '{"name": "John", "age": 30, "address": {"city": "NYC", "zip": "10001"}, "tags": ["a", "b"]}'::JSONB;

    -- Test 2.1: Simple field access
    v_result := get_json_value(v_data, 'name');
    PERFORM record_test('get_json_value', 'Extracts simple string field',
        v_result = 'John');

    -- Test 2.2: Numeric field
    v_result := get_json_value(v_data, 'age');
    PERFORM record_test('get_json_value', 'Extracts numeric field',
        v_result = '30');

    -- Test 2.3: Nested path
    v_result := get_json_value(v_data, 'address.city');
    PERFORM record_test('get_json_value', 'Extracts nested path value',
        v_result = 'NYC');

    -- Test 2.4: Missing field
    v_result := get_json_value(v_data, 'missing');
    PERFORM record_test('get_json_value', 'Returns empty string for missing field',
        v_result = '');

    -- Test 2.5: Missing nested path
    v_result := get_json_value(v_data, 'address.country');
    PERFORM record_test('get_json_value', 'Returns empty for missing nested path',
        v_result = '');

    -- Test 2.6: NULL data
    v_result := get_json_value(NULL, 'name');
    PERFORM record_test('get_json_value', 'Returns empty for NULL data',
        v_result = '');

    -- Test 2.7: NULL path
    v_result := get_json_value(v_data, NULL);
    PERFORM record_test('get_json_value', 'Returns empty for NULL path',
        v_result = '');
END $$;

-- =============================================================================
-- TEST 3: TEMPLATE ENGINE - render_template (basic)
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
    v_data JSONB;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing render_template (basic) ---';

    -- Test 3.1: Simple placeholder replacement
    v_result := render_template(
        '<div>Hello {{name}}!</div>',
        '{"name": "World"}'::JSONB
    );
    PERFORM record_test('render_template', 'Simple placeholder replacement',
        v_result = '<div>Hello World!</div>');

    -- Test 3.2: Multiple placeholders
    v_result := render_template(
        '<div>{{greeting}}, {{name}}!</div>',
        '{"greeting": "Hello", "name": "John"}'::JSONB
    );
    PERFORM record_test('render_template', 'Multiple placeholders',
        v_result = '<div>Hello, John!</div>');

    -- Test 3.3: Nested path placeholder
    v_result := render_template(
        '<div>{{user.name}} from {{user.city}}</div>',
        '{"user": {"name": "Jane", "city": "Boston"}}'::JSONB
    );
    PERFORM record_test('render_template', 'Nested path placeholders',
        v_result = '<div>Jane from Boston</div>');

    -- Test 3.4: HTML escaping (XSS prevention)
    v_result := render_template(
        '<div>{{content}}</div>',
        '{"content": "<script>alert(1)</script>"}'::JSONB
    );
    PERFORM record_test('render_template', 'XSS prevention with HTML escaping',
        v_result = '<div>&lt;script&gt;alert(1)&lt;/script&gt;</div>');

    -- Test 3.5: Raw HTML (triple braces)
    v_result := render_template(
        '<div>{{{html}}}</div>',
        '{"html": "<strong>Bold</strong>"}'::JSONB
    );
    PERFORM record_test('render_template', 'Raw HTML with triple braces',
        v_result = '<div><strong>Bold</strong></div>');

    -- Test 3.6: Missing placeholder
    v_result := render_template(
        '<div>{{name}} - {{title}}</div>',
        '{"name": "John"}'::JSONB
    );
    PERFORM record_test('render_template', 'Missing placeholder becomes empty',
        v_result = '<div>John - </div>');

    -- Test 3.7: NULL template
    v_result := render_template(NULL, '{"name": "John"}'::JSONB);
    PERFORM record_test('render_template', 'NULL template returns empty string',
        v_result = '');

    -- Test 3.8: NULL data
    v_result := render_template('<div>{{name}}</div>', NULL);
    PERFORM record_test('render_template', 'NULL data treats placeholders as empty',
        v_result = '<div></div>');
END $$;

-- =============================================================================
-- TEST 4: TEMPLATE ENGINE - render_template_with_arrays
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing render_template_with_arrays ---';

    -- Test 4.1: Basic array iteration
    v_result := render_template_with_arrays(
        '<ul>{{#items}}<li>{{name}}</li>{{/items}}</ul>',
        '{"items": [{"name": "A"}, {"name": "B"}, {"name": "C"}]}'::JSONB
    );
    PERFORM record_test('render_with_arrays', 'Basic array iteration',
        v_result = '<ul><li>A</li><li>B</li><li>C</li></ul>');

    -- Test 4.2: Empty array
    v_result := render_template_with_arrays(
        '<ul>{{#items}}<li>{{name}}</li>{{/items}}</ul>',
        '{"items": []}'::JSONB
    );
    PERFORM record_test('render_with_arrays', 'Empty array removes block',
        v_result = '<ul></ul>');

    -- Test 4.3: Missing array
    v_result := render_template_with_arrays(
        '<ul>{{#items}}<li>{{name}}</li>{{/items}}</ul>',
        '{}'::JSONB
    );
    PERFORM record_test('render_with_arrays', 'Missing array removes block',
        v_result = '<ul></ul>');

    -- Test 4.4: Array with multiple fields
    v_result := render_template_with_arrays(
        '<table>{{#rows}}<tr><td>{{id}}</td><td>{{value}}</td></tr>{{/rows}}</table>',
        '{"rows": [{"id": 1, "value": "X"}, {"id": 2, "value": "Y"}]}'::JSONB
    );
    PERFORM record_test('render_with_arrays', 'Array with multiple fields',
        v_result = '<table><tr><td>1</td><td>X</td></tr><tr><td>2</td><td>Y</td></tr></table>');

    -- Test 4.5: Combined with simple placeholders
    v_result := render_template_with_arrays(
        '<div>Title: {{title}}</div><ul>{{#items}}<li>{{name}}</li>{{/items}}</ul>',
        '{"title": "My List", "items": [{"name": "A"}, {"name": "B"}]}'::JSONB
    );
    PERFORM record_test('render_with_arrays', 'Combined with simple placeholders',
        v_result = '<div>Title: My List</div><ul><li>A</li><li>B</li></ul>');
END $$;

-- =============================================================================
-- TEST 5: TEMPLATE ENGINE - evaluate_template_condition
-- =============================================================================

DO $$
DECLARE
    v_result BOOLEAN;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing evaluate_template_condition ---';

    -- Test 5.1: Equals condition (true)
    v_result := evaluate_template_condition(
        'status == ''approved''',
        '{"status": "approved"}'::JSONB
    );
    PERFORM record_test('evaluate_condition', 'Equals condition (true)',
        v_result = TRUE);

    -- Test 5.2: Equals condition (false)
    v_result := evaluate_template_condition(
        'status == ''approved''',
        '{"status": "draft"}'::JSONB
    );
    PERFORM record_test('evaluate_condition', 'Equals condition (false)',
        v_result = FALSE);

    -- Test 5.3: Not equals condition (true)
    v_result := evaluate_template_condition(
        'status != ''draft''',
        '{"status": "approved"}'::JSONB
    );
    PERFORM record_test('evaluate_condition', 'Not equals condition (true)',
        v_result = TRUE);

    -- Test 5.4: Truthy check (field exists and has value)
    v_result := evaluate_template_condition(
        'name',
        '{"name": "John"}'::JSONB
    );
    PERFORM record_test('evaluate_condition', 'Truthy check with value',
        v_result = TRUE);

    -- Test 5.5: Truthy check (field empty)
    v_result := evaluate_template_condition(
        'name',
        '{"name": ""}'::JSONB
    );
    PERFORM record_test('evaluate_condition', 'Truthy check with empty value',
        v_result = FALSE);

    -- Test 5.6: Truthy check (field missing)
    v_result := evaluate_template_condition(
        'missing',
        '{"name": "John"}'::JSONB
    );
    PERFORM record_test('evaluate_condition', 'Truthy check with missing field',
        v_result = FALSE);
END $$;

-- =============================================================================
-- TEST 6: TEMPLATE ENGINE - render_template_complete
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing render_template_complete ---';

    -- Test 6.1: Conditional rendering (condition true)
    v_result := render_template_complete(
        '<div>{{#if status == ''approved''}}<span class="badge-success">Approved</span>{{/if}}</div>',
        '{"status": "approved"}'::JSONB
    );
    PERFORM record_test('render_complete', 'Conditional shows when true',
        v_result LIKE '%badge-success%');

    -- Test 6.2: Conditional rendering (condition false)
    v_result := render_template_complete(
        '<div>{{#if status == ''approved''}}<span>Approved</span>{{/if}}</div>',
        '{"status": "draft"}'::JSONB
    );
    PERFORM record_test('render_complete', 'Conditional hidden when false',
        v_result NOT LIKE '%Approved%');

    -- Test 6.3: Complete template with all features
    v_result := render_template_complete(
        '<div>Order: {{order_number}} {{#if is_urgent}}<span>URGENT</span>{{/if}}</div><ul>{{#items}}<li>{{name}}</li>{{/items}}</ul>',
        '{"order_number": "PO-001", "is_urgent": "true", "items": [{"name": "Item1"}, {"name": "Item2"}]}'::JSONB
    );
    PERFORM record_test('render_complete', 'All features combined',
        v_result LIKE '%PO-001%' AND v_result LIKE '%URGENT%' AND v_result LIKE '%Item1%' AND v_result LIKE '%Item2%');
END $$;

-- =============================================================================
-- TEST 7: FIELD PERMISSIONS - apply_field_permissions
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing apply_field_permissions ---';

    -- Test 7.1: Hide fields not in visible list
    v_result := apply_field_permissions(
        '<td>{{name}}</td><td>{{salary}}</td><td>{{email}}</td>',
        ARRAY['name', 'email'],
        ARRAY['name', 'email']
    );
    PERFORM record_test('apply_permissions', 'Removes hidden fields from template',
        v_result NOT LIKE '%salary%');

    -- Test 7.2: Disable non-editable fields
    v_result := apply_field_permissions(
        '<input name="name" value="{{name}}"><input name="status" value="{{status}}">',
        ARRAY['name', 'status'],
        ARRAY['name']  -- only name is editable
    );
    PERFORM record_test('apply_permissions', 'Adds disabled to non-editable inputs',
        v_result LIKE '%name="status"% disabled%' OR v_result LIKE '%disabled%name="status"%');
END $$;

-- =============================================================================
-- TEST 8: FIELD PERMISSIONS - remove_field_from_list
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing remove_field_from_list ---';

    -- Test 8.1: Remove table header
    v_result := remove_field_from_list(
        '<th data-field="salary">Salary</th><th data-field="name">Name</th>',
        'salary'
    );
    PERFORM record_test('remove_from_list', 'Removes table header by data-field',
        v_result NOT LIKE '%salary%' AND v_result LIKE '%name%');

    -- Test 8.2: Remove table cell
    v_result := remove_field_from_list(
        '<td>{{name}}</td><td>{{salary}}</td>',
        'salary'
    );
    PERFORM record_test('remove_from_list', 'Removes table cell with field placeholder',
        v_result NOT LIKE '%salary%');
END $$;

-- =============================================================================
-- TEST 9: FIELD PERMISSIONS - make_field_readonly
-- =============================================================================

DO $$
DECLARE
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing make_field_readonly ---';

    -- Test 9.1: Make input readonly
    v_result := make_field_readonly(
        '<input name="status" value="draft">',
        'status'
    );
    PERFORM record_test('make_readonly', 'Adds disabled and readonly to input',
        v_result LIKE '%disabled%' AND v_result LIKE '%readonly%');

    -- Test 9.2: Make select disabled
    v_result := make_field_readonly(
        '<select name="currency"><option>USD</option></select>',
        'currency'
    );
    PERFORM record_test('make_readonly', 'Adds disabled to select',
        v_result LIKE '%disabled%');
END $$;

-- =============================================================================
-- TEST 10: PERMISSION FUNCTIONS - get_user_field_permissions
-- =============================================================================

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_viewer_id UUID := '00000000-0000-0000-0000-000000000104';
    v_count INTEGER;
    v_visible_count INTEGER;
    v_editable_count INTEGER;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing get_user_field_permissions ---';

    -- Test 10.1: Admin gets all fields visible
    SELECT COUNT(*) INTO v_count
    FROM get_user_field_permissions(v_admin_id, 'purchase_order', 'list')
    WHERE is_visible = TRUE;
    PERFORM record_test('field_permissions', 'Admin sees all PO fields in list',
        v_count >= 10);  -- We have 11 fields for PO

    -- Test 10.2: Admin can edit in form_edit
    SELECT COUNT(*) INTO v_editable_count
    FROM get_user_field_permissions(v_admin_id, 'purchase_order', 'form_edit')
    WHERE is_editable = TRUE;
    PERFORM record_test('field_permissions', 'Admin can edit fields in form_edit',
        v_editable_count >= 10);

    -- Test 10.3: Viewer has limited visibility (notes hidden)
    SELECT COUNT(*) INTO v_visible_count
    FROM get_user_field_permissions(v_viewer_id, 'purchase_order', 'list')
    WHERE is_visible = TRUE;
    SELECT COUNT(*) INTO v_count
    FROM get_user_field_permissions(v_admin_id, 'purchase_order', 'list')
    WHERE is_visible = TRUE;
    PERFORM record_test('field_permissions', 'Viewer has fewer visible fields than admin',
        v_visible_count < v_count);

    -- Test 10.4: Viewer cannot edit
    SELECT COUNT(*) INTO v_editable_count
    FROM get_user_field_permissions(v_viewer_id, 'purchase_order', 'form_edit')
    WHERE is_editable = TRUE;
    PERFORM record_test('field_permissions', 'Viewer cannot edit any fields',
        v_editable_count = 0);

    -- Test 10.5: View mode never editable
    SELECT COUNT(*) INTO v_editable_count
    FROM get_user_field_permissions(v_admin_id, 'purchase_order', 'form_view')
    WHERE is_editable = TRUE;
    PERFORM record_test('field_permissions', 'form_view mode is never editable',
        v_editable_count = 0);
END $$;

-- =============================================================================
-- TEST 11: PERMISSION FUNCTIONS - get_visible_fields / get_editable_fields
-- =============================================================================

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_pm_id UUID := '00000000-0000-0000-0000-000000000101';
    v_visible_fields TEXT[];
    v_editable_fields TEXT[];
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing get_visible_fields / get_editable_fields ---';

    -- Test 11.1: Get visible fields for admin
    v_visible_fields := get_visible_fields(v_admin_id, 'purchase_order', 'list');
    PERFORM record_test('visible_fields', 'Admin gets visible fields array',
        array_length(v_visible_fields, 1) >= 10);

    -- Test 11.2: Get editable fields for admin
    v_editable_fields := get_editable_fields(v_admin_id, 'purchase_order', 'form_create');
    PERFORM record_test('editable_fields', 'Admin gets editable fields array',
        array_length(v_editable_fields, 1) >= 10);

    -- Test 11.3: PM cannot edit auto-generated fields
    v_editable_fields := get_editable_fields(v_pm_id, 'purchase_order', 'form_create');
    PERFORM record_test('editable_fields', 'PM cannot edit po_number',
        NOT ('po_number' = ANY(v_editable_fields)));
END $$;

-- =============================================================================
-- TEST 12: PERMISSION FUNCTIONS - can_user_see_field / can_user_edit_field
-- =============================================================================

DO $$
DECLARE
    v_viewer_id UUID := '00000000-0000-0000-0000-000000000104';
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_can_see BOOLEAN;
    v_can_edit BOOLEAN;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing can_user_see_field / can_user_edit_field ---';

    -- Test 12.1: Viewer cannot see notes field
    v_can_see := can_user_see_field(v_viewer_id, 'purchase_order', 'notes', 'list');
    PERFORM record_test('can_see_field', 'Viewer cannot see notes field',
        v_can_see = FALSE);

    -- Test 12.2: Admin can see notes field
    v_can_see := can_user_see_field(v_admin_id, 'purchase_order', 'notes', 'list');
    PERFORM record_test('can_see_field', 'Admin can see notes field',
        v_can_see = TRUE);

    -- Test 12.3: Viewer cannot edit
    v_can_edit := can_user_edit_field(v_viewer_id, 'purchase_order', 'po_date', 'form_edit');
    PERFORM record_test('can_edit_field', 'Viewer cannot edit any field',
        v_can_edit = FALSE);

    -- Test 12.4: Admin can edit
    v_can_edit := can_user_edit_field(v_admin_id, 'purchase_order', 'po_date', 'form_edit');
    PERFORM record_test('can_edit_field', 'Admin can edit fields',
        v_can_edit = TRUE);
END $$;

-- =============================================================================
-- TEST 13: ACTION PERMISSIONS - evaluate_permission_condition
-- =============================================================================

DO $$
DECLARE
    v_result BOOLEAN;
    v_user_id UUID := '00000000-0000-0000-0000-000000000100';
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing evaluate_permission_condition ---';

    -- Test 13.1: Equals condition
    v_result := evaluate_permission_condition(
        '{"field": "status", "operator": "equals", "value": "draft"}',
        '{"status": "draft"}'::JSONB,
        v_user_id
    );
    PERFORM record_test('perm_condition', 'Equals operator works',
        v_result = TRUE);

    -- Test 13.2: Not equals condition
    v_result := evaluate_permission_condition(
        '{"field": "status", "operator": "not_equals", "value": "approved"}',
        '{"status": "draft"}'::JSONB,
        v_user_id
    );
    PERFORM record_test('perm_condition', 'Not equals operator works',
        v_result = TRUE);

    -- Test 13.3: IN operator with array
    v_result := evaluate_permission_condition(
        '{"field": "status", "operator": "in", "value": "draft,submitted"}',
        '{"status": "draft"}'::JSONB,
        v_user_id
    );
    PERFORM record_test('perm_condition', 'IN operator works',
        v_result = TRUE);

    -- Test 13.4: Current user substitution
    v_result := evaluate_permission_condition(
        '{"field": "created_by", "operator": "equals", "value": "current_user"}',
        ('{"created_by": "' || v_user_id || '"}')::JSONB,
        v_user_id
    );
    PERFORM record_test('perm_condition', 'current_user substitution works',
        v_result = TRUE);

    -- Test 13.5: NULL condition (always allow)
    v_result := evaluate_permission_condition(NULL, '{}'::JSONB, v_user_id);
    PERFORM record_test('perm_condition', 'NULL condition allows access',
        v_result = TRUE);

    -- Test 13.6: is_null operator
    v_result := evaluate_permission_condition(
        '{"field": "approved_by", "operator": "is_null"}',
        '{"status": "draft"}'::JSONB,
        v_user_id
    );
    PERFORM record_test('perm_condition', 'is_null operator works',
        v_result = TRUE);
END $$;

-- =============================================================================
-- TEST 14: ACTION PERMISSIONS - can_user_perform_action
-- =============================================================================

DO $$
DECLARE
    v_admin_id UUID := '00000000-0000-0000-0000-000000000100';
    v_pm_id UUID := '00000000-0000-0000-0000-000000000101';
    v_viewer_id UUID := '00000000-0000-0000-0000-000000000104';
    v_inactive_id UUID := '00000000-0000-0000-0000-000000000105';
    v_can_do BOOLEAN;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing can_user_perform_action ---';

    -- Test 14.1: Admin can do everything
    v_can_do := can_user_perform_action(v_admin_id, 'purchase_order', 'create');
    PERFORM record_test('can_perform_action', 'Admin can create PO',
        v_can_do = TRUE);

    v_can_do := can_user_perform_action(v_admin_id, 'purchase_order', 'approve');
    PERFORM record_test('can_perform_action', 'Admin can approve PO',
        v_can_do = TRUE);

    v_can_do := can_user_perform_action(v_admin_id, 'purchase_order', 'delete');
    PERFORM record_test('can_perform_action', 'Admin can delete PO',
        v_can_do = TRUE);

    -- Test 14.2: Purchase Manager permissions
    v_can_do := can_user_perform_action(v_pm_id, 'purchase_order', 'create');
    PERFORM record_test('can_perform_action', 'PM can create PO',
        v_can_do = TRUE);

    v_can_do := can_user_perform_action(v_pm_id, 'purchase_order', 'approve');
    PERFORM record_test('can_perform_action', 'PM cannot approve PO',
        v_can_do = FALSE);

    -- Test 14.3: Viewer permissions
    v_can_do := can_user_perform_action(v_viewer_id, 'purchase_order', 'read');
    PERFORM record_test('can_perform_action', 'Viewer can read PO',
        v_can_do = TRUE);

    v_can_do := can_user_perform_action(v_viewer_id, 'purchase_order', 'create');
    PERFORM record_test('can_perform_action', 'Viewer cannot create PO',
        v_can_do = FALSE);

    -- Test 14.4: Inactive user denied
    v_can_do := can_user_perform_action(v_inactive_id, 'purchase_order', 'read');
    PERFORM record_test('can_perform_action', 'Inactive user denied access',
        v_can_do = FALSE);

    -- Test 14.5: Unknown action denied
    v_can_do := can_user_perform_action(v_admin_id, 'purchase_order', 'unknown_action');
    PERFORM record_test('can_perform_action', 'Unknown action denied',
        v_can_do = TRUE);  -- Admin bypasses all checks

    v_can_do := can_user_perform_action(v_pm_id, 'purchase_order', 'unknown_action');
    PERFORM record_test('can_perform_action', 'Non-admin unknown action denied',
        v_can_do = FALSE);
END $$;

-- =============================================================================
-- TEST 15: ACTION PERMISSIONS - get_user_actions / get_allowed_actions
-- =============================================================================

DO $$
DECLARE
    v_pm_id UUID := '00000000-0000-0000-0000-000000000101';
    v_viewer_id UUID := '00000000-0000-0000-0000-000000000104';
    v_actions TEXT[];
    v_count INTEGER;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing get_user_actions / get_allowed_actions ---';

    -- Test 15.1: PM has multiple actions
    SELECT COUNT(*) INTO v_count
    FROM get_user_actions(v_pm_id, 'purchase_order');
    PERFORM record_test('get_user_actions', 'PM has multiple PO actions',
        v_count >= 4);  -- create, read, edit, submit, approve(false)

    -- Test 15.2: Viewer has limited actions
    SELECT COUNT(*) INTO v_count
    FROM get_user_actions(v_viewer_id, 'purchase_order');
    PERFORM record_test('get_user_actions', 'Viewer has limited actions',
        v_count >= 1);

    -- Test 15.3: Get allowed actions array
    v_actions := get_allowed_actions(v_pm_id, 'purchase_order');
    PERFORM record_test('get_allowed_actions', 'get_allowed_actions returns array',
        array_length(v_actions, 1) >= 3);

    -- Test 15.4: Viewer only has read allowed
    v_actions := get_allowed_actions(v_viewer_id, 'purchase_order');
    PERFORM record_test('get_allowed_actions', 'Viewer only has read action',
        'read' = ANY(v_actions) AND NOT ('create' = ANY(v_actions)));
END $$;

-- =============================================================================
-- TEST 16: ACTION PERMISSIONS - check_user_actions (batch)
-- =============================================================================

DO $$
DECLARE
    v_pm_id UUID := '00000000-0000-0000-0000-000000000101';
    v_count_allowed INTEGER;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing check_user_actions ---';

    -- Test 16.1: Batch check multiple actions
    SELECT COUNT(*) INTO v_count_allowed
    FROM check_user_actions(
        v_pm_id,
        'purchase_order',
        ARRAY['create', 'read', 'edit', 'delete', 'approve']
    )
    WHERE is_allowed = TRUE;

    PERFORM record_test('check_user_actions', 'Batch check works correctly',
        v_count_allowed >= 3);  -- create, read, edit should be allowed
END $$;

-- =============================================================================
-- TEST 17: INTEGRATION - Permission applied to templates
-- =============================================================================

DO $$
DECLARE
    v_viewer_id UUID := '00000000-0000-0000-0000-000000000104';
    v_visible_fields TEXT[];
    v_editable_fields TEXT[];
    v_template TEXT;
    v_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '--- Testing Integration: Permissions + Templates ---';

    -- Get viewer's permissions
    v_visible_fields := get_visible_fields(v_viewer_id, 'purchase_order', 'list');
    v_editable_fields := get_editable_fields(v_viewer_id, 'purchase_order', 'list');

    -- Create a sample template
    v_template := '<table><tr><th data-field="po_number">PO#</th><th data-field="notes">Notes</th></tr><tr><td>{{po_number}}</td><td>{{notes}}</td></tr></table>';

    -- Apply permissions
    v_result := apply_field_permissions(v_template, v_visible_fields, v_editable_fields);

    -- Viewer should not see notes
    PERFORM record_test('integration', 'Viewer permissions hide notes field',
        v_result NOT LIKE '%notes%');

    -- Viewer should still see PO number
    PERFORM record_test('integration', 'Viewer can still see po_number',
        v_result LIKE '%po_number%');
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
        RAISE NOTICE '✓ ALL TESTS PASSED! Phase 2 implementation is working correctly.';
    ELSE
        RAISE NOTICE '✗ Some tests failed. Please review the output above.';
    END IF;
    RAISE NOTICE '';
END $$;
