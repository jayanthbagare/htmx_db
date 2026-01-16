-- Data Layer Functions
-- Function: build_where_clause
-- Description: Converts filter JSON to secure SQL WHERE clause
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- HELPER FUNCTION: Get Filter Operator
-- =============================================================================
-- Extracts operator from filter key suffix

CREATE OR REPLACE FUNCTION get_filter_operator(p_key TEXT)
RETURNS TABLE (field_name TEXT, operator TEXT, sql_operator TEXT) AS $$
BEGIN
    -- Check for operator suffixes
    IF p_key LIKE '%_gte' THEN
        RETURN QUERY SELECT
            substring(p_key from 1 for length(p_key) - 4),
            'gte'::TEXT,
            '>='::TEXT;
    ELSIF p_key LIKE '%_gt' THEN
        RETURN QUERY SELECT
            substring(p_key from 1 for length(p_key) - 3),
            'gt'::TEXT,
            '>'::TEXT;
    ELSIF p_key LIKE '%_lte' THEN
        RETURN QUERY SELECT
            substring(p_key from 1 for length(p_key) - 4),
            'lte'::TEXT,
            '<='::TEXT;
    ELSIF p_key LIKE '%_lt' THEN
        RETURN QUERY SELECT
            substring(p_key from 1 for length(p_key) - 3),
            'lt'::TEXT,
            '<'::TEXT;
    ELSIF p_key LIKE '%_like' THEN
        RETURN QUERY SELECT
            substring(p_key from 1 for length(p_key) - 5),
            'like'::TEXT,
            'ILIKE'::TEXT;
    ELSIF p_key LIKE '%_not' THEN
        RETURN QUERY SELECT
            substring(p_key from 1 for length(p_key) - 4),
            'not'::TEXT,
            '<>'::TEXT;
    ELSIF p_key LIKE '%_notnull' THEN
        RETURN QUERY SELECT
            substring(p_key from 1 for length(p_key) - 8),
            'notnull'::TEXT,
            'IS NOT NULL'::TEXT;
    ELSIF p_key LIKE '%_null' THEN
        RETURN QUERY SELECT
            substring(p_key from 1 for length(p_key) - 5),
            'null'::TEXT,
            'IS NULL'::TEXT;
    ELSE
        -- Default: equals or IN (for arrays)
        RETURN QUERY SELECT
            p_key,
            'eq'::TEXT,
            '='::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION get_filter_operator(TEXT) IS 'Extracts operator from filter key suffix';

-- =============================================================================
-- HELPER FUNCTION: Quote and Escape Value
-- =============================================================================
-- Safely quotes a value for SQL (prevents SQL injection)

CREATE OR REPLACE FUNCTION quote_filter_value(p_value TEXT, p_data_type TEXT DEFAULT 'text')
RETURNS TEXT AS $$
BEGIN
    IF p_value IS NULL THEN
        RETURN 'NULL';
    END IF;

    -- Use quote_literal for safe escaping
    CASE p_data_type
        WHEN 'integer', 'bigint', 'smallint' THEN
            -- Validate it's actually a number
            IF p_value ~ '^-?[0-9]+$' THEN
                RETURN p_value;
            ELSE
                RAISE EXCEPTION 'Invalid integer value: %', p_value;
            END IF;
        WHEN 'numeric', 'decimal', 'real', 'double precision' THEN
            IF p_value ~ '^-?[0-9]+\.?[0-9]*$' THEN
                RETURN p_value;
            ELSE
                RAISE EXCEPTION 'Invalid numeric value: %', p_value;
            END IF;
        WHEN 'boolean' THEN
            IF lower(p_value) IN ('true', 'false', 't', 'f', '1', '0') THEN
                RETURN p_value;
            ELSE
                RAISE EXCEPTION 'Invalid boolean value: %', p_value;
            END IF;
        WHEN 'uuid' THEN
            IF p_value ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                RETURN quote_literal(p_value);
            ELSE
                RAISE EXCEPTION 'Invalid UUID value: %', p_value;
            END IF;
        WHEN 'date' THEN
            -- Validate date format
            IF p_value ~ '^\d{4}-\d{2}-\d{2}$' THEN
                RETURN quote_literal(p_value);
            ELSE
                RAISE EXCEPTION 'Invalid date value: %', p_value;
            END IF;
        ELSE
            -- Default: text, use quote_literal for safe escaping
            RETURN quote_literal(p_value);
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION quote_filter_value(TEXT, TEXT) IS 'Safely quotes a value for SQL';

