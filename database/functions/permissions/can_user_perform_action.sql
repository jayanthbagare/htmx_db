-- Action Permission Functions
-- Function: can_user_perform_action
-- Description: Checks if user can perform an action on an entity
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- FUNCTION: Evaluate Condition Rule
-- =============================================================================
-- Evaluates JSON condition rules for dynamic permissions

CREATE OR REPLACE FUNCTION evaluate_permission_condition(
    p_condition_rule TEXT,
    p_record_data JSONB,
    p_user_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_condition JSONB;
    v_field TEXT;
    v_operator TEXT;
    v_expected_value TEXT;
    v_actual_value TEXT;
BEGIN
    -- Handle NULL or empty condition (always allow)
    IF p_condition_rule IS NULL OR p_condition_rule = '' THEN
        RETURN TRUE;
    END IF;

    -- Parse JSON condition
    BEGIN
        v_condition := p_condition_rule::JSONB;
    EXCEPTION WHEN OTHERS THEN
        -- Invalid JSON, deny by default
        RAISE WARNING 'Invalid condition rule JSON: %', p_condition_rule;
        RETURN FALSE;
    END;

    -- Extract condition components
    v_field := v_condition->>'field';
    v_operator := v_condition->>'operator';
    v_expected_value := v_condition->>'value';

    -- If no record data provided, can't evaluate record-level conditions
    IF p_record_data IS NULL OR p_record_data = '{}'::JSONB THEN
        -- If condition requires record data, deny
        IF v_field IS NOT NULL THEN
            RETURN FALSE;
        END IF;
        RETURN TRUE;
    END IF;

    -- Get actual value from record
    v_actual_value := p_record_data->>v_field;

    -- Replace special values
    IF v_expected_value = 'current_user' THEN
        v_expected_value := p_user_id::TEXT;
    END IF;

    -- Evaluate based on operator
    CASE v_operator
        WHEN 'equals', '=', '==' THEN
            RETURN v_actual_value = v_expected_value;

        WHEN 'not_equals', '!=', '<>' THEN
            RETURN v_actual_value != v_expected_value OR v_actual_value IS NULL;

        WHEN 'in' THEN
            -- v_expected_value should be comma-separated or JSON array
            IF v_expected_value LIKE '[%]' THEN
                -- JSON array
                RETURN v_actual_value = ANY(
                    SELECT jsonb_array_elements_text(v_expected_value::JSONB)
                );
            ELSE
                -- Comma-separated
                RETURN v_actual_value = ANY(string_to_array(v_expected_value, ','));
            END IF;

        WHEN 'not_in' THEN
            IF v_expected_value LIKE '[%]' THEN
                RETURN v_actual_value != ALL(
                    SELECT jsonb_array_elements_text(v_expected_value::JSONB)
                );
            ELSE
                RETURN v_actual_value != ALL(string_to_array(v_expected_value, ','));
            END IF;

        WHEN 'greater_than', '>' THEN
            RETURN v_actual_value::NUMERIC > v_expected_value::NUMERIC;

        WHEN 'less_than', '<' THEN
            RETURN v_actual_value::NUMERIC < v_expected_value::NUMERIC;

        WHEN 'is_null' THEN
            RETURN v_actual_value IS NULL;

        WHEN 'is_not_null' THEN
            RETURN v_actual_value IS NOT NULL;

        ELSE
            -- Unknown operator, deny by default
            RAISE WARNING 'Unknown operator in condition: %', v_operator;
            RETURN FALSE;
    END CASE;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION evaluate_permission_condition(TEXT, JSONB, UUID) IS 'Evaluates JSON condition rules for dynamic permissions';

-- =============================================================================
-- MAIN FUNCTION: Can User Perform Action
-- =============================================================================
-- Checks if user has permission to perform an action on an entity

CREATE OR REPLACE FUNCTION can_user_perform_action(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_action_name VARCHAR,
    p_record_data JSONB DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_permission RECORD;
    v_user_role_id UUID;
    v_is_allowed BOOLEAN;
BEGIN
    -- Get user's role
    SELECT role_id INTO v_user_role_id
    FROM users
    WHERE user_id = p_user_id
      AND is_active = TRUE;

    -- If user not found or inactive, deny
    IF v_user_role_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check if admin (admins can do everything)
    IF EXISTS (
        SELECT 1 FROM roles r
        JOIN users u ON u.role_id = r.role_id
        WHERE u.user_id = p_user_id
          AND r.role_name = 'admin'
          AND r.is_active = TRUE
    ) THEN
        RETURN TRUE;
    END IF;

    -- Look up permission
    SELECT
        ap.is_allowed,
        ap.condition_rule
    INTO v_permission
    FROM ui_action_permissions ap
    JOIN ui_entity_types e ON ap.entity_type_id = e.entity_type_id
    WHERE ap.role_id = v_user_role_id
      AND e.entity_name = p_entity_type
      AND ap.action_name = p_action_name;

    -- If no permission record found, deny by default
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- If not allowed at all, deny
    IF NOT v_permission.is_allowed THEN
        RETURN FALSE;
    END IF;

    -- If no condition rule, allow
    IF v_permission.condition_rule IS NULL OR v_permission.condition_rule = '' THEN
        RETURN TRUE;
    END IF;

    -- Evaluate condition rule
    v_is_allowed := evaluate_permission_condition(
        v_permission.condition_rule,
        p_record_data,
        p_user_id
    );

    RETURN v_is_allowed;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION can_user_perform_action(UUID, VARCHAR, VARCHAR, JSONB) IS 'Checks if user can perform action on entity with optional record-level conditions';

-- =============================================================================
-- HELPER FUNCTION: Get User Actions
-- =============================================================================
-- Returns list of actions user can perform on an entity

CREATE OR REPLACE FUNCTION get_user_actions(
    p_user_id UUID,
    p_entity_type VARCHAR
)
RETURNS TABLE (
    action_name VARCHAR,
    is_allowed BOOLEAN,
    has_conditions BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ap.action_name::VARCHAR,
        ap.is_allowed,
        (ap.condition_rule IS NOT NULL AND ap.condition_rule != '') AS has_conditions
    FROM users u
    JOIN ui_action_permissions ap ON ap.role_id = u.role_id
    JOIN ui_entity_types e ON ap.entity_type_id = e.entity_type_id
    WHERE u.user_id = p_user_id
      AND e.entity_name = p_entity_type
      AND u.is_active = TRUE
    ORDER BY ap.action_name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_user_actions(UUID, VARCHAR) IS 'Returns list of actions user can perform on entity';

-- =============================================================================
-- HELPER FUNCTION: Get Allowed Actions as Array
-- =============================================================================
-- Returns just array of allowed action names

CREATE OR REPLACE FUNCTION get_allowed_actions(
    p_user_id UUID,
    p_entity_type VARCHAR
)
RETURNS TEXT[] AS $$
DECLARE
    v_actions TEXT[];
BEGIN
    SELECT ARRAY(
        SELECT action_name
        FROM get_user_actions(p_user_id, p_entity_type)
        WHERE is_allowed = TRUE
    ) INTO v_actions;

    RETURN v_actions;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_allowed_actions(UUID, VARCHAR) IS 'Returns array of allowed action names';

-- =============================================================================
-- BATCH CHECK FUNCTION: Check Multiple Actions
-- =============================================================================
-- Efficiently checks multiple actions at once

CREATE OR REPLACE FUNCTION check_user_actions(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_actions VARCHAR[]
)
RETURNS TABLE (
    action_name VARCHAR,
    is_allowed BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        a::VARCHAR AS action_name,
        can_user_perform_action(p_user_id, p_entity_type, a) AS is_allowed
    FROM unnest(p_actions) AS a;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION check_user_actions(UUID, VARCHAR, VARCHAR[]) IS 'Checks multiple actions at once';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Check if user can create purchase orders
SELECT can_user_perform_action(
    '00000000-0000-0000-0000-000000000100'::UUID,  -- admin user
    'purchase_order',
    'create'
);
-- Result: TRUE (admin can do everything)

-- Check if user can approve purchase orders
SELECT can_user_perform_action(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'approve'
);

-- Check with record-level condition (can only edit own records)
SELECT can_user_perform_action(
    'some-user-uuid'::UUID,
    'purchase_order',
    'edit',
    '{"created_by": "some-user-uuid", "status": "draft"}'::JSONB
);

-- Get all actions user can perform
SELECT * FROM get_user_actions(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order'
);

-- Get just allowed action names
SELECT get_allowed_actions(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order'
);

-- Check multiple actions at once
SELECT * FROM check_user_actions(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    ARRAY['create', 'read', 'edit', 'delete', 'approve']
);

-- Example condition rules:
-- Can only edit own records:
-- {"field": "created_by", "operator": "equals", "value": "current_user"}

-- Can only edit drafts:
-- {"field": "status", "operator": "in", "value": "draft,submitted"}

-- Can approve if amount <= 10000:
-- {"field": "total_amount", "operator": "<=", "value": "10000"}
*/
