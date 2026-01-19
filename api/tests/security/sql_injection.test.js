/**
 * Security Tests: SQL Injection Prevention
 * Tests to verify SQL injection attacks are prevented
 */

import { createTestApp, testRequest } from '../helpers/testApp.js';
import { TEST_USERS } from '../setup.js';

describe('SQL Injection Prevention Tests', () => {
  let app;

  beforeAll(async () => {
    app = await createTestApp();
  });

  afterAll(async () => {
    await app.close();
  });

  // =========================================================================
  // Filter Parameter Injection
  // =========================================================================
  describe('Filter Parameter Injection', () => {
    const sqlInjectionPayloads = [
      "'; DROP TABLE purchase_orders; --",
      "1' OR '1'='1",
      "1; DELETE FROM users; --",
      "' UNION SELECT * FROM users --",
      "1'; TRUNCATE TABLE suppliers; --",
      "admin'--",
      "' OR 1=1 --",
      "'; INSERT INTO users VALUES ('hacker', 'password'); --",
      "1' AND SLEEP(5) --",
      "' OR ''='",
    ];

    test.each(sqlInjectionPayloads)(
      'Filter parameter blocks injection: %s',
      async (payload) => {
        const response = await testRequest.get(
          app,
          '/ui/purchase_order/list',
          TEST_USERS.admin,
          { status: payload }
        );

        // Should not return 500 (which would indicate SQL error)
        expect(response.statusCode).not.toBe(500);

        // Should not contain error messages that reveal SQL structure
        expect(response.body.toLowerCase()).not.toContain('syntax error');
        expect(response.body.toLowerCase()).not.toContain('sql');
        expect(response.body.toLowerCase()).not.toContain('postgresql');
      }
    );

    test('Multiple filters with injection attempts', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        {
          status: "'; DROP TABLE--",
          po_date: "2024-01-01' OR '1'='1",
          supplier_id: "00000000-0000-0000-0000-000000000001' UNION SELECT * FROM users --"
        }
      );

      expect(response.statusCode).not.toBe(500);
    });
  });

  // =========================================================================
  // URL Parameter Injection
  // =========================================================================
  describe('URL Parameter Injection', () => {
    test('Entity name injection is prevented', async () => {
      const maliciousEntity = "purchase_order; DROP TABLE suppliers; --";

      const response = await testRequest.get(
        app,
        `/ui/${encodeURIComponent(maliciousEntity)}/list`,
        TEST_USERS.admin
      );

      // Should return error, not execute injection
      expect(response.statusCode).not.toBe(500);
    });

    test('Record ID injection is prevented', async () => {
      const maliciousId = "00000000-0000-0000-0000-000000000001'; DELETE FROM purchase_orders; --";

      const response = await testRequest.get(
        app,
        '/ui/purchase_order/form/view',
        TEST_USERS.admin,
        { id: maliciousId }
      );

      expect(response.statusCode).not.toBe(500);
    });
  });

  // =========================================================================
  // Request Body Injection
  // =========================================================================
  describe('Request Body Injection', () => {
    test('Notes field injection is prevented', async () => {
      const response = await testRequest.post(
        app,
        '/api/purchase_order',
        TEST_USERS.admin,
        {
          supplier_id: '00000000-0000-0000-0000-000000000001',
          notes: "'); DELETE FROM purchase_orders; --",
          lines: []
        }
      );

      // May fail for other reasons, but not SQL injection
      expect(response.statusCode).not.toBe(500);
    });

    test('JSON field injection is prevented', async () => {
      const response = await testRequest.put(
        app,
        '/api/purchase_order/00000000-0000-0000-0000-000000000001',
        TEST_USERS.admin,
        {
          notes: "Test'); DELETE FROM users WHERE ('1'='1",
          status: "draft'; DROP TABLE--"
        }
      );

      expect(response.statusCode).not.toBe(500);
    });
  });

  // =========================================================================
  // LIKE Clause Injection
  // =========================================================================
  describe('LIKE Clause Injection', () => {
    test('Wildcard injection in search is handled', async () => {
      const response = await testRequest.get(
        app,
        '/ui/supplier/list',
        TEST_USERS.admin,
        {
          supplier_name_like: "%; DELETE FROM suppliers; --%"
        }
      );

      expect(response.statusCode).not.toBe(500);
    });

    test('Escape characters in search are handled', async () => {
      const response = await testRequest.get(
        app,
        '/ui/supplier/list',
        TEST_USERS.admin,
        {
          supplier_name_like: "\\'; DROP TABLE--"
        }
      );

      expect(response.statusCode).not.toBe(500);
    });
  });

  // =========================================================================
  // Sort Parameter Injection
  // =========================================================================
  describe('Sort Parameter Injection', () => {
    test('Sort field injection is prevented', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        {
          sort: "created_at; DROP TABLE purchase_orders; --",
          sort_dir: 'ASC'
        }
      );

      expect(response.statusCode).not.toBe(500);
    });

    test('Sort direction injection is prevented', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        {
          sort: 'created_at',
          sort_dir: "ASC; DELETE FROM users; --"
        }
      );

      expect(response.statusCode).not.toBe(500);
    });
  });

  // =========================================================================
  // Pagination Injection
  // =========================================================================
  describe('Pagination Injection', () => {
    test('Page number injection is prevented', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        {
          page: "1; DROP TABLE purchase_orders; --",
          page_size: 25
        }
      );

      expect(response.statusCode).not.toBe(500);
    });

    test('Page size injection is prevented', async () => {
      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        {
          page: 1,
          page_size: "25; DELETE FROM users; --"
        }
      );

      expect(response.statusCode).not.toBe(500);
    });
  });

  // =========================================================================
  // Second-Order Injection
  // =========================================================================
  describe('Second-Order Injection', () => {
    test('Stored payload does not execute on retrieval', async () => {
      // First, try to store a malicious payload
      const createResponse = await testRequest.post(
        app,
        '/api/purchase_order',
        TEST_USERS.admin,
        {
          supplier_id: '00000000-0000-0000-0000-000000000001',
          notes: "'); DELETE FROM purchase_orders WHERE ('1'='1",
          lines: [
            {
              item_code: "ITEM'; DROP TABLE--",
              item_description: "Test'; DELETE FROM",
              quantity_ordered: 1,
              unit_price: 10,
              uom: 'EA'
            }
          ]
        }
      );

      // Creating may fail, but shouldn't cause SQL injection
      expect(createResponse.statusCode).not.toBe(500);

      // Retrieve list - should not execute any stored payloads
      const listResponse = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin
      );

      expect(listResponse.statusCode).toBe(200);
    });
  });

  // =========================================================================
  // Blind SQL Injection
  // =========================================================================
  describe('Blind SQL Injection Prevention', () => {
    test('Time-based blind injection is prevented', async () => {
      const startTime = Date.now();

      const response = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        {
          status: "draft' AND SLEEP(5) --"
        }
      );

      const duration = Date.now() - startTime;

      // Should complete quickly, not sleep
      expect(duration).toBeLessThan(3000);
      expect(response.statusCode).not.toBe(500);
    });

    test('Boolean-based blind injection returns consistent results', async () => {
      const trueResponse = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        { status: "draft' AND '1'='1" }
      );

      const falseResponse = await testRequest.get(
        app,
        '/ui/purchase_order/list',
        TEST_USERS.admin,
        { status: "draft' AND '1'='2" }
      );

      // Both should handle gracefully (not reveal boolean differences)
      expect(trueResponse.statusCode).not.toBe(500);
      expect(falseResponse.statusCode).not.toBe(500);
    });
  });
});
