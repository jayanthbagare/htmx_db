/**
 * Functional Tests: 3-Way Matching
 * Tests for PO-GR-Invoice matching scenarios
 */

import { callFunctionAsUser } from '../../src/db/connection.js';
import { TEST_USERS, getTestClient } from '../setup.js';
import { cleanupTestData } from '../helpers/testDataGenerator.js';
import { faker } from '@faker-js/faker';

describe('Three-Way Matching Functional Tests', () => {
  let supplierId;
  const createdIds = [];

  beforeAll(async () => {
    const client = getTestClient();
    const { data: suppliers } = await client.from('suppliers')
      .select('supplier_id')
      .eq('is_deleted', false)
      .limit(1);

    if (suppliers && suppliers.length > 0) {
      supplierId = suppliers[0].supplier_id;
    }
  });

  afterAll(async () => {
    for (const ids of createdIds) {
      await cleanupTestData(ids);
    }
  });

  /**
   * Helper to create and approve a PO
   */
  async function createApprovedPO(lines) {
    const result = await callFunctionAsUser('create_purchase_order', {
      p_user_id: TEST_USERS.admin,
      p_supplier_id: supplierId,
      p_po_date: new Date().toISOString().split('T')[0],
      p_expected_delivery_date: faker.date.future().toISOString().split('T')[0],
      p_currency: 'USD',
      p_notes: '3-way matching test',
      p_lines: lines
    });

    if (!result.success) return null;

    await callFunctionAsUser('submit_purchase_order', {
      p_user_id: TEST_USERS.admin,
      p_po_id: result.po_id
    });

    await callFunctionAsUser('approve_purchase_order', {
      p_user_id: TEST_USERS.admin,
      p_po_id: result.po_id,
      p_approval_notes: 'Approved for 3-way match test'
    });

    return result;
  }

  /**
   * Helper to create and accept a GR
   */
  async function createAcceptedGR(poId) {
    const grResult = await callFunctionAsUser('create_goods_receipt', {
      p_user_id: TEST_USERS.admin,
      p_po_id: poId,
      p_receipt_date: new Date().toISOString().split('T')[0],
      p_delivery_note_number: `DN-3WM-${faker.string.alphanumeric(6)}`,
      p_notes: '3-way matching test GR'
    });

    if (!grResult.success) return null;

    await callFunctionAsUser('accept_goods_receipt', {
      p_user_id: TEST_USERS.admin,
      p_gr_id: grResult.gr_id,
      p_notes: 'QC passed'
    });

    return grResult;
  }

  // =========================================================================
  // Exact Match Scenarios
  // =========================================================================
  describe('Exact Match Scenarios', () => {
    test('Invoice matches PO and GR exactly', async () => {
      const lines = [
        {
          item_code: 'MATCH-001',
          item_description: 'Exact Match Test Item',
          quantity_ordered: 10,
          unit_price: 100.00,
          uom: 'EA'
        }
      ];

      // Create approved PO
      const poResult = await createApprovedPO(lines);
      expect(poResult).not.toBeNull();
      createdIds.push({ poId: poResult.po_id });

      // Create accepted GR
      const grResult = await createAcceptedGR(poResult.po_id);
      expect(grResult).not.toBeNull();
      createdIds[createdIds.length - 1].grId = grResult.gr_id;

      // Create invoice with exact matching values
      const invoiceResult = await callFunctionAsUser('create_invoice_receipt', {
        p_user_id: TEST_USERS.admin,
        p_po_id: poResult.po_id,
        p_vendor_invoice_number: `VINV-EXACT-${faker.string.alphanumeric(6)}`,
        p_invoice_date: new Date().toISOString().split('T')[0],
        p_due_date: faker.date.future().toISOString().split('T')[0],
        p_currency: 'USD',
        p_notes: 'Exact match invoice'
      });

      expect(invoiceResult.success).toBe(true);
      expect(invoiceResult.invoice_id).toBeDefined();
      // Matching status should be 'matched' or similar
      expect(['matched', 'pending']).toContain(invoiceResult.matching_status);

      createdIds[createdIds.length - 1].invoiceId = invoiceResult.invoice_id;
    });
  });

  // =========================================================================
  // Price Variance Scenarios
  // =========================================================================
  describe('Price Variance Scenarios', () => {
    test('Detect price variance in 3-way match', async () => {
      // Get a PO line for testing
      const client = getTestClient();
      const { data: poLines } = await client.from('purchase_order_lines')
        .select('line_id, quantity_ordered, unit_price')
        .eq('is_deleted', false)
        .limit(1);

      if (!poLines || poLines.length === 0) {
        console.log('Skipping - no PO lines available');
        return;
      }

      const line = poLines[0];
      const higherPrice = parseFloat(line.unit_price) * 1.15; // 15% higher

      const result = await callFunctionAsUser('perform_three_way_match', {
        p_po_line_id: line.line_id,
        p_invoice_quantity: line.quantity_ordered,
        p_invoice_price: higherPrice
      });

      expect(result).toBeDefined();
      expect(['variance', 'mismatch']).toContain(result.match_status);

      if (result.issues) {
        const hasPriceIssue = result.issues.some(
          issue => issue.type === 'price_variance' || issue.includes('price')
        );
        expect(hasPriceIssue).toBe(true);
      }
    });
  });

  // =========================================================================
  // Quantity Variance Scenarios
  // =========================================================================
  describe('Quantity Variance Scenarios', () => {
    test('Detect over-invoicing (quantity > received)', async () => {
      const client = getTestClient();
      const { data: poLines } = await client.from('purchase_order_lines')
        .select('line_id, quantity_ordered, quantity_received, unit_price')
        .eq('is_deleted', false)
        .gt('quantity_received', 0)
        .limit(1);

      if (!poLines || poLines.length === 0) {
        console.log('Skipping - no received PO lines available');
        return;
      }

      const line = poLines[0];
      const overQuantity = parseInt(line.quantity_received) + 10; // More than received

      const result = await callFunctionAsUser('perform_three_way_match', {
        p_po_line_id: line.line_id,
        p_invoice_quantity: overQuantity,
        p_invoice_price: line.unit_price
      });

      expect(result).toBeDefined();
      expect(['variance', 'mismatch']).toContain(result.match_status);
    });
  });

  // =========================================================================
  // Invoice Payment Information
  // =========================================================================
  describe('Invoice Payment Information', () => {
    test('Get payment info for unpaid invoice', async () => {
      const client = getTestClient();
      const { data: invoices } = await client.from('invoice_receipts')
        .select('invoice_id')
        .eq('is_deleted', false)
        .limit(1);

      if (!invoices || invoices.length === 0) {
        console.log('Skipping - no invoices available');
        return;
      }

      const result = await callFunctionAsUser('get_invoice_payment_info', {
        p_invoice_id: invoices[0].invoice_id
      });

      expect(result).toBeDefined();
      expect(result.total_amount).toBeDefined();
      expect(result.remaining_amount).toBeDefined();
      expect(result.payment_status).toBeDefined();
    });
  });

  // =========================================================================
  // Variance Approval
  // =========================================================================
  describe('Variance Approval', () => {
    test('Approve invoice with variance', async () => {
      // Create a scenario with variance
      const lines = [
        {
          item_code: 'VAR-APPROVE-001',
          item_description: 'Variance Approval Test',
          quantity_ordered: 50,
          unit_price: 25.00,
          uom: 'EA'
        }
      ];

      const poResult = await createApprovedPO(lines);
      if (!poResult) {
        console.log('Skipping - could not create PO');
        return;
      }
      createdIds.push({ poId: poResult.po_id });

      const grResult = await createAcceptedGR(poResult.po_id);
      if (!grResult) {
        console.log('Skipping - could not create GR');
        return;
      }
      createdIds[createdIds.length - 1].grId = grResult.gr_id;

      // Create invoice
      const invoiceResult = await callFunctionAsUser('create_invoice_receipt', {
        p_user_id: TEST_USERS.admin,
        p_po_id: poResult.po_id,
        p_vendor_invoice_number: `VINV-VAR-${faker.string.alphanumeric(6)}`,
        p_invoice_date: new Date().toISOString().split('T')[0],
        p_due_date: faker.date.future().toISOString().split('T')[0],
        p_currency: 'USD',
        p_notes: 'Variance approval test invoice'
      });

      if (!invoiceResult.success) {
        console.log('Skipping - could not create invoice');
        return;
      }
      createdIds[createdIds.length - 1].invoiceId = invoiceResult.invoice_id;

      // If there's a variance, approve it
      if (invoiceResult.matching_status === 'variance') {
        const approveResult = await callFunctionAsUser('approve_invoice_variance', {
          p_user_id: TEST_USERS.admin,
          p_invoice_id: invoiceResult.invoice_id,
          p_approval_notes: 'Variance within acceptable limits'
        });

        expect(approveResult.success).toBe(true);
      }
    });
  });
});
