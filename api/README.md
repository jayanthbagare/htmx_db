# HTMX Database API

Minimal Fastify API layer for the HTMX Database-First Architecture.

## Overview

This API serves as a thin proxy between the browser and PostgreSQL database functions. All business logic, UI generation, and permission enforcement happens in the database layer.

## Architecture

```
Browser (HTMX)
      ↓
Fastify API (this layer)
      ↓
PostgreSQL Functions
```

## Quick Start

### Prerequisites

- Node.js 18+
- Supabase project (or PostgreSQL database)

### Setup

1. Install dependencies:
   ```bash
   cd api
   npm install
   ```

2. Configure environment:
   ```bash
   cp .env.example .env
   # Edit .env with your Supabase credentials
   ```

3. Start the server:
   ```bash
   # Development (with auto-reload)
   npm run dev

   # Production
   npm start
   ```

4. Open http://localhost:3000

## API Endpoints

### UI Generation Routes (`/ui`)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/ui/:entity/list` | Generate list view HTML |
| GET | `/ui/:entity/list/table` | Generate table-only (for partial updates) |
| GET | `/ui/:entity/form/create` | Generate create form HTML |
| GET | `/ui/:entity/form/edit?id=` | Generate edit form HTML |
| GET | `/ui/:entity/form/view?id=` | Generate view-only form HTML |
| GET | `/ui/:entity/lookup/:field` | Get dropdown options |
| GET | `/ui/nav` | Generate navigation menu |
| GET | `/ui/dashboard` | Generate dashboard view |

### Business Logic Routes (`/api`)

#### Purchase Orders
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/purchase_order` | Create PO |
| PUT | `/api/purchase_order/:id` | Update PO |
| POST | `/api/purchase_order/:id/submit` | Submit for approval |
| POST | `/api/purchase_order/:id/approve` | Approve PO |
| POST | `/api/purchase_order/:id/reject` | Reject PO |
| DELETE | `/api/purchase_order/:id` | Cancel PO |

#### Goods Receipts
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/goods_receipt` | Create GR |
| POST | `/api/goods_receipt/:id/accept` | Accept (QC pass) |
| POST | `/api/goods_receipt/:id/reject` | Reject (QC fail) |

#### Invoice Receipts
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/invoice_receipt` | Create invoice |
| POST | `/api/invoice_receipt/:id/approve_variance` | Approve variance |
| GET | `/api/invoice_receipt/:id/matching` | Get matching details |

#### Payments
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/payment` | Create payment |
| POST | `/api/payment/:id/process` | Process payment |
| POST | `/api/payment/:id/clear` | Clear payment |
| POST | `/api/payment/:id/cancel` | Cancel payment |

#### Generic CRUD
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/:entity` | List records (JSON) |
| GET | `/api/:entity/:id` | Get single record (JSON) |
| PUT | `/api/:entity/:id` | Update record |
| DELETE | `/api/:entity/:id` | Soft delete record |
| POST | `/api/:entity/:id/restore` | Restore deleted record |

### Authentication Routes (`/auth`)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/login` | Login with credentials |
| POST | `/auth/logout` | Logout |
| GET | `/auth/me` | Get current user |
| GET | `/auth/demo-users` | List demo users (dev only) |
| POST | `/auth/switch-demo-user` | Switch demo user (dev only) |

## Development

### Demo Users

In development mode, the API provides demo users for testing:

| User | Role | Capabilities |
|------|------|--------------|
| admin | Admin | Full access |
| purchase_manager | Purchase Manager | Create/edit POs, approve |
| warehouse_staff | Warehouse Staff | Receive goods, QC |
| accountant | Accountant | Invoices, payments |
| viewer | Viewer | Read-only access |

Switch users via:
- Header: `X-Demo-User: admin`
- Query: `?demo_user=admin`
- UI: Demo user selector in header

### Project Structure

```
api/
├── src/
│   ├── server.js          # Main entry point
│   ├── db/
│   │   └── connection.js  # Database connection
│   ├── middleware/
│   │   ├── auth.js        # Authentication
│   │   └── errorHandler.js # Error handling
│   └── routes/
│       ├── ui.js          # UI generation routes
│       ├── api.js         # Business logic routes
│       └── auth.js        # Auth routes
├── public/
│   ├── index.html         # Main app shell
│   ├── login.html         # Login page
│   └── css/
│       └── styles.css     # Styles
└── package.json
```

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| SUPABASE_URL | Supabase project URL | Yes |
| SUPABASE_ANON_KEY | Supabase anonymous key | Yes |
| SUPABASE_SERVICE_ROLE_KEY | Supabase service role key | No |
| PORT | Server port (default: 3000) | No |
| HOST | Server host (default: 0.0.0.0) | No |
| NODE_ENV | Environment (development/production) | No |
| SESSION_SECRET | Cookie signing secret | Yes (production) |
| LOG_LEVEL | Logging level (default: info) | No |

## License

MIT
