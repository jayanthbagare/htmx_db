-- UI Generation Functions
-- Function: generate_htmx_list
-- Description: Generates complete HTMX list view HTML for an entity
-- Author: happyveggie & Claude Opus 4.5

-- =============================================================================
-- HELPER FUNCTION: Log UI Generation Performance
-- =============================================================================
-- Logs performance metrics for UI generation

CREATE OR REPLACE FUNCTION log_ui_generation(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_view_type VARCHAR,
    p_start_time TIMESTAMPTZ,
    p_record_count INTEGER DEFAULT 0,
    p_template_cached BOOLEAN DEFAULT FALSE,
    p_error_message TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_duration_ms INTEGER;
BEGIN
    v_duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - p_start_time)) * 1000;

    INSERT INTO ui_generation_logs (
        user_id,
        entity_type,
        view_type,
        generation_time_ms,
        record_count,
        template_cached,
        error_message,
        created_at
    ) VALUES (
        p_user_id,
        p_entity_type,
        p_view_type,
        v_duration_ms,
        p_record_count,
        p_template_cached,
        p_error_message,
        NOW()
    );
EXCEPTION WHEN OTHERS THEN
    -- Don't fail the main operation if logging fails
    RAISE WARNING 'Failed to log UI generation: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION log_ui_generation(UUID, VARCHAR, VARCHAR, TIMESTAMPTZ, INTEGER, BOOLEAN, TEXT) IS 'Logs UI generation performance metrics';

-- =============================================================================
-- HELPER FUNCTION: Get Template for Entity/View
-- =============================================================================
-- Fetches the active template for an entity and view type

CREATE OR REPLACE FUNCTION get_entity_template(
    p_entity_type VARCHAR,
    p_view_type VARCHAR
)
RETURNS TEXT AS $$
DECLARE
    v_template TEXT;
BEGIN
    SELECT t.base_template INTO v_template
    FROM htmx_templates t
    JOIN ui_entity_types e ON t.entity_type_id = e.entity_type_id
    WHERE e.entity_name = p_entity_type
      AND t.view_type = p_view_type
      AND t.is_active = TRUE
    ORDER BY t.version DESC
    LIMIT 1;

    RETURN v_template;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_entity_template(VARCHAR, VARCHAR) IS 'Gets active template for entity/view type';

-- =============================================================================
-- HELPER FUNCTION: Build Pagination Data
-- =============================================================================
-- Calculates pagination metadata for templates

CREATE OR REPLACE FUNCTION build_pagination_data(
    p_total_count BIGINT,
    p_page_size INTEGER,
    p_current_page INTEGER
)
RETURNS JSONB AS $$
DECLARE
    v_total_pages INTEGER;
    v_page_start INTEGER;
    v_page_end INTEGER;
