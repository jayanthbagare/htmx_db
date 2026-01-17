/**
 * Authentication Middleware
 * Handles user authentication via Supabase Auth
 */

import { getSupabase, getSupabaseAdmin } from '../db/connection.js';

// Demo user for development (when no auth configured)
const DEMO_USERS = {
  admin: {
    user_id: '00000000-0000-0000-0000-000000000100',
    email: 'admin@example.com',
    role: 'admin'
  },
  purchase_manager: {
    user_id: '00000000-0000-0000-0000-000000000101',
    email: 'pm@example.com',
    role: 'purchase_manager'
  },
  warehouse_staff: {
    user_id: '00000000-0000-0000-0000-000000000102',
    email: 'warehouse@example.com',
    role: 'warehouse_staff'
  },
  accountant: {
    user_id: '00000000-0000-0000-0000-000000000103',
    email: 'accountant@example.com',
    role: 'accountant'
  },
  viewer: {
    user_id: '00000000-0000-0000-0000-000000000104',
    email: 'viewer@example.com',
    role: 'viewer'
  }
};

/**
 * Extract token from request
 */
function extractToken(request) {
  // Check Authorization header
  const authHeader = request.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    return authHeader.substring(7);
  }

  // Check cookie
  const token = request.cookies?.access_token;
  if (token) {
    return token;
  }

  return null;
}

/**
 * Get demo user from header or query param (development only)
 */
function getDemoUser(request) {
  if (process.env.NODE_ENV === 'production') {
    return null;
  }

  // Check X-Demo-User header
  const demoUserHeader = request.headers['x-demo-user'];
  if (demoUserHeader && DEMO_USERS[demoUserHeader]) {
    return DEMO_USERS[demoUserHeader];
  }

  // Check query param
  const demoUserParam = request.query?.demo_user;
  if (demoUserParam && DEMO_USERS[demoUserParam]) {
    return DEMO_USERS[demoUserParam];
  }

  // Default to admin in development
  return DEMO_USERS.admin;
}

/**
 * Verify token and get user
 */
async function verifyToken(token) {
  try {
    const supabase = getSupabase();
    const { data: { user }, error } = await supabase.auth.getUser(token);

    if (error || !user) {
      return null;
    }

    // Get user details from database
    const supabaseAdmin = getSupabaseAdmin();
    const { data: dbUser, error: dbError } = await supabaseAdmin
      .from('users')
      .select('user_id, email, display_name, role_id, roles(role_name)')
      .eq('auth_user_id', user.id)
      .single();

    if (dbError || !dbUser) {
      return null;
    }

    return {
      user_id: dbUser.user_id,
      email: dbUser.email,
      display_name: dbUser.display_name,
      role: dbUser.roles?.role_name,
      role_id: dbUser.role_id
    };
  } catch (err) {
    console.error('Token verification error:', err);
    return null;
  }
}

/**
 * Required authentication middleware
 * Rejects request if not authenticated
 */
export async function authMiddleware(request, reply) {
  // Try to get authenticated user
  const token = extractToken(request);

  if (token) {
    const user = await verifyToken(token);
    if (user) {
      request.user = user;
      return;
    }
  }

  // In development, use demo user
  const demoUser = getDemoUser(request);
  if (demoUser) {
    request.user = demoUser;
    request.log.debug({ demoUser: demoUser.email }, 'Using demo user');
    return;
  }

  // Not authenticated
  const isHtmxRequest = request.headers['hx-request'] === 'true';

  if (isHtmxRequest) {
    // Return HTMX-friendly error
    reply.code(401).header('HX-Redirect', '/login').send(
      '<div class="error-message">Please log in to continue.</div>'
    );
  } else {
    reply.code(401).send({
      error: 'Unauthorized',
      message: 'Authentication required'
    });
  }
}

/**
 * Optional authentication middleware
 * Allows unauthenticated requests but sets user if authenticated
 */
export async function optionalAuthMiddleware(request, reply) {
  const token = extractToken(request);

  if (token) {
    const user = await verifyToken(token);
    if (user) {
      request.user = user;
      return;
    }
  }

  // In development, use demo user
  const demoUser = getDemoUser(request);
  if (demoUser) {
    request.user = demoUser;
    return;
  }

  // Set anonymous user placeholder
  request.user = null;
}

/**
 * Role-based access middleware factory
 */
export function requireRole(...allowedRoles) {
  return async (request, reply) => {
    // Ensure user is authenticated first
    if (!request.user) {
      await authMiddleware(request, reply);
      if (reply.sent) return;
    }

    // Check role
    if (!allowedRoles.includes(request.user.role)) {
      const isHtmxRequest = request.headers['hx-request'] === 'true';

      if (isHtmxRequest) {
        reply.code(403).send(
          '<div class="error-message">You do not have permission to access this resource.</div>'
        );
      } else {
        reply.code(403).send({
          error: 'Forbidden',
          message: 'Insufficient permissions',
          required_roles: allowedRoles
        });
      }
    }
  };
}

/**
 * Get current user ID from request
 */
export function getUserId(request) {
  return request.user?.user_id || null;
}

/**
 * Check if user has specific role
 */
export function hasRole(request, role) {
  return request.user?.role === role;
}

/**
 * Check if user is admin
 */
export function isAdmin(request) {
  return request.user?.role === 'admin';
}

export default {
  authMiddleware,
  optionalAuthMiddleware,
  requireRole,
  getUserId,
  hasRole,
  isAdmin,
  DEMO_USERS
};
