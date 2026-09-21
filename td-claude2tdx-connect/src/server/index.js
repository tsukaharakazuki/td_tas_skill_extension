#!/usr/bin/env node
/*
 * td-claude2tdx-connect — launcher
 *
 * Runs `tdx mcp` (the official Treasure AI CLI's MCP server, bundled here) as a
 * child process and sits between it and the client as a JSON-RPC proxy.
 *
 * Why a proxy rather than patching tdx: `tdx mcp` exposes a single tool,
 * `tdx_run`, which executes any tdx CLI command. There is no read-only switch,
 * and tdx ships a new calendar-versioned release most months with a minified
 * build, so anything that reaches into its internals would break. Speaking the
 * protocol instead keeps this layer independent of tdx's implementation.
 *
 * What the proxy does:
 *   - checks every tdx_run call against the configured permission mode and
 *     refuses the ones the mode does not allow, before tdx ever sees them
 *   - refuses work_create_item in readonly mode
 *   - annotates the tool descriptions so the assistant knows what it may call
 *
 * The permission mode is convenience and blast-radius reduction. It is NOT the
 * security boundary: tdx acts with the full rights of the Treasure Data user
 * behind the API key. Scope that user with a Treasure Data policy. See README.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const policy = require('./policy.js');

function fatal(message) {
  process.stderr.write(`[td-claude2tdx-connect] ${message}\n`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// An optional user_config field that the user left blank can arrive as an empty
// string or, on some hosts, as the unexpanded "${user_config.x}" placeholder.
// Treat both as "not set".
function setting(name, fallback) {
  const value = (process.env[name] || '').trim();
  if (!value || value.startsWith('${')) return fallback;
  return value;
}

const mode = setting('TDCC_MODE', 'full').toLowerCase();
if (!policy.MODES.has(mode)) {
  fatal(
    `Unknown permission mode "${mode}". Choose one of: ${[...policy.MODES].join(', ')}.`
  );
}

const allowAdmin = setting('TDCC_ALLOW_ADMIN', 'false').toLowerCase() === 'true';

const profile = setting('TDX_PROFILE', '');
const apiKey = setting('TDX_API_KEY', '');

if (!profile && !apiKey) {
  fatal(
    'No credentials configured. Open Settings -> Extensions -> Treasure Data (tdx) ' +
      'and enter either an API key or the name of an existing tdx profile.'
  );
}

const VALID_SITES = ['us01', 'jp01', 'eu01', 'ap02', 'ap03'];
const site = setting('TDX_SITE', 'jp01');
if (!VALID_SITES.includes(site)) {
  fatal(`TDX_SITE "${site}" is not a known region. Choose one of: ${VALID_SITES.join(', ')}.`);
}

const childEnv = Object.assign({}, process.env, { TDX_SITE: site });
if (profile) {
  // A named profile wins; drop the key so tdx does not mix the two.
  childEnv.TDX_PROFILE = profile;
  delete childEnv.TDX_API_KEY;
} else {
  delete childEnv.TDX_PROFILE;
  childEnv.TDX_API_KEY = apiKey;
}
// Our own settings are consumed here; the child does not need them.
delete childEnv.TDCC_MODE;
delete childEnv.TDCC_ALLOW_ADMIN;

const MODE_NOTE = {
  full: 'This connection runs in FULL mode: every tdx command is available, including ones that write.',
  operate:
    'This connection runs in OPERATE mode: reading, plus running and recovering jobs, workflows and schedules. ' +
    'Definitions cannot be edited and SQL must be read-only.',
  readonly:
    'This connection runs in READ-ONLY mode: only reading commands, and SQL must be read-only.',
}[mode];

// ---------------------------------------------------------------------------
// Start tdx
// ---------------------------------------------------------------------------

// Resolved by path rather than require.resolve: the package declares an
// "exports" map that does not expose dist/bin.js as a subpath.
const tdxBin = path.join(__dirname, 'node_modules', '@treasuredata', 'tdx', 'dist', 'bin.js');

if (!fs.existsSync(tdxBin)) {
  fatal(
    'The bundled tdx CLI is missing from this extension. Reinstall it from ' +
      'https://github.com/tsukaharakazuki/td_tas_skill_extension'
  );
}

const child = spawn(process.execPath, [tdxBin, 'mcp'], {
  env: childEnv,
  stdio: ['pipe', 'pipe', 'pipe'],
  cwd: path.dirname(tdxBin),
});

child.on('error', (error) => {
  fatal(`Could not start the bundled tdx: ${error.message}`);
});

child.on('exit', (code, signal) => {
  process.exit(typeof code === 'number' ? code : signal ? 1 : 0);
});

child.stderr.on('data', (chunk) => process.stderr.write(chunk));

// ---------------------------------------------------------------------------
// JSON-RPC plumbing
// ---------------------------------------------------------------------------

function send(stream, message) {
  stream.write(JSON.stringify(message) + '\n');
}

function toolError(id, text) {
  return {
    jsonrpc: '2.0',
    id,
    result: {
      content: [{ type: 'text', text }],
      isError: true,
    },
  };
}

// Reads newline-delimited JSON, passing through anything it cannot parse so a
// protocol change does not turn into dropped traffic.
function makeLineReader(onMessage, onPassthrough) {
  let buffer = '';
  return (chunk) => {
    buffer += chunk.toString('utf8');
    let index;
    while ((index = buffer.indexOf('\n')) !== -1) {
      const line = buffer.slice(0, index);
      buffer = buffer.slice(index + 1);
      if (!line.trim()) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch (error) {
        onPassthrough(line);
        continue;
      }
      onMessage(message, line);
    }
  };
}

// --- client -> tdx -----------------------------------------------------------

process.stdin.on(
  'data',
  makeLineReader(
    (message, line) => {
      const isToolCall =
        message && message.method === 'tools/call' && message.params && message.params.name;

      if (!isToolCall) {
        child.stdin.write(line + '\n');
        return;
      }

      const name = message.params.name;
      const args = (message.params.arguments || {}).args;

      if (name === 'tdx_run') {
        const verdict = policy.check(args, { mode, allowAdmin });
        if (!verdict.allowed) {
          send(process.stdout, toolError(message.id, verdict.reason));
          return;
        }
      } else if (name === 'work_create_item' && mode === 'readonly') {
        send(
          process.stdout,
          toolError(
            message.id,
            'Creating work items is not available in read-only mode.'
          )
        );
        return;
      }

      child.stdin.write(line + '\n');
    },
    (line) => child.stdin.write(line + '\n')
  )
);

process.stdin.on('end', () => child.stdin.end());

// --- tdx -> client -----------------------------------------------------------

child.stdout.on(
  'data',
  makeLineReader(
    (message, line) => {
      const tools = message && message.result && message.result.tools;
      if (!Array.isArray(tools)) {
        process.stdout.write(line + '\n');
        return;
      }

      const annotated = tools
        .filter((tool) => !(mode === 'readonly' && tool && tool.name === 'work_create_item'))
        .map((tool) => {
          if (!tool || typeof tool.description !== 'string') return tool;
          if (tool.name !== 'tdx_run' && tool.name !== 'work_create_item') return tool;
          return Object.assign({}, tool, {
            description: `${tool.description}\n\n${MODE_NOTE}`,
          });
        });

      send(
        process.stdout,
        Object.assign({}, message, {
          result: Object.assign({}, message.result, { tools: annotated }),
        })
      );
    },
    (line) => process.stdout.write(line + '\n')
  )
);

// Keep the child's lifetime tied to ours.
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    child.kill(signal);
  });
}
