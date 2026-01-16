-- Data Layer Functions
-- Function: fetch_form_data
-- Description: Fetches single record data for forms with lookups
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- MAIN FUNCTION: Fetch Form Data
-- =============================================================================
-- Fetches a single record for form display/editing with lookups resolved

CREATE OR REPLACE FUNCTION fetch_form_data(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_id UUID,
    p_view_type VARCHAR DEFAULT 'form_view'
)
RETURNS JSONB AS $$
DECLARE
    v_table_name TEXT;
    v_pk_column TEXT;
    v_base_query TEXT;
    v_where_clause TEXT;
    v_data_query TEXT;
    v_result JSONB;
    v_visible_fields TEXT[];
    v_action_name VARCHAR;
BEGIN
    -- Determine action based on view type
    v_action_name := CASE p_view_type
        WHEN 'form_create' THEN 'create'
        WHEN 'form_edit' THEN 'edit'
        ELSE 'read'
    END;

    -- Validate user has permission for this action
    IF NOT can_user_perform_action(p_user_id, p_entity_type, v_action_name) THEN
        RAISE EXCEPTION 'User % does not have % permission for %', p_user_id, v_action_name, p_entity_type;
    END IF;

    -- Get entity metadata
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types
    WHERE entity_name = p_entity_type;

    IF v_table_name IS NULL THEN
        RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
    END IF;

    v_pk_column := get_entity_pk(p_entity_type);

    -- Get visible fields for this view type
    v_visible_fields := get_visible_fields(p_user_id, p_entity_type, p_view_type);

    -- Build base query with lookups
    v_base_query := build_query_with_joins(p_entity_type, v_visible_fields, TRUE);

    -- Build where clause for single record
    v_where_clause := format('WHERE t.%I = %L', v_pk_column, p_record_id);

    -- Add soft delete filter if applicable
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = v_table_name AND column_name = 'is_deleted'
    ) THEN
        v_where_clause := v_where_clause || ' AND t.is_deleted = FALSE';
    END IF;

    -- Build full query
    v_data_query := v_base_query || ' ' || v_where_clause;

    -- Execute query
    EXECUTE format(
        'SELECT row_to_json(subq) FROM (%s) subq',
        v_data_query
    ) INTO v_result;

    IF v_result IS NULL THEN
        RAISE EXCEPTION 'Record not found: % with id %', p_entity_type, p_record_id;
    END IF;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fetch_form_data(UUID, VARCHAR, UUID, VARCHAR) IS 'Fetches single record with lookups for form display';

-- =============================================================================
-- HELPER FUNCTION: Fetch Form Data with Edit Info
-- =============================================================================
-- Returns form data with editability information

CREATE OR REPLACE FUNCTION fetch_form_data_with_permissions(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_id UUID,
    p_view_type VARCHAR DEFAULT 'form_edit'
)
RETURNS JSONB AS $$
DECLARE
    v_data JSONB;
    v_editable_fields TEXT[];
    v_visible_fields TEXT[];
    v_field_info JSONB := '{}'::JSONB;
    v_field RECORD;
