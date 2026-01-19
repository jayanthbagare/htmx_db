/**
 * Test Application Helper
 * Creates a test instance of the Fastify app
 */

import Fastify from 'fastify';
import cors from '@fastify/cors';
import formbody from '@fastify/formbody';
import cookie from '@fastify/cookie';
import { errorHandler } from '../../src/middleware/errorHandler.js';
import { optionalAuthMiddleware, authMiddleware } from '../../src/middleware/auth.js';
import uiRoutes from '../../src/routes/ui.js';
import apiRoutes from '../../src/routes/api.js';
import authRoutes from '../../src/routes/auth.js';

/**
 * Create a test instance of the Fastify application
 */
export async function createTestApp() {
  const app = Fastify({
    logger: false  // Disable logging during tests
  });

  // Register plugins
  await app.register(cors, { origin: true, credentials: true });
  await app.register(formbody);
  await app.register(cookie, { secret: 'test-secret' });

  // Health check
  app.get('/health', async () => ({ status: 'ok' }));

  // Auth routes
  await app.register(authRoutes, { prefix: '/auth' });

  // UI routes with optional auth
  await app.register(async (instance) => {
    instance.addHook('preHandler', optionalAuthMiddleware);
    await instance.register(uiRoutes);
  }, { prefix: '/ui' });

  // API routes with required auth
  await app.register(async (instance) => {
    instance.addHook('preHandler', authMiddleware);
    await instance.register(apiRoutes);
  }, { prefix: '/api' });

  // Error handler
  app.setErrorHandler(errorHandler);

  await app.ready();
  return app;
}

/**
 * Helper to inject requests with authentication
 */
export function injectWithAuth(app, userId, options = {}) {
  const headers = options.headers || {};

  // Add demo user header for testing
  headers['x-demo-user'] = userId;

  return app.inject({
    ...options,
    headers
  });
}

/**
 * Common test request helpers
 */
export const testRequest = {
  async get(app, url, userId, query = {}) {
    const queryString = new URLSearchParams(query).toString();
    const fullUrl = queryString ? `${url}?${queryString}` : url;

    return injectWithAuth(app, userId, {
      method: 'GET',
      url: fullUrl
    });
  },

  async post(app, url, userId, payload = {}) {
    return injectWithAuth(app, userId, {
      method: 'POST',
      url,
      payload,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  },

  async put(app, url, userId, payload = {}) {
    return injectWithAuth(app, userId, {
      method: 'PUT',
      url,
      payload,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  },

  async delete(app, url, userId, payload = {}) {
    return injectWithAuth(app, userId, {
      method: 'DELETE',
      url,
      payload,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  }
};

export default { createTestApp, injectWithAuth, testRequest };
