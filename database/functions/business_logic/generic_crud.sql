-- Business Logic Functions
-- Module: Generic CRUD Operations
-- Description: Generic update, soft delete, and restore functions
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- FUNCTION: Update Record
-- =============================================================================
-- Generic function to update any entity record with permission checks

CREATE OR REPLACE FUNCTION update_record(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_id UUID,
    p_updates JSONB
)
RETURNS JSONB AS $$
DECLARE
    v_table_name TEXT;
    v_pk_column TEXT;
    v_update_cols TEXT := '';
    v_editable_fields TEXT[];
    v_field TEXT;
    v_value TEXT;
    v_field_type TEXT;
    v_sql TEXT;
    v_old_values JSONB;
    v_new_values JSONB;
    v_updates_applied INTEGER := 0;
BEGIN
    -- Validate user has edit permission
    IF NOT can_user_perform_action(p_user_id, p_entity_type, 'edit') THEN
        RAISE EXCEPTION 'User does not have permission to edit %', p_entity_type;
    END IF;

    -- Get table metadata
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types WHERE entity_name = p_entity_type;

    IF v_table_name IS NULL THEN
        RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
    END IF;

    v_pk_column := get_entity_pk(p_entity_type);

    -- Get editable fields for user
    v_editable_fields := get_editable_fields(p_user_id, p_entity_type, 'form_edit');

    -- Validate record exists and is not deleted
    EXECUTE format(
        'SELECT row_to_json(t) FROM %I t WHERE %I = $1 AND is_deleted = FALSE',
        v_table_name, v_pk_column
    ) INTO v_old_values USING p_record_id;

    IF v_old_values IS NULL THEN
        RAISE EXCEPTION 'Record not found: % with id %', p_entity_type, p_record_id;
    END IF;

    -- Build dynamic UPDATE statement
    FOR v_field, v_value IN SELECT * FROM jsonb_each_text(p_updates)
    LOOP
        -- Skip if field is not editable
        IF NOT (v_field = ANY(v_editable_fields)) THEN
            RAISE NOTICE 'Skipping non-editable field: %', v_field;
            CONTINUE;
        END IF;

        -- Skip system fields
        IF v_field IN ('created_at', 'created_by', 'updated_at', 'updated_by',
                       'is_deleted', 'deleted_at', 'deleted_by') THEN
            CONTINUE;
        END IF;

        -- Skip if field doesn't exist in table
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = v_table_name AND column_name = v_field
        ) THEN
            RAISE NOTICE 'Skipping unknown field: %', v_field;
            CONTINUE;
        END IF;

        -- Get field type for proper casting
        SELECT data_type INTO v_field_type
        FROM information_schema.columns
        WHERE table_name = v_table_name AND column_name = v_field;

        -- Add to update list
        IF v_update_cols != '' THEN
            v_update_cols := v_update_cols || ', ';
        END IF;

        -- Handle NULL values
        IF v_value IS NULL THEN
            v_update_cols := v_update_cols || format('%I = NULL', v_field);
        ELSE
            -- Cast based on type
            CASE v_field_type
                WHEN 'uuid' THEN
                    v_update_cols := v_update_cols || format('%I = %L::UUID', v_field, v_value);
                WHEN 'integer', 'bigint', 'smallint' THEN
                    v_update_cols := v_update_cols || format('%I = %L::INTEGER', v_field, v_value);
                WHEN 'numeric', 'decimal' THEN
                    v_update_cols := v_update_cols || format('%I = %L::DECIMAL', v_field, v_value);
                WHEN 'boolean' THEN
                    v_update_cols := v_update_cols || format('%I = %L::BOOLEAN', v_field, v_value);
                WHEN 'date' THEN
                    v_update_cols := v_update_cols || format('%I = %L::DATE', v_field, v_value);
                WHEN 'timestamp with time zone', 'timestamp without time zone' THEN
                    v_update_cols := v_update_cols || format('%I = %L::TIMESTAMP', v_field, v_value);
                WHEN 'jsonb' THEN
                    v_update_cols := v_update_cols || format('%I = %L::JSONB', v_field, v_value);
                ELSE
                    v_update_cols := v_update_cols || format('%I = %L', v_field, v_value);
            END CASE;
        END IF;

        v_updates_applied := v_updates_applied + 1;
    END LOOP;

    IF v_updates_applied = 0 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'No valid fields to update'
        );
    END IF;

    -- Add audit fields
    v_update_cols := v_update_cols || ', updated_at = NOW(), updated_by = ' || quote_literal(p_user_id) || '::UUID';

    -- Execute update
    v_sql := format(
        'UPDATE %I SET %s WHERE %I = $1 AND is_deleted = FALSE RETURNING row_to_json(%I)',
        v_table_name, v_update_cols, v_pk_column, v_table_name
    );

    EXECUTE v_sql INTO v_new_values USING p_record_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'entity_type', p_entity_type,
        'record_id', p_record_id,
        'fields_updated', v_updates_applied,
        'old_values', v_old_values,
        'new_values', v_new_values,
        'message', 'Record updated successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION update_record(UUID, VARCHAR, UUID, JSONB) IS 'Generic function to update entity records';

