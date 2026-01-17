/**
 * UI Generation Routes
 * Routes that call PostgreSQL functions to generate HTMX HTML
 */

import { callFunctionAsUser, parseResult } from '../db/connection.js';
import { getUserId } from '../middleware/auth.js';
import { errors } from '../middleware/errorHandler.js';

/**
 * Parse filter parameters from query string
 * Converts URL params to JSONB filter format
 */
function parseFilters(query) {
  const filters = {};
  const reserved = ['page', 'page_size', 'sort', 'sort_dir', 'demo_user'];

  for (const [key, value] of Object.entries(query)) {
    if (reserved.includes(key)) continue;
    if (value === '' || value === undefined) continue;

    // Handle array values (multiple select)
    if (Array.isArray(value)) {
      filters[key] = value;
    } else if (value.includes(',')) {
      filters[key] = value.split(',');
    } else {
      filters[key] = value;
    }
  }

  return filters;
}

export default async function uiRoutes(fastify) {
  /**
   * GET /ui/:entity/list
   * Generate list view for an entity
   */
  fastify.get('/:entity/list', async (request, reply) => {
    const { entity } = request.params;
    const userId = getUserId(request);

    if (!userId) {
      throw errors.unauthorized('Authentication required');
    }

    const {
      page = 1,
      page_size = 25,
      sort = null,
      sort_dir = 'ASC'
    } = request.query;

    const filters = parseFilters(request.query);

    try {
      const html = await callFunctionAsUser('generate_htmx_list', {
        p_user_id: userId,
        p_entity_type: entity,
        p_filters: filters,
        p_sort_field: sort,
        p_sort_direction: sort_dir.toUpperCase(),
        p_page_size: parseInt(page_size, 10),
        p_page_number: parseInt(page, 10)
      });

      reply
        .header('Content-Type', 'text/html; charset=utf-8')
        .send(html);
    } catch (err) {
      request.log.error({ err, entity, filters }, 'Failed to generate list view');
      throw err;
    }
  });

  /**
   * GET /ui/:entity/list/table
   * Generate just the table portion (for HTMX partial updates)
   */
  fastify.get('/:entity/list/table', async (request, reply) => {
    const { entity } = request.params;
    const userId = getUserId(request);

    if (!userId) {
      throw errors.unauthorized('Authentication required');
    }

    const {
      page = 1,
      page_size = 25,
      sort = null,
      sort_dir = 'ASC'
    } = request.query;

    const filters = parseFilters(request.query);

    try {
      const html = await callFunctionAsUser('generate_htmx_list_table', {
        p_user_id: userId,
        p_entity_type: entity,
        p_filters: filters,
        p_sort_field: sort,
        p_sort_direction: sort_dir.toUpperCase(),
        p_page_size: parseInt(page_size, 10),
        p_page_number: parseInt(page, 10)
      });

      reply
        .header('Content-Type', 'text/html; charset=utf-8')
        .send(html);
    } catch (err) {
      request.log.error({ err, entity }, 'Failed to generate list table');
      throw err;
    }
  });

  /**
   * GET /ui/:entity/form/create
   * Generate create form for an entity
   */
  fastify.get('/:entity/form/create', async (request, reply) => {
    const { entity } = request.params;
    const userId = getUserId(request);

    if (!userId) {
      throw errors.unauthorized('Authentication required');
    }

    try {
      const html = await callFunctionAsUser('generate_htmx_form', {
        p_user_id: userId,
        p_entity_type: entity,
        p_view_type: 'form_create',
        p_record_id: null
      });

      reply
        .header('Content-Type', 'text/html; charset=utf-8')
        .send(html);
    } catch (err) {
      request.log.error({ err, entity }, 'Failed to generate create form');
      throw err;
    }
  });

  /**
   * GET /ui/:entity/form/edit
   * Generate edit form for a specific record
   */
  fastify.get('/:entity/form/edit', async (request, reply) => {
    const { entity } = request.params;
    const { id } = request.query;
    const userId = getUserId(request);

    if (!userId) {
      throw errors.unauthorized('Authentication required');
    }

    if (!id) {
      throw errors.badRequest('Record ID is required');
    }

    try {
      const html = await callFunctionAsUser('generate_htmx_form', {
        p_user_id: userId,
        p_entity_type: entity,
        p_view_type: 'form_edit',
        p_record_id: id
      });

      reply
        .header('Content-Type', 'text/html; charset=utf-8')
        .send(html);
    } catch (err) {
      request.log.error({ err, entity, id }, 'Failed to generate edit form');
      throw err;
    }
  });

  /**
   * GET /ui/:entity/form/view
   * Generate view-only form for a specific record
   */
  fastify.get('/:entity/form/view', async (request, reply) => {
    const { entity } = request.params;
    const { id } = request.query;
    const userId = getUserId(request);

    if (!userId) {
      throw errors.unauthorized('Authentication required');
    }

    if (!id) {
      throw errors.badRequest('Record ID is required');
    }

    try {
      const html = await callFunctionAsUser('generate_htmx_form', {
        p_user_id: userId,
        p_entity_type: entity,
        p_view_type: 'form_view',
        p_record_id: id
      });

      reply
        .header('Content-Type', 'text/html; charset=utf-8')
        .send(html);
    } catch (err) {
      request.log.error({ err, entity, id }, 'Failed to generate view form');
      throw err;
    }
  });

  /**
   * GET /ui/:entity/lookup
   * Get lookup options for a field (dropdown data)
   */
  fastify.get('/:entity/lookup/:field', async (request, reply) => {
    const { entity, field } = request.params;
    const { search = null, limit = 50 } = request.query;
    const userId = getUserId(request);

    if (!userId) {
      throw errors.unauthorized('Authentication required');
    }

    try {
      const options = await callFunctionAsUser('fetch_lookup_options', {
        p_user_id: userId,
        p_entity_type: entity,
        p_field_name: field,
        p_search_term: search,
        p_limit: parseInt(limit, 10)
      });

      // Return as HTML options for HTMX
      const html = options.map(opt =>
        `<option value="${opt.id}">${opt.label}</option>`
      ).join('\n');

      reply
        .header('Content-Type', 'text/html; charset=utf-8')
        .send(html);
    } catch (err) {
      request.log.error({ err, entity, field }, 'Failed to fetch lookup options');
      throw err;
    }
  });

  /**
   * GET /ui/nav
   * Generate navigation menu based on user permissions
   */
  fastify.get('/nav', async (request, reply) => {
    const userId = getUserId(request);

    // Define available entities
    const entities = [
      { name: 'supplier', label: 'Suppliers', icon: 'building' },
      { name: 'purchase_order', label: 'Purchase Orders', icon: 'file-text' },
      { name: 'goods_receipt', label: 'Goods Receipts', icon: 'package' },
      { name: 'invoice_receipt', label: 'Invoices', icon: 'file-invoice' },
      { name: 'payment', label: 'Payments', icon: 'credit-card' }
    ];

    // Build navigation HTML
    let navHtml = '<nav class="main-nav"><ul>';

    for (const entity of entities) {
      // Check if user can read this entity
      let canRead = true;
      if (userId) {
        try {
          canRead = await callFunctionAsUser('can_user_perform_action', {
            p_user_id: userId,
            p_entity_type: entity.name,
            p_action_name: 'read'
          });
        } catch {
          canRead = false;
        }
      }

      if (canRead) {
        navHtml += `
          <li>
            <a href="#" hx-get="/ui/${entity.name}/list" hx-target="#main-content" hx-push-url="true">
              <i class="fa fa-${entity.icon}"></i>
              <span>${entity.label}</span>
            </a>
          </li>
        `;
      }
    }

    navHtml += '</ul></nav>';

    reply
      .header('Content-Type', 'text/html; charset=utf-8')
      .send(navHtml);
  });

  /**
   * GET /ui/dashboard
   * Generate dashboard view with summary stats
   */
  fastify.get('/dashboard', async (request, reply) => {
    const userId = getUserId(request);

    // Simple dashboard HTML
    const html = `
<div class="dashboard">
  <h1>Dashboard</h1>
  <p>Welcome! Select an item from the navigation to get started.</p>

  <div class="dashboard-cards">
    <div class="card" hx-get="/ui/purchase_order/list" hx-target="#main-content" hx-trigger="click">
      <h3>Purchase Orders</h3>
      <p>Manage purchase orders and approvals</p>
    </div>

    <div class="card" hx-get="/ui/goods_receipt/list" hx-target="#main-content" hx-trigger="click">
      <h3>Goods Receipts</h3>
      <p>Record received goods</p>
    </div>

    <div class="card" hx-get="/ui/invoice_receipt/list" hx-target="#main-content" hx-trigger="click">
      <h3>Invoices</h3>
      <p>Process vendor invoices</p>
    </div>

    <div class="card" hx-get="/ui/payment/list" hx-target="#main-content" hx-trigger="click">
      <h3>Payments</h3>
      <p>Manage payments</p>
    </div>
  </div>
</div>
    `.trim();

    reply
      .header('Content-Type', 'text/html; charset=utf-8')
      .send(html);
  });
}
