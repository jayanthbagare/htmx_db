-- Template Rendering Engine
-- Function: render_template
-- Description: Renders HTML templates by replacing placeholders with data
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- HELPER FUNCTION: HTML Escape
-- =============================================================================
-- Escapes HTML special characters to prevent XSS

CREATE OR REPLACE FUNCTION escape_html(p_text TEXT)
RETURNS TEXT AS $$
BEGIN
    IF p_text IS NULL THEN
        RETURN '';
    END IF;

    RETURN REPLACE(
        REPLACE(
            REPLACE(
                REPLACE(
                    REPLACE(p_text, '&', '&amp;'),
                    '<', '&lt;'
                ),
                '>', '&gt;'
            ),
            '"', '&quot;'
        ),
        '''', '&#39;'
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION escape_html(TEXT) IS 'Escapes HTML special characters for XSS prevention';

-- =============================================================================
-- HELPER FUNCTION: Extract JSON Value by Path
-- =============================================================================
-- Extracts value from JSONB using dot notation path

CREATE OR REPLACE FUNCTION get_json_value(
    p_data JSONB,
    p_path TEXT
)
RETURNS TEXT AS $$
DECLARE
    v_parts TEXT[];
    v_current JSONB;
    v_part TEXT;
    v_result TEXT;
BEGIN
    -- Handle empty or null data
    IF p_data IS NULL OR p_path IS NULL THEN
        RETURN '';
    END IF;

    -- Split path by dots (e.g., 'supplier.name' -> ['supplier', 'name'])
    v_parts := string_to_array(p_path, '.');
    v_current := p_data;

    -- Navigate through the JSON structure
    FOREACH v_part IN ARRAY v_parts
    LOOP
        -- Check if current level has the key
        IF jsonb_typeof(v_current) = 'object' AND v_current ? v_part THEN
            v_current := v_current -> v_part;
        ELSE
            -- Path not found, return empty string
            RETURN '';
        END IF;
    END LOOP;

    -- Extract final value as text
    IF jsonb_typeof(v_current) = 'string' THEN
        v_result := v_current #>> '{}';
    ELSIF jsonb_typeof(v_current) IN ('number', 'boolean') THEN
        v_result := v_current::TEXT;
    ELSIF jsonb_typeof(v_current) = 'null' THEN
        v_result := '';
    ELSE
        -- For objects or arrays, return JSON representation
        v_result := v_current::TEXT;
    END IF;

    RETURN COALESCE(v_result, '');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION get_json_value(JSONB, TEXT) IS 'Extracts value from JSONB using dot notation path';

-- =============================================================================
-- MAIN FUNCTION: Render Template
-- =============================================================================
-- Replaces {{placeholders}} in template with actual values from data

CREATE OR REPLACE FUNCTION render_template(
    p_template TEXT,
    p_data JSONB
)
RETURNS TEXT AS $$
DECLARE
    v_result TEXT;
    v_placeholder TEXT;
    v_field_name TEXT;
    v_field_value TEXT;
    v_is_raw BOOLEAN;
    v_matches TEXT[];
    v_match TEXT;
BEGIN
    -- Start with original template
    v_result := p_template;

    -- Handle null inputs
    IF p_template IS NULL THEN
        RETURN '';
    END IF;

    IF p_data IS NULL THEN
        p_data := '{}'::JSONB;
    END IF;

    -- Find all {{...}} and {{{...}}} patterns
    -- Using regexp_matches to find all placeholders
    FOR v_match IN
        SELECT unnest(regexp_matches(p_template, '\{\{(\{?[^}]+\}?)\}\}', 'g'))
    LOOP
        -- Check if it's raw (triple braces)
        IF v_match LIKE '{%}' THEN
            v_is_raw := TRUE;
            v_field_name := trim(both '{}' from v_match);
        ELSE
            v_is_raw := FALSE;
            v_field_name := trim(v_match);
        END IF;

        -- Get the value from data
        v_field_value := get_json_value(p_data, v_field_name);

        -- Apply HTML escaping unless it's raw
        IF NOT v_is_raw THEN
            v_field_value := escape_html(v_field_value);
        END IF;

        -- Replace in result
        IF v_is_raw THEN
            v_placeholder := '{{{' || v_field_name || '}}}';
        ELSE
            v_placeholder := '{{' || v_field_name || '}}';
        END IF;

        v_result := REPLACE(v_result, v_placeholder, v_field_value);
    END LOOP;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION render_template(TEXT, JSONB) IS 'Renders template by replacing {{placeholders}} with data values';

-- =============================================================================
-- ADVANCED FUNCTION: Render Template with Array Support
-- =============================================================================
-- Handles array iteration: {{#items}}...{{/items}}

CREATE OR REPLACE FUNCTION render_template_with_arrays(
    p_template TEXT,
    p_data JSONB
)
RETURNS TEXT AS $$
DECLARE
    v_result TEXT;
    v_array_name TEXT;
    v_array_template TEXT;
    v_array_data JSONB;
    v_array_item JSONB;
    v_rendered_items TEXT;
    v_pattern TEXT;
    v_match RECORD;
BEGIN
    v_result := p_template;

    -- Handle null inputs
    IF p_template IS NULL THEN
        RETURN '';
    END IF;

    IF p_data IS NULL THEN
        p_data := '{}'::JSONB;
    END IF;

    -- Find all {{#array_name}}...{{/array_name}} blocks
    FOR v_match IN
        SELECT
            matches[1] AS array_name,
            matches[2] AS inner_template
        FROM (
            SELECT regexp_matches(
                p_template,
                '\{\{#(\w+)\}\}(.*?)\{\{/\1\}\}',
                'gs'
            ) AS matches
        ) AS subq
    LOOP
        v_array_name := v_match.array_name;
        v_array_template := v_match.inner_template;

        -- Get array data
        v_array_data := p_data -> v_array_name;

        IF v_array_data IS NOT NULL AND jsonb_typeof(v_array_data) = 'array' THEN
            v_rendered_items := '';

            -- Iterate over array items
            FOR v_array_item IN
                SELECT * FROM jsonb_array_elements(v_array_data)
            LOOP
                -- Recursively render each item
                v_rendered_items := v_rendered_items ||
                    render_template(v_array_template, v_array_item);
            END LOOP;

            -- Replace the entire block with rendered items
            v_pattern := '{{#' || v_array_name || '}}' ||
                        v_array_template ||
                        '{{/' || v_array_name || '}}';
            v_result := REPLACE(v_result, v_pattern, v_rendered_items);
        ELSE
            -- Array is empty or not found, remove the block
            v_pattern := '{{#' || v_array_name || '}}' ||
                        v_array_template ||
                        '{{/' || v_array_name || '}}';
            v_result := REPLACE(v_result, v_pattern, '');
        END IF;
    END LOOP;

    -- Handle simple placeholders in the remaining template
    v_result := render_template(v_result, p_data);

    RETURN v_result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION render_template_with_arrays(TEXT, JSONB) IS 'Renders template with array iteration support';

-- =============================================================================
-- CONDITIONAL RENDERING HELPER
-- =============================================================================
-- Handles {{#if condition}}...{{/if}} blocks

CREATE OR REPLACE FUNCTION evaluate_template_condition(
    p_condition TEXT,
    p_data JSONB
)
RETURNS BOOLEAN AS $$
DECLARE
    v_parts TEXT[];
    v_field TEXT;
    v_operator TEXT;
    v_value TEXT;
    v_field_value TEXT;
BEGIN
    -- Parse simple conditions like "status == 'approved'"
    -- Split by operators
    IF p_condition LIKE '%==%' THEN
        v_parts := string_to_array(p_condition, '==');
        v_operator := '==';
    ELSIF p_condition LIKE '%!=%' THEN
        v_parts := string_to_array(p_condition, '!=');
        v_operator := '!=';
    ELSE
        -- Just check if field exists and is truthy
        v_field_value := get_json_value(p_data, trim(p_condition));
        RETURN v_field_value IS NOT NULL AND v_field_value != '' AND v_field_value != 'false';
    END IF;

    v_field := trim(v_parts[1]);
    v_value := trim(both '''' from trim(v_parts[2]));

    v_field_value := get_json_value(p_data, v_field);

    -- Evaluate condition
    CASE v_operator
        WHEN '==' THEN
            RETURN v_field_value = v_value;
        WHEN '!=' THEN
            RETURN v_field_value != v_value;
        ELSE
            RETURN FALSE;
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION evaluate_template_condition(TEXT, JSONB) IS 'Evaluates simple template conditions';

-- =============================================================================
-- COMPLETE TEMPLATE RENDERER (All Features)
-- =============================================================================
-- Handles all template features: placeholders, arrays, conditionals

CREATE OR REPLACE FUNCTION render_template_complete(
    p_template TEXT,
    p_data JSONB
)
RETURNS TEXT AS $$
DECLARE
    v_result TEXT;
    v_condition TEXT;
    v_if_template TEXT;
    v_match RECORD;
    v_pattern TEXT;
    v_should_render BOOLEAN;
BEGIN
    v_result := p_template;

    -- Handle null inputs
    IF p_template IS NULL THEN
        RETURN '';
    END IF;

    IF p_data IS NULL THEN
        p_data := '{}'::JSONB;
    END IF;

    -- First, handle conditionals {{#if condition}}...{{/if}}
    FOR v_match IN
        SELECT
            matches[1] AS condition,
            matches[2] AS inner_template
        FROM (
            SELECT regexp_matches(
                v_result,
                '\{\{#if\s+([^}]+)\}\}(.*?)\{\{/if\}\}',
                'gs'
            ) AS matches
        ) AS subq
    LOOP
        v_condition := v_match.condition;
        v_if_template := v_match.inner_template;

        -- Evaluate condition
        v_should_render := evaluate_template_condition(v_condition, p_data);

        v_pattern := '{{#if ' || v_condition || '}}' ||
                    v_if_template ||
                    '{{/if}}';

        IF v_should_render THEN
            -- Keep the content
            v_result := REPLACE(v_result, v_pattern, v_if_template);
        ELSE
            -- Remove the content
            v_result := REPLACE(v_result, v_pattern, '');
        END IF;
    END LOOP;

    -- Then handle arrays
    v_result := render_template_with_arrays(v_result, p_data);

    RETURN v_result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION render_template_complete(TEXT, JSONB) IS 'Complete template renderer with all features';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

-- Example Usage:
/*
-- Simple placeholder replacement
SELECT render_template(
    '<div>Hello {{name}}!</div>',
    '{"name": "World"}'::JSONB
);
-- Result: <div>Hello World!</div>

-- Nested paths
SELECT render_template(
    '<div>{{supplier.name}} - {{supplier.email}}</div>',
    '{"supplier": {"name": "Acme Corp", "email": "info@acme.com"}}'::JSONB
);
-- Result: <div>Acme Corp - info@acme.com</div>

-- HTML escaping
SELECT render_template(
    '<div>{{content}}</div>',
    '{"content": "<script>alert(1)</script>"}'::JSONB
);
-- Result: <div>&lt;script&gt;alert(1)&lt;/script&gt;</div>

-- Raw HTML (no escaping)
SELECT render_template(
    '<div>{{{html_content}}}</div>',
    '{"html_content": "<strong>Bold</strong>"}'::JSONB
);
-- Result: <div><strong>Bold</strong></div>

-- Array iteration
SELECT render_template_with_arrays(
    '<ul>{{#items}}<li>{{name}}: {{price}}</li>{{/items}}</ul>',
    '{"items": [{"name": "Item1", "price": 10}, {"name": "Item2", "price": 20}]}'::JSONB
);
-- Result: <ul><li>Item1: 10</li><li>Item2: 20</li></ul>

-- Conditionals
SELECT render_template_complete(
    '<div>{{#if status == ''approved''}}<span class="badge-success">Approved</span>{{/if}}</div>',
    '{"status": "approved"}'::JSONB
);
-- Result: <div><span class="badge-success">Approved</span></div>
*/
