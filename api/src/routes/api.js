/**
 * Business Logic API Routes
 * Routes for CRUD operations and workflow actions
 */

import { callFunctionAsUser, parseResult, isSuccess, getErrorMessage } from '../db/connection.js';
import { getUserId } from '../middleware/auth.js';
import { errors } from '../middleware/errorHandler.js';

/**
 * Valid entity types - prevents arbitrary entity access
 */
const VALID_ENTITIES = [
  'supplier',
  'purchase_order',
  'goods_receipt',
  'invoice_receipt',
  'payment'
];

/**
 * Updatable fields per entity - prevents mass assignment attacks
 */
const UPDATABLE_FIELDS = {
  supplier: ['supplier_name', 'contact_name', 'email', 'phone', 'address', 'city', 'country', 'payment_terms_days', 'is_active', 'notes'],
  purchase_order: ['expected_delivery_date', 'notes'],
  goods_receipt: ['notes'],
  invoice_receipt: ['notes'],
  payment: ['reference_number', 'notes']
};

/**
 * HTML escape function to prevent XSS
 */
function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  const s = String(str);
  const map = {
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  };
  return s.replace(/[&<>"']/g, m => map[m]);
}

/**
 * Validate entity type
 */
function validateEntity(entity) {
  if (!VALID_ENTITIES.includes(entity)) {
    throw errors.badRequest(`Invalid entity type`);
  }
}

/**
 * Validate UUID format
 */
function isValidUUID(str) {
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
}

/**
 * Filter updates to only allowed fields (mass assignment protection)
 */
function filterUpdates(entity, updates) {
  const allowedFields = UPDATABLE_FIELDS[entity] || [];
  const filtered = {};

  for (const field of allowedFields) {
    if (field in updates) {
      filtered[field] = updates[field];
    }
  }

  return filtered;
}

/**
 * Helper to handle database function results
 * Returns HTMX-friendly response for success/failure
 */
function handleResult(result, reply, successMessage = null) {
  const isHtmx = true; // All these endpoints are called via HTMX

  if (isSuccess(result)) {
    const message = successMessage || result.message || 'Operation completed successfully';

    if (isHtmx) {
      // Return success toast/notification - escape message to prevent XSS
      reply
        .header('Content-Type', 'text/html; charset=utf-8')
        .header('HX-Trigger', JSON.stringify({
          showToast: { message: escapeHtml(message), type: 'success' }
        }))
        .send(`<div class="success-message">${escapeHtml(message)}</div>`);
    } else {
      reply.send(result);
    }
  } else {
    const message = getErrorMessage(result);

    if (isHtmx) {
      // Escape error message to prevent XSS from database errors
      reply
        .code(400)
        .header('Content-Type', 'text/html; charset=utf-8')
        .header('HX-Trigger', JSON.stringify({
          showToast: { message: escapeHtml(message), type: 'error' }
        }))
        .send(`<div class="error-message">${escapeHtml(message)}</div>`);
    } else {
      reply.code(400).send({ error: message });
    }
  }
}

export default async function apiRoutes(fastify) {

  // =========================================================================
  // PURCHASE ORDER ROUTES
  // =========================================================================

  /**
   * POST /api/purchase_order
   * Create a new purchase order
   */
  fastify.post('/purchase_order', async (request, reply) => {
    const userId = getUserId(request);
    const {
      supplier_id,
      po_date,
      expected_delivery_date,
      currency = 'USD',
      notes,
      lines = []
    } = request.body;

    if (!supplier_id) {
      throw errors.badRequest('Supplier is required');
    }

    const result = await callFunctionAsUser('create_purchase_order', {
      p_user_id: userId,
      p_supplier_id: supplier_id,
      p_po_date: po_date || new Date().toISOString().split('T')[0],
      p_expected_delivery_date: expected_delivery_date || null,
      p_currency: currency,
      p_notes: notes || null,
      p_lines: lines
    });

    handleResult(result, reply, `Purchase order ${result.po_number} created`);
  });

  /**
   * PUT /api/purchase_order/:id
   * Update a purchase order
   */
  fastify.put('/purchase_order/:id', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;

    const result = await callFunctionAsUser('update_record', {
      p_user_id: userId,
      p_entity_type: 'purchase_order',
      p_record_id: id,
      p_updates: request.body
    });

    handleResult(result, reply, 'Purchase order updated');
  });

  /**
   * POST /api/purchase_order/:id/submit
   * Submit a PO for approval
   */
  fastify.post('/purchase_order/:id/submit', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;

    const result = await callFunctionAsUser('submit_purchase_order', {
      p_user_id: userId,
      p_po_id: id
    });

    handleResult(result, reply, 'Purchase order submitted for approval');
  });

  /**
   * POST /api/purchase_order/:id/approve
   * Approve a submitted PO
   */
  fastify.post('/purchase_order/:id/approve', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;
    const { notes } = request.body || {};

    const result = await callFunctionAsUser('approve_purchase_order', {
      p_user_id: userId,
      p_po_id: id,
      p_approval_notes: notes || null
    });

    handleResult(result, reply, 'Purchase order approved');
  });

  /**
   * POST /api/purchase_order/:id/reject
   * Reject a submitted PO
   */
  fastify.post('/purchase_order/:id/reject', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;
    const { reason } = request.body || {};

    if (!reason) {
      throw errors.badRequest('Rejection reason is required');
    }

    const result = await callFunctionAsUser('reject_purchase_order', {
      p_user_id: userId,
      p_po_id: id,
      p_rejection_reason: reason
    });

    handleResult(result, reply, 'Purchase order rejected');
  });

  /**
   * DELETE /api/purchase_order/:id
   * Cancel/soft delete a PO
   */
  fastify.delete('/purchase_order/:id', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;
    const { reason } = request.body || {};

    const result = await callFunctionAsUser('cancel_purchase_order', {
      p_user_id: userId,
      p_po_id: id,
      p_cancellation_reason: reason || 'Cancelled by user'
    });

    handleResult(result, reply, 'Purchase order cancelled');
  });

  // =========================================================================
  // GOODS RECEIPT ROUTES
  // =========================================================================

  /**
   * POST /api/goods_receipt
   * Create a goods receipt
   */
  fastify.post('/goods_receipt', async (request, reply) => {
    const userId = getUserId(request);
    const {
      po_id,
      receipt_date,
      delivery_note_number,
      notes,
      lines = []
    } = request.body;

    if (!po_id) {
      throw errors.badRequest('Purchase order is required');
    }

    const result = await callFunctionAsUser('create_goods_receipt', {
      p_user_id: userId,
      p_po_id: po_id,
      p_receipt_date: receipt_date || new Date().toISOString().split('T')[0],
      p_delivery_note_number: delivery_note_number || null,
      p_notes: notes || null,
      p_lines: lines
    });

    handleResult(result, reply, `Goods receipt ${result.gr_number} created`);
  });

  /**
   * POST /api/goods_receipt/:id/accept
   * Accept a goods receipt (QC passed)
   */
  fastify.post('/goods_receipt/:id/accept', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;
    const { notes } = request.body || {};

    const result = await callFunctionAsUser('accept_goods_receipt', {
      p_user_id: userId,
      p_gr_id: id,
      p_notes: notes || null
    });

    handleResult(result, reply, 'Goods receipt accepted');
  });

  /**
   * POST /api/goods_receipt/:id/reject
   * Reject a goods receipt (QC failed)
   */
  fastify.post('/goods_receipt/:id/reject', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;
    const { reason } = request.body || {};

    if (!reason) {
      throw errors.badRequest('Rejection reason is required');
    }

    const result = await callFunctionAsUser('reject_goods_receipt', {
      p_user_id: userId,
      p_gr_id: id,
      p_rejection_reason: reason
    });

    handleResult(result, reply, 'Goods receipt rejected');
  });

  // =========================================================================
  // INVOICE RECEIPT ROUTES
  // =========================================================================

  /**
   * POST /api/invoice_receipt
   * Create an invoice receipt
   */
  fastify.post('/invoice_receipt', async (request, reply) => {
    const userId = getUserId(request);
    const {
      po_id,
      vendor_invoice_number,
      invoice_date,
      due_date,
      currency = 'USD',
      notes,
      lines = []
    } = request.body;

    if (!po_id) {
      throw errors.badRequest('Purchase order is required');
    }
    if (!vendor_invoice_number) {
      throw errors.badRequest('Vendor invoice number is required');
    }

    const result = await callFunctionAsUser('create_invoice_receipt', {
      p_user_id: userId,
      p_po_id: po_id,
      p_vendor_invoice_number: vendor_invoice_number,
      p_invoice_date: invoice_date || new Date().toISOString().split('T')[0],
      p_due_date: due_date || null,
      p_currency: currency,
      p_notes: notes || null,
      p_lines: lines
    });

    handleResult(result, reply, `Invoice ${result.invoice_number} created`);
  });

  /**
   * POST /api/invoice_receipt/:id/approve_variance
   * Approve invoice with variances
   */
  fastify.post('/invoice_receipt/:id/approve_variance', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;
    const { notes } = request.body || {};

    const result = await callFunctionAsUser('approve_invoice_variance', {
      p_user_id: userId,
      p_invoice_id: id,
      p_approval_notes: notes || null
    });

    handleResult(result, reply, 'Invoice variance approved');
  });

  /**
   * GET /api/invoice_receipt/:id/matching
   * Get 3-way matching details
   */
  fastify.get('/invoice_receipt/:id/matching', async (request, reply) => {
    const { id } = request.params;

    const result = await callFunctionAsUser('get_invoice_matching_summary', {
      p_invoice_id: id
    });

    reply.send(result);
  });

  // =========================================================================
  // PAYMENT ROUTES
  // =========================================================================

  /**
   * POST /api/payment
   * Create a payment
   */
  fastify.post('/payment', async (request, reply) => {
    const userId = getUserId(request);
    const {
      invoice_id,
      amount,
      payment_method = 'bank_transfer',
      payment_date,
      reference_number,
      notes
    } = request.body;

    if (!invoice_id) {
      throw errors.badRequest('Invoice is required');
    }
    if (!amount || amount <= 0) {
      throw errors.badRequest('Valid amount is required');
    }

    const result = await callFunctionAsUser('create_payment', {
      p_user_id: userId,
      p_invoice_id: invoice_id,
      p_amount: parseFloat(amount),
      p_payment_method: payment_method,
      p_payment_date: payment_date || new Date().toISOString().split('T')[0],
      p_reference_number: reference_number || null,
      p_notes: notes || null
    });

    handleResult(result, reply, `Payment ${result.payment_number} created`);
  });

  /**
   * POST /api/payment/:id/process
   * Process a pending payment
   */
  fastify.post('/payment/:id/process', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;
    const { transaction_id } = request.body || {};

    const result = await callFunctionAsUser('process_payment', {
      p_user_id: userId,
      p_payment_id: id,
      p_transaction_id: transaction_id || null
    });

    handleResult(result, reply, 'Payment processed');
  });

  /**
   * POST /api/payment/:id/clear
   * Clear a processed payment (bank reconciliation)
   */
  fastify.post('/payment/:id/clear', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;
    const { cleared_date, bank_reference } = request.body || {};

    const result = await callFunctionAsUser('clear_payment', {
      p_user_id: userId,
      p_payment_id: id,
      p_cleared_date: cleared_date || new Date().toISOString().split('T')[0],
      p_bank_reference: bank_reference || null
    });

    handleResult(result, reply, 'Payment cleared');
  });

  /**
   * POST /api/payment/:id/cancel
   * Cancel a pending payment
   */
  fastify.post('/payment/:id/cancel', async (request, reply) => {
    const userId = getUserId(request);
    const { id } = request.params;
    const { reason } = request.body || {};

    if (!reason) {
      throw errors.badRequest('Cancellation reason is required');
    }

    const result = await callFunctionAsUser('cancel_payment', {
      p_user_id: userId,
      p_payment_id: id,
      p_cancellation_reason: reason
    });

    handleResult(result, reply, 'Payment cancelled');
  });

  // =========================================================================
  // GENERIC CRUD ROUTES
  // =========================================================================

  /**
   * PUT /api/:entity/:id
   * Update any entity record
   */
  fastify.put('/:entity/:id', async (request, reply) => {
    const userId = getUserId(request);
    const { entity, id } = request.params;

    const result = await callFunctionAsUser('update_record', {
      p_user_id: userId,
      p_entity_type: entity,
      p_record_id: id,
      p_updates: request.body
    });

    handleResult(result, reply, `${entity} updated`);
  });

  /**
   * DELETE /api/:entity/:id
   * Soft delete any entity record
   */
  fastify.delete('/:entity/:id', async (request, reply) => {
    const userId = getUserId(request);
    const { entity, id } = request.params;
    const { reason } = request.body || {};

    const result = await callFunctionAsUser('soft_delete_record', {
      p_user_id: userId,
      p_entity_type: entity,
      p_record_id: id,
      p_reason: reason || null
    });

    handleResult(result, reply, `${entity} deleted`);
  });

  /**
   * POST /api/:entity/:id/restore
   * Restore a soft-deleted record
   */
  fastify.post('/:entity/:id/restore', async (request, reply) => {
    const userId = getUserId(request);
    const { entity, id } = request.params;

    const result = await callFunctionAsUser('restore_record', {
      p_user_id: userId,
      p_entity_type: entity,
      p_record_id: id
    });

    handleResult(result, reply, `${entity} restored`);
  });

  // =========================================================================
  // DATA FETCH ROUTES (JSON)
  // =========================================================================

  /**
   * GET /api/:entity
   * Fetch list data as JSON
   */
  fastify.get('/:entity', async (request, reply) => {
    const userId = getUserId(request);
    const { entity } = request.params;
    const {
      page = 1,
      page_size = 25,
      sort = null,
      sort_dir = 'ASC',
      ...filters
    } = request.query;

    const result = await callFunctionAsUser('fetch_list_data', {
      p_user_id: userId,
      p_entity_type: entity,
      p_filters: filters,
      p_sort_field: sort,
      p_sort_direction: sort_dir.toUpperCase(),
      p_page_size: parseInt(page_size, 10),
      p_page_number: parseInt(page, 10)
    });

    reply.send(result);
  });

  /**
   * GET /api/:entity/:id
   * Fetch single record as JSON
   */
  fastify.get('/:entity/:id', async (request, reply) => {
    const userId = getUserId(request);
    const { entity, id } = request.params;

    const result = await callFunctionAsUser('fetch_form_data', {
      p_user_id: userId,
      p_entity_type: entity,
      p_record_id: id,
      p_view_type: 'form_view'
    });

    reply.send(result);
  });
}
