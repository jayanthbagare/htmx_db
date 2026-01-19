/**
 * Load Tests: Sustained Load & Spike Testing
 * k6 load test for measuring system behavior under various load patterns
 *
 * Run with: k6 run tests/load/sustained_load.k6.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

// Custom metrics
const responseDuration = new Trend('response_duration');
const errorRate = new Rate('errors');
const successRate = new Rate('success');
const requestCount = new Counter('total_requests');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const ADMIN_USER = '00000000-0000-0000-0000-000000000100';

// Test options - Multiple load scenarios
export const options = {
  scenarios: {
    // Scenario 1: Sustained low load (10 req/sec for 5 minutes)
    sustained_low: {
      executor: 'constant-arrival-rate',
      rate: 10,
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 20,
      maxVUs: 50,
      exec: 'mixedOperations',
    },
    // Scenario 2: Sustained medium load (50 req/sec for 5 minutes)
    sustained_medium: {
      executor: 'constant-arrival-rate',
      rate: 50,
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 100,
      maxVUs: 200,
      exec: 'mixedOperations',
      startTime: '6m',
    },
    // Scenario 3: Spike test (0 to 100 req/sec)
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: 200,
      maxVUs: 500,
      stages: [
        { duration: '30s', target: 100 },  // Ramp up
        { duration: '1m', target: 100 },   // Stay at peak
        { duration: '30s', target: 0 },    // Ramp down
      ],
      exec: 'mixedOperations',
      startTime: '12m',
    },
    // Scenario 4: Gradual ramp (1 to 100 req/sec over 10 minutes)
    gradual_ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 1,
      timeUnit: '1s',
      preAllocatedVUs: 200,
      maxVUs: 500,
      stages: [
        { duration: '10m', target: 100 },
      ],
      exec: 'mixedOperations',
      startTime: '15m',
    },
    // Scenario 5: Concurrent users test
    concurrent_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 10 },   // Ramp to 10 users
        { duration: '2m', target: 10 },   // Stay at 10
        { duration: '1m', target: 50 },   // Ramp to 50 users
        { duration: '2m', target: 50 },   // Stay at 50
        { duration: '1m', target: 100 },  // Ramp to 100 users
        { duration: '2m', target: 100 },  // Stay at 100
        { duration: '1m', target: 0 },    // Ramp down
      ],
      exec: 'userSession',
      startTime: '26m',
    },
  },
  thresholds: {
    // Response time thresholds
    'http_req_duration': [
      'p(50)<200',   // 50% of requests < 200ms
      'p(95)<1000',  // 95% of requests < 1s
      'p(99)<2000',  // 99% of requests < 2s
    ],
    // Error rate threshold
    'errors': ['rate<0.01'],  // Less than 1% errors
    // Success rate threshold
    'success': ['rate>0.99'],  // More than 99% success
  },
};

// Entities and operations for testing
const ENTITIES = ['purchase_order', 'supplier', 'goods_receipt', 'invoice_receipt', 'payment'];

// Headers for authenticated requests
function getHeaders() {
  return {
    'Content-Type': 'application/json',
    'x-demo-user': ADMIN_USER,
  };
}

// Mixed operations - simulates realistic workload
export function mixedOperations() {
  const random = Math.random();
  const entity = ENTITIES[Math.floor(Math.random() * ENTITIES.length)];

  let response;
  let operationType;

  if (random < 0.5) {
    // 50% - List views (most common)
    operationType = 'list';
    response = http.get(
      `${BASE_URL}/ui/${entity}/list?page=1&page_size=25`,
      { headers: getHeaders(), tags: { operation: 'list' } }
    );
  } else if (random < 0.8) {
    // 30% - Form views
    operationType = 'form';
    response = http.get(
      `${BASE_URL}/ui/${entity}/form/create`,
      { headers: getHeaders(), tags: { operation: 'form' } }
    );
  } else if (random < 0.95) {
    // 15% - API data fetch
    operationType = 'api';
    response = http.get(
      `${BASE_URL}/api/${entity}`,
      { headers: getHeaders(), tags: { operation: 'api' } }
    );
  } else {
    // 5% - Dashboard and navigation
    operationType = 'dashboard';
    response = http.get(
      `${BASE_URL}/ui/dashboard`,
      { headers: getHeaders(), tags: { operation: 'dashboard' } }
    );
  }

  requestCount.add(1);
  responseDuration.add(response.timings.duration);

  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 1s': (r) => r.timings.duration < 1000,
    'response has content': (r) => r.body && r.body.length > 0,
  });

  errorRate.add(!success);
  successRate.add(success);
}

// User session - simulates a real user browsing
export function userSession() {
  // 1. View dashboard
  let response = http.get(
    `${BASE_URL}/ui/dashboard`,
    { headers: getHeaders() }
  );
  requestCount.add(1);
  check(response, { 'dashboard loads': (r) => r.status === 200 });
  sleep(1);

  // 2. Browse purchase orders
  response = http.get(
    `${BASE_URL}/ui/purchase_order/list`,
    { headers: getHeaders() }
  );
  requestCount.add(1);
  responseDuration.add(response.timings.duration);
  check(response, { 'PO list loads': (r) => r.status === 200 });
  sleep(2);

  // 3. Apply filter
  response = http.get(
    `${BASE_URL}/ui/purchase_order/list?status=approved&page=1`,
    { headers: getHeaders() }
  );
  requestCount.add(1);
  responseDuration.add(response.timings.duration);
  check(response, { 'filtered list loads': (r) => r.status === 200 });
  sleep(1);

  // 4. Open create form
  response = http.get(
    `${BASE_URL}/ui/purchase_order/form/create`,
    { headers: getHeaders() }
  );
  requestCount.add(1);
  responseDuration.add(response.timings.duration);
  check(response, { 'create form loads': (r) => r.status === 200 });
  sleep(1);

  // 5. Browse suppliers
  response = http.get(
    `${BASE_URL}/ui/supplier/list`,
    { headers: getHeaders() }
  );
  requestCount.add(1);
  responseDuration.add(response.timings.duration);
  check(response, { 'supplier list loads': (r) => r.status === 200 });
  sleep(1);

  // 6. View invoices
  response = http.get(
    `${BASE_URL}/ui/invoice_receipt/list`,
    { headers: getHeaders() }
  );
  requestCount.add(1);
  responseDuration.add(response.timings.duration);
  check(response, { 'invoice list loads': (r) => r.status === 200 });
  sleep(1);
}

// Health check scenario for basic availability testing
export function healthCheck() {
  const response = http.get(`${BASE_URL}/health`);
  check(response, {
    'health check OK': (r) => r.status === 200,
    'health check fast': (r) => r.timings.duration < 100,
  });
}

// Summary handler
export function handleSummary(data) {
  const summary = [];

  summary.push('');
  summary.push('========================================');
  summary.push('LOAD TEST SUMMARY');
  summary.push('========================================');
  summary.push('');

  // HTTP request stats
  if (data.metrics.http_req_duration) {
    const httpStats = data.metrics.http_req_duration.values;
    summary.push('HTTP Request Duration:');
    summary.push(`  Average: ${httpStats.avg.toFixed(2)}ms`);
    summary.push(`  P50: ${httpStats['p(50)'].toFixed(2)}ms`);
    summary.push(`  P95: ${httpStats['p(95)'].toFixed(2)}ms`);
    summary.push(`  P99: ${httpStats['p(99)'].toFixed(2)}ms`);
    summary.push(`  Max: ${httpStats.max.toFixed(2)}ms`);
    summary.push('');
  }

  // Error rate
  if (data.metrics.errors) {
    const errRate = data.metrics.errors.values.rate * 100;
    summary.push(`Error Rate: ${errRate.toFixed(2)}%`);
  }

  // Success rate
  if (data.metrics.success) {
    const succRate = data.metrics.success.values.rate * 100;
    summary.push(`Success Rate: ${succRate.toFixed(2)}%`);
  }

  // Total requests
  if (data.metrics.total_requests) {
    summary.push(`Total Requests: ${data.metrics.total_requests.values.count}`);
  }

  // HTTP request count
  if (data.metrics.http_reqs) {
    summary.push(`HTTP Requests: ${data.metrics.http_reqs.values.count}`);
    const rps = data.metrics.http_reqs.values.rate;
    summary.push(`Requests/sec: ${rps.toFixed(2)}`);
  }

  summary.push('');
  summary.push('Threshold Results:');

  // Check thresholds
  if (data.root_group && data.root_group.checks) {
    for (const [name, check] of Object.entries(data.root_group.checks)) {
      const passed = check.passes / (check.passes + check.fails) * 100;
      summary.push(`  ${name}: ${passed.toFixed(1)}% passed`);
    }
  }

  summary.push('');
  summary.push('========================================');
  summary.push('');

  console.log(summary.join('\n'));

  return {
    'stdout': summary.join('\n'),
    'load-test-results.json': JSON.stringify(data),
  };
}
