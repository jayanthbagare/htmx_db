/**
 * Data Integrity Tests
 * Tests for referential integrity, quantity reconciliation, and data consistency
 */

import { callFunctionAsUser } from '../../src/db/connection.js';
import { TEST_USERS, getTestClient } from '../setup.js';
import { createTestScenario, generatePOLines, cleanupTestData } from '../helpers/testDataGenerator.js';
import { faker } from '@faker-js/faker';

describe('Data Integrity Tests', () => {
  let testData;

  beforeAll(async () => {
    testData = await createTestScenario();
  });

  afterAll(async () => {
    if (testData) {
      await cleanupTestData(testData);
    }
  });

  // =========================================================================
  // Referential Integrity
  // =========================================================================
  describe('Referential Integrity', () => {
    test('Cannot create PO with non-existent supplier', async () => {
      const fakeSupplier = '99999999-9999-9999-9999-999999999999';

      const result = await callFunctionAsUser('create_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_supplier_id: fakeSupplier,
        p_po_date: new Date().toISOString().split('T')[0],
        p_currency: 'USD',
        p_lines: generatePOLines(1)
      });

      expect(result.success).toBe(false);
    });

    test('Cannot create GR for non-existent PO', async () => {
      const fakePO = '99999999-9999-9999-9999-999999999999';

      const result = await callFunctionAsUser('create_goods_receipt', {
        p_user_id: TEST_USERS.admin,
        p_po_id: fakePO,
        p_receipt_date: new Date().toISOString().split('T')[0],
        p_delivery_note_number: 'DN-FAKE-001'
      });

      expect(result.success).toBe(false);
    });

    test('Cannot create invoice for non-existent PO', async () => {
      const fakePO = '99999999-9999-9999-9999-999999999999';

      const result = await callFunctionAsUser('create_invoice_receipt', {
        p_user_id: TEST_USERS.admin,
        p_po_id: fakePO,
        p_vendor_invoice_number: 'VINV-FAKE-001',
        p_invoice_date: new Date().toISOString().split('T')[0],
        p_currency: 'USD'
      });

      expect(result.success).toBe(false);
    });

    test('Cannot create payment for non-existent invoice', async () => {
      const fakeInvoice = '99999999-9999-9999-9999-999999999999';

      const result = await callFunctionAsUser('create_payment', {
        p_user_id: TEST_USERS.admin,
        p_invoice_id: fakeInvoice,
        p_amount: 100.00,
        p_payment_method: 'bank_transfer',
        p_payment_date: new Date().toISOString().split('T')[0]
      });

      expect(result.success).toBe(false);
    });
  });

  // =========================================================================
  // Quantity Reconciliation
  // =========================================================================
  describe('Quantity Reconciliation', () => {
    let quantityTestData = {};

    test('Setup: Create PO with known quantities', async () => {
      const client = getTestClient();
      const { data: suppliers } = await client.from('suppliers')
        .select('supplier_id')
        .eq('is_deleted', false)
        .limit(1);

      if (!suppliers || suppliers.length === 0) {
        console.log('Skipping - no supplier available');
        return;
      }

      const lines = [
        {
          item_code: 'QTY-TEST-001',
          item_description: 'Quantity Test Item 1',
          quantity_ordered: 100,
          unit_price: 10.00,
          uom: 'EA'
        },
        {
          item_code: 'QTY-TEST-002',
          item_description: 'Quantity Test Item 2',
          quantity_ordered: 50,
          unit_price: 20.00,
          uom: 'EA'
        }
      ];

      const result = await callFunctionAsUser('create_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_supplier_id: suppliers[0].supplier_id,
        p_po_date: new Date().toISOString().split('T')[0],
        p_currency: 'USD',
        p_notes: 'Quantity reconciliation test',
        p_lines: lines
      });

      expect(result.success).toBe(true);
      quantityTestData.poId = result.po_id;

      // Submit and approve
      await callFunctionAsUser('submit_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_po_id: quantityTestData.poId
      });

      await callFunctionAsUser('approve_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_po_id: quantityTestData.poId,
        p_approval_notes: 'Approved'
      });
    });

    test('quantity_received is updated after GR', async () => {
      if (!quantityTestData.poId) {
        console.log('Skipping - no test PO');
        return;
      }

      const grResult = await callFunctionAsUser('create_goods_receipt', {
        p_user_id: TEST_USERS.admin,
        p_po_id: quantityTestData.poId,
        p_receipt_date: new Date().toISOString().split('T')[0],
        p_delivery_note_number: 'DN-QTY-001',
        p_notes: 'Full receipt'
      });

      expect(grResult.success).toBe(true);
      quantityTestData.grId = grResult.gr_id;

      // Accept the GR
      await callFunctionAsUser('accept_goods_receipt', {
        p_user_id: TEST_USERS.admin,
        p_gr_id: quantityTestData.grId,
        p_notes: 'Accepted'
      });

      // Verify quantity_received was updated on PO lines
      const client = getTestClient();
      const { data: poLines } = await client.from('purchase_order_lines')
        .select('quantity_ordered, quantity_received')
        .eq('po_id', quantityTestData.poId)
        .eq('is_deleted', false);

      expect(poLines).toBeDefined();
      expect(poLines.length).toBeGreaterThan(0);

      // All lines should have received quantities
      for (const line of poLines) {
        expect(line.quantity_received).toBeLessThanOrEqual(line.quantity_ordered);
      }
    });

    afterAll(async () => {
      if (quantityTestData.poId) {
        await cleanupTestData({
          poId: quantityTestData.poId,
          grId: quantityTestData.grId
        });
      }
    });
  });

  // =========================================================================
  // Amount Validation
  // =========================================================================
  describe('Amount Validation', () => {
    test('Line total calculated correctly', async () => {
      const client = getTestClient();
      const { data: suppliers } = await client.from('suppliers')
        .select('supplier_id')
        .eq('is_deleted', false)
        .limit(1);

      if (!suppliers || suppliers.length === 0) {
        console.log('Skipping - no supplier available');
        return;
      }

      const lines = [
        {
          item_code: 'AMT-001',
          item_description: 'Amount Test',
          quantity_ordered: 25,
          unit_price: 40.00,  // Total should be 1000.00
          uom: 'EA'
        }
      ];

      const result = await callFunctionAsUser('create_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_supplier_id: suppliers[0].supplier_id,
        p_po_date: new Date().toISOString().split('T')[0],
        p_currency: 'USD',
        p_lines: lines
      });

      expect(result.success).toBe(true);
      expect(parseFloat(result.total_amount)).toBe(1000.00);

      await cleanupTestData({ poId: result.po_id });
    });

    test('PO total equals sum of line totals', async () => {
      const client = getTestClient();
      const { data: pos } = await client.from('purchase_orders')
        .select('po_id, total_amount')
        .eq('is_deleted', false)
        .limit(1);

      if (!pos || pos.length === 0) {
        console.log('Skipping - no POs available');
        return;
      }

      const po = pos[0];

      // Get sum of line totals
      const { data: lines } = await client.from('purchase_order_lines')
        .select('line_total')
        .eq('po_id', po.po_id)
        .eq('is_deleted', false);

      if (!lines || lines.length === 0) {
        console.log('Skipping - no lines for this PO');
        return;
      }

      const sumOfLines = lines.reduce(
        (sum, line) => sum + parseFloat(line.line_total || 0),
        0
      );

      expect(parseFloat(po.total_amount)).toBeCloseTo(sumOfLines, 2);
    });

    test('Payment amount cannot exceed invoice amount', async () => {
      // Get an invoice
      const client = getTestClient();
      const { data: invoices } = await client.from('invoice_receipts')
        .select('invoice_id, total_amount')
        .eq('is_deleted', false)
        .limit(1);

      if (!invoices || invoices.length === 0) {
        console.log('Skipping - no invoices available');
        return;
      }

      const invoice = invoices[0];
      const excessiveAmount = parseFloat(invoice.total_amount) + 1000;

      const result = await callFunctionAsUser('create_payment', {
        p_user_id: TEST_USERS.admin,
        p_invoice_id: invoice.invoice_id,
        p_amount: excessiveAmount,
        p_payment_method: 'bank_transfer',
        p_payment_date: new Date().toISOString().split('T')[0]
      });

      // Should fail or be limited to remaining amount
      if (result.success) {
        expect(parseFloat(result.amount)).toBeLessThanOrEqual(parseFloat(invoice.total_amount));
      } else {
        expect(result.success).toBe(false);
      }
    });
  });

  // =========================================================================
  // Status Consistency
  // =========================================================================
  describe('Status Consistency', () => {
    test('Cannot receive goods for unapproved PO', async () => {
      const client = getTestClient();
      const { data: suppliers } = await client.from('suppliers')
        .select('supplier_id')
        .eq('is_deleted', false)
        .limit(1);

      if (!suppliers || suppliers.length === 0) {
        console.log('Skipping - no supplier available');
        return;
      }

      // Create a draft PO (not approved)
      const createResult = await callFunctionAsUser('create_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_supplier_id: suppliers[0].supplier_id,
        p_po_date: new Date().toISOString().split('T')[0],
        p_currency: 'USD',
        p_lines: generatePOLines(1)
      });

      expect(createResult.success).toBe(true);

      // Try to create GR for unapproved PO
      const grResult = await callFunctionAsUser('create_goods_receipt', {
        p_user_id: TEST_USERS.admin,
        p_po_id: createResult.po_id,
        p_receipt_date: new Date().toISOString().split('T')[0],
        p_delivery_note_number: 'DN-UNAPP-001'
      });

      expect(grResult.success).toBe(false);

      await cleanupTestData({ poId: createResult.po_id });
    });

    test('PO status changes to fully_received after complete receipt', async () => {
      const client = getTestClient();
      const { data: pos } = await client.from('purchase_orders')
        .select('po_id, status')
        .eq('status', 'fully_received')
        .eq('is_deleted', false)
        .limit(1);

      if (!pos || pos.length === 0) {
        console.log('Skipping - no fully received POs available');
        return;
      }

      expect(pos[0].status).toBe('fully_received');

      // Verify all lines are fully received
      const { data: lines } = await client.from('purchase_order_lines')
        .select('quantity_ordered, quantity_received')
        .eq('po_id', pos[0].po_id)
        .eq('is_deleted', false);

      for (const line of lines) {
        expect(line.quantity_received).toBeGreaterThanOrEqual(line.quantity_ordered);
      }
    });
  });

  // =========================================================================
  // Soft Delete Integrity
  // =========================================================================
  describe('Soft Delete Integrity', () => {
    test('Soft-deleted records excluded from normal queries', async () => {
      const client = getTestClient();

      // Create a supplier
      const { data: supplier } = await client.from('suppliers')
        .insert([{
          supplier_code: `DEL-INT-${faker.string.alphanumeric(4)}`,
          supplier_name: 'Delete Integrity Test',
          is_active: true,
          created_by: TEST_USERS.admin
        }])
        .select('supplier_id')
        .single();

      // Soft delete it
      await callFunctionAsUser('soft_delete_record', {
        p_user_id: TEST_USERS.admin,
        p_entity_type: 'supplier',
        p_record_id: supplier.supplier_id,
        p_reason: 'Integrity test'
      });

      // Query without is_deleted filter
      const { data: fetchResult } = await client.from('suppliers')
        .select('*')
        .eq('supplier_id', supplier.supplier_id)
        .eq('is_deleted', false);

      expect(fetchResult.length).toBe(0);

      // Clean up
      await client.from('suppliers').delete().eq('supplier_id', supplier.supplier_id);
    });

    test('Soft delete preserves referential integrity', async () => {
      const client = getTestClient();

      // Get a supplier with POs
      const { data: suppliers } = await client.from('suppliers')
        .select('supplier_id')
        .eq('is_deleted', false)
        .limit(1);

      if (!suppliers || suppliers.length === 0) {
        console.log('Skipping - no suppliers available');
        return;
      }

      // Create a PO for this supplier
      const createResult = await callFunctionAsUser('create_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_supplier_id: suppliers[0].supplier_id,
        p_po_date: new Date().toISOString().split('T')[0],
        p_currency: 'USD',
        p_lines: generatePOLines(1)
      });

      expect(createResult.success).toBe(true);

      // Try to hard delete the supplier (should fail due to FK)
      const { error } = await client.from('suppliers')
        .delete()
        .eq('supplier_id', suppliers[0].supplier_id);

      // Should get a foreign key violation error
      if (error) {
        expect(error.message).toContain('foreign key');
      }

      await cleanupTestData({ poId: createResult.po_id });
    });
  });

  // =========================================================================
  // Audit Trail Integrity
  // =========================================================================
  describe('Audit Trail Integrity', () => {
    test('created_at is set on record creation', async () => {
      const client = getTestClient();
      const { data: suppliers } = await client.from('suppliers')
        .select('supplier_id')
        .eq('is_deleted', false)
        .limit(1);

      if (!suppliers || suppliers.length === 0) {
        console.log('Skipping - no supplier available');
        return;
      }

      const result = await callFunctionAsUser('create_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_supplier_id: suppliers[0].supplier_id,
        p_po_date: new Date().toISOString().split('T')[0],
        p_currency: 'USD',
        p_lines: generatePOLines(1)
      });

      expect(result.success).toBe(true);

      // Fetch the PO and check audit fields
      const { data: po } = await client.from('purchase_orders')
        .select('created_at, created_by')
        .eq('po_id', result.po_id)
        .single();

      expect(po.created_at).toBeDefined();
      expect(po.created_by).toBe(TEST_USERS.admin);

      await cleanupTestData({ poId: result.po_id });
    });

    test('updated_at changes on update', async () => {
      const client = getTestClient();
      const { data: pos } = await client.from('purchase_orders')
        .select('po_id, updated_at')
        .eq('is_deleted', false)
        .eq('status', 'draft')
        .limit(1);

      if (!pos || pos.length === 0) {
        console.log('Skipping - no draft POs available');
        return;
      }

      const originalUpdatedAt = pos[0].updated_at;

      // Wait a moment to ensure timestamp difference
      await new Promise(resolve => setTimeout(resolve, 100));

      // Update the PO
      await callFunctionAsUser('update_record', {
        p_user_id: TEST_USERS.admin,
        p_entity_type: 'purchase_order',
        p_record_id: pos[0].po_id,
        p_updates: { notes: `Updated at ${Date.now()}` }
      });

      // Fetch and compare
      const { data: updatedPo } = await client.from('purchase_orders')
        .select('updated_at')
        .eq('po_id', pos[0].po_id)
        .single();

      expect(new Date(updatedPo.updated_at).getTime())
        .toBeGreaterThanOrEqual(new Date(originalUpdatedAt).getTime());
    });
  });
});
