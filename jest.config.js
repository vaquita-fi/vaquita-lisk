/** @type {import('jest').Config} */
const config = {
  // Explicitly tell Jest to only look for tests in this directory.
  // This prevents it from scanning your `lib` folders and finding duplicate packages.
  roots: [
    "<rootDir>/contracts/integration-tests"
  ],

  // This is required for Jest to handle ES Modules (`import` syntax) correctly.
  transform: {},
};

export default config; 