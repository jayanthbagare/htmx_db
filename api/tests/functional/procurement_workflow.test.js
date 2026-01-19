/**
 * Functional Tests: Procurement Workflow
 * End-to-end tests for the complete P2P cycle
 */

import { callFunctionAsUser } from '../../src/db/connection.js';
import { TEST_USERS, getTestClient } from '../setup.js';
import { generatePOLines, cleanupTestData } from '../helpers/testDataGenerator.js';
import { faker } from '@faker-js/faker';

describe('Procurement Workflow Functional Tests', () => {
  let supplierId;
  const createdIds = [];

  beforeAll(async () => {
    // Get or create a test supplier
    const client = getTestClient();
    const { data: suppliers } = await client.from('suppliers')
      .select('supplier_id')
      .eq('is_deleted', false)
      .limit(1);

    if (suppliers && suppliers.length > 0) {
      supplierId = suppliers[0].supplier_id;
    } else {
      const { data: newSupplier } = await client.from('suppliers')
        .insert([{
          supplier_code: `TEST-${faker.string.alphanumeric(6)}`,
          supplier_name: 'Functional Test Supplier',
          is_active: true,
          created_by: TEST_USERS.admin
        }])
        .select('supplier_id')
        .single();
      supplierId = newSupplier.supplier_id;
    }
  });

  afterAll(async () => {
    // Cleanup all created test data
    for (const ids of createdIds) {
      await cleanupTestData(ids);
    }
  });

  // =========================================================================
  // Complete P2P Cycle
  // =========================================================================
  describe('Complete P2P Cycle', () => {
    let cycle = {};

    test('1. Create purchase order with lines', async () => {
      const lines = generatePOLines(3);
      const result = await callFunctionAsUser('create_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_supplier_id: supplierId,
        p_po_date: new Date().toISOString().split('T')[0],
        p_expected_delivery_date: faker.date.future().toISOString().split('T')[0],
        p_currency: 'USD',
        p_notes: 'Functional test PO',
        p_lines: lines
      });

      expect(result).toBeDefined();
      expect(result.success).toBe(true);
      expect(result.po_id).toBeDefined();
      expect(result.po_number).toBeDefined();
      expect(result.status).toBe('draft');
      expect(result.line_count).toBe(3);

      // Calculate expected total
      const expectedTotal = lines.reduce(
        (sum, line) => sum + (line.quantity_ordered * line.unit_price),
        0
      );
      expect(parseFloat(result.total_amount)).toBeCloseTo(expectedTotal, 2);

      cycle.poId = result.po_id;
      cycle.lines = lines;
      createdIds.push({ poId: cycle.poId });
    });

    test('2. Submit purchase order for approval', async () => {
      expect(cycle.poId).toBeDefined();

      const result = await callFunctionAsUser('submit_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_po_id: cycle.poId
      });

      expect(result).toBeDefined();
      expect(result.success).toBe(true);
      expect(result.new_status).toBe('submitted');
    });

    test('3. Cannot submit already submitted PO', async () => {
      expect(cycle.poId).toBeDefined();

      const result = await callFunctionAsUser('submit_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_po_id: cycle.poId
      });

      expect(result).toBeDefined();
      expect(result.success).toBe(false);
    });

    test('4. Approve purchase order', async () => {
      expect(cycle.poId).toBeDefined();

      const result = await callFunctionAsUser('approve_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_po_id: cycle.poId,
        p_approval_notes: 'Approved for functional testing'
      });

      expect(result).toBeDefined();
      expect(result.success).toBe(true);
      expect(result.new_status).toBe('approved');
    });

    test('5. Create goods receipt', async () => {
      expect(cycle.poId).toBeDefined();

      const result = await callFunctionAsUser('create_goods_receipt', {
        p_user_id: TEST_USERS.admin,
        p_po_id: cycle.poId,
        p_receipt_date: new Date().toISOString().split('T')[0],
        p_delivery_note_number: `DN-FUNC-${faker.string.alphanumeric(6)}`,
        p_notes: 'Functional test goods receipt'
      });

      expect(result).toBeDefined();
      expect(result.success).toBe(true);
      expect(result.gr_id).toBeDefined();
      expect(result.gr_number).toBeDefined();

      cycle.grId = result.gr_id;
      createdIds[createdIds.length - 1].grId = cycle.grId;
    });

    test('6. Accept goods receipt (QC pass)', async () => {
      expect(cycle.grId).toBeDefined();

      const result = await callFunctionAsUser('accept_goods_receipt', {
        p_user_id: TEST_USERS.admin,
        p_gr_id: cycle.grId,
        p_notes: 'All items passed QC'
      });

      expect(result).toBeDefined();
      expect(result.success).toBe(true);
      expect(result.new_status).toBe('accepted');
    });

    test('7. Create invoice receipt', async () => {
      expect(cycle.poId).toBeDefined();

      const result = await callFunctionAsUser('create_invoice_receipt', {
        p_user_id: TEST_USERS.admin,
        p_po_id: cycle.poId,
        p_vendor_invoice_number: `VINV-FUNC-${faker.string.alphanumeric(6)}`,
        p_invoice_date: new Date().toISOString().split('T')[0],
        p_due_date: faker.date.future().toISOString().split('T')[0],
        p_currency: 'USD',
        p_notes: 'Functional test invoice'
      });

      expect(result).toBeDefined();
      expect(result.success).toBe(true);
      expect(result.invoice_id).toBeDefined();
      expect(result.matching_status).toBeDefined();

      cycle.invoiceId = result.invoice_id;
      cycle.totalAmount = result.total_amount;
      createdIds[createdIds.length - 1].invoiceId = cycle.invoiceId;
    });

    test('8. Create payment for invoice', async () => {
      expect(cycle.invoiceId).toBeDefined();

      const result = await callFunctionAsUser('create_payment', {
        p_user_id: TEST_USERS.admin,
        p_invoice_id: cycle.invoiceId,
        p_amount: parseFloat(cycle.totalAmount),
        p_payment_method: 'bank_transfer',
        p_payment_date: new Date().toISOString().split('T')[0],
        p_reference_number: `PAY-FUNC-${faker.string.alphanumeric(6)}`,
        p_notes: 'Functional test payment'
      });

      expect(result).toBeDefined();
      expect(result.success).toBe(true);
      expect(result.payment_id).toBeDefined();
      expect(result.payment_number).toBeDefined();

      cycle.paymentId = result.payment_id;
      createdIds[createdIds.length - 1].paymentId = cycle.paymentId;
    });

    test('9. Process payment', async () => {
      expect(cycle.paymentId).toBeDefined();

      const result = await callFunctionAsUser('process_payment', {
        p_user_id: TEST_USERS.admin,
        p_payment_id: cycle.paymentId,
        p_transaction_id: `TXN-${faker.string.alphanumeric(10)}`
      });

      expect(result).toBeDefined();
      expect(result.success).toBe(true);
      expect(result.new_status).toBe('processed');
    });

    test('10. Clear payment', async () => {
      expect(cycle.paymentId).toBeDefined();

      const result = await callFunctionAsUser('clear_payment', {
        p_user_id: TEST_USERS.admin,
        p_payment_id: cycle.paymentId,
        p_cleared_date: new Date().toISOString().split('T')[0],
        p_bank_reference: `BANK-${faker.string.alphanumeric(8)}`
      });

      expect(result).toBeDefined();
      expect(result.success).toBe(true);
      expect(result.new_status).toBe('cleared');
    });
  });

  // =========================================================================
  // Status Transitions
  // =========================================================================
  describe('PO Status Transitions', () => {
    test('Valid transition: draft -> submitted', async () => {
      const result = await callFunctionAsUser('validate_po_status_transition', {
        p_current_status: 'draft',
        p_new_status: 'submitted'
      });

      expect(result).toBe(true);
    });

    test('Valid transition: submitted -> approved', async () => {
      const result = await callFunctionAsUser('validate_po_status_transition', {
        p_current_status: 'submitted',
        p_new_status: 'approved'
      });

      expect(result).toBe(true);
    });

    test('Invalid transition: draft -> approved', async () => {
      const result = await callFunctionAsUser('validate_po_status_transition', {
        p_current_status: 'draft',
        p_new_status: 'approved'
      });

      expect(result).toBe(false);
    });

    test('Invalid transition: cancelled -> approved', async () => {
      const result = await callFunctionAsUser('validate_po_status_transition', {
        p_current_status: 'cancelled',
        p_new_status: 'approved'
      });

      expect(result).toBe(false);
    });
  });

  // =========================================================================
  // Partial Receipts
  // =========================================================================
  describe('Partial Receipts', () => {
    let partialTestData = {};

    test('Create PO for partial receipt test', async () => {
      const lines = [
        {
          item_code: 'PARTIAL-001',
          item_description: 'Partial Receipt Test Item',
          quantity_ordered: 100,
          unit_price: 10.00,
          uom: 'EA'
        }
      ];

      const result = await callFunctionAsUser('create_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_supplier_id: supplierId,
        p_po_date: new Date().toISOString().split('T')[0],
        p_currency: 'USD',
        p_notes: 'Partial receipt test PO',
        p_lines: lines
      });

      expect(result.success).toBe(true);
      partialTestData.poId = result.po_id;
      createdIds.push({ poId: partialTestData.poId });

      // Submit and approve
      await callFunctionAsUser('submit_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_po_id: partialTestData.poId
      });

      await callFunctionAsUser('approve_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_po_id: partialTestData.poId,
        p_approval_notes: 'Approved'
      });
    });

    test('First partial goods receipt (50 of 100)', async () => {
      const result = await callFunctionAsUser('create_goods_receipt', {
        p_user_id: TEST_USERS.admin,
        p_po_id: partialTestData.poId,
        p_receipt_date: new Date().toISOString().split('T')[0],
        p_delivery_note_number: 'DN-PARTIAL-1',
        p_notes: 'First partial receipt'
      });

      expect(result.success).toBe(true);
      partialTestData.gr1Id = result.gr_id;
      createdIds[createdIds.length - 1].grId = partialTestData.gr1Id;

      // Accept the receipt
      await callFunctionAsUser('accept_goods_receipt', {
        p_user_id: TEST_USERS.admin,
        p_gr_id: partialTestData.gr1Id,
        p_notes: 'QC passed'
      });
    });
  });

  // =========================================================================
  // PO Cancellation
  // =========================================================================
  describe('PO Cancellation', () => {
    test('Can cancel draft PO', async () => {
      // Create a draft PO
      const lines = generatePOLines(1);
      const createResult = await callFunctionAsUser('create_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_supplier_id: supplierId,
        p_po_date: new Date().toISOString().split('T')[0],
        p_currency: 'USD',
        p_lines: lines
      });

      expect(createResult.success).toBe(true);
      const poId = createResult.po_id;
      createdIds.push({ poId });

      // Cancel it
      const cancelResult = await callFunctionAsUser('cancel_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_po_id: poId,
        p_cancellation_reason: 'Test cancellation'
      });

      expect(cancelResult.success).toBe(true);
      expect(cancelResult.new_status).toBe('cancelled');
    });
  });

  // =========================================================================
  // Generic CRUD Operations
  // =========================================================================
  describe('Generic CRUD Operations', () => {
    test('Update record changes fields', async () => {
      // Create a test PO
      const lines = generatePOLines(1);
      const createResult = await callFunctionAsUser('create_purchase_order', {
        p_user_id: TEST_USERS.admin,
        p_supplier_id: supplierId,
        p_po_date: new Date().toISOString().split('T')[0],
        p_currency: 'USD',
        p_lines: lines
      });

      expect(createResult.success).toBe(true);
      const poId = createResult.po_id;
      createdIds.push({ poId });

      // Update the notes
      const updateResult = await callFunctionAsUser('update_record', {
        p_user_id: TEST_USERS.admin,
        p_entity_type: 'purchase_order',
        p_record_id: poId,
        p_updates: { notes: 'Updated notes via CRUD test' }
      });

      expect(updateResult.success).toBe(true);
      expect(updateResult.fields_updated).toBeGreaterThan(0);
    });

    test('Soft delete and restore', async () => {
      // Create a test supplier
      const client = getTestClient();
      const { data: supplier } = await client.from('suppliers')
        .insert([{
          supplier_code: `DEL-${faker.string.alphanumeric(6)}`,
          supplier_name: 'Delete Test Supplier',
          is_active: true,
          created_by: TEST_USERS.admin
        }])
        .select('supplier_id')
        .single();

      const supplierId = supplier.supplier_id;

      // Soft delete
      const deleteResult = await callFunctionAsUser('soft_delete_record', {
        p_user_id: TEST_USERS.admin,
        p_entity_type: 'supplier',
        p_record_id: supplierId,
        p_reason: 'Testing soft delete'
      });

      expect(deleteResult.success).toBe(true);

      // Verify deleted
      const { data: deletedSupplier } = await client.from('suppliers')
        .select('is_deleted')
        .eq('supplier_id', supplierId)
        .single();

      expect(deletedSupplier.is_deleted).toBe(true);

      // Restore
      const restoreResult = await callFunctionAsUser('restore_record', {
        p_user_id: TEST_USERS.admin,
        p_entity_type: 'supplier',
        p_record_id: supplierId
      });

      expect(restoreResult.success).toBe(true);

      // Verify restored
      const { data: restoredSupplier } = await client.from('suppliers')
        .select('is_deleted')
        .eq('supplier_id', supplierId)
        .single();

      expect(restoredSupplier.is_deleted).toBe(false);

      // Clean up
      await client.from('suppliers').delete().eq('supplier_id', supplierId);
    });
  });
});