BEGIN
    v_total_pages := CEIL(p_total_count::NUMERIC / p_page_size)::INTEGER;
    v_page_start := ((p_current_page - 1) * p_page_size) + 1;
    v_page_end := LEAST(p_current_page * p_page_size, p_total_count);

    RETURN jsonb_build_object(
        'total_count', p_total_count,
        'total_pages', v_total_pages,
        'current_page', p_current_page,
        'page_size', p_page_size,
        'page_start', v_page_start,
        'page_end', v_page_end,
        'has_prev', p_current_page > 1,
        'has_next', p_current_page < v_total_pages,
        'prev_page', GREATEST(1, p_current_page - 1),
        'next_page', LEAST(v_total_pages, p_current_page + 1)
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION build_pagination_data(BIGINT, INTEGER, INTEGER) IS 'Builds pagination metadata for templates';

-- =============================================================================
-- HELPER FUNCTION: Build User Permissions for Template
-- =============================================================================
-- Returns user action permissions as template data

CREATE OR REPLACE FUNCTION build_user_permission_data(
    p_user_id UUID,
    p_entity_type VARCHAR
)
RETURNS JSONB AS $$
DECLARE
    v_permissions JSONB := '{}'::JSONB;
    v_action RECORD;
BEGIN
    FOR v_action IN
        SELECT action_name, is_allowed
        FROM get_user_actions(p_user_id, p_entity_type)
    LOOP
        v_permissions := v_permissions || jsonb_build_object(
            'user_can_' || v_action.action_name,
            v_action.is_allowed
        );
    END LOOP;

    RETURN v_permissions;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION build_user_permission_data(UUID, VARCHAR) IS 'Builds user permission data for templates';

-- =============================================================================
-- MAIN FUNCTION: Generate HTMX List View
-- =============================================================================
-- Orchestrates complete list view generation with all features

CREATE OR REPLACE FUNCTION generate_htmx_list(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_filters JSONB DEFAULT '{}'::JSONB,
    p_sort_field VARCHAR DEFAULT NULL,
    p_sort_direction VARCHAR DEFAULT 'ASC',
    p_page_size INTEGER DEFAULT 25,
    p_page_number INTEGER DEFAULT 1
)
RETURNS TEXT AS $$
DECLARE
    v_start_time TIMESTAMPTZ := clock_timestamp();
    v_template TEXT;
    v_list_result RECORD;
    v_template_data JSONB;
    v_pagination_data JSONB;
    v_permission_data JSONB;
    v_entity_display_name TEXT;
    v_rendered_html TEXT;
    v_record_count INTEGER;
BEGIN
    -- 1. Check read permission
    IF NOT can_user_perform_action(p_user_id, p_entity_type, 'read') THEN
        PERFORM log_ui_generation(
            p_user_id, p_entity_type, 'list', v_start_time, 0, FALSE,
            'Permission denied: cannot read ' || p_entity_type
        );
        RETURN '<div class="error-message">You do not have permission to view this data.</div>';
    END IF;

    -- 2. Get template
    v_template := get_entity_template(p_entity_type, 'list');

    IF v_template IS NULL THEN
        PERFORM log_ui_generation(
            p_user_id, p_entity_type, 'list', v_start_time, 0, FALSE,
            'No template found for ' || p_entity_type || ' list view'
        );
        RETURN '<div class="error-message">No template configured for this view.</div>';
    END IF;

    -- 3. Get entity display name
    SELECT display_name INTO v_entity_display_name
    FROM ui_entity_types WHERE entity_name = p_entity_type;

    -- 4. Fetch list data with permissions applied
    SELECT * INTO v_list_result
    FROM fetch_list_data(
        p_user_id,
        p_entity_type,
        p_filters,
        p_sort_field,
        p_sort_direction,
        p_page_size,
        p_page_number
    );

    v_record_count := jsonb_array_length(v_list_result.data);

    -- 5. Build pagination data
    v_pagination_data := build_pagination_data(
        v_list_result.total_count,
        p_page_size,
        v_list_result.current_page
    );

    -- 6. Build permission data for template
    v_permission_data := build_user_permission_data(p_user_id, p_entity_type);

    -- 7. Combine all template data
    v_template_data := jsonb_build_object(
        'entity_type', p_entity_type,
        'entity_display_name', COALESCE(v_entity_display_name, p_entity_type),
        'records', v_list_result.data
    ) || v_pagination_data || v_permission_data;

    -- 8. Render template with data
    v_rendered_html := render_template_complete(v_template, v_template_data);

    -- 9. Log performance
    PERFORM log_ui_generation(
        p_user_id, p_entity_type, 'list', v_start_time, v_record_count, FALSE, NULL
    );

    RETURN v_rendered_html;

EXCEPTION WHEN OTHERS THEN
    -- Log error and return error message
    PERFORM log_ui_generation(
        p_user_id, p_entity_type, 'list', v_start_time, 0, FALSE, SQLERRM
    );
    RETURN '<div class="error-message">An error occurred while generating the view: ' ||
           escape_html(SQLERRM) || '</div>';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_htmx_list(UUID, VARCHAR, JSONB, VARCHAR, VARCHAR, INTEGER, INTEGER) IS 'Generates complete HTMX list view HTML';

-- =============================================================================
-- SIMPLIFIED FUNCTION: Generate List Table Only
-- =============================================================================
-- Generates just the table portion (for HTMX partial updates)

CREATE OR REPLACE FUNCTION generate_htmx_list_table(
    p_user_id UUID,
    p_entity_type VARCHAR,
    p_filters JSONB DEFAULT '{}'::JSONB,
    p_sort_field VARCHAR DEFAULT NULL,
    p_sort_direction VARCHAR DEFAULT 'ASC',
    p_page_size INTEGER DEFAULT 25,
    p_page_number INTEGER DEFAULT 1
)
RETURNS TEXT AS $$
DECLARE
    v_start_time TIMESTAMPTZ := clock_timestamp();
    v_list_result RECORD;
    v_template_data JSONB;
    v_pagination_data JSONB;
    v_permission_data JSONB;
    v_row_template TEXT;
    v_rendered_rows TEXT := '';
    v_record JSONB;
    v_rendered_html TEXT;
BEGIN
    -- Check permission
    IF NOT can_user_perform_action(p_user_id, p_entity_type, 'read') THEN
        RETURN '<tr><td colspan="100" class="error">Permission denied</td></tr>';
    END IF;

    -- Fetch data
    SELECT * INTO v_list_result
    FROM fetch_list_data(
        p_user_id, p_entity_type, p_filters, p_sort_field,
        p_sort_direction, p_page_size, p_page_number
    );

    -- Build pagination data
    v_pagination_data := build_pagination_data(
        v_list_result.total_count, p_page_size, v_list_result.current_page
    );

    -- Build permission data
    v_permission_data := build_user_permission_data(p_user_id, p_entity_type);

    -- Get row template (simplified for table-only updates)
    -- This could be fetched from a separate template, but for now we use inline
    v_row_template := (
        SELECT t.base_template
        FROM htmx_templates t
        JOIN ui_entity_types e ON t.entity_type_id = e.entity_type_id
        WHERE e.entity_name = p_entity_type
          AND t.view_type = 'list_row'
          AND t.is_active = TRUE
        ORDER BY t.version DESC
        LIMIT 1
    );

    -- If no row template, generate a basic table structure
    IF v_row_template IS NULL THEN
        -- Build basic template from visible fields
        v_row_template := '<tr>';
        FOR v_record IN
            SELECT jsonb_build_object('field_name', field_name) AS field
            FROM get_user_field_permissions(p_user_id, p_entity_type, 'list')
            WHERE is_visible = TRUE
            LIMIT 10
        LOOP
            v_row_template := v_row_template || '<td>{{' || (v_record->>'field_name') || '}}</td>';
        END LOOP;
        v_row_template := v_row_template || '</tr>';
    END IF;

    -- Render each row
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_list_result.data)
    LOOP
        v_rendered_rows := v_rendered_rows ||
            render_template_complete(v_row_template, v_record || v_permission_data);
    END LOOP;

    -- Build pagination controls
    v_rendered_html := v_rendered_rows || format(
        '<tr class="pagination-row"><td colspan="100">
            <div class="pagination">
                Showing %s to %s of %s
                %s %s
            </div>
        </td></tr>',
        v_pagination_data->>'page_start',
        v_pagination_data->>'page_end',
        v_pagination_data->>'total_count',
        CASE WHEN (v_pagination_data->>'has_prev')::BOOLEAN
             THEN format('<button hx-get="/ui/%s/list?page=%s" hx-target="tbody">Prev</button>',
                         p_entity_type, v_pagination_data->>'prev_page')
             ELSE '' END,
        CASE WHEN (v_pagination_data->>'has_next')::BOOLEAN
             THEN format('<button hx-get="/ui/%s/list?page=%s" hx-target="tbody">Next</button>',
                         p_entity_type, v_pagination_data->>'next_page')
             ELSE '' END
    );

    -- Log performance
    PERFORM log_ui_generation(
        p_user_id, p_entity_type, 'list_table', v_start_time,
        jsonb_array_length(v_list_result.data), FALSE, NULL
    );

    RETURN v_rendered_html;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_htmx_list_table(UUID, VARCHAR, JSONB, VARCHAR, VARCHAR, INTEGER, INTEGER) IS 'Generates just the list table for partial updates';

-- =============================================================================
-- EXAMPLES AND TESTS
-- =============================================================================

/*
-- Generate complete list view
SELECT generate_htmx_list(
    '00000000-0000-0000-0000-000000000100'::UUID,  -- admin user
    'purchase_order',
    '{}'::JSONB,
    'po_date',
    'DESC',
    25,
    1
);

-- Generate with filters
SELECT generate_htmx_list(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    '{"status": ["draft", "submitted"]}'::JSONB,
    'po_date',
    'DESC',
    25,
    1
);

-- Generate just table (for HTMX updates)
SELECT generate_htmx_list_table(
    '00000000-0000-0000-0000-000000000100'::UUID,
    'purchase_order',
    '{}'::JSONB,
    'po_date',
    'DESC',
    25,
    1
);
*/
