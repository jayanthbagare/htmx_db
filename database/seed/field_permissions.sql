-- Field Permissions Seed
-- Description: Complete field permission matrix for all roles
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- FIELD PERMISSIONS FOR PURCHASE ORDERS
-- =============================================================================

-- Get field IDs for purchase_order entity
DO $$
DECLARE
    v_admin_role_id UUID := '00000000-0000-0000-0000-000000000001';
    v_purchase_manager_id UUID := '00000000-0000-0000-0000-000000000002';
    v_warehouse_staff_id UUID := '00000000-0000-0000-0000-000000000003';
    v_accountant_id UUID := '00000000-0000-0000-0000-000000000004';
    v_viewer_id UUID := '00000000-0000-0000-0000-000000000005';
    v_entity_id UUID := '10000000-0000-0000-0000-000000000001';
    v_field RECORD;
BEGIN
    -- ADMIN: Full access to all fields
    FOR v_field IN
        SELECT field_id FROM ui_field_definitions WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, entity_type_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_admin_role_id, v_entity_id, v_field.field_id,
            TRUE, TRUE,  -- list
            TRUE, TRUE,  -- create
            TRUE, TRUE,  -- edit
            TRUE         -- view
        );
    END LOOP;

    -- PURCHASE MANAGER: Can create/edit most fields, cannot approve
    FOR v_field IN
        SELECT field_id, field_name
        FROM ui_field_definitions
        WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, entity_type_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_purchase_manager_id, v_entity_id, v_field.field_id,
            TRUE, FALSE,  -- list (visible, not inline editable)
            -- Create form: all editable except auto-generated fields
            TRUE,
            CASE v_field.field_name
                WHEN 'po_number' THEN FALSE  -- auto-generated
                WHEN 'approved_by' THEN FALSE
                WHEN 'approved_at' THEN FALSE
                WHEN 'created_at' THEN FALSE
                ELSE TRUE
            END,
            -- Edit form: can edit draft/submitted
            TRUE,
            CASE v_field.field_name
                WHEN 'po_number' THEN FALSE
                WHEN 'approved_by' THEN FALSE
                WHEN 'approved_at' THEN FALSE
                WHEN 'created_at' THEN FALSE
                WHEN 'status' THEN FALSE  -- status changes via actions only
                ELSE TRUE
            END,
            TRUE  -- view
        );
    END LOOP;

    -- WAREHOUSE STAFF: Read-only for POs (they handle GRs)
    FOR v_field IN
        SELECT field_id FROM ui_field_definitions WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, entity_type_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_warehouse_staff_id, v_entity_id, v_field.field_id,
            TRUE, FALSE,   -- list
            FALSE, FALSE,  -- create
            FALSE, FALSE,  -- edit
            TRUE           -- view
        );
    END LOOP;

    -- ACCOUNTANT: Read-only for POs (they handle invoices)
    FOR v_field IN
        SELECT field_id, field_name
        FROM ui_field_definitions
        WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, entity_type_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_accountant_id, v_entity_id, v_field.field_id,
            TRUE, FALSE,   -- list
            FALSE, FALSE,  -- create
            FALSE, FALSE,  -- edit
            TRUE           -- view
        );
    END LOOP;

    -- VIEWER: Read-only, but hide sensitive fields
    FOR v_field IN
        SELECT field_id, field_name
        FROM ui_field_definitions
        WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, entity_type_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_viewer_id, v_entity_id, v_field.field_id,
            -- Hide notes field in list
            CASE v_field.field_name WHEN 'notes' THEN FALSE ELSE TRUE END,
            FALSE,  -- never editable
            FALSE, FALSE,  -- no create
            FALSE, FALSE,  -- no edit
            -- Hide notes in view too
            CASE v_field.field_name WHEN 'notes' THEN FALSE ELSE TRUE END
        );
    END LOOP;

    RAISE NOTICE 'Field permissions seeded for purchase_order entity (5 roles)';
