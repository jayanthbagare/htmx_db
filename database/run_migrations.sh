#!/bin/bash

# Database Migration Runner
# Runs all SQL migration files in order
# Author: happyveggie & Claude Sonnet 4.5

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DB_NAME="${DB_NAME:-htmx_db}"
DB_USER="${DB_USER:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MIGRATIONS_DIR="$SCRIPT_DIR/migrations"

# Functions
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}       Database Migration Runner - HTMX UI System       ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check if psql is installed
    if ! command -v psql &> /dev/null; then
        print_error "psql command not found. Please install PostgreSQL client."
        exit 1
    fi

    # Check if migrations directory exists
    if [ ! -d "$MIGRATIONS_DIR" ]; then
        print_error "Migrations directory not found: $MIGRATIONS_DIR"
        exit 1
    fi

    # Check if database exists
    if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        print_warning "Database '$DB_NAME' does not exist."
        read -p "Create database now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME"
            print_success "Database '$DB_NAME' created"
        else
            print_error "Database required. Exiting."
            exit 1
        fi
    fi

    print_success "Prerequisites check passed"
    echo
}

run_migration() {
    local migration_file=$1
    local filename=$(basename "$migration_file")

    print_info "Running migration: $filename"

    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$migration_file" > /dev/null 2>&1; then
        print_success "Migration completed: $filename"
        return 0
    else
        print_error "Migration failed: $filename"
        echo
        print_info "Running migration with verbose output for debugging..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$migration_file"
        return 1
    fi
}

run_all_migrations() {
    local migration_files=(
        "$MIGRATIONS_DIR/001_create_business_domain.sql"
        "$MIGRATIONS_DIR/002_create_ui_framework.sql"
        "$MIGRATIONS_DIR/003_create_audit_tables.sql"
        "$MIGRATIONS_DIR/004_create_triggers_sequences.sql"
        "$MIGRATIONS_DIR/005_create_rls_policies.sql"
        "$MIGRATIONS_DIR/006_initial_seed_data.sql"
    )

    local total=${#migration_files[@]}
    local current=0
    local failed=0

    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "  Running $total migrations..."
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo

    for migration_file in "${migration_files[@]}"; do
        ((current++))
        echo "[$current/$total]"

        if [ ! -f "$migration_file" ]; then
            print_error "Migration file not found: $(basename "$migration_file")"
            ((failed++))
            continue
        fi

        if ! run_migration "$migration_file"; then
            ((failed++))
            if [ "$1" != "--continue-on-error" ]; then
                break
            fi
        fi

        echo
    done

    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    if [ $failed -eq 0 ]; then
        print_success "All migrations completed successfully! ($current/$total)"
        return 0
    else
        print_error "Some migrations failed! ($failed failed, $((current - failed)) succeeded)"
        return 1
    fi
}

verify_installation() {
    print_info "Verifying database schema..."

    local table_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE';
    " | tr -d ' ')

    local sequence_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*)
        FROM information_schema.sequences
        WHERE sequence_schema = 'public';
    " | tr -d ' ')

    local role_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) FROM roles;
    " | tr -d ' ')

    echo
    echo "Schema Verification:"
    echo "  ├─ Tables: $table_count (expected: 18)"
    echo "  ├─ Sequences: $sequence_count (expected: 4)"
    echo "  └─ Roles: $role_count (expected: 5)"
    echo

    if [ "$table_count" -eq 18 ] && [ "$sequence_count" -eq 4 ] && [ "$role_count" -eq 5 ]; then
        print_success "Schema verification passed!"
        return 0
    else
        print_warning "Schema verification found discrepancies. Review output above."
        return 1
    fi
}

show_next_steps() {
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                 Migration Successful!                   ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "Database Connection Info:"
    echo "  ├─ Database: $DB_NAME"
    echo "  ├─ Host: $DB_HOST"
    echo "  ├─ Port: $DB_PORT"
    echo "  └─ User: $DB_USER"
    echo
    echo "Default Admin Account:"
    echo "  ├─ Username: admin"
    echo "  ├─ Email: admin@example.com"
    echo "  └─ ⚠ WARNING: Change password immediately!"
    echo
    echo "Next Steps:"
    echo "  1. Review database/README.md for details"
    echo "  2. Change admin password"
    echo "  3. Set up Supabase Auth (recommended)"
    echo "  4. Configure API server with connection details"
    echo "  5. Proceed to Phase 2: Template & Permission System"
    echo
    print_info "For connection string, use:"
    echo "  postgresql://$DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
    echo
}

# Main execution
main() {
    print_header

    # Display configuration
    echo "Configuration:"
    echo "  ├─ Database: $DB_NAME"
    echo "  ├─ Host: $DB_HOST"
    echo "  ├─ Port: $DB_PORT"
    echo "  └─ User: $DB_USER"
    echo

    # Check prerequisites
    check_prerequisites

    # Confirm before proceeding
    if [ "$1" != "-y" ] && [ "$1" != "--yes" ]; then
        read -p "Proceed with migrations? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Migration cancelled by user"
            exit 0
        fi
        echo
    fi

    # Run migrations
    if run_all_migrations "$@"; then
        verify_installation
        show_next_steps
        exit 0
    else
        print_error "Migration process failed. Check errors above."
        echo
        print_info "Troubleshooting tips:"
        echo "  - Check PostgreSQL version (requires 14+)"
        echo "  - Verify database permissions"
        echo "  - Check for existing objects with same names"
        echo "  - Review migration logs above for specific errors"
        exit 1
    fi
}

# Handle script arguments
case "$1" in
    -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  -y, --yes                 Skip confirmation prompt"
        echo "  --continue-on-error       Continue even if migrations fail"
        echo "  -h, --help                Show this help message"
        echo
        echo "Environment Variables:"
        echo "  DB_NAME      Database name (default: htmx_db)"
        echo "  DB_USER      Database user (default: postgres)"
        echo "  DB_HOST      Database host (default: localhost)"
        echo "  DB_PORT      Database port (default: 5432)"
        echo
        echo "Example:"
        echo "  DB_NAME=mydb DB_USER=myuser $0 -y"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
