-- Data Layer Functions
-- Function: build_query_with_joins
-- Description: Builds query with JOINs for lookup fields
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- HELPER FUNCTION: Get Entity Lookup Fields
-- =============================================================================
-- Returns lookup fields for an entity with their join information

CREATE OR REPLACE FUNCTION get_entity_lookup_fields(p_entity_type VARCHAR)
RETURNS TABLE (
    field_name VARCHAR,
    lookup_entity VARCHAR,
    lookup_table VARCHAR,
    lookup_pk VARCHAR,
    display_field VARCHAR
) AS $$
DECLARE
    v_rule JSONB;
BEGIN
    RETURN QUERY
    SELECT
        f.field_name,
        COALESCE(
            f.lookup_entity,
            CASE WHEN f.validation_rule IS NOT NULL AND f.validation_rule LIKE '{%'
                 THEN (f.validation_rule::JSONB->>'entity')
                 ELSE NULL
            END
        )::VARCHAR AS lookup_entity,
        COALESCE(
            e2.primary_table,
            f.lookup_entity,
            CASE WHEN f.validation_rule IS NOT NULL AND f.validation_rule LIKE '{%'
                 THEN (f.validation_rule::JSONB->>'entity')
                 ELSE f.field_name
            END
        )::VARCHAR AS lookup_table,
        COALESCE(
            CASE
                WHEN f.lookup_entity = 'users' THEN 'user_id'
                WHEN f.lookup_entity IS NOT NULL THEN f.lookup_entity || '_id'
                WHEN f.validation_rule IS NOT NULL AND f.validation_rule LIKE '{%'
                     AND (f.validation_rule::JSONB->>'entity') = 'users' THEN 'user_id'
                WHEN f.validation_rule IS NOT NULL AND f.validation_rule LIKE '{%'
                     THEN (f.validation_rule::JSONB->>'entity') || '_id'
                ELSE f.field_name
            END
        )::VARCHAR AS lookup_pk,
        COALESCE(
            f.lookup_display_field,
            CASE WHEN f.validation_rule IS NOT NULL AND f.validation_rule LIKE '{%'
                 THEN (f.validation_rule::JSONB->>'display_field')
                 ELSE NULL
            END,
            'name'
        )::VARCHAR AS display_field
    FROM ui_field_definitions f
    JOIN ui_entity_types e ON f.entity_type_id = e.entity_type_id
    LEFT JOIN ui_entity_types e2 ON e2.entity_name = COALESCE(
        f.lookup_entity,
        CASE WHEN f.validation_rule IS NOT NULL AND f.validation_rule LIKE '{%'
             THEN (f.validation_rule::JSONB->>'entity')
             ELSE NULL
        END
    )
    WHERE e.entity_name = p_entity_type
      AND f.data_type = 'lookup';
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_entity_lookup_fields(VARCHAR) IS 'Returns lookup fields with join information';

-- =============================================================================
-- HELPER FUNCTION: Get Entity Columns
-- =============================================================================
-- Returns all column names for an entity from ui_field_definitions

CREATE OR REPLACE FUNCTION get_entity_columns(p_entity_type VARCHAR)
RETURNS TEXT[] AS $$
DECLARE
    v_columns TEXT[];
BEGIN
    SELECT ARRAY(
        SELECT f.field_name
        FROM ui_field_definitions f
        JOIN ui_entity_types e ON f.entity_type_id = e.entity_type_id
        WHERE e.entity_name = p_entity_type
        ORDER BY f.field_order
    ) INTO v_columns;

    RETURN v_columns;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_entity_columns(VARCHAR) IS 'Returns column names for an entity';

-- =============================================================================
-- HELPER FUNCTION: Get Primary Key Column
-- =============================================================================
-- Returns the primary key column name for an entity

CREATE OR REPLACE FUNCTION get_entity_pk(p_entity_type VARCHAR)
RETURNS TEXT AS $$
DECLARE
    v_pk TEXT;
    v_table_name TEXT;
BEGIN
    -- Get the primary table name
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types
    WHERE entity_name = p_entity_type;

    -- Common convention: entity_name + '_id' or 'id'
    -- Check information_schema for actual PK
    SELECT kcu.column_name INTO v_pk
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
    WHERE tc.table_name = v_table_name
      AND tc.constraint_type = 'PRIMARY KEY'
    LIMIT 1;

    -- Fallback to convention
    IF v_pk IS NULL THEN
        v_pk := p_entity_type || '_id';
    END IF;

    RETURN v_pk;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_entity_pk(VARCHAR) IS 'Returns primary key column for an entity';

-- =============================================================================
-- MAIN FUNCTION: Build Query with Joins
-- =============================================================================
-- Builds a SELECT query with JOINs for lookup fields

CREATE OR REPLACE FUNCTION build_query_with_joins(
    p_entity_type VARCHAR,
    p_select_columns TEXT[] DEFAULT NULL,
    p_include_lookups BOOLEAN DEFAULT TRUE
)
RETURNS TEXT AS $$
DECLARE
    v_table_name TEXT;
    v_pk_column TEXT;
    v_select_parts TEXT[] := ARRAY[]::TEXT[];
    v_join_parts TEXT[] := ARRAY[]::TEXT[];
    v_column TEXT;
    v_lookup RECORD;
    v_alias_counter INTEGER := 1;
    v_all_columns TEXT[];
