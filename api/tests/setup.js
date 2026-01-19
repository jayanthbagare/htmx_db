/**
 * Jest Global Test Setup
 * Initializes database connection and test fixtures
 */

import dotenv from 'dotenv';
import { initDatabase, closeDatabase, getSupabaseAdmin } from '../src/db/connection.js';

// Load test environment variables
dotenv.config({ path: '.env.test' });
dotenv.config(); // Fallback to .env if .env.test doesn't exist

// Global test timeout
jest.setTimeout(30000);

// Test user IDs (matching seeded data)
export const TEST_USERS = {
  admin: '00000000-0000-0000-0000-000000000100',
  purchaseManager: '00000000-0000-0000-0000-000000000101',
  warehouseStaff: '00000000-0000-0000-0000-000000000102',
  accountant: '00000000-0000-0000-0000-000000000103',
  viewer: '00000000-0000-0000-0000-000000000104'
};

// Global setup - runs once before all tests
beforeAll(async () => {
  try {
    await initDatabase();
    console.log('Test database connection established');
  } catch (error) {
    console.error('Failed to initialize test database:', error);
    throw error;
  }
});

// Global teardown - runs once after all tests
afterAll(async () => {
  try {
    await closeDatabase();
    console.log('Test database connection closed');
  } catch (error) {
    console.error('Error closing test database:', error);
  }
});

// Helper to get admin client for test setup/cleanup
export function getTestClient() {
  return getSupabaseAdmin();
}
