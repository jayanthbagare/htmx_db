-- Migration 001: Create Business Domain Tables
-- Description: Creates all 9 business domain tables for the procurement workflow
-- Dependencies: None (first migration)
-- Author: happyveggie & Claude Sonnet 4.5

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- SUPPLIERS TABLE
-- =============================================================================
-- Stores vendor/supplier master data

CREATE TABLE suppliers (
    supplier_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    supplier_code       VARCHAR(50) NOT NULL UNIQUE,
    supplier_name       VARCHAR(200) NOT NULL,
    contact_email       VARCHAR(100),
    contact_phone       VARCHAR(20),
    payment_terms_days  INTEGER NOT NULL DEFAULT 30,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by          UUID,  -- FK will be added after users table exists

    CONSTRAINT chk_payment_terms CHECK (payment_terms_days >= 0),
    CONSTRAINT chk_supplier_code_format CHECK (supplier_code ~ '^[A-Z0-9-]+$')
);

COMMENT ON TABLE suppliers IS 'Vendor/supplier master data';
COMMENT ON COLUMN suppliers.supplier_code IS 'Unique supplier code (uppercase alphanumeric)';
COMMENT ON COLUMN suppliers.payment_terms_days IS 'Standard payment terms in days';

-- =============================================================================
-- PURCHASE ORDERS TABLE
-- =============================================================================
-- Stores purchase order headers

