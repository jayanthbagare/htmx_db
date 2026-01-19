/**
 * Jest Configuration for HTMX DB API
 */
export default {
  testEnvironment: 'node',
  transform: {},
  moduleFileExtensions: ['js', 'mjs'],
  testMatch: [
    '**/tests/**/*.test.js',
    '**/tests/**/*.test.mjs'
  ],
  testPathIgnorePatterns: [
    '/node_modules/',
    '/tests/database/'  // SQL tests run separately
  ],
  setupFilesAfterEnv: ['./tests/setup.js'],
  testTimeout: 30000,
  verbose: true,
  collectCoverageFrom: [
    'src/**/*.js',
    '!src/server.js'  // Entry point excluded
  ],
  coverageThreshold: {
    global: {
      branches: 70,
      functions: 80,
      lines: 80,
      statements: 80
    }
  }
};