BEGIN
    -- Get the form data
    v_data := fetch_form_data(p_user_id, p_entity_type, p_record_id, p_view_type);

    -- Get field permissions
    v_editable_fields := get_editable_fields(p_user_id, p_entity_type, p_view_type);
    v_visible_fields := get_visible_fields(p_user_id, p_entity_type, p_view_type);

    -- Build field info object
    FOR v_field IN
        SELECT field_name, is_visible, is_editable
        FROM get_user_field_permissions(p_user_id, p_entity_type, p_view_type)
    LOOP
        v_field_info := v_field_info || jsonb_build_object(
            v_field.field_name,
            jsonb_build_object(
                'visible', v_field.is_visible,
                'editable', v_field.is_editable
            )
        );
    END LOOP;

    -- Return combined result
    RETURN jsonb_build_object(
        'data', v_data,
        'field_permissions', v_field_info,
        'editable_fields', to_jsonb(v_editable_fields),
        'visible_fields', to_jsonb(v_visible_fields)
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fetch_form_data_with_permissions(UUID, VARCHAR, UUID, VARCHAR) IS 'Fetches form data with field permission info';

-- =============================================================================
-- HELPER FUNCTION: Fetch Lookup Options
-- =============================================================================
-- Returns lookup options for a field (e.g., supplier dropdown)

CREATE OR REPLACE FUNCTION fetch_lookup_options(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_field_name VARCHAR,
    p_search_term TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 50
)
RETURNS JSONB AS $$
DECLARE
    v_lookup_info RECORD;
    v_query TEXT;
    v_result JSONB;
    v_pk_column TEXT;
    v_where_clause TEXT := '';
BEGIN
    -- Get lookup field info
    SELECT * INTO v_lookup_info
    FROM get_entity_lookup_fields(p_entity_type)
    WHERE field_name = p_field_name;

    IF v_lookup_info IS NULL THEN
        RAISE EXCEPTION 'Field % is not a lookup field in %', p_field_name, p_entity_type;
    END IF;

    v_pk_column := v_lookup_info.lookup_pk;

    -- Build search condition if provided
    IF p_search_term IS NOT NULL AND p_search_term != '' THEN
        v_where_clause := format(
            'WHERE %I ILIKE %L',
            v_lookup_info.display_field,
            '%' || p_search_term || '%'
        );
    END IF;

    -- Add active filter if applicable
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = v_lookup_info.lookup_table AND column_name = 'is_active'
    ) THEN
        IF v_where_clause = '' THEN
            v_where_clause := 'WHERE is_active = TRUE';
        ELSE
            v_where_clause := v_where_clause || ' AND is_active = TRUE';
        END IF;
    END IF;

    -- Build query
    v_query := format(
        'SELECT %I AS id, %I AS label FROM %I %s ORDER BY %I LIMIT %s',
        v_pk_column,
        v_lookup_info.display_field,
        v_lookup_info.lookup_table,
        v_where_clause,
        v_lookup_info.display_field,
        p_limit
    );

    -- Execute query
    EXECUTE format(
        'SELECT COALESCE(jsonb_agg(row_to_json(subq)), ''[]''::JSONB) FROM (%s) subq',
        v_query
    ) INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fetch_lookup_options(UUID, VARCHAR, VARCHAR, TEXT, INTEGER) IS 'Fetches lookup options for dropdown fields';

-- =============================================================================
-- HELPER FUNCTION: Fetch New Form Defaults
-- =============================================================================
-- Returns default values for creating a new record

CREATE OR REPLACE FUNCTION fetch_new_form_defaults(
    p_user_id UUID,
    p_entity_type VARCHAR
)
RETURNS JSONB AS $$
DECLARE
    v_defaults JSONB := '{}'::JSONB;
    v_field RECORD;
    v_table_name TEXT;
    v_default_value TEXT;
