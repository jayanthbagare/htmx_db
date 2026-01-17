-- UI Generation Functions
-- Function: generate_htmx_form
-- Description: Generates complete HTMX form HTML for create/edit/view
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- HELPER FUNCTION: Build Form Field HTML
-- =============================================================================
-- Generates HTML for a form field based on type and permissions

CREATE OR REPLACE FUNCTION build_form_field_html(
    p_field_name VARCHAR,
    p_field_value TEXT,
    p_data_type VARCHAR,
    p_is_editable BOOLEAN,
    p_is_required BOOLEAN DEFAULT FALSE,
    p_lookup_options JSONB DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE
    v_html TEXT;
    v_disabled TEXT := CASE WHEN NOT p_is_editable THEN ' disabled readonly' ELSE '' END;
    v_required TEXT := CASE WHEN p_is_required THEN ' required' ELSE '' END;
    v_option JSONB;
    v_selected TEXT;
BEGIN
    CASE p_data_type
        WHEN 'text', 'varchar' THEN
            v_html := format(
                '<input type="text" name="%s" value="%s"%s%s class="form-control">',
                escape_html(p_field_name),
                escape_html(COALESCE(p_field_value, '')),
                v_disabled,
                v_required
            );

        WHEN 'textarea' THEN
            v_html := format(
                '<textarea name="%s"%s%s class="form-control" rows="3">%s</textarea>',
                escape_html(p_field_name),
                v_disabled,
                v_required,
                escape_html(COALESCE(p_field_value, ''))
            );

        WHEN 'number', 'integer', 'decimal' THEN
            v_html := format(
                '<input type="number" name="%s" value="%s"%s%s class="form-control" step="%s">',
                escape_html(p_field_name),
                escape_html(COALESCE(p_field_value, '')),
                v_disabled,
                v_required,
                CASE WHEN p_data_type = 'decimal' THEN '0.01' ELSE '1' END
            );

        WHEN 'date' THEN
            v_html := format(
                '<input type="date" name="%s" value="%s"%s%s class="form-control">',
                escape_html(p_field_name),
                escape_html(COALESCE(p_field_value, '')),
                v_disabled,
                v_required
            );

        WHEN 'datetime' THEN
            v_html := format(
                '<input type="datetime-local" name="%s" value="%s"%s%s class="form-control">',
                escape_html(p_field_name),
                escape_html(COALESCE(p_field_value, '')),
                v_disabled,
                v_required
            );

        WHEN 'checkbox', 'boolean' THEN
            v_html := format(
                '<input type="checkbox" name="%s" value="true"%s%s class="form-check-input"%s>',
                escape_html(p_field_name),
                CASE WHEN p_field_value = 'true' THEN ' checked' ELSE '' END,
                v_disabled,
                v_required
            );

        WHEN 'select', 'lookup' THEN
            v_html := format('<select name="%s"%s%s class="form-select">',
                            escape_html(p_field_name), v_disabled, v_required);
            v_html := v_html || '<option value="">Select...</option>';

            IF p_lookup_options IS NOT NULL THEN
                FOR v_option IN SELECT * FROM jsonb_array_elements(p_lookup_options)
                LOOP
                    v_selected := CASE
                        WHEN (v_option->>'id')::TEXT = p_field_value THEN ' selected'
                        ELSE '' END;
                    v_html := v_html || format(
                        '<option value="%s"%s>%s</option>',
                        escape_html(v_option->>'id'),
                        v_selected,
                        escape_html(v_option->>'label')
                    );
                END LOOP;
            END IF;

            v_html := v_html || '</select>';

        ELSE
            -- Default to text input
            v_html := format(
                '<input type="text" name="%s" value="%s"%s%s class="form-control">',
                escape_html(p_field_name),
                escape_html(COALESCE(p_field_value, '')),
                v_disabled,
                v_required
            );
    END CASE;

    RETURN v_html;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION build_form_field_html(VARCHAR, TEXT, VARCHAR, BOOLEAN, BOOLEAN, JSONB) IS 'Generates HTML for form field';

-- =============================================================================
-- HELPER FUNCTION: Get Field Definitions for Entity
-- =============================================================================
-- Returns field definitions with display info

CREATE OR REPLACE FUNCTION get_entity_field_definitions(
    p_entity_type VARCHAR
)
RETURNS TABLE (
    field_name VARCHAR,
    display_name VARCHAR,
    data_type VARCHAR,
    is_required BOOLEAN,
    field_order INTEGER,
    lookup_entity VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.field_name::VARCHAR,
        f.display_name::VARCHAR,
        f.data_type::VARCHAR,
        f.is_required,
        f.field_order,
        f.lookup_entity::VARCHAR
    FROM ui_field_definitions f
    JOIN ui_entity_types e ON f.entity_type_id = e.entity_type_id
    WHERE e.entity_name = p_entity_type
    ORDER BY f.field_order;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_entity_field_definitions(VARCHAR) IS 'Returns field definitions for entity';

-- =============================================================================
-- MAIN FUNCTION: Generate HTMX Form View
-- =============================================================================
-- Generates complete form HTML for create/edit/view modes

CREATE OR REPLACE FUNCTION generate_htmx_form(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_view_type VARCHAR,  -- 'form_create', 'form_edit', 'form_view'
    p_record_id UUID DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE
    v_start_time TIMESTAMPTZ := clock_timestamp();
    v_template TEXT;
    v_action_name VARCHAR;
    v_form_data JSONB;
    v_template_data JSONB;
    v_permission_data JSONB;
    v_field_permissions JSONB := '{}'::JSONB;
    v_lookup_data JSONB := '{}'::JSONB;
    v_related_data JSONB := '{}'::JSONB;
    v_entity_display_name TEXT;
    v_rendered_html TEXT;
    v_field RECORD;
    v_perm RECORD;
    v_lookup_options JSONB;
BEGIN
    -- Determine action based on view type
    v_action_name := CASE p_view_type
        WHEN 'form_create' THEN 'create'
        WHEN 'form_edit' THEN 'edit'
        ELSE 'read'
    END;

    -- 1. Check permission
    IF NOT can_user_perform_action(p_user_id, p_entity_type, v_action_name) THEN
        PERFORM log_ui_generation(
            p_user_id, p_entity_type, p_view_type, v_start_time, 0, FALSE,
            'Permission denied: cannot ' || v_action_name || ' ' || p_entity_type
        );
        RETURN '<div class="error-message">You do not have permission to ' ||
               escape_html(v_action_name) || ' this record.</div>';
    END IF;

    -- 2. Get template
    v_template := get_entity_template(p_entity_type, p_view_type);

    IF v_template IS NULL THEN
        PERFORM log_ui_generation(
            p_user_id, p_entity_type, p_view_type, v_start_time, 0, FALSE,
            'No template found for ' || p_entity_type || ' ' || p_view_type
        );
        RETURN '<div class="error-message">No template configured for this view.</div>';
    END IF;

    -- 3. Get entity display name
    SELECT display_name INTO v_entity_display_name
    FROM ui_entity_types WHERE entity_name = p_entity_type;

    -- 4. Get form data based on view type
    IF p_view_type = 'form_create' THEN
        -- Get defaults for new record
        v_form_data := fetch_new_form_defaults(p_user_id, p_entity_type);
    ELSE
        -- Fetch existing record data
        IF p_record_id IS NULL THEN
            PERFORM log_ui_generation(
                p_user_id, p_entity_type, p_view_type, v_start_time, 0, FALSE,
                'Record ID required for ' || p_view_type
            );
            RETURN '<div class="error-message">Record ID is required.</div>';
        END IF;

        v_form_data := fetch_form_data(p_user_id, p_entity_type, p_record_id, p_view_type);

        -- Fetch related records (e.g., PO lines)
        BEGIN
            -- Try to get related line items
            IF p_entity_type = 'purchase_order' THEN
                v_related_data := jsonb_build_object(
                    'lines', fetch_related_records(
                        p_user_id, 'purchase_order', p_record_id, 'purchase_order_line'
                    )
                );
            ELSIF p_entity_type = 'goods_receipt' THEN
                v_related_data := jsonb_build_object(
                    'lines', fetch_related_records(
                        p_user_id, 'goods_receipt', p_record_id, 'goods_receipt_line'
                    )
                );
            ELSIF p_entity_type = 'invoice_receipt' THEN
                v_related_data := jsonb_build_object(
                    'lines', fetch_related_records(
                        p_user_id, 'invoice_receipt', p_record_id, 'invoice_line'
                    )
                );
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Ignore errors fetching related records
            NULL;
        END;
    END IF;

    -- 5. Build field permissions for template
    FOR v_perm IN
        SELECT field_name, is_visible, is_editable
        FROM get_user_field_permissions(p_user_id, p_entity_type, p_view_type)
    LOOP
        v_field_permissions := v_field_permissions || jsonb_build_object(
            v_perm.field_name || '_visible', v_perm.is_visible,
            v_perm.field_name || '_editable', v_perm.is_editable
        );
    END LOOP;

    -- 6. Get lookup options for dropdown fields
    FOR v_field IN
        SELECT field_name, lookup_entity
        FROM get_entity_field_definitions(p_entity_type)
        WHERE lookup_entity IS NOT NULL
    LOOP
        BEGIN
            v_lookup_options := fetch_lookup_options(
                p_user_id, p_entity_type, v_field.field_name, NULL, 100
            );
            v_lookup_data := v_lookup_data || jsonb_build_object(
                v_field.field_name || '_options', v_lookup_options
            );
        EXCEPTION WHEN OTHERS THEN
            -- Skip this lookup if it fails
            NULL;
        END;
    END LOOP;

    -- 7. Build user action permissions
    v_permission_data := build_user_permission_data(p_user_id, p_entity_type);

    -- Add workflow-specific permissions for view mode
    IF p_view_type = 'form_view' AND v_form_data IS NOT NULL THEN
        -- Check submit permission (for draft POs)
        IF (v_form_data->>'status') = 'draft' THEN
            v_permission_data := v_permission_data || jsonb_build_object(
                'user_can_submit', can_user_perform_action(p_user_id, p_entity_type, 'submit')
            );
        END IF;

        -- Check approve permission (for submitted POs)
        IF (v_form_data->>'status') = 'submitted' THEN
            v_permission_data := v_permission_data || jsonb_build_object(
                'user_can_approve', can_user_perform_action(p_user_id, p_entity_type, 'approve')
            );
        END IF;
    END IF;

    -- 8. Combine all template data
    v_template_data := COALESCE(v_form_data, '{}'::JSONB)
        || v_related_data
        || v_field_permissions
        || v_lookup_data
        || v_permission_data
        || jsonb_build_object(
            'entity_type', p_entity_type,
            'entity_display_name', COALESCE(v_entity_display_name, p_entity_type),
            'view_type', p_view_type,
            'is_create', p_view_type = 'form_create',
            'is_edit', p_view_type = 'form_edit',
            'is_view', p_view_type = 'form_view'
        );

    -- 9. Render template with data
    v_rendered_html := render_template_complete(v_template, v_template_data);

    -- 10. Log performance
    PERFORM log_ui_generation(
        p_user_id, p_entity_type, p_view_type, v_start_time, 1, FALSE, NULL
    );

    RETURN v_rendered_html;

EXCEPTION WHEN OTHERS THEN
    -- Log error and return error message
    PERFORM log_ui_generation(
        p_user_id, p_entity_type, p_view_type, v_start_time, 0, FALSE, SQLERRM
    );
    RETURN '<div class="error-message">An error occurred: ' ||
           escape_html(SQLERRM) || '</div>';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_htmx_form(UUID, VARCHAR, VARCHAR, UUID) IS 'Generates complete HTMX form HTML for create/edit/view';

-- =============================================================================
-- CONVENIENCE FUNCTIONS: Specific Form Types
-- =============================================================================

-- Generate Create Form
CREATE OR REPLACE FUNCTION generate_htmx_form_create(
    p_user_id UUID,
    p_entity_type VARCHAR
)
RETURNS TEXT AS $$
BEGIN
    RETURN generate_htmx_form(p_user_id, p_entity_type, 'form_create', NULL);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_htmx_form_create(UUID, VARCHAR) IS 'Generates create form HTML';

-- Generate Edit Form
CREATE OR REPLACE FUNCTION generate_htmx_form_edit(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_id UUID
)
RETURNS TEXT AS $$
BEGIN
    RETURN generate_htmx_form(p_user_id, p_entity_type, 'form_edit', p_record_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_htmx_form_edit(UUID, VARCHAR, UUID) IS 'Generates edit form HTML';

-- Generate View Form
CREATE OR REPLACE FUNCTION generate_htmx_form_view(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_record_id UUID
)
RETURNS TEXT AS $$
BEGIN
    RETURN generate_htmx_form(p_user_id, p_entity_type, 'form_view', p_record_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_htmx_form_view(UUID, VARCHAR, UUID) IS 'Generates view-only form HTML';

-- =============================================================================
-- FUNCTION: Generate Dynamic Form Fields
-- =============================================================================
-- Generates form fields dynamically based on field definitions

CREATE OR REPLACE FUNCTION generate_dynamic_form_fields(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_view_type VARCHAR,
    p_form_data JSONB DEFAULT '{}'::JSONB
)
RETURNS TEXT AS $$
DECLARE
    v_html TEXT := '';
    v_field RECORD;
    v_field_html TEXT;
    v_lookup_options JSONB;
    v_perm RECORD;
    v_is_editable BOOLEAN;
    v_is_visible BOOLEAN;
BEGIN
    -- Get field permissions
    FOR v_field IN
        SELECT
            fd.field_name,
            fd.display_name,
            fd.data_type,
            fd.is_required,
            fd.lookup_entity,
            COALESCE(perm.is_visible, TRUE) AS is_visible,
            COALESCE(perm.is_editable, TRUE) AS is_editable
        FROM get_entity_field_definitions(p_entity_type) fd
        LEFT JOIN get_user_field_permissions(p_user_id, p_entity_type, p_view_type) perm
            ON perm.field_name = fd.field_name
        ORDER BY fd.field_order
    LOOP
        -- Skip hidden fields
        IF NOT v_field.is_visible THEN
            CONTINUE;
        END IF;

        -- View mode is never editable
        v_is_editable := v_field.is_editable AND p_view_type != 'form_view';

        -- Get lookup options if needed
        IF v_field.lookup_entity IS NOT NULL THEN
            BEGIN
                v_lookup_options := fetch_lookup_options(
                    p_user_id, p_entity_type, v_field.field_name, NULL, 100
                );
            EXCEPTION WHEN OTHERS THEN
                v_lookup_options := '[]'::JSONB;
            END;
        ELSE
            v_lookup_options := NULL;
        END IF;

        -- Build field HTML
        v_field_html := format(
            '<div class="form-group%s">
                <label for="%s">%s%s</label>
                %s
            </div>',
            CASE WHEN v_field.is_required THEN ' required' ELSE '' END,
            escape_html(v_field.field_name),
            escape_html(v_field.display_name),
            CASE WHEN v_field.is_required THEN ' *' ELSE '' END,
            build_form_field_html(
                v_field.field_name,
                p_form_data->>v_field.field_name,
                CASE WHEN v_field.lookup_entity IS NOT NULL THEN 'lookup' ELSE v_field.data_type END,
                v_is_editable,
                v_field.is_required,
                v_lookup_options
            )
        );

        v_html := v_html || v_field_html;
    END LOOP;

    RETURN v_html;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_dynamic_form_fields(UUID, VARCHAR, VARCHAR, JSONB) IS 'Generates dynamic form fields HTML';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Generate create form
SELECT generate_htmx_form_create(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order'
);

-- Generate edit form
SELECT generate_htmx_form_edit(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'some-po-uuid'::UUID
);

-- Generate view form
SELECT generate_htmx_form_view(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'some-po-uuid'::UUID
);

-- Generate dynamic fields
SELECT generate_dynamic_form_fields(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    'form_edit',
    '{"po_number": "PO-001", "status": "draft"}'::JSONB
);
*/