-- =============================================================================
-- FUNCTION: Soft Delete Record
-- =============================================================================
-- Marks a record as deleted (soft delete)

CREATE OR REPLACE FUNCTION soft_delete_record(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_table_name TEXT;
    v_pk_column TEXT;
    v_record_exists BOOLEAN;
    v_already_deleted BOOLEAN;
BEGIN
    -- Validate user has delete permission
    IF NOT can_user_perform_action(p_user_id, p_entity_type, 'delete') THEN
        RAISE EXCEPTION 'User does not have permission to delete %', p_entity_type;
    END IF;

    -- Get table metadata
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types WHERE entity_name = p_entity_type;

    IF v_table_name IS NULL THEN
        RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
    END IF;

    v_pk_column := get_entity_pk(p_entity_type);

    -- Check if record exists
    EXECUTE format(
        'SELECT EXISTS(SELECT 1 FROM %I WHERE %I = $1)',
        v_table_name, v_pk_column
    ) INTO v_record_exists USING p_record_id;

    IF NOT v_record_exists THEN
        RAISE EXCEPTION 'Record not found: % with id %', p_entity_type, p_record_id;
    END IF;

    -- Check if already deleted
    EXECUTE format(
        'SELECT is_deleted FROM %I WHERE %I = $1',
        v_table_name, v_pk_column
    ) INTO v_already_deleted USING p_record_id;

    IF v_already_deleted THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Record is already deleted'
        );
    END IF;

    -- Perform soft delete
    EXECUTE format(
        'UPDATE %I SET
            is_deleted = TRUE,
            deleted_at = NOW(),
            deleted_by = $2,
            deletion_reason = $3,
            updated_at = NOW(),
            updated_by = $2
         WHERE %I = $1',
        v_table_name, v_pk_column
    ) USING p_record_id, p_user_id, p_reason;

    RETURN jsonb_build_object(
        'success', TRUE,
        'entity_type', p_entity_type,
        'record_id', p_record_id,
        'action', 'soft_delete',
        'message', 'Record deleted successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION soft_delete_record(UUID, VARCHAR, UUID, TEXT) IS 'Soft deletes an entity record';

-- =============================================================================
-- FUNCTION: Restore Record
-- =============================================================================
-- Restores a soft-deleted record

CREATE OR REPLACE FUNCTION restore_record(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_table_name TEXT;
    v_pk_column TEXT;
    v_record_exists BOOLEAN;
    v_is_deleted BOOLEAN;
BEGIN
    -- Validate user has restore/edit permission
    IF NOT can_user_perform_action(p_user_id, p_entity_type, 'edit') THEN
        RAISE EXCEPTION 'User does not have permission to restore %', p_entity_type;
    END IF;

    -- Get table metadata
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types WHERE entity_name = p_entity_type;

    IF v_table_name IS NULL THEN
        RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
    END IF;

    v_pk_column := get_entity_pk(p_entity_type);

    -- Check if record exists
    EXECUTE format(
        'SELECT EXISTS(SELECT 1 FROM %I WHERE %I = $1)',
        v_table_name, v_pk_column
    ) INTO v_record_exists USING p_record_id;

    IF NOT v_record_exists THEN
        RAISE EXCEPTION 'Record not found: % with id %', p_entity_type, p_record_id;
    END IF;

    -- Check if deleted
    EXECUTE format(
        'SELECT is_deleted FROM %I WHERE %I = $1',
        v_table_name, v_pk_column
    ) INTO v_is_deleted USING p_record_id;

    IF NOT v_is_deleted THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Record is not deleted'
        );
    END IF;

    -- Restore record
    EXECUTE format(
        'UPDATE %I SET
            is_deleted = FALSE,
            deleted_at = NULL,
            deleted_by = NULL,
            deletion_reason = NULL,
            restored_at = NOW(),
            restored_by = $2,
            updated_at = NOW(),
            updated_by = $2
         WHERE %I = $1',
        v_table_name, v_pk_column
    ) USING p_record_id, p_user_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'entity_type', p_entity_type,
        'record_id', p_record_id,
        'action', 'restore',
        'message', 'Record restored successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION restore_record(UUID, VARCHAR, UUID) IS 'Restores a soft-deleted record';

-- =============================================================================
-- FUNCTION: Hard Delete Record (Admin Only)
-- =============================================================================
-- Permanently deletes a record (use with caution)

CREATE OR REPLACE FUNCTION hard_delete_record(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_table_name TEXT;
    v_pk_column TEXT;
    v_record_exists BOOLEAN;
    v_user_role VARCHAR;
BEGIN
    -- Only admins can hard delete
    SELECT r.role_name INTO v_user_role
    FROM users u
    JOIN roles r ON u.role_id = r.role_id
    WHERE u.user_id = p_user_id AND u.is_active = TRUE;

    IF v_user_role != 'admin' THEN
        RAISE EXCEPTION 'Only administrators can permanently delete records';
    END IF;

    -- Get table metadata
    SELECT primary_table INTO v_table_name
    FROM ui_entity_types WHERE entity_name = p_entity_type;

    IF v_table_name IS NULL THEN
        RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
    END IF;

    v_pk_column := get_entity_pk(p_entity_type);

    -- Check if record exists
    EXECUTE format(
        'SELECT EXISTS(SELECT 1 FROM %I WHERE %I = $1)',
        v_table_name, v_pk_column
    ) INTO v_record_exists USING p_record_id;

    IF NOT v_record_exists THEN
        RAISE EXCEPTION 'Record not found: % with id %', p_entity_type, p_record_id;
    END IF;

    -- Hard delete
    EXECUTE format(
        'DELETE FROM %I WHERE %I = $1',
        v_table_name, v_pk_column
    ) USING p_record_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'entity_type', p_entity_type,
        'record_id', p_record_id,
        'action', 'hard_delete',
        'message', 'Record permanently deleted'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', FALSE,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION hard_delete_record(UUID, VARCHAR, UUID) IS 'Permanently deletes a record (admin only)';

-- =============================================================================
-- FUNCTION: Bulk Update Records
-- =============================================================================
-- Updates multiple records with the same changes

CREATE OR REPLACE FUNCTION bulk_update_records(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_ids UUID[],
    p_updates JSONB
)
RETURNS JSONB AS $$
DECLARE
    v_record_id UUID;
    v_result JSONB;
    v_success_count INTEGER := 0;
    v_failure_count INTEGER := 0;
    v_results JSONB := '[]'::JSONB;
BEGIN
    FOREACH v_record_id IN ARRAY p_record_ids
    LOOP
        v_result := update_record(p_user_id, p_entity_type, v_record_id, p_updates);

        IF (v_result->>'success')::BOOLEAN THEN
            v_success_count := v_success_count + 1;
        ELSE
            v_failure_count := v_failure_count + 1;
        END IF;

        v_results := v_results || jsonb_build_object(
            'record_id', v_record_id,
            'success', (v_result->>'success')::BOOLEAN,
            'error', v_result->>'error'
        );
    END LOOP;

    RETURN jsonb_build_object(
        'success', v_failure_count = 0,
        'total', array_length(p_record_ids, 1),
        'success_count', v_success_count,
        'failure_count', v_failure_count,
        'results', v_results
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION bulk_update_records(UUID, VARCHAR, UUID[], JSONB) IS 'Updates multiple records at once';

-- =============================================================================
-- FUNCTION: Bulk Soft Delete Records
-- =============================================================================
-- Soft deletes multiple records

CREATE OR REPLACE FUNCTION bulk_soft_delete_records(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_ids UUID[],
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_record_id UUID;
    v_result JSONB;
    v_success_count INTEGER := 0;
    v_failure_count INTEGER := 0;
BEGIN
    FOREACH v_record_id IN ARRAY p_record_ids
    LOOP
        v_result := soft_delete_record(p_user_id, p_entity_type, v_record_id, p_reason);

        IF (v_result->>'success')::BOOLEAN THEN
            v_success_count := v_success_count + 1;
        ELSE
            v_failure_count := v_failure_count + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', v_failure_count = 0,
        'total', array_length(p_record_ids, 1),
        'success_count', v_success_count,
        'failure_count', v_failure_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION bulk_soft_delete_records(UUID, VARCHAR, UUID[], TEXT) IS 'Soft deletes multiple records';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Update a record
SELECT update_record(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    (SELECT po_id FROM purchase_orders LIMIT 1),
    '{"notes": "Updated notes", "expected_delivery_date": "2024-02-15"}'::JSONB
);

-- Soft delete a record
SELECT soft_delete_record(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    (SELECT po_id FROM purchase_orders WHERE status = 'draft' LIMIT 1),
    'No longer needed'
);

-- Restore a record
SELECT restore_record(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    (SELECT po_id FROM purchase_orders WHERE is_deleted = TRUE LIMIT 1)
);

-- Bulk update
SELECT bulk_update_records(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'supplier',
    ARRAY(SELECT supplier_id FROM suppliers LIMIT 5),
    '{"notes": "Bulk updated"}'::JSONB
);
*/
