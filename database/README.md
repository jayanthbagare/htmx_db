# Database Setup Guide

This directory contains the complete database schema, migrations, and functions for the Database-Driven HTMX UI Generation System.

## Directory Structure

```
database/
├── migrations/           # Database schema migrations
│   ├── 001_create_business_domain.sql
│   ├── 002_create_ui_framework.sql
│   ├── 003_create_audit_tables.sql
│   ├── 004_create_triggers_sequences.sql
│   ├── 005_create_rls_policies.sql
│   └── 006_initial_seed_data.sql
├── functions/           # PostgreSQL functions (to be added in Phase 2+)
│   ├── template_engine/
│   ├── permissions/
│   ├── data_layer/
│   ├── ui_generation/
│   └── business_logic/
├── seed/               # Additional seed data scripts
└── README.md          # This file
```

## Quick Start

### Option 1: Using Supabase

1. **Create a Supabase Project**
   ```bash
   # Visit https://supabase.com and create a new project
   # Note your project URL and API keys
   ```

2. **Run Migrations**
   ```bash
   # Install Supabase CLI
   npm install -g supabase

   # Login to Supabase
   supabase login

   # Link to your project
   supabase link --project-ref <your-project-ref>

   # Run migrations
   supabase db push
   ```

### Option 2: Using Local PostgreSQL

1. **Create Database**
   ```bash
   createdb htmx_db
   ```

2. **Run Migrations Manually**
   ```bash
   psql -d htmx_db -f migrations/001_create_business_domain.sql
   psql -d htmx_db -f migrations/002_create_ui_framework.sql
   psql -d htmx_db -f migrations/003_create_audit_tables.sql
   psql -d htmx_db -f migrations/004_create_triggers_sequences.sql
   psql -d htmx_db -f migrations/005_create_rls_policies.sql
   psql -d htmx_db -f migrations/006_initial_seed_data.sql
   ```

3. **Or Use the Migration Runner Script**
   ```bash
   ./run_migrations.sh
   ```

## Migration Details

### 001: Business Domain Tables (9 tables)
Creates core business tables for procurement workflow:
- `suppliers` - Vendor master data
- `purchase_orders` + `purchase_order_lines` - Purchase orders
- `goods_receipts` + `goods_receipt_lines` - Receiving documents
- `invoice_receipts` + `invoice_lines` - Vendor invoices
- `payments` - Payment records
- `clearing_entries` - Payment reconciliation

**Total Tables**: 9
**Total Indexes**: 25+

### 002: UI Framework Tables (7 tables)
Creates framework for dynamic UI generation:
- `roles` - User roles
- `users` - User accounts
- `ui_entity_types` - Business entity definitions
- `ui_field_definitions` - Field metadata for each entity
- `htmx_templates` - HTML templates with placeholders
- `field_permissions` - Field-level permissions
- `ui_action_permissions` - Action-level permissions

**Total Tables**: 7
**Total Indexes**: 15+

### 003: Audit & Performance Tables (3 tables + 1 view)
Creates logging and monitoring infrastructure:
- `ui_generation_logs` - Logs every UI generation request
- `performance_metrics` - Aggregated performance data
- `audit_trail` - Generic change tracking
- `performance_dashboard` (materialized view) - Quick performance stats

**Includes Helper Functions**:
- `refresh_performance_dashboard()` - Refresh the dashboard view
- `cleanup_old_logs(days)` - Archive old log records
- `get_performance_summary(entity, hours)` - Get quick stats

### 004: Triggers & Sequences
Creates automation and numbering:
- **Sequences**: `po_number_seq`, `gr_number_seq`, `invoice_number_seq`, `payment_number_seq`
- **Auto-update triggers**: Automatically update `updated_at` columns
- **Calculation triggers**: Auto-calculate line totals
- **Template management**: Auto-deactivate old template versions
- **Audit logging**: Generic audit trail trigger

**Includes Number Generation Functions**:
- `generate_po_number()` - Format: PO-YYYYMM-00001
- `generate_gr_number()` - Format: GR-YYYYMM-00001
- `generate_invoice_number()` - Format: INV-YYYYMM-00001
- `generate_payment_number()` - Format: PAY-YYYYMM-00001

### 005: Row Level Security Policies
Implements data-level security:
- **Enabled RLS** on: purchase_orders, goods_receipts, invoices, payments, users
- **Policy Examples**:
  - Users see submitted/approved POs + their own drafts
  - Warehouse staff can create/edit goods receipts
  - Accountants process invoices and payments
  - Admins have full access to everything

**Includes Helper Functions**:
- `current_user_role()` - Get current user's role
- `is_admin()` - Check if current user is admin
- `set_current_user_id(uuid)` - Set user ID for session
- `get_current_user_id()` - Get user ID from session

**Database Roles Created**:
- `app_user` - Standard application access
- `app_admin` - Administrative access
- `app_readonly` - Read-only access

