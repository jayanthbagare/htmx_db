# API Endpoints Documentation

## Overview

The HTMX DB API is a minimal Fastify proxy layer that routes requests to PostgreSQL functions. The API is organized into three main route groups:

- `/ui/*` - UI generation endpoints (returns HTML)
- `/api/*` - Business logic endpoints (returns HTML for HTMX or JSON)
- `/auth/*` - Authentication endpoints

## Authentication

All API routes (except `/health`) require authentication via the `x-demo-user` header:

```http
GET /api/purchase_order
x-demo-user: 00000000-0000-0000-0000-000000000100
```

In production, this would be replaced with proper JWT authentication via Supabase Auth.

---

## UI Generation Endpoints

These endpoints return server-rendered HTML for HTMX consumption.

### List View

```http
GET /ui/:entity/list
```

Generates a complete list view with table, filters, and pagination.

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| page | integer | 1 | Page number |
| page_size | integer | 25 | Items per page |
| sort | string | null | Sort field name |
| sort_dir | string | ASC | Sort direction (ASC/DESC) |
| [filters] | various | - | Filter parameters |

**Example:**
```http
GET /ui/purchase_order/list?page=1&page_size=25&status=approved&sort=created_at&sort_dir=DESC
```

**Response:** `text/html`

---

### List Table (Partial)

```http
GET /ui/:entity/list/table
```

Returns just the table portion for HTMX partial updates.

**Parameters:** Same as list view

**Example:**
```http
GET /ui/purchase_order/list/table?page=2
```

**Response:** `text/html` (table body only)

---

### Create Form

```http
GET /ui/:entity/form/create
```

Generates an empty form for creating new records.

**Example:**
```http
GET /ui/purchase_order/form/create
```

**Response:** `text/html` (form)

---

### Edit Form

```http
GET /ui/:entity/form/edit?id=:record_id
```

Generates a pre-populated form for editing.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| id | UUID | Yes | Record ID to edit |

**Example:**
```http
GET /ui/purchase_order/form/edit?id=550e8400-e29b-41d4-a716-446655440000
```

**Response:** `text/html` (form with data)

---

### View Form

```http
GET /ui/:entity/form/view?id=:record_id
```

Generates a read-only view of a record.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| id | UUID | Yes | Record ID to view |

**Example:**
```http
GET /ui/purchase_order/form/view?id=550e8400-e29b-41d4-a716-446655440000
```

**Response:** `text/html` (read-only form)

---

### Lookup Options

```http
GET /ui/:entity/lookup/:field
```

Returns dropdown options for lookup fields.

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| search | string | null | Search term |
| limit | integer | 50 | Max results |

**Example:**
```http
GET /ui/purchase_order/lookup/supplier_id?search=acme&limit=10
```

**Response:** `text/html` (option elements)

---

### Dashboard

```http
GET /ui/dashboard
```

Returns the main dashboard HTML.

**Response:** `text/html`

---

### Navigation

```http
GET /ui/nav
```

Returns the navigation menu based on user permissions.

**Response:** `text/html` (nav element)

---

## Business Logic API Endpoints

These endpoints handle CRUD operations and workflow actions.

### Purchase Orders

#### Create Purchase Order

```http
POST /api/purchase_order
Content-Type: application/json

{
  "supplier_id": "uuid",
  "po_date": "2024-01-15",
  "expected_delivery_date": "2024-02-15",
  "currency": "USD",
  "notes": "Optional notes",
  "lines": [
    {
      "item_code": "ITEM-001",
      "item_description": "Widget",
      "quantity_ordered": 100,
      "unit_price": 25.00,
      "uom": "EA"
    }
  ]
}
```

**Response:** HTML with HX-Trigger header for toast notification

---

#### Update Purchase Order

```http
PUT /api/purchase_order/:id
Content-Type: application/json

{
  "notes": "Updated notes",
  "expected_delivery_date": "2024-02-20"
}
```

---

#### Submit Purchase Order

```http
POST /api/purchase_order/:id/submit
```

Submits a draft PO for approval.

**Preconditions:** PO must be in `draft` status

---

#### Approve Purchase Order

```http
POST /api/purchase_order/:id/approve
Content-Type: application/json

{
  "notes": "Approved for budget Q1"
}
```

**Preconditions:** PO must be in `submitted` status

---

#### Reject Purchase Order

```http
POST /api/purchase_order/:id/reject
Content-Type: application/json

{
  "reason": "Over budget"  // Required
}
```

---

#### Cancel Purchase Order

```http
DELETE /api/purchase_order/:id
Content-Type: application/json

{
  "reason": "No longer needed"
}
```

---

### Goods Receipts

#### Create Goods Receipt

```http
POST /api/goods_receipt
Content-Type: application/json

{
  "po_id": "uuid",
  "receipt_date": "2024-01-20",
  "delivery_note_number": "DN-12345",
  "notes": "All items received"
}
```

**Preconditions:** PO must be in `approved` or `partially_received` status

---

#### Accept Goods Receipt

