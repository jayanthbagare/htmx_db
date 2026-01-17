/**
 * Authentication Routes
 * Login, logout, and session management
 */

import { getSupabase } from '../db/connection.js';
import { DEMO_USERS } from '../middleware/auth.js';

export default async function authRoutes(fastify) {
  /**
   * POST /auth/login
   * Login with email and password
   */
  fastify.post('/login', async (request, reply) => {
    const { email, password } = request.body;
    const isHtmx = request.headers['hx-request'] === 'true';

    if (!email || !password) {
      if (isHtmx) {
        return reply
          .code(400)
          .header('Content-Type', 'text/html')
          .send('<div class="error-message">Email and password are required</div>');
      }
      return reply.code(400).send({ error: 'Email and password are required' });
    }

    try {
      const supabase = getSupabase();
      const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password
      });

      if (error) {
        if (isHtmx) {
          return reply
            .code(401)
            .header('Content-Type', 'text/html')
            .send('<div class="error-message">Invalid email or password</div>');
        }
        return reply.code(401).send({ error: 'Invalid credentials' });
      }

      // Set session cookie
      reply.setCookie('access_token', data.session.access_token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'lax',
        path: '/',
        maxAge: 60 * 60 * 24 * 7 // 7 days
      });

      if (isHtmx) {
        // Redirect to dashboard
        return reply
          .header('HX-Redirect', '/')
          .send('<div class="success-message">Login successful</div>');
      }

      return reply.send({
        success: true,
        user: {
          id: data.user.id,
          email: data.user.email
        }
      });
    } catch (err) {
      request.log.error({ err }, 'Login error');

      if (isHtmx) {
        return reply
          .code(500)
          .header('Content-Type', 'text/html')
          .send('<div class="error-message">An error occurred during login</div>');
      }
      return reply.code(500).send({ error: 'Login failed' });
    }
  });

  /**
   * POST /auth/logout
   * Logout and clear session
   */
  fastify.post('/logout', async (request, reply) => {
    const isHtmx = request.headers['hx-request'] === 'true';

    try {
      const supabase = getSupabase();
      await supabase.auth.signOut();
    } catch (err) {
      request.log.warn({ err }, 'Error during logout');
    }

    // Clear cookie
    reply.clearCookie('access_token', { path: '/' });

    if (isHtmx) {
      return reply
        .header('HX-Redirect', '/login')
        .send('<div class="success-message">Logged out</div>');
    }

    return reply.send({ success: true });
  });

  /**
   * GET /auth/me
   * Get current user info
   */
  fastify.get('/me', async (request, reply) => {
    if (request.user) {
      return reply.send({
        authenticated: true,
        user: request.user
      });
    }

    return reply.send({
      authenticated: false,
      user: null
    });
  });

  /**
   * GET /auth/demo-users
   * Get list of demo users (development only)
   */
  fastify.get('/demo-users', async (request, reply) => {
    if (process.env.NODE_ENV === 'production') {
      return reply.code(404).send({ error: 'Not found' });
    }

    const users = Object.entries(DEMO_USERS).map(([key, user]) => ({
      key,
      email: user.email,
      role: user.role
    }));

    return reply.send({ users });
  });

  /**
   * POST /auth/switch-demo-user
   * Switch to a different demo user (development only)
   */
  fastify.post('/switch-demo-user', async (request, reply) => {
    if (process.env.NODE_ENV === 'production') {
      return reply.code(404).send({ error: 'Not found' });
    }

    const { user } = request.body;
    const isHtmx = request.headers['hx-request'] === 'true';

    if (!DEMO_USERS[user]) {
      if (isHtmx) {
        return reply
          .code(400)
          .header('Content-Type', 'text/html')
          .send('<div class="error-message">Invalid demo user</div>');
      }
      return reply.code(400).send({ error: 'Invalid demo user' });
    }

    // Set demo user cookie
    reply.setCookie('demo_user', user, {
      httpOnly: false,
      path: '/',
      maxAge: 60 * 60 * 24 // 1 day
    });

    if (isHtmx) {
      return reply
        .header('HX-Refresh', 'true')
        .send(`<div class="success-message">Switched to ${user}</div>`);
    }

    return reply.send({
      success: true,
      user: DEMO_USERS[user]
    });
  });

  /**
   * GET /auth/login-form
   * Get login form HTML (for HTMX)
   */
  fastify.get('/login-form', async (request, reply) => {
    const isDev = process.env.NODE_ENV !== 'production';

    let demoUserOptions = '';
    if (isDev) {
      demoUserOptions = Object.entries(DEMO_USERS)
        .map(([key, user]) =>
          `<option value="${key}">${user.email} (${user.role})</option>`
        )
        .join('\n');
    }

    const html = `
<div class="login-container">
  <h2>Login</h2>

  <form hx-post="/auth/login" hx-target="#login-result" hx-swap="innerHTML">
    <div class="form-group">
      <label for="email">Email</label>
      <input type="email" id="email" name="email" required class="form-control"
             placeholder="Enter your email">
    </div>

    <div class="form-group">
      <label for="password">Password</label>
      <input type="password" id="password" name="password" required class="form-control"
             placeholder="Enter your password">
    </div>

    <div id="login-result"></div>

    <button type="submit" class="btn btn-primary">Login</button>
  </form>

  ${isDev ? `
  <hr>
  <div class="demo-login">
    <h4>Demo Users (Development Only)</h4>
    <form hx-post="/auth/switch-demo-user" hx-target="#login-result">
      <select name="user" class="form-select">
        ${demoUserOptions}
      </select>
      <button type="submit" class="btn btn-secondary">Switch User</button>
    </form>
  </div>
  ` : ''}
</div>
    `.trim();

    reply
      .header('Content-Type', 'text/html; charset=utf-8')
      .send(html);
  });
}
