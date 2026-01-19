/**
 * API Integration Tests
 * Tests for all API endpoints
 */

import { createTestApp, testRequest } from '../helpers/testApp.js';
import { TEST_USERS } from '../setup.js';
import { createTestScenario, cleanupTestData } from '../helpers/testDataGenerator.js';

describe('API Integration Tests', () => {
  let app;
  let testData;

  beforeAll(async () => {
    app = await createTestApp();
    testData = await createTestScenario();
  });

  afterAll(async () => {
    if (testData) {
      await cleanupTestData(testData);
    }
    await app.close();
  });

  // =========================================================================
  // Health Check
  // =========================================================================
  describe('Health Check', () => {
    test('GET /health returns 200', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/health'
      });

      expect(response.statusCode).toBe(200);
      expect(JSON.parse(response.body)).toHaveProperty('status', 'ok');
    });
  });

  // =========================================================================
  // UI Endpoints
  // =========================================================================
  describe('UI Generation Endpoints', () => {
    test('GET /ui/:entity/list returns HTML', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(200);
      expect(response.headers['content-type']).toContain('text/html');
    });

    test('GET /ui/:entity/list supports pagination', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        { page: 1, page_size: 10 }
      );

      expect(response.statusCode).toBe(200);
      expect(response.headers['content-type']).toContain('text/html');
    });

    test('GET /ui/:entity/list supports filtering', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        { status: 'draft' }
      );

      expect(response.statusCode).toBe(200);
    });

    test('GET /ui/:entity/list supports sorting', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        { sort: 'created_at', sort_dir: 'DESC' }
      );

      expect(response.statusCode).toBe(200);
    });

    test('GET /ui/:entity/form/create returns HTML form', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/form/create',
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(200);
      expect(response.headers['content-type']).toContain('text/html');
      expect(response.body).toContain('form');
    });

    test('GET /ui/:entity/form/view requires record ID', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/form/view',
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(400);
    });

    test('GET /ui/:entity/form/view returns record form', async () => {
      if (!testData.poId) {
        console.log('Skipping - no test PO available');
        return;
      }

      const response = await testRequest.get(
        app,
        '/ui/purchase_order/form/view',
        TEST_USERS.admin,
        { id: testData.poId }
      );

      expect(response.statusCode).toBe(200);
      expect(response.headers['content-type']).toContain('text/html');
    });

    test('GET /ui/dashboard returns dashboard HTML', async () => {
      const response = await testRequest.get(
        app,
        '/ui/dashboard',
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(200);
      expect(response.body).toContain('Dashboard');
    });

    test('GET /ui/nav returns navigation HTML', async () => {
      const response = await testRequest.get(
        app,
        '/ui/nav',
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(200);
      expect(response.body).toContain('nav');
    });
  });

  // =========================================================================
  // Purchase Order API
  // =========================================================================
  describe('Purchase Order API', () => {
    let createdPoId;

    test('POST /api/purchase_order creates a PO', async () => {
      const response = await testRequest.post(
        app,
        '/api/purchase_order',
        TEST_USERS.admin,
        {
          supplier_id: testData.supplierId,
          po_date: new Date().toISOString().split('T')[0],
          currency: 'USD',
          notes: 'Integration test PO',
          lines: [
            {
              item_code: 'TEST-INT-001',
              item_description: 'Integration Test Item',
              quantity_ordered: 10,
              unit_price: 50.00,
              uom: 'EA'
            }
          ]
        }
      );

      expect(response.statusCode).toBe(200);
      expect(response.headers['content-type']).toContain('text/html');

      // Try to extract PO ID from HX-Trigger header if available
      const hxTrigger = response.headers['hx-trigger'];
      if (hxTrigger) {
        const triggerData = JSON.parse(hxTrigger);
        if (triggerData.showToast?.type === 'success') {
          // PO was created successfully
          createdPoId = testData.poId; // Use existing test data for cleanup
        }
      }
    });

    test('POST /api/purchase_order requires supplier', async () => {
      const response = await testRequest.post(
        app,
        '/api/purchase_order',
        TEST_USERS.admin,
        {
          po_date: new Date().toISOString().split('T')[0],
          lines: []
        }
      );

      expect(response.statusCode).toBe(400);
    });

    test('GET /api/purchase_order returns list data', async () => {
      const response = await testRequest.get(
        app,
        '/api/purchase_order',
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.body);
      expect(data).toBeDefined();
    });

    test('GET /api/purchase_order/:id returns single record', async () => {
      if (!testData.poId) {
        console.log('Skipping - no test PO available');
        return;
      }

      const response = await testRequest.get(
        app,
        `/api/purchase_order/${testData.poId}`,
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(200);
    });

    test('PUT /api/purchase_order/:id updates record', async () => {
      if (!testData.poId) {
        console.log('Skipping - no test PO available');
        return;
      }

      const response = await testRequest.put(
        app,
        `/api/purchase_order/${testData.poId}`,
        TEST_USERS.admin,
        { notes: 'Updated via integration test' }
      );

      expect(response.statusCode).toBe(200);
    });
  });

  // =========================================================================
  // Goods Receipt API
  // =========================================================================
  describe('Goods Receipt API', () => {
    test('POST /api/goods_receipt requires po_id', async () => {
      const response = await testRequest.post(
        app,
        '/api/goods_receipt',
        TEST_USERS.admin,
        {
          receipt_date: new Date().toISOString().split('T')[0]
        }
      );

      expect(response.statusCode).toBe(400);
    });

    test('GET /api/goods_receipt returns list data', async () => {
      const response = await testRequest.get(
        app,
        '/api/goods_receipt',
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(200);
    });
  });

  // =========================================================================
  // Invoice Receipt API
  // =========================================================================
  describe('Invoice Receipt API', () => {
    test('POST /api/invoice_receipt requires po_id', async () => {
      const response = await testRequest.post(
        app,
        '/api/invoice_receipt',
        TEST_USERS.admin,
        {
          vendor_invoice_number: 'TEST-INV-001'
        }
      );

      expect(response.statusCode).toBe(400);
    });

    test('POST /api/invoice_receipt requires vendor_invoice_number', async () => {
      const response = await testRequest.post(
        app,
        '/api/invoice_receipt',
        TEST_USERS.admin,
        {
          po_id: testData.poId
        }
      );

      expect(response.statusCode).toBe(400);
    });

    test('GET /api/invoice_receipt returns list data', async () => {
      const response = await testRequest.get(
        app,
        '/api/invoice_receipt',
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(200);
    });
  });

  // =========================================================================
  // Payment API
  // =========================================================================
  describe('Payment API', () => {
    test('POST /api/payment requires invoice_id', async () => {
      const response = await testRequest.post(
        app,
        '/api/payment',
        TEST_USERS.admin,
        {
          amount: 100.00
        }
      );

      expect(response.statusCode).toBe(400);
    });

    test('POST /api/payment requires valid amount', async () => {
      const response = await testRequest.post(
        app,
        '/api/payment',
        TEST_USERS.admin,
        {
          invoice_id: '00000000-0000-0000-0000-000000000001',
          amount: 0
        }
      );

      expect(response.statusCode).toBe(400);
    });

    test('GET /api/payment returns list data', async () => {
      const response = await testRequest.get(
        app,
        '/api/payment',
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(200);
    });
  });

  // =========================================================================
  // Generic CRUD
  // =========================================================================
  describe('Generic CRUD Endpoints', () => {
    test('GET /api/supplier returns list data', async () => {
      const response = await testRequest.get(
        app,
        '/api/supplier',
        TEST_USERS.admin
      );

      expect(response.statusCode).toBe(200);
    });

    test('PUT /api/:entity/:id updates record', async () => {
      if (!testData.supplierId) {
        console.log('Skipping - no test supplier available');
        return;
      }

      const response = await testRequest.put(
        app,
        `/api/supplier/${testData.supplierId}`,
        TEST_USERS.admin,
        { notes: 'Updated via generic CRUD test' }
      );

      expect(response.statusCode).toBe(200);
    });
  });

  // =========================================================================
  // Authentication
  // =========================================================================
  describe('Authentication', () => {
    test('API routes require authentication', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/api/purchase_order'
      });

      expect(response.statusCode).toBe(401);
    });

    test('UI routes work with demo user header', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.viewer
      );

      expect(response.statusCode).toBe(200);
    });
  });
});
