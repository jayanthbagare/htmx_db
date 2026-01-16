-- Data Layer Functions
-- Function: fetch_list_data
-- Description: Fetches paginated list data with filtering and sorting
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- MAIN FUNCTION: Fetch List Data
-- =============================================================================
-- Fetches paginated list data with filtering, sorting, and security

CREATE OR REPLACE FUNCTION fetch_list_data(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_filters JSONB DEFAULT '{}'::JSONB,
    p_sort_field VARCHAR DEFAULT NULL,
    p_sort_direction VARCHAR DEFAULT 'ASC',
    p_page_size INTEGER DEFAULT 25,
    p_page_number INTEGER DEFAULT 1
)
RETURNS TABLE (
    total_count BIGINT,
    page_count INTEGER,
    current_page INTEGER,
    data JSONB
) AS $$
DECLARE
    v_table_name TEXT;
    v_pk_column TEXT;
    v_base_query TEXT;
    v_where_clause TEXT;
    v_order_clause TEXT;
    v_pagination TEXT;
    v_count_query TEXT;
    v_data_query TEXT;
    v_total BIGINT;
    v_data JSONB;
    v_page_size INTEGER;
    v_visible_fields TEXT[];
    v_soft_delete_condition TEXT;
BEGIN
    -- Validate user can read this entity
    IF NOT can_user_perform_action(p_user_id, p_entity_type, 'read') THEN
        RAISE EXCEPTION 'User % does not have permission to read %', p_user_id, p_entity_type;
    END IF;

    -- Get entity metadata
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types
    WHERE entity_name = p_entity_type;

    IF v_table_name IS NULL THEN
        RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
    END IF;

    v_pk_column := get_entity_pk(p_entity_type);

    -- Get visible fields for the user
    v_visible_fields := get_visible_fields(p_user_id, p_entity_type, 'list');

    -- Build query components
    v_base_query := build_query_with_joins(p_entity_type, v_visible_fields, TRUE);
    v_where_clause := build_where_clause(p_entity_type, p_filters, 't');
    v_order_clause := build_order_by_clause(p_entity_type, p_sort_field, p_sort_direction, 't');

    -- Validate and constrain page size
    v_page_size := GREATEST(1, LEAST(COALESCE(p_page_size, 25), 1000));
    v_pagination := build_pagination_clause(v_page_size, p_page_number);

    -- Add soft delete filter if table has is_deleted column
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = v_table_name AND column_name = 'is_deleted'
    ) THEN
        IF v_where_clause = '' THEN
            v_soft_delete_condition := 'WHERE t.is_deleted = FALSE';
        ELSE
            v_soft_delete_condition := ' AND t.is_deleted = FALSE';
        END IF;
    ELSE
        v_soft_delete_condition := '';
    END IF;

    -- Build count query
    v_count_query := format(
        'SELECT COUNT(*) FROM %I t %s %s',
        v_table_name,
        CASE WHEN v_where_clause = '' THEN v_soft_delete_condition
             ELSE v_where_clause || v_soft_delete_condition END,
        ''
    );

    -- Execute count query
    EXECUTE v_count_query INTO v_total;

    -- Build data query
    v_data_query := format(
        '%s %s %s %s %s',
        v_base_query,
        CASE WHEN v_where_clause = '' THEN v_soft_delete_condition
             ELSE v_where_clause || v_soft_delete_condition END,
        v_order_clause,
        v_pagination,
        ''
    );

    -- Execute data query and convert to JSON array
    EXECUTE format(
        'SELECT COALESCE(jsonb_agg(row_to_json(subq)), ''[]''::JSONB) FROM (%s) subq',
        v_data_query
    ) INTO v_data;

    -- Return results
    RETURN QUERY SELECT
        v_total,
        CEIL(v_total::NUMERIC / v_page_size)::INTEGER,
        COALESCE(p_page_number, 1),
        v_data;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fetch_list_data(UUID, VARCHAR, JSONB, VARCHAR, VARCHAR, INTEGER, INTEGER) IS 'Fetches paginated list data with filtering and sorting';

-- =============================================================================
-- SIMPLIFIED VERSION: Fetch List Data (Returns JSON only)
-- =============================================================================
-- Simpler version that returns just the JSON array of records

CREATE OR REPLACE FUNCTION fetch_list_data_simple(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_filters JSONB DEFAULT '{}'::JSONB,
    p_sort_field VARCHAR DEFAULT NULL,
    p_sort_direction VARCHAR DEFAULT 'ASC',
    p_limit INTEGER DEFAULT 100
)
RETURNS JSONB AS $$
DECLARE
    v_result RECORD;
BEGIN
    SELECT * INTO v_result
    FROM fetch_list_data(
        p_user_id,
        p_entity_type,
        p_filters,
        p_sort_field,
        p_sort_direction,
        p_limit,
        1
    );

    RETURN v_result.data;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fetch_list_data_simple(UUID, VARCHAR, JSONB, VARCHAR, VARCHAR, INTEGER) IS 'Simplified list data fetch returning JSON array';

