/**
 * Database Connection Module
 * Handles Supabase client and direct database connections
 */

import { createClient } from '@supabase/supabase-js';

// Supabase client for auth and general queries
let supabase = null;

// Service role client for admin operations
let supabaseAdmin = null;

/**
 * Initialize database connections
 */
export async function initDatabase() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
  const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error('Missing SUPABASE_URL or SUPABASE_ANON_KEY environment variables');
  }

  // Create public client (for user-authenticated requests)
  supabase = createClient(supabaseUrl, supabaseAnonKey, {
    auth: {
      autoRefreshToken: true,
      persistSession: false
    }
  });

  // Create admin client (for service operations)
  if (supabaseServiceKey) {
    supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false
      }
    });
  }

  // Test connection
  const { error } = await supabase.from('roles').select('count').limit(1);
  if (error) {
    throw new Error(`Database connection test failed: ${error.message}`);
  }

  return true;
}

/**
 * Close database connections
 */
export async function closeDatabase() {
  // Supabase client doesn't require explicit cleanup
  supabase = null;
  supabaseAdmin = null;
}

/**
 * Get the public Supabase client
 */
export function getSupabase() {
  if (!supabase) {
    throw new Error('Database not initialized. Call initDatabase() first.');
  }
  return supabase;
}

/**
 * Get the admin Supabase client
 */
export function getSupabaseAdmin() {
  if (!supabaseAdmin) {
    throw new Error('Admin database not initialized. Ensure SUPABASE_SERVICE_ROLE_KEY is set.');
  }
  return supabaseAdmin;
}

/**
 * Execute a database function (RPC call)
 * @param {string} functionName - Name of the PostgreSQL function
 * @param {object} params - Parameters to pass to the function
 * @param {object} options - Options (useAdmin: boolean)
 */
export async function callFunction(functionName, params = {}, options = {}) {
  const client = options.useAdmin ? getSupabaseAdmin() : getSupabase();

  const { data, error } = await client.rpc(functionName, params);

  if (error) {
    throw new DatabaseError(error.message, functionName, params);
  }

  return data;
}

/**
 * Execute a database function with user context
 * Sets the authenticated user for RLS policies
 */
export async function callFunctionAsUser(functionName, params = {}, userId = null) {
  const client = getSupabaseAdmin();

  // Add user_id to params if the function expects it
  const paramsWithUser = userId ? { ...params, p_user_id: userId } : params;

  const { data, error } = await client.rpc(functionName, paramsWithUser);

  if (error) {
    throw new DatabaseError(error.message, functionName, paramsWithUser);
  }

  return data;
}

/**
 * Custom database error class
 */
export class DatabaseError extends Error {
  constructor(message, functionName, params) {
    super(message);
    this.name = 'DatabaseError';
    this.functionName = functionName;
    this.params = params;
  }
}

/**
 * Helper to parse PostgreSQL function results
 * Handles JSONB returns from functions
 */
export function parseResult(data) {
  if (data === null || data === undefined) {
    return null;
  }

  // If it's already an object, return as-is
  if (typeof data === 'object') {
    return data;
  }

  // Try to parse JSON string
  try {
    return JSON.parse(data);
  } catch {
    return data;
  }
}

/**
 * Check if a function result indicates success
 */
export function isSuccess(result) {
  if (!result || typeof result !== 'object') {
    return false;
  }
  return result.success === true;
}

/**
 * Extract error message from function result
 */
export function getErrorMessage(result) {
  if (!result || typeof result !== 'object') {
    return 'Unknown error';
  }
  return result.error || result.message || 'Unknown error';
}

export default {
  initDatabase,
  closeDatabase,
  getSupabase,
  getSupabaseAdmin,
  callFunction,
  callFunctionAsUser,
  parseResult,
  isSuccess,
  getErrorMessage,
  DatabaseError
};
