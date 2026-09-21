#!/usr/bin/env node
/*
 * td-claude2td-connect — launcher
 *
 * Wraps the official Treasure Data MCP server (@treasuredata/mcp-server, Apache-2.0)
 * and adds two guarantees before handing over control:
 *
 *   1. Write operations are hard-locked off. TD_ENABLE_UPDATES cannot be turned on
 *      from the outside, so the `execute` tool always refuses.
 *   2. The upstream read-only guard is tightened. Upstream strips only `--` comments
 *      when it classifies a statement, so a block comment disguises a write:
 *          "/* x *\/ DROP TABLE t"  ->  queryType UNKNOWN  ->  allowed through
 *      The patch below re-checks every statement after stripping block comments,
 *      line comments and string literals, and fails closed.
 *
 * This is defence in depth, not the primary control. The primary control is the
 * Treasure Data side: use a dedicated read-only user whose policy is scoped to the
 * databases it is allowed to see. See README.md.
 */

'use strict';

process.env.TD_ENABLE_UPDATES = 'false';

function fatal(message) {
  console.error(`[td-claude2td-connect] ${message}`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Harden the upstream query validator (fail closed if it cannot be patched)
// ---------------------------------------------------------------------------

let QueryValidator;
try {
  ({ QueryValidator } = require('@treasuredata/mcp-server/dist/security/query-validator.js'));
} catch (error) {
  fatal(
    'Could not load the upstream query validator, so the read-only guard cannot be ' +
      'installed. Refusing to start. Please report this at ' +
      'https://github.com/tsukaharakazuki/td_tas_skill_extension/issues'
  );
}

if (!QueryValidator || typeof QueryValidator.prototype.validate !== 'function') {
  fatal(
    'The upstream query validator has an unexpected shape, so the read-only guard ' +
      'cannot be installed. Refusing to start.'
  );
}

// Remove block comments, line comments and single-quoted string literals so that
// keyword matching cannot be fooled by disguised or quoted text.
function normalize(sql) {
  return String(sql == null ? '' : sql)
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--[^\n]*/g, ' ')
    .replace(/'(?:[^']|'')*'/g, "''");
}

const READ_ONLY_HEAD = /^\s*\(*\s*(WITH|SELECT|SHOW|DESCRIBE|DESC|EXPLAIN)\b/i;
const WRITE_KEYWORD =
  /\b(INSERT|UPDATE|DELETE|MERGE|CREATE|DROP|ALTER|TRUNCATE|GRANT|REVOKE|CALL|SET\s+SESSION)\b/i;

const upstreamValidate = QueryValidator.prototype.validate;

QueryValidator.prototype.validate = function validate(sql) {
  const result = upstreamValidate.call(this, sql);
  if (!result || result.isValid === false) {
    return result;
  }

  const bare = normalize(sql);

  if (!READ_ONLY_HEAD.test(bare)) {
    return {
      isValid: false,
      queryType: result.queryType,
      error:
        'This connection is read-only. A statement must begin with SELECT, WITH, SHOW, ' +
        'DESCRIBE or EXPLAIN once comments are removed.',
    };
  }

  if (WRITE_KEYWORD.test(bare)) {
    return {
      isValid: false,
      queryType: result.queryType,
      error:
        'This connection is read-only. The statement contains a write keyword ' +
        '(INSERT / UPDATE / DELETE / MERGE / CREATE / DROP / ALTER / TRUNCATE).',
    };
  }

  return result;
};

// ---------------------------------------------------------------------------
// Remove the tools that can change state
// ---------------------------------------------------------------------------
// `execute` runs write SQL (it refuses while updates are off, but listing it
// invites the assistant to try). `kill_attempt`, `retry_session` and
// `retry_attempt` act on Treasure Workflow and are NOT covered by
// TD_ENABLE_UPDATES or by SQL validation, so for a read-only connection they
// have to be withheld here. Fail closed if the filter cannot be installed.

const BLOCKED_TOOLS = new Set([
  'execute',
  'kill_attempt',
  'retry_session',
  'retry_attempt',
]);

try {
  const { Server } = require('@modelcontextprotocol/sdk/server/index.js');
  const originalSetRequestHandler = Server.prototype.setRequestHandler;

  Server.prototype.setRequestHandler = function setRequestHandler(schema, handler) {
    const wrapped = async function wrappedHandler(...args) {
      const request = args[0];
      const name = request && request.params && request.params.name;
      if (name && BLOCKED_TOOLS.has(name)) {
        throw new Error(
          `"${name}" is not available: this connection is read-only.`
        );
      }

      const response = await handler.apply(this, args);
      if (response && Array.isArray(response.tools)) {
        return Object.assign({}, response, {
          tools: response.tools.filter((tool) => !BLOCKED_TOOLS.has(tool && tool.name)),
        });
      }
      return response;
    };
    return originalSetRequestHandler.call(this, schema, wrapped);
  };
} catch (error) {
  fatal(
    'Could not install the read-only tool filter, so state-changing tools would ' +
      'be exposed. Refusing to start.'
  );
}

// ---------------------------------------------------------------------------
// Configuration sanity checks (clearer messages than the upstream defaults)
// ---------------------------------------------------------------------------

const VALID_SITES = ['us01', 'jp01', 'eu01', 'ap02', 'ap03'];

if (!process.env.TD_API_KEY) {
  fatal(
    'No API key is configured. Open Settings -> Extensions -> Treasure Data (read-only) ' +
      'and paste your Treasure Data API key.'
  );
}

if (!process.env.TD_SITE) {
  process.env.TD_SITE = 'jp01';
}

if (!VALID_SITES.includes(process.env.TD_SITE)) {
  fatal(
    `TD_SITE "${process.env.TD_SITE}" is not a known region. ` +
      `Choose one of: ${VALID_SITES.join(', ')}.`
  );
}

// ---------------------------------------------------------------------------
// Hand over to the official server
// ---------------------------------------------------------------------------

require('@treasuredata/mcp-server');