-- =============================================================================
-- HELPER FUNCTION: Get Column Data Type
-- =============================================================================
-- Gets the data type for a column from ui_field_definitions or information_schema

CREATE OR REPLACE FUNCTION get_column_data_type(
    p_entity_type VARCHAR,
    p_column_name VARCHAR
)
RETURNS TEXT AS $$
DECLARE
    v_data_type TEXT;
    v_table_name TEXT;
BEGIN
    -- First try ui_field_definitions
    SELECT f.data_type INTO v_data_type
    FROM ui_field_definitions f
    JOIN ui_entity_types e ON f.entity_type_id = e.entity_type_id
    WHERE e.entity_name = p_entity_type
      AND f.field_name = p_column_name;

    IF FOUND THEN
        -- Map our data types to SQL data types
        CASE v_data_type
            WHEN 'text', 'textarea', 'email', 'phone', 'select' THEN
                RETURN 'text';
            WHEN 'number', 'integer' THEN
                RETURN 'integer';
            WHEN 'decimal' THEN
                RETURN 'numeric';
            WHEN 'date' THEN
                RETURN 'date';
            WHEN 'datetime' THEN
                RETURN 'timestamp';
            WHEN 'checkbox' THEN
                RETURN 'boolean';
            WHEN 'lookup' THEN
                RETURN 'uuid';
            ELSE
                RETURN 'text';
        END CASE;
    END IF;

    -- Fall back to information_schema
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types WHERE entity_name = p_entity_type;

    IF v_table_name IS NOT NULL THEN
        SELECT data_type INTO v_data_type
        FROM information_schema.columns
        WHERE table_name = v_table_name
          AND column_name = p_column_name;

        IF FOUND THEN
            RETURN v_data_type;
        END IF;
    END IF;

    -- Default to text
    RETURN 'text';
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_column_data_type(VARCHAR, VARCHAR) IS 'Gets column data type for validation';

-- =============================================================================
-- MAIN FUNCTION: Build WHERE Clause
-- =============================================================================
-- Converts filter JSON to secure SQL WHERE clause

CREATE OR REPLACE FUNCTION build_where_clause(
    p_entity_type VARCHAR,
    p_filters JSONB,
    p_table_alias VARCHAR DEFAULT 't'
)
RETURNS TEXT AS $$
DECLARE
    v_where_parts TEXT[] := ARRAY[]::TEXT[];
    v_key TEXT;
    v_value JSONB;
    v_filter_info RECORD;
    v_sql_value TEXT;
    v_condition TEXT;
    v_data_type TEXT;
    v_array_values TEXT[];
    v_quoted_values TEXT[];
    v_i INTEGER;
