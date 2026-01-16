-- Apply Field Permissions to Templates
-- Function: apply_field_permissions
-- Description: Filters template fields based on user permissions
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- FUNCTION: Apply Field Permissions
-- =============================================================================
-- Removes or disables fields in template based on visibility and editability

CREATE OR REPLACE FUNCTION apply_field_permissions(
    p_template TEXT,
    p_visible_fields TEXT[],
    p_editable_fields TEXT[]
)
RETURNS TEXT AS $$
DECLARE
    v_result TEXT;
    v_field_name TEXT;
    v_field_pattern TEXT;
    v_is_visible BOOLEAN;
    v_is_editable BOOLEAN;
BEGIN
    v_result := p_template;

    -- Handle null inputs
    IF p_template IS NULL THEN
        RETURN '';
    END IF;

    IF p_visible_fields IS NULL THEN
        p_visible_fields := ARRAY[]::TEXT[];
    END IF;

    IF p_editable_fields IS NULL THEN
        p_editable_fields := ARRAY[]::TEXT[];
    END IF;

    -- For each placeholder in template, check permissions
    -- Find all {{field_name}} patterns
    FOR v_field_name IN
        SELECT DISTINCT unnest(regexp_matches(p_template, '\{\{([a-zA-Z0-9_.]+)\}\}', 'g'))
    LOOP
        -- Skip special patterns (like #if, #items, etc.)
        CONTINUE WHEN v_field_name LIKE '#%';
        CONTINUE WHEN v_field_name LIKE '/%';

        -- Check if field is in visible list
        v_is_visible := v_field_name = ANY(p_visible_fields);

        -- If not visible, remove all occurrences
        IF NOT v_is_visible THEN
            -- Remove table cells containing this field
            v_result := regexp_replace(
                v_result,
                '<td[^>]*>.*?\{\{' || v_field_name || '\}\}.*?</td>',
                '',
                'g'
            );

            -- Remove table headers for this field (look for data-field attribute)
            v_result := regexp_replace(
                v_result,
                '<th[^>]*data-field="' || v_field_name || '"[^>]*>.*?</th>',
                '',
                'g'
            );

            -- Remove form fields containing this placeholder
            v_result := regexp_replace(
                v_result,
                '<div[^>]*class="[^"]*form-field[^"]*"[^>]*>.*?\{\{' || v_field_name || '\}\}.*?</div>',
                '',
                'gs'
            );

            -- Remove individual input fields
            v_result := regexp_replace(
                v_result,
                '<input[^>]*name="' || v_field_name || '"[^>]*/?>',
                '',
                'g'
            );

            v_result := regexp_replace(
                v_result,
                '<select[^>]*name="' || v_field_name || '"[^>]*>.*?</select>',
                '',
                'gs'
            );

            v_result := regexp_replace(
                v_result,
                '<textarea[^>]*name="' || v_field_name || '"[^>]*>.*?</textarea>',
                '',
                'gs'
            );
        ELSE
            -- Field is visible, check if it's editable
            v_is_editable := v_field_name = ANY(p_editable_fields);

            -- If not editable, add disabled attribute to form inputs
            IF NOT v_is_editable THEN
                -- Add disabled to input fields
                v_result := regexp_replace(
                    v_result,
                    '(<input[^>]*name="' || v_field_name || '"[^>]*)(/>|>)',
                    '\1 disabled\2',
                    'g'
                );

                -- Add disabled to select fields
                v_result := regexp_replace(
                    v_result,
                    '(<select[^>]*name="' || v_field_name || '"[^>]*)(>)',
                    '\1 disabled\2',
                    'g'
                );

                -- Add disabled to textarea fields
                v_result := regexp_replace(
                    v_result,
                    '(<textarea[^>]*name="' || v_field_name || '"[^>]*)(>)',
                    '\1 disabled\2',
                    'g'
                );

                -- Add readonly class to the form field container
                v_result := regexp_replace(
                    v_result,
                    '(<div[^>]*class="[^"]*form-field[^"]*"[^>]*>)(.*?name="' || v_field_name || '".*?)(</div>)',
                    '\1<div class="readonly-field">\2</div>\3',
                    'gs'
                );
            END IF;
        END IF;
    END LOOP;

    -- Clean up any double spaces or empty lines created by removals
    v_result := regexp_replace(v_result, '\s+', ' ', 'g');
    v_result := regexp_replace(v_result, '>\s+<', '><', 'g');

    RETURN v_result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION apply_field_permissions(TEXT, TEXT[], TEXT[]) IS 'Filters template fields based on visibility and editability permissions';

-- =============================================================================
-- HELPER FUNCTION: Remove Field from List Template
-- =============================================================================
-- More targeted removal of fields from list/table templates

CREATE OR REPLACE FUNCTION remove_field_from_list(
    p_template TEXT,
    p_field_name TEXT
)
RETURNS TEXT AS $$
DECLARE
    v_result TEXT;
BEGIN
    v_result := p_template;

    -- Remove table header for this field
    -- Use [^<]* instead of .*? because PostgreSQL regex doesn't support non-greedy matching
    v_result := regexp_replace(
        v_result,
        '<th[^>]*data-field="' || p_field_name || '"[^>]*>[^<]*</th>',
        '',
        'g'
    );

    -- Also try without data-field attribute (match by content)
    v_result := regexp_replace(
        v_result,
        '<th[^>]*>\s*\{\{' || p_field_name || '(_label|\.display_label)?\}\}\s*</th>',
        '',
        'g'
    );

    -- Remove table cell containing this field placeholder
    v_result := regexp_replace(
        v_result,
        '<td[^>]*>\s*\{\{' || p_field_name || '\}\}\s*</td>',
        '',
        'g'
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION remove_field_from_list(TEXT, TEXT) IS 'Removes a specific field from list/table template';

-- =============================================================================
-- HELPER FUNCTION: Make Field Readonly in Form
-- =============================================================================
-- Adds disabled attribute and styling to form fields

CREATE OR REPLACE FUNCTION make_field_readonly(
    p_template TEXT,
    p_field_name TEXT
)
RETURNS TEXT AS $$
DECLARE
    v_result TEXT;
BEGIN
    v_result := p_template;

    -- Add disabled to input
    v_result := regexp_replace(
        v_result,
        '(<input[^>]*name="' || p_field_name || '"[^>]*)(/>|>)',
        '\1 disabled readonly\2',
        'g'
    );

    -- Add disabled to select
    v_result := regexp_replace(
        v_result,
        '(<select[^>]*name="' || p_field_name || '"[^>]*)(>)',
        '\1 disabled\2',
        'g'
    );

    -- Add disabled to textarea
    v_result := regexp_replace(
        v_result,
        '(<textarea[^>]*name="' || p_field_name || '"[^>]*)(>)',
        '\1 disabled readonly\2',
        'g'
    );

    -- Add readonly class to container
    v_result := regexp_replace(
        v_result,
        '(<div[^>]*class="[^"]*form-field[^"]*"[^>]*>.*?name="' || p_field_name || '".*?</div>)',
        '<div class="form-field readonly">\1</div>',
        'gs'
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION make_field_readonly(TEXT, TEXT) IS 'Makes a specific field read-only in form template';

-- =============================================================================
-- OPTIMIZED VERSION: Apply Field Permissions (Better Performance)
-- =============================================================================
-- More efficient version that processes in a single pass

CREATE OR REPLACE FUNCTION apply_field_permissions_optimized(
    p_template TEXT,
    p_visible_fields TEXT[],
    p_editable_fields TEXT[],
    p_view_type VARCHAR DEFAULT 'list'
)
RETURNS TEXT AS $$
DECLARE
    v_result TEXT;
    v_field_name TEXT;
    v_all_fields TEXT[];
    v_hidden_fields TEXT[];
    v_readonly_fields TEXT[];
BEGIN
    v_result := p_template;

    -- Handle null inputs
    IF p_template IS NULL OR p_template = '' THEN
        RETURN '';
    END IF;

    IF p_visible_fields IS NULL THEN
        p_visible_fields := ARRAY[]::TEXT[];
    END IF;

    IF p_editable_fields IS NULL THEN
        p_editable_fields := ARRAY[]::TEXT[];
    END IF;

    -- Extract all field names from template
    SELECT ARRAY(
        SELECT DISTINCT unnest(regexp_matches(p_template, '\{\{([a-zA-Z0-9_.]+)\}\}', 'g'))
    ) INTO v_all_fields;

    -- Determine which fields to hide (not in visible list)
    SELECT ARRAY(
        SELECT f
        FROM unnest(v_all_fields) AS f
        WHERE NOT (f = ANY(p_visible_fields))
          AND f NOT LIKE '#%'
          AND f NOT LIKE '/%'
    ) INTO v_hidden_fields;

    -- Determine which fields to make readonly (visible but not editable)
    SELECT ARRAY(
        SELECT f
        FROM unnest(v_all_fields) AS f
        WHERE f = ANY(p_visible_fields)
          AND NOT (f = ANY(p_editable_fields))
    ) INTO v_readonly_fields;

    -- Remove hidden fields
    IF array_length(v_hidden_fields, 1) > 0 THEN
        FOREACH v_field_name IN ARRAY v_hidden_fields
        LOOP
            IF p_view_type = 'list' THEN
                v_result := remove_field_from_list(v_result, v_field_name);
            ELSE
                -- For forms, remove entire form field div
                v_result := regexp_replace(
                    v_result,
                    '<div[^>]*class="[^"]*form-field[^"]*"[^>]*>.*?name="' || v_field_name || '".*?</div>',
                    '',
                    'gs'
                );
            END IF;
        END LOOP;
    END IF;

    -- Make readonly fields non-editable
    IF array_length(v_readonly_fields, 1) > 0 AND p_view_type != 'list' THEN
        FOREACH v_field_name IN ARRAY v_readonly_fields
        LOOP
            v_result := make_field_readonly(v_result, v_field_name);
        END LOOP;
    END IF;

    -- Clean up excessive whitespace
    v_result := regexp_replace(v_result, '\s+', ' ', 'g');
    v_result := regexp_replace(v_result, '>\s+<', '><', 'g');

    RETURN v_result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION apply_field_permissions_optimized(TEXT, TEXT[], TEXT[], VARCHAR) IS 'Optimized field permission filtering with view type support';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Example: Remove hidden fields from list
SELECT apply_field_permissions(
    '<table><tr><th>Name</th><th>Email</th><th>Salary</th></tr><tr><td>{{name}}</td><td>{{email}}</td><td>{{salary}}</td></tr></table>',
    ARRAY['name', 'email'], -- visible fields (salary hidden)
    ARRAY['name', 'email']  -- editable fields
);
-- Result: Only name and email columns remain

-- Example: Make field readonly
SELECT apply_field_permissions(
    '<div class="form-field"><label>Name</label><input name="name" value="{{name}}"></div><div class="form-field"><label>Status</label><input name="status" value="{{status}}"></div>',
    ARRAY['name', 'status'], -- both visible
    ARRAY['name']            -- only name editable, status readonly
);
-- Result: status input gets disabled attribute
*/