-- =============================================================================
-- CURSOR-BASED PAGINATION FUNCTION
-- =============================================================================
-- For efficient pagination with large datasets

CREATE OR REPLACE FUNCTION fetch_list_data_cursor(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_filters JSONB DEFAULT '{}'::JSONB,
    p_sort_field VARCHAR DEFAULT NULL,
    p_sort_direction VARCHAR DEFAULT 'ASC',
    p_cursor_value TEXT DEFAULT NULL,
    p_page_size INTEGER DEFAULT 25
)
RETURNS TABLE (
    data JSONB,
    next_cursor TEXT,
    has_more BOOLEAN
) AS $$
DECLARE
    v_table_name TEXT;
    v_pk_column TEXT;
    v_base_query TEXT;
    v_where_clause TEXT;
    v_order_clause TEXT;
    v_cursor_condition TEXT;
    v_data_query TEXT;
    v_data JSONB;
    v_last_value TEXT;
    v_sort_col TEXT;
    v_has_more BOOLEAN;
    v_page_size INTEGER;
    v_visible_fields TEXT[];
BEGIN
    -- Validate user can read
    IF NOT can_user_perform_action(p_user_id, p_entity_type, 'read') THEN
        RAISE EXCEPTION 'User % does not have permission to read %', p_user_id, p_entity_type;
    END IF;

    -- Get entity metadata
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types WHERE entity_name = p_entity_type;

    v_pk_column := get_entity_pk(p_entity_type);
    v_sort_col := COALESCE(p_sort_field, v_pk_column);
    v_page_size := GREATEST(1, LEAST(COALESCE(p_page_size, 25), 1000));

    -- Get visible fields
    v_visible_fields := get_visible_fields(p_user_id, p_entity_type, 'list');

    -- Build base query
    v_base_query := build_query_with_joins(p_entity_type, v_visible_fields, TRUE);
    v_where_clause := build_where_clause(p_entity_type, p_filters, 't');
    v_order_clause := build_order_by_clause(p_entity_type, v_sort_col, p_sort_direction, 't');

    -- Add cursor condition if provided
    IF p_cursor_value IS NOT NULL THEN
        v_cursor_condition := format(
            ' AND t.%I %s %L',
            v_sort_col,
            CASE WHEN upper(p_sort_direction) = 'DESC' THEN '<' ELSE '>' END,
            p_cursor_value
        );
    ELSE
        v_cursor_condition := '';
    END IF;

    -- Add soft delete filter
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = v_table_name AND column_name = 'is_deleted'
    ) THEN
        IF v_where_clause = '' THEN
            v_where_clause := 'WHERE t.is_deleted = FALSE';
        ELSE
            v_where_clause := v_where_clause || ' AND t.is_deleted = FALSE';
        END IF;
    END IF;

    -- Build query with cursor condition
    v_data_query := format(
        '%s %s %s %s LIMIT %s',
        v_base_query,
        v_where_clause || v_cursor_condition,
        v_order_clause,
        '',
        v_page_size + 1  -- Fetch one extra to check for more
    );

    -- Execute query
    EXECUTE format(
        'SELECT COALESCE(jsonb_agg(row_to_json(subq)), ''[]''::JSONB) FROM (%s) subq',
        v_data_query
    ) INTO v_data;

    -- Check if there are more records
    v_has_more := jsonb_array_length(v_data) > v_page_size;

    -- Remove extra record if present
    IF v_has_more THEN
        v_data := v_data - (jsonb_array_length(v_data) - 1);
    END IF;

    -- Get cursor value from last record
    IF jsonb_array_length(v_data) > 0 THEN
        v_last_value := v_data->(jsonb_array_length(v_data) - 1)->>v_sort_col;
    ELSE
        v_last_value := NULL;
    END IF;

    RETURN QUERY SELECT v_data, v_last_value, v_has_more;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fetch_list_data_cursor(UUID, VARCHAR, JSONB, VARCHAR, VARCHAR, TEXT, INTEGER) IS 'Cursor-based pagination for large datasets';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Basic list fetch
SELECT * FROM fetch_list_data(
    '00000000-0000-0000-0000-000000000100'::UUID,  -- admin user
    'purchase_order'
);

-- With filters and sorting
SELECT * FROM fetch_list_data(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    '{"status": ["draft", "submitted"]}'::JSONB,
    'po_date',
    'DESC',
    25,
    1
);

-- Simple version
SELECT fetch_list_data_simple(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'supplier',
    '{"is_active": true}'::JSONB,
    'supplier_name',
    'ASC',
    50
);

-- Cursor-based pagination
SELECT * FROM fetch_list_data_cursor(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    '{}'::JSONB,
    'po_date',
    'DESC',
    NULL,  -- no cursor for first page
    25
);

-- Next page with cursor
SELECT * FROM fetch_list_data_cursor(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    '{}'::JSONB,
    'po_date',
    'DESC',
    '2024-01-15',  -- cursor from previous result
    25
);
*/
