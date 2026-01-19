/**
 * Test Data Generator
 * Generates realistic test data for P2P workflow testing
 */

import { faker } from '@faker-js/faker';
import { callFunctionAsUser } from '../../src/db/connection.js';
import { TEST_USERS } from '../setup.js';

/**
 * Generate a random supplier
 */
export function generateSupplier() {
  return {
    supplier_code: `SUP-${faker.string.alphanumeric(6).toUpperCase()}`,
    supplier_name: faker.company.name(),
    contact_name: faker.person.fullName(),
    email: faker.internet.email(),
    phone: faker.phone.number(),
    address: faker.location.streetAddress(),
    city: faker.location.city(),
    country: faker.location.country(),
    payment_terms_days: faker.helpers.arrayElement([15, 30, 45, 60, 90]),
    is_active: true
  };
}

/**
 * Generate purchase order lines
 */
export function generatePOLines(count = 3) {
  const lines = [];
  for (let i = 0; i < count; i++) {
    lines.push({
      item_code: `ITEM-${faker.string.alphanumeric(6).toUpperCase()}`,
      item_description: faker.commerce.productName(),
      quantity_ordered: faker.number.int({ min: 1, max: 100 }),
      unit_price: parseFloat(faker.commerce.price({ min: 10, max: 1000 })),
      uom: faker.helpers.arrayElement(['EA', 'PC', 'BOX', 'KG', 'LT'])
    });
  }
  return lines;
}

/**
 * Generate a purchase order payload
 */
export function generatePurchaseOrder(supplierId, lineCount = 3) {
  return {
    supplier_id: supplierId,
    po_date: faker.date.recent().toISOString().split('T')[0],
    expected_delivery_date: faker.date.future().toISOString().split('T')[0],
    currency: faker.helpers.arrayElement(['USD', 'EUR', 'GBP']),
    notes: faker.lorem.sentence(),
    lines: generatePOLines(lineCount)
  };
}

/**
 * Create a complete P2P test scenario
 * Returns all created entities for verification
 */
export async function createTestScenario(options = {}) {
  const userId = options.userId || TEST_USERS.admin;
  const scenario = {};

  // 1. Get or create a supplier
  const client = (await import('../../src/db/connection.js')).getSupabaseAdmin();
  const { data: suppliers } = await client.from('suppliers')
    .select('supplier_id')
    .eq('is_deleted', false)
    .limit(1);

  if (suppliers && suppliers.length > 0) {
    scenario.supplierId = suppliers[0].supplier_id;
  } else {
    // Create a test supplier directly
    const supplierData = generateSupplier();
    const { data: newSupplier } = await client.from('suppliers')
      .insert([{ ...supplierData, created_by: userId }])
      .select('supplier_id')
      .single();
    scenario.supplierId = newSupplier.supplier_id;
  }

  // 2. Create a purchase order
  const poPayload = generatePurchaseOrder(scenario.supplierId, options.lineCount || 3);
  const poResult = await callFunctionAsUser('create_purchase_order', {
    p_user_id: userId,
    p_supplier_id: poPayload.supplier_id,
    p_po_date: poPayload.po_date,
    p_expected_delivery_date: poPayload.expected_delivery_date,
    p_currency: poPayload.currency,
    p_notes: poPayload.notes,
    p_lines: poPayload.lines
  });

  if (poResult && poResult.success) {
    scenario.poId = poResult.po_id;
    scenario.poNumber = poResult.po_number;
    scenario.poLines = poPayload.lines;
    scenario.totalAmount = poResult.total_amount;
  }

  return scenario;
}

/**
 * Create a full P2P cycle for testing
 * Goes through: PO -> Submit -> Approve -> GR -> Invoice -> Payment
 */
export async function createFullP2PCycle(options = {}) {
  const userId = options.userId || TEST_USERS.admin;
  const cycle = await createTestScenario(options);

  if (!cycle.poId) {
    throw new Error('Failed to create purchase order');
  }

  // Submit PO
  const submitResult = await callFunctionAsUser('submit_purchase_order', {
    p_user_id: userId,
    p_po_id: cycle.poId
  });
  cycle.submitted = submitResult?.success;

  // Approve PO
  const approveResult = await callFunctionAsUser('approve_purchase_order', {
    p_user_id: userId,
    p_po_id: cycle.poId,
    p_approval_notes: 'Approved for testing'
  });
  cycle.approved = approveResult?.success;

  // Create Goods Receipt
  if (cycle.approved) {
    const grResult = await callFunctionAsUser('create_goods_receipt', {
      p_user_id: userId,
      p_po_id: cycle.poId,
      p_receipt_date: new Date().toISOString().split('T')[0],
      p_delivery_note_number: `DN-${faker.string.alphanumeric(8).toUpperCase()}`,
      p_notes: 'Test goods receipt'
    });

    if (grResult?.success) {
      cycle.grId = grResult.gr_id;
      cycle.grNumber = grResult.gr_number;

      // Accept the goods receipt
      const acceptResult = await callFunctionAsUser('accept_goods_receipt', {
        p_user_id: userId,
        p_gr_id: cycle.grId,
        p_notes: 'QC passed'
      });
      cycle.grAccepted = acceptResult?.success;
    }
  }

  // Create Invoice
  if (cycle.grAccepted) {
    const invoiceResult = await callFunctionAsUser('create_invoice_receipt', {
      p_user_id: userId,
      p_po_id: cycle.poId,
      p_vendor_invoice_number: `INV-${faker.string.alphanumeric(8).toUpperCase()}`,
      p_invoice_date: new Date().toISOString().split('T')[0],
      p_due_date: faker.date.future().toISOString().split('T')[0],
      p_currency: 'USD',
      p_notes: 'Test invoice'
    });

    if (invoiceResult?.success) {
      cycle.invoiceId = invoiceResult.invoice_id;
      cycle.invoiceNumber = invoiceResult.invoice_number;
      cycle.matchingStatus = invoiceResult.matching_status;
    }
  }

  // Create Payment (if invoice was created)
  if (cycle.invoiceId) {
    const paymentResult = await callFunctionAsUser('create_payment', {
      p_user_id: userId,
      p_invoice_id: cycle.invoiceId,
      p_amount: cycle.totalAmount,
      p_payment_method: 'bank_transfer',
      p_payment_date: new Date().toISOString().split('T')[0],
      p_reference_number: `PAY-${faker.string.alphanumeric(8).toUpperCase()}`,
      p_notes: 'Test payment'
    });

    if (paymentResult?.success) {
      cycle.paymentId = paymentResult.payment_id;
      cycle.paymentNumber = paymentResult.payment_number;
    }
  }

  return cycle;
}

/**
 * Clean up test data by soft-deleting
 */
export async function cleanupTestData(ids = {}) {
  const client = (await import('../../src/db/connection.js')).getSupabaseAdmin();

  if (ids.paymentId) {
    await client.from('payments')
      .update({ is_deleted: true })
      .eq('payment_id', ids.paymentId);
  }

  if (ids.invoiceId) {
    await client.from('invoice_receipts')
      .update({ is_deleted: true })
      .eq('invoice_id', ids.invoiceId);
  }

  if (ids.grId) {
    await client.from('goods_receipts')
      .update({ is_deleted: true })
      .eq('gr_id', ids.grId);
  }

  if (ids.poId) {
    await client.from('purchase_orders')
      .update({ is_deleted: true })
      .eq('po_id', ids.poId);
  }
}

export default {
  generateSupplier,
  generatePOLines,
  generatePurchaseOrder,
  createTestScenario,
  createFullP2PCycle,
  cleanupTestData
};
