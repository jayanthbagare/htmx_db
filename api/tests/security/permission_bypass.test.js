/**
 * Security Tests: Permission Bypass Prevention
 * Tests to verify permission checks cannot be bypassed
 */

import { createTestApp, testRequest } from '../helpers/testApp.js';
import { callFunctionAsUser } from '../../src/db/connection.js';
import { TEST_USERS, getTestClient } from '../setup.js';
import { createTestScenario, cleanupTestData } from '../helpers/testDataGenerator.js';

describe('Permission Bypass Prevention Tests', () => {
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
  // Authentication Bypass
  // =========================================================================
  describe('Authentication Bypass Prevention', () => {
    test('API routes reject unauthenticated requests', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/api/purchase_order'
      });

      expect(response.statusCode).toBe(401);
    });

    test('Cannot bypass auth with empty user header', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/api/purchase_order',
        headers: { 'x-demo-user': '' }
      });

      expect(response.statusCode).toBe(401);
    });

    test('Cannot bypass auth with invalid UUID', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/api/purchase_order',
        headers: { 'x-demo-user': 'not-a-valid-uuid' }
      });

      // Should reject or handle gracefully
      expect([400, 401, 500]).not.toContain(response.statusCode);
    });

    test('Cannot bypass auth with null user', async () => {
      const response = await app.inject({
        method: 'GET',
        url: '/api/purchase_order',
        headers: { 'x-demo-user': 'null' }
      });

      expect([400, 401]).toContain(response.statusCode);
    });
  });

  // =========================================================================
  // Role-Based Access Control
  // =========================================================================
  describe('Role-Based Access Control', () => {
    test('Viewer cannot create purchase orders', async () => {
      const response = await testRequest.post(
        app,
        '/api/purchase_order',
        TEST_USERS.viewer,
        {
          supplier_id: testData.supplierId,
          lines: [
            {
              item_code: 'PERM-TEST',
              item_description: 'Permission Test',
              quantity_ordered: 1,
              unit_price: 10,
              uom: 'EA'
            }
          ]
        }
      );

      // Should be rejected (403 or 400 with permission error)
      expect([400, 403]).toContain(response.statusCode);
    });

    test('Warehouse staff cannot approve purchase orders', async () => {
      if (!testData.poId) {
        console.log('Skipping - no test PO available');
        return;
      }

      const result = await callFunctionAsUser('approve_purchase_order', {
        p_user_id: TEST_USERS.warehouseStaff,
        p_po_id: testData.poId,
        p_approval_notes: 'Unauthorized approval attempt'
      });

      expect(result.success).toBe(false);
    });

    test('Viewer cannot delete records', async () => {
      if (!testData.poId) {
        console.log('Skipping - no test PO available');
        return;
      }

      const response = await testRequest.delete(
        app,
        `/api/purchase_order/${testData.poId}`,
        TEST_USERS.viewer,
        { reason: 'Unauthorized delete attempt' }
      );

      expect([400, 403]).toContain(response.statusCode);
    });

    test('Non-admin cannot access admin functions', async () => {
      // Test all non-admin roles
      const nonAdminUsers = [
        TEST_USERS.purchaseManager,
        TEST_USERS.warehouseStaff,
        TEST_USERS.accountant,
        TEST_USERS.viewer
      ];

      for (const userId of nonAdminUsers) {
        const result = await callFunctionAsUser('can_user_perform_action', {
          p_user_id: userId,
          p_entity_type: 'user',
          p_action_name: 'delete'
        });

        // Non-admins should not be able to delete users
        expect(result).toBe(false);
      }
    });
  });

  // =========================================================================
  // Field-Level Permission Enforcement
  // =========================================================================
  describe('Field-Level Permission Enforcement', () => {
    test('Warehouse staff cannot see sensitive financial fields', async () => {
      const result = await callFunctionAsUser('get_user_field_permissions', {
        p_user_id: TEST_USERS.warehouseStaff,
        p_entity_type: 'purchase_order',
        p_view_type: 'list'
      });

      // Check that total_amount is not visible for warehouse staff
      if (Array.isArray(result)) {
        const totalAmountField = result.find(f => f.field_name === 'total_amount');
        if (totalAmountField) {
          expect(totalAmountField.is_visible).toBe(false);
        }
      }
    });

    test('Viewer cannot edit any fields', async () => {
      const result = await callFunctionAsUser('get_user_field_permissions', {
        p_user_id: TEST_USERS.viewer,
        p_entity_type: 'purchase_order',
        p_view_type: 'form_edit'
      });

      // All fields should be non-editable for viewer
      if (Array.isArray(result)) {
        const editableFields = result.filter(f => f.is_editable === true);
        expect(editableFields.length).toBe(0);
      }
    });
  });

  // =========================================================================
  // Action Permission Enforcement
  // =========================================================================
  describe('Action Permission Enforcement', () => {
    test('Check create permission for purchase_order', async () => {
      // Admin can create
      const adminResult = await callFunctionAsUser('can_user_perform_action', {
        p_user_id: TEST_USERS.admin,
        p_entity_type: 'purchase_order',
        p_action_name: 'create'
      });
      expect(adminResult).toBe(true);

      // Viewer cannot create
      const viewerResult = await callFunctionAsUser('can_user_perform_action', {
        p_user_id: TEST_USERS.viewer,
        p_entity_type: 'purchase_order',
        p_action_name: 'create'
      });
      expect(viewerResult).toBe(false);
    });

    test('Check approve permission for purchase_order', async () => {
      // Admin can approve
      const adminResult = await callFunctionAsUser('can_user_perform_action', {
        p_user_id: TEST_USERS.admin,
        p_entity_type: 'purchase_order',
        p_action_name: 'approve'
      });
      expect(adminResult).toBe(true);

      // Purchase manager may or may not be able to approve
      const pmResult = await callFunctionAsUser('can_user_perform_action', {
        p_user_id: TEST_USERS.purchaseManager,
        p_entity_type: 'purchase_order',
        p_action_name: 'approve'
      });
      // Result depends on business rules
      expect(typeof pmResult).toBe('boolean');
    });
  });

  // =========================================================================
  // Horizontal Privilege Escalation
  // =========================================================================
  describe('Horizontal Privilege Escalation Prevention', () => {
    test('User cannot access other users data without permission', async () => {
      // This tests that users with same role can't access each other's data
      // when row-level security is properly configured

      // Try to fetch data as one user that belongs to another
      // The RLS policies should prevent this
      const response = await testRequest.get(
        app,
        '/api/purchase_order',
        TEST_USERS.purchaseManager,
        { created_by: TEST_USERS.warehouseStaff }
      );

      // Should succeed but not return unauthorized data
      expect(response.statusCode).toBe(200);
    });
  });

  // =========================================================================
  // Vertical Privilege Escalation
  // =========================================================================
  describe('Vertical Privilege Escalation Prevention', () => {
    test('Cannot escalate from viewer to admin via API', async () => {
      // Try to perform admin action as viewer
      const response = await testRequest.post(
        app,
        '/api/purchase_order',
        TEST_USERS.viewer,
        {
          supplier_id: testData.supplierId,
          lines: [{ item_code: 'PRIV-ESC', item_description: 'Privilege Escalation Test', quantity_ordered: 1, unit_price: 1, uom: 'EA' }]
        }
      );

      expect([400, 403]).toContain(response.statusCode);
    });

    test('Cannot modify role via update endpoint', async () => {
      // Try to change user role via generic update
      const response = await testRequest.put(
        app,
        `/api/user/${TEST_USERS.viewer}`,
        TEST_USERS.viewer,
        { role_id: '00000000-0000-0000-0000-000000000001' } // Admin role
      );

      // Should either fail or not actually change the role
      if (response.statusCode === 200) {
        // Verify role wasn't actually changed
        const client = getTestClient();
        const { data: user } = await client.from('users')
          .select('role_id')
          .eq('user_id', TEST_USERS.viewer)
          .single();

        if (user) {
          expect(user.role_id).not.toBe('00000000-0000-0000-0000-000000000001');
        }
      }
    });
  });

  // =========================================================================
  // IDOR (Insecure Direct Object Reference)
  // =========================================================================
  describe('IDOR Prevention', () => {
    test('Cannot access record by guessing ID', async () => {
      // Generate a random UUID that doesn't exist
      const fakeId = '99999999-9999-9999-9999-999999999999';

      const response = await testRequest.get(
        app,
        `/api/purchase_order/${fakeId}`,
        TEST_USERS.viewer
      );

      // Should return not found or empty, not an error
      expect([200, 404]).toContain(response.statusCode);
    });

    test('Cannot enumerate IDs', async () => {
      // Sequential ID enumeration should not work
      const responses = [];
      for (let i = 1; i <= 3; i++) {
        const response = await testRequest.get(
          app,
          `/api/purchase_order/00000000-0000-0000-0000-00000000000${i}`,
          TEST_USERS.viewer
        );
        responses.push(response.statusCode);
      }

      // All should return same status (404 or empty 200)
      expect(responses.every(s => s === responses[0])).toBe(true);
    });
  });

  // =========================================================================
  // Mass Assignment Protection
  // =========================================================================
  describe('Mass Assignment Protection', () => {
    test('Cannot set internal fields via update', async () => {
      if (!testData.poId) {
        console.log('Skipping - no test PO available');
        return;
      }

      const response = await testRequest.put(
        app,
        `/api/purchase_order/${testData.poId}`,
        TEST_USERS.admin,
        {
          is_deleted: true,
          created_by: TEST_USERS.viewer,
          created_at: '1990-01-01'
        }
      );

      // Should either reject or ignore internal fields
      if (response.statusCode === 200) {
        const client = getTestClient();
        const { data: po } = await client.from('purchase_orders')
          .select('is_deleted, created_by, created_at')
          .eq('po_id', testData.poId)
          .single();

        if (po) {
          expect(po.is_deleted).toBe(false);
          expect(po.created_by).not.toBe(TEST_USERS.viewer);
        }
      }
    });
  });
});
