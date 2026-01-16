-- Permission Resolution Functions
-- Function: get_user_field_permissions
-- Description: Gets field-level permissions for a user
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- FUNCTION: Get User Field Permissions
-- =============================================================================
-- Returns which fields are visible and editable for a user in a specific view

CREATE OR REPLACE FUNCTION get_user_field_permissions(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_view_type VARCHAR -- 'list', 'form_create', 'form_edit', 'form_view'
)
RETURNS TABLE (
    field_name VARCHAR,
    is_visible BOOLEAN,
    is_editable BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.field_name::VARCHAR,
        CASE
            WHEN p_view_type = 'list' THEN COALESCE(fp.list_visible, TRUE)
            WHEN p_view_type = 'form_create' THEN COALESCE(fp.form_create_visible, TRUE)
            WHEN p_view_type = 'form_edit' THEN COALESCE(fp.form_edit_visible, TRUE)
            WHEN p_view_type = 'form_view' THEN COALESCE(fp.form_view_visible, TRUE)
            ELSE TRUE
        END AS is_visible,
        CASE
            WHEN p_view_type = 'list' THEN COALESCE(fp.list_editable, FALSE)
            WHEN p_view_type = 'form_create' THEN COALESCE(fp.form_create_editable, TRUE)
            WHEN p_view_type = 'form_edit' THEN COALESCE(fp.form_edit_editable, TRUE)
            WHEN p_view_type = 'form_view' THEN FALSE  -- View mode is never editable
            ELSE FALSE
        END AS is_editable
    FROM ui_field_definitions f
    JOIN ui_entity_types e ON f.entity_type_id = e.entity_type_id
    LEFT JOIN users u ON u.user_id = p_user_id
    LEFT JOIN field_permissions fp ON (
        fp.field_id = f.field_id
        AND fp.role_id = u.role_id
    )
    WHERE e.entity_name = p_entity_type
      AND (u.is_active = TRUE OR u.user_id IS NULL)
    ORDER BY f.field_order;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_user_field_permissions(UUID, VARCHAR, VARCHAR) IS 'Returns field visibility and editability for user in specific view';

-- =============================================================================
-- HELPER FUNCTION: Get Visible Fields as Array
-- =============================================================================
-- Returns just the list of visible field names

CREATE OR REPLACE FUNCTION get_visible_fields(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_view_type VARCHAR
)
RETURNS TEXT[] AS $$
DECLARE
    v_visible_fields TEXT[];
BEGIN
    SELECT ARRAY(
        SELECT field_name
        FROM get_user_field_permissions(p_user_id, p_entity_type, p_view_type)
        WHERE is_visible = TRUE
    ) INTO v_visible_fields;

    RETURN v_visible_fields;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_visible_fields(UUID, VARCHAR, VARCHAR) IS 'Returns array of visible field names for user';

-- =============================================================================
-- HELPER FUNCTION: Get Editable Fields as Array
-- =============================================================================
-- Returns just the list of editable field names

CREATE OR REPLACE FUNCTION get_editable_fields(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_view_type VARCHAR
)
RETURNS TEXT[] AS $$
DECLARE
    v_editable_fields TEXT[];
BEGIN
    SELECT ARRAY(
        SELECT field_name
        FROM get_user_field_permissions(p_user_id, p_entity_type, p_view_type)
        WHERE is_editable = TRUE
    ) INTO v_editable_fields;

    RETURN v_editable_fields;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_editable_fields(UUID, VARCHAR, VARCHAR) IS 'Returns array of editable field names for user';

-- =============================================================================
-- FUNCTION: Check if User Can See Field
-- =============================================================================
-- Quick check if user has permission to see a specific field

CREATE OR REPLACE FUNCTION can_user_see_field(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_field_name VARCHAR,
    p_view_type VARCHAR
)
RETURNS BOOLEAN AS $$
DECLARE
    v_can_see BOOLEAN;
BEGIN
    SELECT is_visible INTO v_can_see
    FROM get_user_field_permissions(p_user_id, p_entity_type, p_view_type)
    WHERE field_name = p_field_name;

    RETURN COALESCE(v_can_see, FALSE);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION can_user_see_field(UUID, VARCHAR, VARCHAR, VARCHAR) IS 'Checks if user can see a specific field';

-- =============================================================================
-- FUNCTION: Check if User Can Edit Field
-- =============================================================================
-- Quick check if user has permission to edit a specific field

CREATE OR REPLACE FUNCTION can_user_edit_field(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_field_name VARCHAR,
    p_view_type VARCHAR
)
RETURNS BOOLEAN AS $$
DECLARE
    v_can_edit BOOLEAN;
BEGIN
    SELECT is_editable INTO v_can_edit
    FROM get_user_field_permissions(p_user_id, p_entity_type, p_view_type)
    WHERE field_name = p_field_name;

    RETURN COALESCE(v_can_edit, FALSE);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION can_user_edit_field(UUID, VARCHAR, VARCHAR, VARCHAR) IS 'Checks if user can edit a specific field';

-- =============================================================================
-- FUNCTION: Get Field Permissions Summary
-- =============================================================================
-- Returns summary of permissions for debugging/admin purposes

CREATE OR REPLACE FUNCTION get_field_permissions_summary(
    p_user_id UUID,
    p_entity_type VARCHAR
)
RETURNS TABLE (
    field_name VARCHAR,
    list_visible BOOLEAN,
    list_editable BOOLEAN,
    form_create_visible BOOLEAN,
    form_create_editable BOOLEAN,
    form_edit_visible BOOLEAN,
    form_edit_editable BOOLEAN,
    form_view_visible BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.field_name::VARCHAR,
        COALESCE(fp.list_visible, TRUE) AS list_visible,
        COALESCE(fp.list_editable, FALSE) AS list_editable,
        COALESCE(fp.form_create_visible, TRUE) AS form_create_visible,
        COALESCE(fp.form_create_editable, TRUE) AS form_create_editable,
        COALESCE(fp.form_edit_visible, TRUE) AS form_edit_visible,
        COALESCE(fp.form_edit_editable, TRUE) AS form_edit_editable,
        COALESCE(fp.form_view_visible, TRUE) AS form_view_visible
    FROM ui_field_definitions f
    JOIN ui_entity_types e ON f.entity_type_id = e.entity_type_id
    LEFT JOIN users u ON u.user_id = p_user_id
    LEFT JOIN field_permissions fp ON (
        fp.field_id = f.field_id
        AND fp.role_id = u.role_id
    )
    WHERE e.entity_name = p_entity_type
    ORDER BY f.field_order;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_field_permissions_summary(UUID, VARCHAR) IS 'Returns complete permission summary for all views (debugging)';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Get field permissions for purchase_manager viewing purchase_order list
SELECT *
FROM get_user_field_permissions(
    '00000000-0000-0000-0000-000000000100'::UUID,  -- user_id
    'purchase_order',
    'list'
);

-- Get just visible field names
SELECT get_visible_fields(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'list'
);

-- Get just editable field names
SELECT get_editable_fields(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'form_create'
);

-- Check specific field permission
SELECT can_user_see_field(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'total_amount',
    'list'
);

-- Get complete permission summary
SELECT *
FROM get_field_permissions_summary(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order'
);
*/