BEGIN
    -- Handle NULL or empty filters
    IF p_filters IS NULL OR p_filters = '{}'::JSONB THEN
        RETURN '';
    END IF;

    -- Iterate through filter keys
    FOR v_key, v_value IN SELECT * FROM jsonb_each(p_filters)
    LOOP
        -- Skip null values
        IF v_value IS NULL OR v_value = 'null'::JSONB THEN
            CONTINUE;
        END IF;

        -- Get operator info from key
        SELECT * INTO v_filter_info
        FROM get_filter_operator(v_key);

        -- Get data type for the column
        v_data_type := get_column_data_type(p_entity_type, v_filter_info.field_name);

        -- Handle different value types and operators
        IF jsonb_typeof(v_value) = 'array' THEN
            -- Array: use IN clause
            v_array_values := ARRAY(SELECT jsonb_array_elements_text(v_value));
            v_quoted_values := ARRAY[]::TEXT[];

            FOREACH v_sql_value IN ARRAY v_array_values
            LOOP
                v_quoted_values := array_append(
                    v_quoted_values,
                    quote_filter_value(v_sql_value, v_data_type)
                );
            END LOOP;

            v_condition := format(
                '%s.%I IN (%s)',
                p_table_alias,
                v_filter_info.field_name,
                array_to_string(v_quoted_values, ', ')
            );
        ELSIF v_filter_info.operator = 'null' THEN
            v_condition := format(
                '%s.%I IS NULL',
                p_table_alias,
                v_filter_info.field_name
            );
        ELSIF v_filter_info.operator = 'notnull' THEN
            v_condition := format(
                '%s.%I IS NOT NULL',
                p_table_alias,
                v_filter_info.field_name
            );
        ELSIF v_filter_info.operator = 'like' THEN
            -- ILIKE for case-insensitive search
            v_sql_value := quote_filter_value(v_value #>> '{}', 'text');
            v_condition := format(
                '%s.%I ILIKE %s',
                p_table_alias,
                v_filter_info.field_name,
                v_sql_value
            );
        ELSE
            -- Simple comparison
            v_sql_value := quote_filter_value(v_value #>> '{}', v_data_type);
            v_condition := format(
                '%s.%I %s %s',
                p_table_alias,
                v_filter_info.field_name,
                v_filter_info.sql_operator,
                v_sql_value
            );
        END IF;

        v_where_parts := array_append(v_where_parts, v_condition);
    END LOOP;

    -- Return empty string if no conditions
    IF array_length(v_where_parts, 1) IS NULL THEN
        RETURN '';
    END IF;

    -- Join with AND
    RETURN 'WHERE ' || array_to_string(v_where_parts, ' AND ');
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION build_where_clause(VARCHAR, JSONB, VARCHAR) IS 'Converts filter JSON to secure SQL WHERE clause';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Basic filter
SELECT build_where_clause(
    'purchase_order',
    '{"status": "draft"}'::JSONB
);
-- Result: WHERE t."status" = 'draft'

-- Multiple values (IN clause)
SELECT build_where_clause(
    'purchase_order',
    '{"status": ["draft", "submitted", "approved"]}'::JSONB
);
-- Result: WHERE t."status" IN ('draft', 'submitted', 'approved')

-- Range filters
SELECT build_where_clause(
    'purchase_order',
    '{"po_date_gte": "2024-01-01", "po_date_lte": "2024-12-31"}'::JSONB
);
-- Result: WHERE t."po_date" >= '2024-01-01' AND t."po_date" <= '2024-12-31'

-- Greater than
SELECT build_where_clause(
    'purchase_order',
    '{"total_amount_gt": 10000}'::JSONB
);
-- Result: WHERE t."total_amount" > 10000

-- LIKE search
SELECT build_where_clause(
    'supplier',
    '{"supplier_name_like": "%Acme%"}'::JSONB
);
-- Result: WHERE t."supplier_name" ILIKE '%Acme%'

-- Combined filters
SELECT build_where_clause(
    'purchase_order',
    '{"status": ["draft", "submitted"], "po_date_gte": "2024-01-01", "total_amount_gt": 5000}'::JSONB
);
-- Result: WHERE t."status" IN ('draft', 'submitted') AND t."po_date" >= '2024-01-01' AND t."total_amount" > 5000

-- NULL check
SELECT build_where_clause(
    'purchase_order',
    '{"approved_by_null": true}'::JSONB
);
-- Result: WHERE t."approved_by" IS NULL

-- NOT NULL check
SELECT build_where_clause(
    'purchase_order',
    '{"approved_by_notnull": true}'::JSONB
);
-- Result: WHERE t."approved_by" IS NOT NULL
*/