BEGIN
    -- Validate user can create
    IF NOT can_user_perform_action(p_user_id, p_entity_type, 'create') THEN
        RAISE EXCEPTION 'User % does not have create permission for %', p_user_id, p_entity_type;
    END IF;

    -- Get table name
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types WHERE entity_name = p_entity_type;

    -- Get field definitions and their defaults
    FOR v_field IN
        SELECT
            f.field_name,
            f.data_type,
            c.column_default
        FROM ui_field_definitions f
        JOIN ui_entity_types e ON f.entity_type_id = e.entity_type_id
        LEFT JOIN information_schema.columns c ON (
            c.table_name = v_table_name
            AND c.column_name = f.field_name
        )
        WHERE e.entity_name = p_entity_type
        ORDER BY f.field_order
    LOOP
        -- Set defaults based on data type and column defaults
        IF v_field.column_default IS NOT NULL THEN
            -- Use database default (simplified parsing)
            IF v_field.column_default LIKE '''%''::character%' THEN
                v_default_value := substring(v_field.column_default from '''([^'']+)''');
            ELSIF v_field.column_default = 'CURRENT_DATE' THEN
                v_default_value := CURRENT_DATE::TEXT;
            ELSIF v_field.column_default = 'now()' THEN
                v_default_value := NOW()::TEXT;
            ELSIF v_field.column_default ~ '^[0-9]+$' THEN
                v_default_value := v_field.column_default;
            ELSE
                v_default_value := NULL;
            END IF;
        ELSE
            -- Type-based defaults
            CASE v_field.data_type
                WHEN 'date' THEN
                    v_default_value := CURRENT_DATE::TEXT;
                WHEN 'checkbox' THEN
                    v_default_value := 'false';
                WHEN 'number', 'integer', 'decimal' THEN
                    v_default_value := '0';
                ELSE
                    v_default_value := NULL;
            END CASE;
        END IF;

        IF v_default_value IS NOT NULL THEN
            v_defaults := v_defaults || jsonb_build_object(v_field.field_name, v_default_value);
        END IF;
    END LOOP;

    -- Add created_by if exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = v_table_name AND column_name = 'created_by'
    ) THEN
        v_defaults := v_defaults || jsonb_build_object('created_by', p_user_id);
    END IF;

    RETURN v_defaults;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fetch_new_form_defaults(UUID, VARCHAR) IS 'Returns default values for new record creation';

-- =============================================================================
-- HELPER FUNCTION: Fetch Related Records
-- =============================================================================
-- Returns related records (e.g., PO lines for a PO)

CREATE OR REPLACE FUNCTION fetch_related_records(
    p_user_id UUID,
    p_parent_entity_type VARCHAR,
    p_parent_id UUID,
    p_child_entity_type VARCHAR
)
RETURNS JSONB AS $$
DECLARE
    v_child_table TEXT;
    v_parent_fk TEXT;
    v_query TEXT;
    v_result JSONB;
BEGIN
    -- Get child table info
    SELECT primary_table INTO v_child_table
    FROM ui_entity_types WHERE entity_name = p_child_entity_type;

    IF v_child_table IS NULL THEN
        RAISE EXCEPTION 'Unknown entity type: %', p_child_entity_type;
    END IF;

    -- Determine FK column (convention: parent_entity_id)
    v_parent_fk := replace(p_parent_entity_type, '_', '') || '_id';
    IF p_parent_entity_type = 'purchase_order' THEN
        v_parent_fk := 'po_id';
    END IF;

    -- Check if FK column exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = v_child_table AND column_name = v_parent_fk
    ) THEN
        RETURN '[]'::JSONB;
    END IF;

    -- Build query
    v_query := format(
        'SELECT * FROM %I WHERE %I = %L ORDER BY line_number',
        v_child_table,
        v_parent_fk,
        p_parent_id
    );

    -- Execute query
    EXECUTE format(
        'SELECT COALESCE(jsonb_agg(row_to_json(subq)), ''[]''::JSONB) FROM (%s) subq',
        v_query
    ) INTO v_result;

    RETURN v_result;
EXCEPTION
    WHEN undefined_column THEN
        -- If line_number doesn't exist, try without ORDER BY
        v_query := format(
            'SELECT * FROM %I WHERE %I = %L',
            v_child_table,
            v_parent_fk,
            p_parent_id
        );
        EXECUTE format(
            'SELECT COALESCE(jsonb_agg(row_to_json(subq)), ''[]''::JSONB) FROM (%s) subq',
            v_query
        ) INTO v_result;
        RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fetch_related_records(UUID, VARCHAR, UUID, VARCHAR) IS 'Fetches related child records for a parent';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Fetch single PO for viewing
SELECT fetch_form_data(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'some-po-uuid-here'::UUID,
    'form_view'
);

-- Fetch PO for editing with permission info
SELECT fetch_form_data_with_permissions(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'some-po-uuid-here'::UUID,
    'form_edit'
);

-- Fetch supplier dropdown options
SELECT fetch_lookup_options(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'supplier_id',
    'Acme',  -- search term
    20
);

-- Get defaults for new PO
SELECT fetch_new_form_defaults(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order'
);

-- Fetch PO lines for a PO
SELECT fetch_related_records(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'some-po-uuid-here'::UUID,
    'purchase_order_line'
);
*/
