/**
 * Error Handler Middleware
 * Handles all errors and returns appropriate responses
 */

import { DatabaseError } from '../db/connection.js';

/**
 * Escape HTML for safe display
 */
function escapeHtml(text) {
  if (!text) return '';
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Generate error HTML for HTMX responses
 */
function generateErrorHtml(statusCode, title, message, details = null) {
  const detailsHtml = details
    ? `<details class="error-details"><summary>Technical Details</summary><pre>${escapeHtml(details)}</pre></details>`
    : '';

  return `
<div class="error-container error-${statusCode}">
  <div class="error-icon">
    ${statusCode >= 500 ? '⚠️' : '❌'}
  </div>
  <div class="error-content">
    <h3 class="error-title">${escapeHtml(title)}</h3>
    <p class="error-message">${escapeHtml(message)}</p>
    ${detailsHtml}
  </div>
  <div class="error-actions">
    <button onclick="history.back()" class="btn btn-secondary">Go Back</button>
    <button onclick="location.reload()" class="btn btn-primary">Retry</button>
  </div>
</div>
`.trim();
}

/**
 * Main error handler
 */
export function errorHandler(error, request, reply) {
  const isHtmxRequest = request.headers['hx-request'] === 'true';
  const isDevelopment = process.env.NODE_ENV !== 'production';

  // Log the error
  request.log.error({
    err: error,
    url: request.url,
    method: request.method,
    userId: request.user?.user_id
  }, 'Request error');

  // Determine status code and message
  let statusCode = 500;
  let title = 'Server Error';
  let message = 'An unexpected error occurred';
  let details = isDevelopment ? error.stack : null;

  // Handle specific error types
  if (error instanceof DatabaseError) {
    statusCode = 400;
    title = 'Database Error';
    message = error.message;

    // Check for specific database errors
    if (error.message.includes('permission')) {
      statusCode = 403;
      title = 'Permission Denied';
    } else if (error.message.includes('not found')) {
      statusCode = 404;
      title = 'Not Found';
    }

    if (isDevelopment) {
      details = `Function: ${error.functionName}\nParams: ${JSON.stringify(error.params, null, 2)}`;
    }
  } else if (error.validation) {
    // Fastify validation error
    statusCode = 400;
    title = 'Validation Error';
    message = error.message;
    details = isDevelopment ? JSON.stringify(error.validation, null, 2) : null;
  } else if (error.statusCode) {
    // Error with explicit status code
    statusCode = error.statusCode;

    switch (statusCode) {
      case 400:
        title = 'Bad Request';
        break;
      case 401:
        title = 'Unauthorized';
        message = 'Please log in to continue';
        break;
      case 403:
        title = 'Forbidden';
        message = 'You do not have permission to access this resource';
        break;
      case 404:
        title = 'Not Found';
        message = 'The requested resource was not found';
        break;
      case 409:
        title = 'Conflict';
        break;
      default:
        if (statusCode >= 500) {
          title = 'Server Error';
        }
    }

    message = error.message || message;
  }

  // Send response
  if (isHtmxRequest) {
    // HTMX response - return HTML
    const html = generateErrorHtml(statusCode, title, message, details);

    reply
      .code(statusCode)
      .header('Content-Type', 'text/html; charset=utf-8')
      .send(html);
  } else {
    // JSON API response
    const response = {
      error: title,
      message,
      statusCode
    };

    if (isDevelopment && details) {
      response.details = details;
    }

    reply.code(statusCode).send(response);
  }
}

/**
 * Not found handler for 404s
 */
export function notFoundHandler(request, reply) {
  const isHtmxRequest = request.headers['hx-request'] === 'true';

  if (isHtmxRequest) {
    reply
      .code(404)
      .header('Content-Type', 'text/html; charset=utf-8')
      .send(generateErrorHtml(
        404,
        'Page Not Found',
        'The page you requested could not be found.'
      ));
  } else {
    reply.code(404).send({
      error: 'Not Found',
      message: 'The requested resource was not found',
      statusCode: 404
    });
  }
}

/**
 * Create a custom HTTP error
 */
export function createError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

/**
 * Common error creators
 */
export const errors = {
  badRequest: (message = 'Bad request') => createError(400, message),
  unauthorized: (message = 'Unauthorized') => createError(401, message),
  forbidden: (message = 'Forbidden') => createError(403, message),
  notFound: (message = 'Not found') => createError(404, message),
  conflict: (message = 'Conflict') => createError(409, message),
  serverError: (message = 'Internal server error') => createError(500, message)
};

export default {
  errorHandler,
  notFoundHandler,
  createError,
  errors
};