### 006: Initial Seed Data
Seeds initial configuration:
- **5 Roles**: admin, purchase_manager, warehouse_staff, accountant, viewer
- **1 Admin User**: username: `admin`, email: `admin@example.com`
- **5 Entity Types**: purchase_order, goods_receipt, invoice_receipt, payment, supplier
- **Field Definitions**: For purchase_order and supplier entities
- **Action Permissions**: Full permission matrix for all roles

## Database Schema

### Total Objects
- **Tables**: 18 (9 business + 7 framework + 2 audit)
- **Indexes**: 40+
- **Sequences**: 4
- **Triggers**: 8+
- **Functions**: 15+
- **Materialized Views**: 1
- **Constraints**: 50+ (FK, CHECK, UNIQUE)

### Key Design Decisions

1. **UUIDs for Primary Keys**: Better for distributed systems, harder to guess
2. **Soft Deletes**: `is_deleted` flags preserve referential integrity
3. **Audit Fields**: `created_at`, `updated_at`, `created_by` on all tables
4. **Status Enums**: VARCHAR with CHECK constraints (easier to modify than PostgreSQL ENUMs)
5. **Decimal for Money**: DECIMAL(15,2) not FLOAT (precision matters)
6. **Template Versioning**: Support A/B testing and rollback

## Important Security Notes

### Row Level Security (RLS)

⚠️ **CRITICAL**: The application MUST call `set_current_user_id(uuid)` at the start of each session for RLS to work correctly.

```sql
-- At session start (in your API layer)
SELECT set_current_user_id('user-uuid-here'::UUID);
```

### Default Admin Account

⚠️ **WARNING**: The seeded admin account (`admin@example.com`) should:
1. Have password changed immediately
2. NOT be used in production
3. Be replaced with proper Supabase Auth accounts

### Database Roles

The migration creates three database roles:
- `app_user` - Use this for normal application connections
- `app_admin` - Use for administrative tasks only
- `app_readonly` - Use for reporting/analytics connections

## Performance Considerations

### Indexes
All foreign keys have indexes for efficient joins.
Common filter fields (status, dates, is_deleted) are indexed.
Composite indexes created for common query patterns.

### Soft Deletes
All queries should filter `WHERE is_deleted = FALSE`.
Indexes include `WHERE is_deleted = FALSE` for efficiency.

### Materialized Views
`performance_dashboard` should be refreshed periodically:
```sql
SELECT refresh_performance_dashboard();
```

Consider scheduling with pg_cron or external scheduler.

## Monitoring

### Performance Logging

Every UI generation request is logged to `ui_generation_logs` with:
- Duration in milliseconds
- Cache hit rates
- Row counts
- Error messages

### Quick Performance Check

```sql
-- Get performance summary for purchase orders (last 24 hours)
SELECT * FROM get_performance_summary('purchase_order', 24);

-- View dashboard (last hour)
SELECT * FROM performance_dashboard;
```

### Log Cleanup

Logs older than 90 days can be archived:
```sql
SELECT cleanup_old_logs(90);
```

## Next Steps (Future Migrations)

The following will be added in subsequent phases:

### Phase 2: Template & Permission System
- Complete field permission matrix
- Sample HTMX templates for all view types
- Template rendering functions

### Phase 3: Data Layer Functions
- `fetch_list_data()` - Dynamic query building
- `fetch_form_data()` - Single record retrieval
- Filter and sort helpers

### Phase 4: HTMX Generation Functions
- `generate_htmx_list()` - List view generation
- `generate_htmx_form()` - Form generation

### Phase 5: Business Logic Functions
- `create_purchase_order()`
- `submit_purchase_order()`
- `approve_purchase_order()`
- `create_goods_receipt()`
- `create_invoice_receipt()` with 3-way matching
- `create_payment()`
- `process_payment()`

## Troubleshooting

### Migration Errors

If migrations fail:
1. Check PostgreSQL version (requires 14+)
2. Verify uuid-ossp extension is available
3. Ensure proper database permissions
4. Check for existing objects with same names

### RLS Not Working

If row-level security seems ineffective:
1. Verify `set_current_user_id()` was called
2. Check user has an active record in `users` table
3. Verify user role is set correctly
4. Test with `SELECT current_user_role();`

### Performance Issues

If queries are slow:
1. Run `ANALYZE` on all tables
2. Check `EXPLAIN ANALYZE` for query plans
3. Verify indexes are being used
4. Check `pg_stat_statements` for slow queries

## Testing

### Verify Migrations

```sql
-- Check all tables exist
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- Should return 18 tables

-- Check indexes
SELECT
    tablename,
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- Check sequences
SELECT sequence_name
FROM information_schema.sequences
WHERE sequence_schema = 'public';

-- Should return 4 sequences

-- Verify seed data
SELECT role_name FROM roles ORDER BY role_name;
-- Should return: accountant, admin, purchase_manager, viewer, warehouse_staff

SELECT username FROM users;
-- Should return: admin
```

## Contributors

- **happyveggie** - Database Design & Implementation
- **Claude Sonnet 4.5** (Anthropic) - Architecture & Planning

## License

Proprietary

---

**Last Updated**: 2026-01-16
**Migration Version**: 006
**Status**: Phase 1 Complete - Database Foundation Ready