CREATE TABLE purchase_orders (
    po_id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_number               VARCHAR(50) NOT NULL UNIQUE,
    supplier_id             UUID NOT NULL,
    po_date                 DATE NOT NULL DEFAULT CURRENT_DATE,
    expected_delivery_date  DATE,
    total_amount            DECIMAL(15,2) NOT NULL DEFAULT 0,
    currency                VARCHAR(3) NOT NULL DEFAULT 'USD',
    status                  VARCHAR(20) NOT NULL DEFAULT 'draft',
    notes                   TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by              UUID,
    approved_by             UUID,
    approved_at             TIMESTAMPTZ,

    CONSTRAINT fk_po_supplier FOREIGN KEY (supplier_id)
        REFERENCES suppliers(supplier_id),
    CONSTRAINT chk_po_status CHECK (status IN (
        'draft', 'submitted', 'approved',
        'partially_received', 'fully_received', 'cancelled'
    )),
    CONSTRAINT chk_po_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT chk_po_total_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_po_expected_delivery CHECK (
        expected_delivery_date IS NULL OR
        expected_delivery_date >= po_date
    ),
    CONSTRAINT chk_po_approved_at CHECK (
        (approved_by IS NULL AND approved_at IS NULL) OR
        (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    )
);

COMMENT ON TABLE purchase_orders IS 'Purchase order headers';
COMMENT ON COLUMN purchase_orders.status IS 'PO status: draft, submitted, approved, partially_received, fully_received, cancelled';
COMMENT ON COLUMN purchase_orders.is_deleted IS 'Soft delete flag - deleted records not shown in queries';

-- =============================================================================
-- PURCHASE ORDER LINES TABLE
-- =============================================================================
-- Stores individual line items for purchase orders

CREATE TABLE purchase_order_lines (
    po_line_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id               UUID NOT NULL,
    line_number         INTEGER NOT NULL,
    item_code           VARCHAR(100) NOT NULL,
    item_description    TEXT NOT NULL,
    quantity_ordered    DECIMAL(10,2) NOT NULL,
    unit_price          DECIMAL(15,2) NOT NULL,
    line_total          DECIMAL(15,2) NOT NULL,
    quantity_received   DECIMAL(10,2) NOT NULL DEFAULT 0,
    quantity_invoiced   DECIMAL(10,2) NOT NULL DEFAULT 0,
    uom                 VARCHAR(20) NOT NULL DEFAULT 'EA',
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_po_line_po FOREIGN KEY (po_id)
        REFERENCES purchase_orders(po_id),
    CONSTRAINT uq_po_line_number UNIQUE (po_id, line_number),
    CONSTRAINT chk_po_line_quantity_ordered CHECK (quantity_ordered > 0),
    CONSTRAINT chk_po_line_unit_price CHECK (unit_price >= 0),
    CONSTRAINT chk_po_line_total CHECK (line_total >= 0),
    CONSTRAINT chk_po_line_qty_received CHECK (quantity_received >= 0),
    CONSTRAINT chk_po_line_qty_invoiced CHECK (quantity_invoiced >= 0),
    CONSTRAINT chk_po_line_qty_received_max CHECK (quantity_received <= quantity_ordered * 1.1),
    CONSTRAINT chk_po_line_qty_invoiced_max CHECK (quantity_invoiced <= quantity_ordered * 1.1)
);

COMMENT ON TABLE purchase_order_lines IS 'Purchase order line items';
COMMENT ON COLUMN purchase_order_lines.quantity_received IS 'Total quantity received across all goods receipts';
COMMENT ON COLUMN purchase_order_lines.quantity_invoiced IS 'Total quantity invoiced';
COMMENT ON COLUMN purchase_order_lines.uom IS 'Unit of measure (EA=Each, BX=Box, CS=Case, etc.)';

-- =============================================================================
-- GOODS RECEIPTS TABLE
-- =============================================================================
-- Stores goods receipt headers (receiving documents)

CREATE TABLE goods_receipts (
    gr_id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    gr_number           VARCHAR(50) NOT NULL UNIQUE,
    po_id               UUID NOT NULL,
    receipt_date        DATE NOT NULL DEFAULT CURRENT_DATE,
    received_by         UUID,
    warehouse_location  VARCHAR(100),
    status              VARCHAR(20) NOT NULL DEFAULT 'draft',
    notes               TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_gr_po FOREIGN KEY (po_id)
        REFERENCES purchase_orders(po_id),
    CONSTRAINT chk_gr_status CHECK (status IN ('draft', 'confirmed', 'cancelled'))
);

COMMENT ON TABLE goods_receipts IS 'Goods receipt headers (receiving documents)';
COMMENT ON COLUMN goods_receipts.received_by IS 'User who physically received the goods';
COMMENT ON COLUMN goods_receipts.warehouse_location IS 'Where goods were stored';

-- =============================================================================
-- GOODS RECEIPT LINES TABLE
-- =============================================================================
-- Stores individual line items for goods receipts

CREATE TABLE goods_receipt_lines (
    gr_line_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    gr_id               UUID NOT NULL,
    po_line_id          UUID NOT NULL,
    quantity_received   DECIMAL(10,2) NOT NULL,
    quality_status      VARCHAR(20) NOT NULL DEFAULT 'accepted',
    notes               TEXT,

    CONSTRAINT fk_gr_line_gr FOREIGN KEY (gr_id)
        REFERENCES goods_receipts(gr_id),
    CONSTRAINT fk_gr_line_po_line FOREIGN KEY (po_line_id)
        REFERENCES purchase_order_lines(po_line_id),
    CONSTRAINT chk_gr_line_quantity CHECK (quantity_received > 0),
    CONSTRAINT chk_gr_line_quality_status CHECK (quality_status IN (
        'accepted', 'rejected', 'pending_inspection'
    ))
);

COMMENT ON TABLE goods_receipt_lines IS 'Goods receipt line items';
COMMENT ON COLUMN goods_receipt_lines.quality_status IS 'Quality inspection result: accepted, rejected, pending_inspection';

-- =============================================================================
-- INVOICE RECEIPTS TABLE
-- =============================================================================
-- Stores vendor invoices

CREATE TABLE invoice_receipts (
    invoice_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invoice_number          VARCHAR(50) NOT NULL UNIQUE,
    supplier_invoice_number VARCHAR(50),
    po_id                   UUID NOT NULL,
    invoice_date            DATE NOT NULL,
    due_date                DATE NOT NULL,
    total_amount            DECIMAL(15,2) NOT NULL,
    tax_amount              DECIMAL(15,2) NOT NULL DEFAULT 0,
    status                  VARCHAR(20) NOT NULL DEFAULT 'received',
    matching_status         VARCHAR(20) NOT NULL DEFAULT 'pending',
    is_deleted              BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    verified_by             UUID,
    approved_by             UUID,

    CONSTRAINT fk_invoice_po FOREIGN KEY (po_id)
        REFERENCES purchase_orders(po_id),
    CONSTRAINT chk_invoice_status CHECK (status IN (
        'received', 'verified', 'approved', 'disputed', 'cancelled'
    )),
    CONSTRAINT chk_invoice_matching_status CHECK (matching_status IN (
        'pending', 'matched', 'variance'
    )),
    CONSTRAINT chk_invoice_total_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_invoice_tax_amount CHECK (tax_amount >= 0),
    CONSTRAINT chk_invoice_due_date CHECK (due_date >= invoice_date)
);

COMMENT ON TABLE invoice_receipts IS 'Vendor invoices with 3-way matching';
COMMENT ON COLUMN invoice_receipts.supplier_invoice_number IS 'Invoice number from supplier system';
COMMENT ON COLUMN invoice_receipts.matching_status IS '3-way matching result: pending, matched, variance';

-- =============================================================================
-- INVOICE LINES TABLE
-- =============================================================================
-- Stores individual line items for invoices

CREATE TABLE invoice_lines (
    invoice_line_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invoice_id          UUID NOT NULL,
    po_line_id          UUID NOT NULL,
    gr_line_id          UUID,
    quantity_invoiced   DECIMAL(10,2) NOT NULL,
    unit_price          DECIMAL(15,2) NOT NULL,
    line_total          DECIMAL(15,2) NOT NULL,
    variance_amount     DECIMAL(15,2) NOT NULL DEFAULT 0,

    CONSTRAINT fk_invoice_line_invoice FOREIGN KEY (invoice_id)
        REFERENCES invoice_receipts(invoice_id),
    CONSTRAINT fk_invoice_line_po_line FOREIGN KEY (po_line_id)
        REFERENCES purchase_order_lines(po_line_id),
    CONSTRAINT fk_invoice_line_gr_line FOREIGN KEY (gr_line_id)
        REFERENCES goods_receipt_lines(gr_line_id),
    CONSTRAINT chk_invoice_line_quantity CHECK (quantity_invoiced > 0),
    CONSTRAINT chk_invoice_line_unit_price CHECK (unit_price >= 0),
    CONSTRAINT chk_invoice_line_line_total CHECK (line_total >= 0)
);

COMMENT ON TABLE invoice_lines IS 'Invoice line items with variance tracking';
COMMENT ON COLUMN invoice_lines.variance_amount IS 'Calculated variance from 3-way matching';

-- =============================================================================
-- PAYMENTS TABLE
-- =============================================================================
-- Stores payment records

CREATE TABLE payments (
    payment_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_number      VARCHAR(50) NOT NULL UNIQUE,
    invoice_id          UUID NOT NULL,
    payment_date        DATE NOT NULL DEFAULT CURRENT_DATE,
    payment_method      VARCHAR(50) NOT NULL,
    payment_amount      DECIMAL(15,2) NOT NULL,
    reference_number    VARCHAR(100),
    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_by        UUID,

    CONSTRAINT fk_payment_invoice FOREIGN KEY (invoice_id)
        REFERENCES invoice_receipts(invoice_id),
    CONSTRAINT chk_payment_method CHECK (payment_method IN (
        'bank_transfer', 'check', 'wire', 'credit_card', 'ach'
    )),
    CONSTRAINT chk_payment_status CHECK (status IN (
        'pending', 'processed', 'cleared', 'failed', 'cancelled'
    )),
    CONSTRAINT chk_payment_amount CHECK (payment_amount > 0)
);

COMMENT ON TABLE payments IS 'Payment records against invoices';
COMMENT ON COLUMN payments.payment_method IS 'bank_transfer, check, wire, credit_card, ach';
COMMENT ON COLUMN payments.reference_number IS 'Bank reference, check number, or transaction ID';

-- =============================================================================
-- CLEARING ENTRIES TABLE
-- =============================================================================
-- Stores payment-to-invoice clearing/reconciliation

CREATE TABLE clearing_entries (
    clearing_id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_id              UUID NOT NULL,
    invoice_id              UUID NOT NULL,
    cleared_amount          DECIMAL(15,2) NOT NULL,
    clearing_date           DATE NOT NULL DEFAULT CURRENT_DATE,
    status                  VARCHAR(20) NOT NULL DEFAULT 'pending',
    reconciliation_reference VARCHAR(100),
    notes                   TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_clearing_payment FOREIGN KEY (payment_id)
        REFERENCES payments(payment_id),
    CONSTRAINT fk_clearing_invoice FOREIGN KEY (invoice_id)
        REFERENCES invoice_receipts(invoice_id),
    CONSTRAINT chk_clearing_status CHECK (status IN (
        'pending', 'cleared', 'reconciled'
    )),
    CONSTRAINT chk_clearing_amount CHECK (cleared_amount > 0)
);

COMMENT ON TABLE clearing_entries IS 'Payment-to-invoice clearing and reconciliation';
COMMENT ON COLUMN clearing_entries.reconciliation_reference IS 'Bank reconciliation reference';

-- =============================================================================
-- INDEXES FOR BUSINESS DOMAIN TABLES
-- =============================================================================
-- Note: Primary keys and unique constraints automatically create indexes
-- These are additional indexes for performance

-- Suppliers
CREATE INDEX idx_suppliers_active ON suppliers(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_suppliers_created_at ON suppliers(created_at);

-- Purchase Orders
CREATE INDEX idx_po_supplier ON purchase_orders(supplier_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_po_status ON purchase_orders(status) WHERE is_deleted = FALSE;
CREATE INDEX idx_po_date ON purchase_orders(po_date) WHERE is_deleted = FALSE;
CREATE INDEX idx_po_status_date ON purchase_orders(status, po_date) WHERE is_deleted = FALSE;
CREATE INDEX idx_po_created_by ON purchase_orders(created_by) WHERE is_deleted = FALSE;

-- Purchase Order Lines
CREATE INDEX idx_po_lines_po ON purchase_order_lines(po_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_po_lines_item_code ON purchase_order_lines(item_code) WHERE is_deleted = FALSE;

-- Goods Receipts
CREATE INDEX idx_gr_po ON goods_receipts(po_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_gr_date ON goods_receipts(receipt_date) WHERE is_deleted = FALSE;
CREATE INDEX idx_gr_status ON goods_receipts(status) WHERE is_deleted = FALSE;

-- Goods Receipt Lines
CREATE INDEX idx_gr_lines_gr ON goods_receipt_lines(gr_id);
CREATE INDEX idx_gr_lines_po_line ON goods_receipt_lines(po_line_id);

-- Invoice Receipts
CREATE INDEX idx_invoice_po ON invoice_receipts(po_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_invoice_status ON invoice_receipts(status) WHERE is_deleted = FALSE;
CREATE INDEX idx_invoice_matching_status ON invoice_receipts(matching_status) WHERE is_deleted = FALSE;
CREATE INDEX idx_invoice_date ON invoice_receipts(invoice_date) WHERE is_deleted = FALSE;
CREATE INDEX idx_invoice_due_date ON invoice_receipts(due_date) WHERE is_deleted = FALSE;

-- Invoice Lines
CREATE INDEX idx_invoice_lines_invoice ON invoice_lines(invoice_id);
CREATE INDEX idx_invoice_lines_po_line ON invoice_lines(po_line_id);

-- Payments
CREATE INDEX idx_payment_invoice ON payments(invoice_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_payment_status ON payments(status) WHERE is_deleted = FALSE;
CREATE INDEX idx_payment_date ON payments(payment_date) WHERE is_deleted = FALSE;

-- Clearing Entries
CREATE INDEX idx_clearing_payment ON clearing_entries(payment_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_clearing_invoice ON clearing_entries(invoice_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_clearing_status ON clearing_entries(status) WHERE is_deleted = FALSE;

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 001 completed successfully';
    RAISE NOTICE 'Created 9 business domain tables with indexes';
    RAISE NOTICE 'Tables: suppliers, purchase_orders, purchase_order_lines, goods_receipts, goods_receipt_lines, invoice_receipts, invoice_lines, payments, clearing_entries';
END $$;