```http
POST /api/goods_receipt/:id/accept
Content-Type: application/json

{
  "notes": "QC passed"
}
```

---

#### Reject Goods Receipt

```http
POST /api/goods_receipt/:id/reject
Content-Type: application/json

{
  "reason": "Quality issues"  // Required
}
```

---

### Invoice Receipts

#### Create Invoice Receipt

```http
POST /api/invoice_receipt
Content-Type: application/json

{
  "po_id": "uuid",
  "vendor_invoice_number": "VINV-2024-001",
  "invoice_date": "2024-01-25",
  "due_date": "2024-02-25",
  "currency": "USD",
  "notes": "Standard invoice"
}
```

**Response includes:** `matching_status` indicating 3-way match result

---

#### Approve Invoice Variance

```http
POST /api/invoice_receipt/:id/approve_variance
Content-Type: application/json

{
  "notes": "Variance approved by manager"
}
```

---

#### Get Matching Details

```http
GET /api/invoice_receipt/:id/matching
```

Returns detailed 3-way matching information.

**Response:** JSON with match status and variance details

---

### Payments

#### Create Payment

```http
POST /api/payment
Content-Type: application/json

{
  "invoice_id": "uuid",
  "amount": 1250.00,
  "payment_method": "bank_transfer",
  "payment_date": "2024-02-01",
  "reference_number": "PAY-REF-001",
  "notes": "Full payment"
}
```

**Payment Methods:** `bank_transfer`, `check`, `wire`, `credit_card`

---

#### Process Payment

```http
POST /api/payment/:id/process
Content-Type: application/json

{
  "transaction_id": "TXN-12345678"
}
```

**Preconditions:** Payment must be in `pending` status

---

#### Clear Payment

```http
POST /api/payment/:id/clear
Content-Type: application/json

{
  "cleared_date": "2024-02-05",
  "bank_reference": "BANK-REF-001"
}
```

**Preconditions:** Payment must be in `processed` status

---

#### Cancel Payment

```http
POST /api/payment/:id/cancel
Content-Type: application/json

{
  "reason": "Duplicate payment"  // Required
}
```

---

### Generic CRUD

These endpoints work for any entity type.

#### List Records (JSON)

```http
GET /api/:entity
```

Returns paginated list data as JSON.

**Parameters:** Same as UI list endpoint

---

#### Get Single Record (JSON)

```http
GET /api/:entity/:id
```

Returns a single record as JSON.

---

#### Update Any Record

```http
PUT /api/:entity/:id
Content-Type: application/json

{
  "field1": "value1",
  "field2": "value2"
}
```

---

#### Delete Any Record

```http
DELETE /api/:entity/:id
Content-Type: application/json

{
  "reason": "No longer needed"
}
```

Performs a soft delete.

---

#### Restore Deleted Record

```http
POST /api/:entity/:id/restore
```

Restores a soft-deleted record.

---

## System Endpoints

### Health Check

```http
GET /health
```

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

---

## Response Headers

### HX-Trigger

Success and error responses include an `HX-Trigger` header for HTMX toast notifications:

```http
HX-Trigger: {"showToast": {"message": "Purchase order created", "type": "success"}}
```

Types: `success`, `error`, `warning`, `info`

---

## Error Responses

### 400 Bad Request

```json
{
  "error": "Supplier is required"
}
```

### 401 Unauthorized

```json
{
  "error": "Authentication required"
}
```

### 403 Forbidden

```json
{
  "error": "Permission denied"
}
```

### 404 Not Found

```json
{
  "error": "Record not found"
}
```

### 500 Internal Server Error

```json
{
  "error": "Internal server error"
}
```

---

## Filter Syntax

Filters are passed as query parameters with special suffixes:

| Suffix | Operator | Example |
|--------|----------|---------|
| (none) | = or IN | `status=approved` or `status=approved,submitted` |
| `_gte` | >= | `po_date_gte=2024-01-01` |
| `_lte` | <= | `po_date_lte=2024-12-31` |
| `_gt` | > | `total_amount_gt=1000` |
| `_lt` | < | `total_amount_lt=10000` |
| `_like` | ILIKE | `supplier_name_like=acme%` |

**Example:**
```http
GET /api/purchase_order?status=approved,submitted&po_date_gte=2024-01-01&total_amount_gt=1000
```

---

## Entity Names

| Entity | URL Path |
|--------|----------|
| Suppliers | `supplier` |
| Purchase Orders | `purchase_order` |
| Goods Receipts | `goods_receipt` |
| Invoice Receipts | `invoice_receipt` |
| Payments | `payment` |

---

## Pagination

All list endpoints support pagination:

```http
GET /api/purchase_order?page=2&page_size=50
```

**Response includes:**
- `total_count`: Total number of matching records
- `data`: Array of records for current page

---

## Sorting

```http
GET /api/purchase_order?sort=created_at&sort_dir=DESC
```

**Parameters:**
- `sort`: Field name to sort by
- `sort_dir`: `ASC` (default) or `DESC`