END $$;

-- =============================================================================
-- FIELD PERMISSIONS FOR SUPPLIERS
-- =============================================================================

DO $$
DECLARE
    v_admin_role_id UUID := '00000000-0000-0000-0000-000000000001';
    v_purchase_manager_id UUID := '00000000-0000-0000-0000-000000000002';
    v_warehouse_staff_id UUID := '00000000-0000-0000-0000-000000000003';
    v_accountant_id UUID := '00000000-0000-0000-0000-000000000004';
    v_viewer_id UUID := '00000000-0000-0000-0000-000000000005';
    v_entity_id UUID := '10000000-0000-0000-0000-000000000005';
    v_field RECORD;
BEGIN
    -- ADMIN: Full access
    FOR v_field IN
        SELECT field_id FROM ui_field_definitions WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, entity_type_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_admin_role_id, v_entity_id, v_field.field_id,
            TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE
        );
    END LOOP;

    -- PURCHASE MANAGER: Can create and edit suppliers
    FOR v_field IN
        SELECT field_id FROM ui_field_definitions WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, entity_type_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_purchase_manager_id, v_entity_id, v_field.field_id,
            TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE
        );
    END LOOP;

    -- WAREHOUSE STAFF: Read-only
    FOR v_field IN
        SELECT field_id FROM ui_field_definitions WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, entity_type_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_warehouse_staff_id, v_entity_id, v_field.field_id,
            TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE
        );
    END LOOP;

    -- ACCOUNTANT: Read-only
    FOR v_field IN
        SELECT field_id FROM ui_field_definitions WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, entity_type_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_accountant_id, v_entity_id, v_field.field_id,
            TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE
        );
    END LOOP;

    -- VIEWER: Read-only, hide contact details
    FOR v_field IN
        SELECT field_id, field_name
        FROM ui_field_definitions
        WHERE entity_type_id = v_entity_id
    LOOP
        INSERT INTO field_permissions (
            role_id, entity_type_id, field_id,
            list_visible, list_editable,
            form_create_visible, form_create_editable,
            form_edit_visible, form_edit_editable,
            form_view_visible
        ) VALUES (
            v_viewer_id, v_entity_id, v_field.field_id,
            -- Hide contact info
            CASE v_field.field_name
                WHEN 'contact_email' THEN FALSE
                WHEN 'contact_phone' THEN FALSE
                ELSE TRUE
            END,
            FALSE, FALSE, FALSE, FALSE, FALSE,
            CASE v_field.field_name
                WHEN 'contact_email' THEN FALSE
                WHEN 'contact_phone' THEN FALSE
                ELSE TRUE
            END
        );
    END LOOP;

    RAISE NOTICE 'Field permissions seeded for supplier entity (5 roles)';
END $$;

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================

DO $$
DECLARE
    v_total_perms INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_total_perms FROM field_permissions;

    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE 'Field Permissions Seeding Complete';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE 'Total field permissions created: %', v_total_perms;
    RAISE NOTICE '';
    RAISE NOTICE 'Permission Matrix:';
    RAISE NOTICE '  - Admin: Full access to all fields';
    RAISE NOTICE '  - Purchase Manager: Create/edit POs and suppliers';
    RAISE NOTICE '  - Warehouse Staff: View only for POs';
    RAISE NOTICE '  - Accountant: View only for POs';
    RAISE NOTICE '  - Viewer: View only with hidden sensitive fields';
    RAISE NOTICE '';
    RAISE NOTICE 'Test permissions with:';
    RAISE NOTICE '  SELECT * FROM get_user_field_permissions(';
    RAISE NOTICE '    ''00000000-0000-0000-0000-000000000100''::UUID,';
    RAISE NOTICE '    ''purchase_order'',';
    RAISE NOTICE '    ''list''';
    RAISE NOTICE '  );';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
END $$;
