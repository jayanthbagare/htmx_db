/**
 * HTMX Database API Server
 * Minimal Fastify proxy layer for PostgreSQL-generated HTMX
 */

import Fastify from 'fastify';
import cors from '@fastify/cors';
import formbody from '@fastify/formbody';
import cookie from '@fastify/cookie';
import fastifyStatic from '@fastify/static';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

// Get directory paths
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Import modules
import { initDatabase, closeDatabase } from './db/connection.js';
import { authMiddleware, optionalAuthMiddleware } from './middleware/auth.js';
import { errorHandler } from './middleware/errorHandler.js';
import uiRoutes from './routes/ui.js';
import apiRoutes from './routes/api.js';
import authRoutes from './routes/auth.js';

// Create Fastify instance
const fastify = Fastify({
  logger: {
    level: process.env.LOG_LEVEL || 'info',
    transport: process.env.NODE_ENV === 'development' ? {
      target: 'pino-pretty',
      options: {
        translateTime: 'HH:MM:ss Z',
        ignore: 'pid,hostname'
      }
    } : undefined
  }
});

// Register plugins
async function registerPlugins() {
  // CORS
  await fastify.register(cors, {
    origin: true,
    credentials: true
  });

  // Form body parsing (for HTMX form submissions)
  await fastify.register(formbody);

  // Cookie support
  await fastify.register(cookie, {
    secret: process.env.SESSION_SECRET || 'default-secret-change-in-production',
    parseOptions: {}
  });

  // Static file serving (for frontend)
  await fastify.register(fastifyStatic, {
    root: join(__dirname, '../public'),
    prefix: '/'
  });
}

// Register routes
async function registerRoutes() {
  // Health check
  fastify.get('/health', async () => ({ status: 'ok', timestamp: new Date().toISOString() }));

  // Auth routes (login, logout, etc.)
  await fastify.register(authRoutes, { prefix: '/auth' });

  // UI generation routes (protected)
  await fastify.register(async (instance) => {
    instance.addHook('preHandler', optionalAuthMiddleware);
    await instance.register(uiRoutes);
  }, { prefix: '/ui' });

  // API routes for business logic (protected)
  await fastify.register(async (instance) => {
    instance.addHook('preHandler', authMiddleware);
    await instance.register(apiRoutes);
  }, { prefix: '/api' });
}

// Set error handler
fastify.setErrorHandler(errorHandler);

// Graceful shutdown
const gracefulShutdown = async (signal) => {
  fastify.log.info(`Received ${signal}, shutting down gracefully...`);

  try {
    await fastify.close();
    await closeDatabase();
    fastify.log.info('Server closed successfully');
    process.exit(0);
  } catch (err) {
    fastify.log.error('Error during shutdown:', err);
    process.exit(1);
  }
};

process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));

// Start server
async function start() {
  try {
    // Initialize database connection
    await initDatabase();
    fastify.log.info('Database connection initialized');

    // Register plugins and routes
    await registerPlugins();
    await registerRoutes();

    // Start listening
    const port = parseInt(process.env.PORT || '3000', 10);
    const host = process.env.HOST || '0.0.0.0';

    await fastify.listen({ port, host });
    fastify.log.info(`Server running at http://${host}:${port}`);

  } catch (err) {
    fastify.log.error('Failed to start server:', err);
    process.exit(1);
  }
}

start();

export default fastify;
