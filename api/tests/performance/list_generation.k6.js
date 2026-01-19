/**
 * Performance Tests: List Generation
 * k6 load test for measuring list generation performance
 *
 * Run with: k6 run tests/performance/list_generation.k6.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

// Custom metrics
const listGenDuration = new Trend('list_generation_duration');
const formGenDuration = new Trend('form_generation_duration');
const errorRate = new Rate('errors');
const requestCount = new Counter('requests');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const ADMIN_USER = '00000000-0000-0000-0000-000000000100';

// Test options
export const options = {
  scenarios: {
    // Scenario 1: List generation performance
    list_generation: {
      executor: 'constant-vus',
      vus: 5,
      duration: '1m',
      exec: 'testListGeneration',
    },
    // Scenario 2: Form generation performance
    form_generation: {
      executor: 'constant-vus',
      vus: 3,
      duration: '1m',
      exec: 'testFormGeneration',
      startTime: '1m',
    },
    // Scenario 3: Mixed workload
    mixed_workload: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '1m', target: 10 },
        { duration: '30s', target: 0 },
      ],
      exec: 'testMixedWorkload',
      startTime: '2m',
    },
  },
  thresholds: {
    // List generation thresholds
    'list_generation_duration': ['p(95)<300', 'avg<200'],
    // Form generation thresholds
    'form_generation_duration': ['p(95)<200', 'avg<100'],
    // Error rate threshold
    'errors': ['rate<0.01'],
    // HTTP duration thresholds
    'http_req_duration': ['p(95)<500'],
  },
};

// Headers for authenticated requests
function getHeaders() {
  return {
    'Content-Type': 'application/json',
    'x-demo-user': ADMIN_USER,
  };
}

// Test entities to cycle through
const ENTITIES = ['purchase_order', 'supplier', 'goods_receipt', 'invoice_receipt', 'payment'];

// Scenario: List Generation
export function testListGeneration() {
  const entity = ENTITIES[Math.floor(Math.random() * ENTITIES.length)];
  const page = Math.floor(Math.random() * 5) + 1;

  const response = http.get(
    `${BASE_URL}/ui/${entity}/list?page=${page}&page_size=25`,
    { headers: getHeaders() }
  );

  requestCount.add(1);
  listGenDuration.add(response.timings.duration);

  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response is HTML': (r) => r.headers['Content-Type'].includes('text/html'),
    'response time < 300ms': (r) => r.timings.duration < 300,
    'response has content': (r) => r.body && r.body.length > 0,
  });

  errorRate.add(!success);
  sleep(0.5);
}

// Scenario: Form Generation
export function testFormGeneration() {
  const entity = ENTITIES[Math.floor(Math.random() * ENTITIES.length)];

  // Test create form
  const createResponse = http.get(
    `${BASE_URL}/ui/${entity}/form/create`,
    { headers: getHeaders() }
  );

  requestCount.add(1);
  formGenDuration.add(createResponse.timings.duration);

  const success = check(createResponse, {
    'create form status is 200': (r) => r.status === 200,
    'create form is HTML': (r) => r.headers['Content-Type'].includes('text/html'),
    'create form time < 200ms': (r) => r.timings.duration < 200,
    'create form has form element': (r) => r.body && r.body.includes('form'),
  });

  errorRate.add(!success);
  sleep(0.5);
}

// Scenario: Mixed Workload
export function testMixedWorkload() {
  const random = Math.random();

  if (random < 0.6) {
    // 60% list views
    testListGeneration();
  } else if (random < 0.9) {
    // 30% form views
    testFormGeneration();
  } else {
    // 10% API data fetch
    const entity = ENTITIES[Math.floor(Math.random() * ENTITIES.length)];
    const response = http.get(
      `${BASE_URL}/api/${entity}`,
      { headers: getHeaders() }
    );

    requestCount.add(1);

    check(response, {
      'API status is 200': (r) => r.status === 200,
      'API response time < 300ms': (r) => r.timings.duration < 300,
    });
  }

  sleep(0.3);
}

// Summary handler
export function handleSummary(data) {
  console.log('\n========================================');
  console.log('PERFORMANCE TEST SUMMARY');
  console.log('========================================\n');

  // List generation stats
  if (data.metrics.list_generation_duration) {
    const listStats = data.metrics.list_generation_duration.values;
    console.log('List Generation:');
    console.log(`  Average: ${listStats.avg.toFixed(2)}ms`);
    console.log(`  P95: ${listStats['p(95)'].toFixed(2)}ms`);
    console.log(`  Max: ${listStats.max.toFixed(2)}ms`);
    console.log('');
  }

  // Form generation stats
  if (data.metrics.form_generation_duration) {
    const formStats = data.metrics.form_generation_duration.values;
    console.log('Form Generation:');
    console.log(`  Average: ${formStats.avg.toFixed(2)}ms`);
    console.log(`  P95: ${formStats['p(95)'].toFixed(2)}ms`);
    console.log(`  Max: ${formStats.max.toFixed(2)}ms`);
    console.log('');
  }

  // Error rate
  if (data.metrics.errors) {
    const errRate = data.metrics.errors.values.rate * 100;
    console.log(`Error Rate: ${errRate.toFixed(2)}%`);
    console.log('');
  }

  // Total requests
  if (data.metrics.requests) {
    console.log(`Total Requests: ${data.metrics.requests.values.count}`);
  }

  console.log('\n========================================\n');

  return {
    'stdout': JSON.stringify(data, null, 2),
    'performance-results.json': JSON.stringify(data),
  };
}