BEGIN
    -- Get entity metadata
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types
    WHERE entity_name = p_entity_type;

    IF v_table_name IS NULL THEN
        RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
    END IF;

    v_pk_column := get_entity_pk(p_entity_type);

    -- Get columns to select
    IF p_select_columns IS NULL OR array_length(p_select_columns, 1) IS NULL THEN
        v_all_columns := get_entity_columns(p_entity_type);
    ELSE
        v_all_columns := p_select_columns;
    END IF;

    -- Build SELECT parts for main table columns
    FOREACH v_column IN ARRAY v_all_columns
    LOOP
        v_select_parts := array_append(v_select_parts, format('t.%I', v_column));
    END LOOP;

    -- Add primary key if not already included
    IF NOT (v_pk_column = ANY(v_all_columns)) THEN
        v_select_parts := array_prepend(format('t.%I', v_pk_column), v_select_parts);
    END IF;

    -- Add lookup fields with JOINs
    IF p_include_lookups THEN
        FOR v_lookup IN
            SELECT * FROM get_entity_lookup_fields(p_entity_type)
        LOOP
            -- Add lookup display field to SELECT
            v_select_parts := array_append(
                v_select_parts,
                format('lkp%s.%I AS %I',
                    v_alias_counter,
                    v_lookup.display_field,
                    v_lookup.field_name || '_display'
                )
            );

            -- Add LEFT JOIN for lookup table
            v_join_parts := array_append(
                v_join_parts,
                format('LEFT JOIN %I lkp%s ON t.%I = lkp%s.%I',
                    v_lookup.lookup_table,
                    v_alias_counter,
                    v_lookup.field_name,
                    v_alias_counter,
                    v_lookup.lookup_pk
                )
            );

            v_alias_counter := v_alias_counter + 1;
        END LOOP;
    END IF;

    -- Build the query
    RETURN format(
        'SELECT %s FROM %I t %s',
        array_to_string(v_select_parts, ', '),
        v_table_name,
        array_to_string(v_join_parts, ' ')
    );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION build_query_with_joins(VARCHAR, TEXT[], BOOLEAN) IS 'Builds SELECT query with JOINs for lookups';

-- =============================================================================
-- HELPER FUNCTION: Build Order By Clause
-- =============================================================================
-- Builds ORDER BY clause with validation

CREATE OR REPLACE FUNCTION build_order_by_clause(
    p_entity_type VARCHAR,
    p_sort_field VARCHAR,
    p_sort_direction VARCHAR DEFAULT 'ASC',
    p_table_alias VARCHAR DEFAULT 't'
)
RETURNS TEXT AS $$
DECLARE
    v_valid_columns TEXT[];
    v_direction TEXT;
BEGIN
    -- Validate sort direction
    v_direction := upper(COALESCE(p_sort_direction, 'ASC'));
    IF v_direction NOT IN ('ASC', 'DESC') THEN
        v_direction := 'ASC';
    END IF;

    -- If no sort field specified, return empty
    IF p_sort_field IS NULL OR p_sort_field = '' THEN
        RETURN '';
    END IF;

    -- Get valid columns for this entity
    v_valid_columns := get_entity_columns(p_entity_type);

    -- Validate sort field exists
    IF NOT (p_sort_field = ANY(v_valid_columns)) THEN
        -- Check if it's a lookup display field
        IF p_sort_field LIKE '%_display' THEN
            -- Allow lookup display fields
            RETURN format('ORDER BY %I %s', p_sort_field, v_direction);
        ELSE
            RAISE WARNING 'Invalid sort field: %. Using default order.', p_sort_field;
            RETURN '';
        END IF;
    END IF;

    RETURN format('ORDER BY %s.%I %s', p_table_alias, p_sort_field, v_direction);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION build_order_by_clause(VARCHAR, VARCHAR, VARCHAR, VARCHAR) IS 'Builds ORDER BY clause with validation';

-- =============================================================================
-- HELPER FUNCTION: Build Pagination Clause
-- =============================================================================
-- Builds LIMIT/OFFSET for pagination

CREATE OR REPLACE FUNCTION build_pagination_clause(
    p_page_size INTEGER,
    p_page_number INTEGER
)
RETURNS TEXT AS $$
DECLARE
    v_limit INTEGER;
    v_offset INTEGER;
BEGIN
    -- Validate and set defaults
    v_limit := GREATEST(1, LEAST(COALESCE(p_page_size, 25), 1000));  -- Max 1000 rows
    v_offset := GREATEST(0, (COALESCE(p_page_number, 1) - 1)) * v_limit;

    RETURN format('LIMIT %s OFFSET %s', v_limit, v_offset);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION build_pagination_clause(INTEGER, INTEGER) IS 'Builds LIMIT/OFFSET for pagination';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Build query for purchase_order with lookups
SELECT build_query_with_joins('purchase_order');
-- Result: SELECT t."po_id", t."po_number", t."supplier_id", ..., lkp1."supplier_name" AS "supplier_id_display", lkp2."full_name" AS "approved_by_display"
--         FROM "purchase_orders" t
--         LEFT JOIN "suppliers" lkp1 ON t."supplier_id" = lkp1."supplier_id"
--         LEFT JOIN "users" lkp2 ON t."approved_by" = lkp2."user_id"

-- Build query without lookups
SELECT build_query_with_joins('purchase_order', NULL, FALSE);
-- Result: SELECT t."po_id", t."po_number", t."supplier_id", ...
--         FROM "purchase_orders" t

-- Build query with specific columns
SELECT build_query_with_joins('purchase_order', ARRAY['po_number', 'status', 'total_amount']);
-- Result: SELECT t."po_id", t."po_number", t."status", t."total_amount"
--         FROM "purchase_orders" t

-- Build order by clause
SELECT build_order_by_clause('purchase_order', 'po_date', 'DESC');
-- Result: ORDER BY t."po_date" DESC

-- Build pagination clause
SELECT build_pagination_clause(25, 2);
-- Result: LIMIT 25 OFFSET 25
*/
