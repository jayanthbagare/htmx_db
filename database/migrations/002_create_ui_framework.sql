-- Migration 002: Create UI Framework Tables
-- Description: Creates all 7 UI framework tables for dynamic HTMX generation
-- Dependencies: 001_create_business_domain.sql
-- Author: happyveggie & Claude Sonnet 4.5

-- =============================================================================
-- ROLES TABLE
-- =============================================================================
-- Stores user roles for permission management

CREATE TABLE roles (
    role_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role_name       VARCHAR(100) NOT NULL UNIQUE,
    description     TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_role_name_format CHECK (role_name ~ '^[a-z_]+$')
);

COMMENT ON TABLE roles IS 'User roles for permission management';
COMMENT ON COLUMN roles.role_name IS 'Role identifier (lowercase with underscores): admin, purchase_manager, etc.';

-- =============================================================================
-- USERS TABLE
-- =============================================================================
-- Stores user accounts

CREATE TABLE users (
    user_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username        VARCHAR(100) NOT NULL UNIQUE,
    email           VARCHAR(200) NOT NULL UNIQUE,
    full_name       VARCHAR(200) NOT NULL,
    role_id         UUID NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_user_role FOREIGN KEY (role_id)
        REFERENCES roles(role_id),
    CONSTRAINT chk_username_format CHECK (username ~ '^[a-z0-9_.-]+$'),
    CONSTRAINT chk_email_format CHECK (email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$')
);

COMMENT ON TABLE users IS 'User accounts for authentication and authorization';
COMMENT ON COLUMN users.username IS 'Unique username (lowercase alphanumeric with ._-)';

-- Add foreign key constraints to business tables now that users table exists
ALTER TABLE suppliers
    ADD CONSTRAINT fk_supplier_created_by FOREIGN KEY (created_by) REFERENCES users(user_id);

ALTER TABLE purchase_orders
    ADD CONSTRAINT fk_po_created_by FOREIGN KEY (created_by) REFERENCES users(user_id),
    ADD CONSTRAINT fk_po_approved_by FOREIGN KEY (approved_by) REFERENCES users(user_id);

ALTER TABLE goods_receipts
    ADD CONSTRAINT fk_gr_received_by FOREIGN KEY (received_by) REFERENCES users(user_id);

ALTER TABLE invoice_receipts
    ADD CONSTRAINT fk_invoice_verified_by FOREIGN KEY (verified_by) REFERENCES users(user_id),
    ADD CONSTRAINT fk_invoice_approved_by FOREIGN KEY (approved_by) REFERENCES users(user_id);

ALTER TABLE payments
    ADD CONSTRAINT fk_payment_processed_by FOREIGN KEY (processed_by) REFERENCES users(user_id);

-- =============================================================================
-- UI ENTITY TYPES TABLE
-- =============================================================================
-- Defines each business entity for UI generation

CREATE TABLE ui_entity_types (
    entity_type_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_name         VARCHAR(100) NOT NULL UNIQUE,
    display_name        VARCHAR(200) NOT NULL,
    primary_table       VARCHAR(100) NOT NULL,
    icon_class          VARCHAR(100),
    description         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_entity_name_format CHECK (entity_name ~ '^[a-z_]+$'),
    CONSTRAINT chk_primary_table_format CHECK (primary_table ~ '^[a-z_]+$')
);

COMMENT ON TABLE ui_entity_types IS 'Business entity definitions for UI generation';
COMMENT ON COLUMN ui_entity_types.entity_name IS 'Entity identifier (e.g., purchase_order, goods_receipt)';
COMMENT ON COLUMN ui_entity_types.primary_table IS 'Main database table name for this entity';
COMMENT ON COLUMN ui_entity_types.icon_class IS 'CSS class for entity icon (e.g., fa-shopping-cart)';

-- =============================================================================
-- UI FIELD DEFINITIONS TABLE
-- =============================================================================
-- Defines all fields for each entity with metadata

CREATE TABLE ui_field_definitions (
    field_id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type_id          UUID NOT NULL,
    field_name              VARCHAR(100) NOT NULL,
    display_label           VARCHAR(200) NOT NULL,
    data_type               VARCHAR(50) NOT NULL,
    field_order             INTEGER NOT NULL DEFAULT 0,
    is_required             BOOLEAN NOT NULL DEFAULT FALSE,
    validation_rule         TEXT,
    lookup_entity           VARCHAR(100),
    lookup_display_field    VARCHAR(100),
    default_value           TEXT,
    help_text               TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_field_entity_type FOREIGN KEY (entity_type_id)
        REFERENCES ui_entity_types(entity_type_id),
    CONSTRAINT uq_field_entity_name UNIQUE (entity_type_id, field_name),
    CONSTRAINT chk_field_data_type CHECK (data_type IN (
        'text', 'number', 'decimal', 'date', 'datetime', 'time',
        'select', 'multiselect', 'textarea', 'checkbox', 'radio',
        'lookup', 'email', 'phone', 'url', 'password', 'hidden'
    )),
    CONSTRAINT chk_field_lookup_complete CHECK (
        (lookup_entity IS NULL AND lookup_display_field IS NULL) OR
        (lookup_entity IS NOT NULL AND lookup_display_field IS NOT NULL)
    )
);

COMMENT ON TABLE ui_field_definitions IS 'Field metadata for each entity';
COMMENT ON COLUMN ui_field_definitions.data_type IS 'Field type: text, number, date, select, textarea, lookup, etc.';
COMMENT ON COLUMN ui_field_definitions.validation_rule IS 'JSON string with validation rules (e.g., {"min": 0, "max": 100})';
COMMENT ON COLUMN ui_field_definitions.lookup_entity IS 'Entity to lookup (for foreign keys)';
COMMENT ON COLUMN ui_field_definitions.lookup_display_field IS 'Field to display from lookup entity';

-- =============================================================================
-- HTMX TEMPLATES TABLE
-- =============================================================================
-- Stores HTML templates with placeholders for UI generation

CREATE TABLE htmx_templates (
    template_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type_id      UUID NOT NULL,
    view_type           VARCHAR(50) NOT NULL,
    template_name       VARCHAR(200) NOT NULL,
    base_template       TEXT NOT NULL,
    version             INTEGER NOT NULL DEFAULT 1,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_template_entity_type FOREIGN KEY (entity_type_id)
        REFERENCES ui_entity_types(entity_type_id),
    CONSTRAINT chk_template_view_type CHECK (view_type IN (
        'list', 'form_create', 'form_edit', 'form_view', 'filter_panel', 'detail'
    )),
    CONSTRAINT chk_template_version CHECK (version > 0)
);

COMMENT ON TABLE htmx_templates IS 'HTML templates with placeholders for dynamic UI generation';
COMMENT ON COLUMN htmx_templates.view_type IS 'Template type: list, form_create, form_edit, form_view, filter_panel';
COMMENT ON COLUMN htmx_templates.base_template IS 'HTML template with {{placeholder}} syntax';
COMMENT ON COLUMN htmx_templates.version IS 'Template version for A/B testing or rollback';
COMMENT ON COLUMN htmx_templates.is_active IS 'Only active templates are used for rendering';

-- Create unique index to ensure only one active template per entity/view combination
CREATE UNIQUE INDEX idx_template_active_unique
    ON htmx_templates(entity_type_id, view_type)
    WHERE is_active = TRUE;

-- =============================================================================
-- FIELD PERMISSIONS TABLE
-- =============================================================================
-- Defines field-level permissions per role

CREATE TABLE field_permissions (
    permission_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role_id                 UUID NOT NULL,
    entity_type_id          UUID NOT NULL,
    field_id                UUID NOT NULL,
    list_visible            BOOLEAN NOT NULL DEFAULT TRUE,
    list_editable           BOOLEAN NOT NULL DEFAULT FALSE,
    form_create_visible     BOOLEAN NOT NULL DEFAULT TRUE,
    form_create_editable    BOOLEAN NOT NULL DEFAULT TRUE,
    form_edit_visible       BOOLEAN NOT NULL DEFAULT TRUE,
    form_edit_editable      BOOLEAN NOT NULL DEFAULT TRUE,
    form_view_visible       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_field_perm_role FOREIGN KEY (role_id)
        REFERENCES roles(role_id),
    CONSTRAINT fk_field_perm_entity FOREIGN KEY (entity_type_id)
        REFERENCES ui_entity_types(entity_type_id),
    CONSTRAINT fk_field_perm_field FOREIGN KEY (field_id)
        REFERENCES ui_field_definitions(field_id),
    CONSTRAINT uq_field_perm_role_field UNIQUE (role_id, field_id),
    CONSTRAINT chk_list_editable_implies_visible CHECK (
        NOT list_editable OR list_visible
    ),
    CONSTRAINT chk_form_create_editable_implies_visible CHECK (
        NOT form_create_editable OR form_create_visible
    ),
    CONSTRAINT chk_form_edit_editable_implies_visible CHECK (
        NOT form_edit_editable OR form_edit_visible
    )
);

COMMENT ON TABLE field_permissions IS 'Field-level visibility and editability per role';
COMMENT ON COLUMN field_permissions.list_visible IS 'Can see field in list view';
COMMENT ON COLUMN field_permissions.list_editable IS 'Can edit field in list view (inline editing)';
COMMENT ON COLUMN field_permissions.form_create_visible IS 'Can see field in create form';
COMMENT ON COLUMN field_permissions.form_create_editable IS 'Can edit field in create form';

-- =============================================================================
-- UI ACTION PERMISSIONS TABLE
-- =============================================================================
-- Defines action-level permissions per role and entity

CREATE TABLE ui_action_permissions (
    action_permission_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role_id                 UUID NOT NULL,
    entity_type_id          UUID NOT NULL,
    action_name             VARCHAR(50) NOT NULL,
    is_allowed              BOOLEAN NOT NULL DEFAULT FALSE,
    condition_rule          TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_action_perm_role FOREIGN KEY (role_id)
        REFERENCES roles(role_id),
    CONSTRAINT fk_action_perm_entity FOREIGN KEY (entity_type_id)
        REFERENCES ui_entity_types(entity_type_id),
    CONSTRAINT uq_action_perm_role_entity_action UNIQUE (role_id, entity_type_id, action_name),
    CONSTRAINT chk_action_name CHECK (action_name IN (
        'create', 'read', 'edit', 'delete', 'approve', 'submit',
        'cancel', 'export', 'import', 'print'
    ))
);

COMMENT ON TABLE ui_action_permissions IS 'Action-level permissions per role and entity';
COMMENT ON COLUMN ui_action_permissions.action_name IS 'Action: create, read, edit, delete, approve, submit, cancel';
COMMENT ON COLUMN ui_action_permissions.condition_rule IS 'JSON with conditional logic (e.g., can only edit own records)';

-- =============================================================================
-- INDEXES FOR UI FRAMEWORK TABLES
-- =============================================================================

-- Roles
CREATE INDEX idx_roles_active ON roles(is_active) WHERE is_active = TRUE;

-- Users
CREATE INDEX idx_users_role ON users(role_id) WHERE is_active = TRUE;
CREATE INDEX idx_users_active ON users(is_active);
CREATE INDEX idx_users_email ON users(email) WHERE is_active = TRUE;

-- UI Entity Types
CREATE INDEX idx_entity_types_name ON ui_entity_types(entity_name);

-- UI Field Definitions
CREATE INDEX idx_field_defs_entity ON ui_field_definitions(entity_type_id);
CREATE INDEX idx_field_defs_order ON ui_field_definitions(entity_type_id, field_order);

-- HTMX Templates
CREATE INDEX idx_templates_entity_view ON htmx_templates(entity_type_id, view_type);
CREATE INDEX idx_templates_active ON htmx_templates(is_active) WHERE is_active = TRUE;

-- Field Permissions
CREATE INDEX idx_field_perm_role ON field_permissions(role_id);
CREATE INDEX idx_field_perm_entity ON field_permissions(entity_type_id);
CREATE INDEX idx_field_perm_field ON field_permissions(field_id);

-- UI Action Permissions
CREATE INDEX idx_action_perm_role ON ui_action_permissions(role_id);
CREATE INDEX idx_action_perm_entity ON ui_action_permissions(entity_type_id);
CREATE INDEX idx_action_perm_role_entity ON ui_action_permissions(role_id, entity_type_id);

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 002 completed successfully';
    RAISE NOTICE 'Created 7 UI framework tables with indexes';
    RAISE NOTICE 'Tables: roles, users, ui_entity_types, ui_field_definitions, htmx_templates, field_permissions, ui_action_permissions';
    RAISE NOTICE 'Added foreign key constraints to business tables for user references';
END $$;
