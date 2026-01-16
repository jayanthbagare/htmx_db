# Database-Driven HTMX UI Generation System

A novel approach to web application development where **PostgreSQL generates complete HTMX user interfaces** dynamically. All UI generation, business logic, and permission enforcement happens in the database layer.

## 🎯 Project Status

**Current Phase**: Planning Complete
**Next Phase**: Foundation & Database Setup

## 📋 Quick Links

- **[Complete Project Plan](PROJECT_PLAN.md)** - Comprehensive architecture and implementation guide
- **[Original Prompt](prompt.md)** - Detailed project requirements

## 🚀 What Makes This Unique

Traditional web apps have business logic scattered across frontend, API layer, and database. This project takes a radically different approach:

- **Database-First**: All business logic lives in PostgreSQL functions
- **Dynamic UI**: HTML templates stored in database, rendered on demand
- **Zero JavaScript Framework**: HTMX handles all interactivity
- **Granular Permissions**: Field-level and action-level security enforced at database layer

## 🏗️ Architecture Overview

```
PostgreSQL (Business Logic + UI Generation)
    ↕
Fastify API (Thin Proxy Layer)
    ↕
HTMX (Browser - No Framework Needed)
```

## 💼 Business Domain

Complete **Procure-to-Pay (P2P)** workflow:

```
Purchase Order → Goods Receipt → Invoice Receipt → Payment → Clearing
```

Features:
- Role-based access control (5 standard roles)
- 3-way matching (PO-GR-Invoice variance detection)
- Soft deletes with complete audit trail
- Dynamic permission enforcement
- Real-time performance monitoring

## 🛠️ Technology Stack

- **Database**: PostgreSQL 14+ (via Supabase)
- **API**: Node.js + Fastify
- **Frontend**: HTMX + Tailwind CSS
- **Testing**: pgTAP + Jest + k6
- **Language**: PL/pgSQL for all business logic

## 📊 Database Schema

18 tables organized in 3 groups:
- **Business Domain** (9 tables): suppliers, purchase_orders, goods_receipts, invoices, payments, etc.
- **UI Framework** (7 tables): entity_types, field_definitions, templates, permissions
- **Audit & Performance** (2 tables): generation_logs, performance_metrics

## 🎯 Performance Targets

- List generation: **< 300ms** p95 (even for 100k records)
- Form generation: **< 200ms** p95
- Template cache hit rate: **> 85%**
- Concurrent users: **50+ users** with < 1s p95 latency

## 🧪 Testing Strategy

Comprehensive test suite with 80+ tests:
- **Unit Tests** (pgTAP): Database function testing
- **Integration Tests** (Jest): API endpoint testing
- **Functional Tests** (Jest): Complete workflow testing
- **Performance Tests** (k6): Response time validation
- **Load Tests** (k6): Concurrent user simulation
- **Security Tests**: SQL injection, permission bypass attempts

## 📅 Implementation Timeline

**30-day implementation plan** across 8 phases:

1. **Phase 1** (Days 1-3): Database foundation
2. **Phase 2** (Days 4-7): Template & permission systems
3. **Phase 3** (Days 8-11): Data layer & query building
4. **Phase 4** (Days 12-15): HTMX generation
5. **Phase 5** (Days 16-20): Business logic workflows
6. **Phase 6** (Days 21-23): API layer
7. **Phase 7** (Days 24-28): Testing & optimization
8. **Phase 8** (Days 29-30): Documentation & test data

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for detailed breakdown.

## 🚦 Getting Started

### Prerequisites

- PostgreSQL 14+ or Supabase account
- Node.js 18+
- Git

### Quick Setup

```bash
# Clone repository
git clone <repository-url>
cd htmx_db

# Install API dependencies
cd api
npm install

# Set up environment variables
cp .env.example .env
# Edit .env with your Supabase credentials

# Run database migrations (coming soon)
# npm run migrate

# Start development server (coming soon)
# npm run dev
```

## 📖 Documentation

- [Complete Project Plan](PROJECT_PLAN.md) - Full architecture and implementation guide
- Database Schema Documentation (coming soon)
- API Endpoints Documentation (coming soon)
- Developer Guides (coming soon)

## 🎓 Key Concepts

### Template Rendering
Templates stored in database with placeholder syntax:
```html
<tr>
    <td>{{po_number}}</td>
    <td>{{supplier.supplier_name}}</td>
    <td>{{total_amount}}</td>
</tr>
```

### Permission Model
Three levels of security:
1. **Action-level**: Can user create/edit/delete this entity?
2. **Field-level**: Can user see/edit this field in this view?
3. **Row-level**: Can user access this specific record?

### Dynamic Query Building
Filters passed as JSON, converted to secure SQL:
```json
{
  "status": ["approved", "submitted"],
  "po_date_gte": "2024-01-01",
  "total_amount_gt": 10000
}
```

## 🤝 Contributing

This is currently a private project. See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the complete architecture if you're interested in the approach.

## 📝 License

Proprietary

## 👥 Contributors

- **happyveggie** - Project Lead & Implementation
- **Claude Sonnet 4.5** (Anthropic) - Architecture Design & Planning

## 📞 Contact

For questions about this project, please contact the project lead.

---

**Last Updated**: 2026-01-16
**Version**: 1.0
**Status**: 📋 Planning Complete → 🔨 Ready for Implementation
