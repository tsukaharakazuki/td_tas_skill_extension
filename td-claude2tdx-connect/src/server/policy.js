'use strict';

/*
 * Permission policy for tdx_run.
 *
 * tdx exposes a single MCP tool that runs any tdx CLI command, so the policy
 * has to be expressed over command names rather than over tools. Everything is
 * decided from the `args` array the assistant passes.
 */

// Commands that are never allowed, in any mode.
//   auth / profile / profiles / mcp — already refused by tdx itself; repeated
//     here so the refusal message is ours and the intent is explicit
//   upgrade — would rewrite the copy of tdx bundled inside this extension
//   claude / codex — launch interactive agents; they would hang a tool call
const ALWAYS_BLOCKED = new Set([
  'auth',
  'profile',
  'profiles',
  'mcp',
  'upgrade',
  'claude',
  'codex',
]);

// Account administration. Gated behind its own switch, separate from the mode,
// because `policy` can widen the very permissions this connection runs under.
const ADMIN_COMMANDS = new Set(['user', 'users', 'policy']);

// Aliases documented in `tdx --help`.
const ALIASES = {
  db: 'database',
  sg: 'segment',
  ps: 'parent-segment',
  wf: 'workflow',
  desc: 'describe',
};

// Top-level commands that only read, whatever subcommand follows.
const READ_COMMANDS = new Set([
  'databases',
  'tables',
  'segments',
  'journeys',
  'agents',
  'activations',
  'chats',
  'status',
  'show',
  'describe',
  'use',
  'unset',
]);

// Subcommands that only read, for the group commands below.
const READ_SUBCOMMANDS = new Set([
  'list',
  'ls',
  'show',
  'get',
  'describe',
  'desc',
  'fields',
  'log',
  'logs',
  'status',
  'history',
  'attempts',
  'tasks',
  'search',
  'diff',
  'validate',
  'pull',
]);

// Group commands whose read subcommands are allowed in readonly mode.
const GROUP_COMMANDS = new Set([
  'database',
  'table',
  'job',
  'workflow',
  'segment',
  'parent-segment',
  'journey',
  'engage',
  'delivery',
  'connection',
  'cas',
  'agent',
  'llm',
  'user',
  'policy',
  'work',
  'schedule',
]);

// Additionally allowed in `operate`: running and recovering existing jobs and
// workflows. Definitions are still not editable.
const OPERATE_COMMANDS = new Set(['workflow', 'job', 'schedule']);

// Commands that carry SQL and therefore need the statement itself checked.
const SQL_COMMANDS = new Set(['query']);

const MODES = new Set(['full', 'operate', 'readonly']);

// --- SQL read-only check -----------------------------------------------------
// Same approach as the read-only Treasure Data extension: strip block comments,
// line comments and string literals before matching, so neither a disguised nor
// a quoted keyword can decide the outcome.

function normalizeSql(sql) {
  return String(sql == null ? '' : sql)
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--[^\n]*/g, ' ')
    .replace(/'(?:[^']|'')*'/g, "''");
}

const READ_ONLY_HEAD = /^\s*\(*\s*(WITH|SELECT|SHOW|DESCRIBE|DESC|EXPLAIN)\b/i;
const WRITE_KEYWORD =
  /\b(INSERT|UPDATE|DELETE|MERGE|CREATE|DROP|ALTER|TRUNCATE|GRANT|REVOKE|CALL)\b/i;

function isReadOnlySql(sql) {
  const bare = normalizeSql(sql);
  if (!bare.trim()) return true; // no statement given; tdx will complain itself
  return READ_ONLY_HEAD.test(bare) && !WRITE_KEYWORD.test(bare);
}

// The first argument that is not an option flag, after the command name.
function firstPositional(args, from) {
  for (let i = from; i < args.length; i++) {
    const value = args[i];
    if (typeof value === 'string' && !value.startsWith('-')) return value;
  }
  return undefined;
}

/**
 * @param {string[]} args   the `args` array from the tdx_run call
 * @param {{mode: string, allowAdmin: boolean}} options
 * @returns {{allowed: boolean, reason?: string}}
 */
function check(args, options) {
  const mode = options.mode;
  const allowAdmin = options.allowAdmin === true;

  if (!Array.isArray(args) || args.length === 0) {
    return { allowed: false, reason: 'No command was given.' };
  }

  const raw = firstPositional(args, 0);
  if (!raw) {
    return { allowed: false, reason: 'No command was given.' };
  }

  const command = ALIASES[raw] || raw;

  if (ALWAYS_BLOCKED.has(command) || ALWAYS_BLOCKED.has(raw)) {
    return {
      allowed: false,
      reason: `"${raw}" is not available through this extension in any mode.`,
    };
  }

  if (ADMIN_COMMANDS.has(command) && !allowAdmin) {
    const subcommand = firstPositional(args, args.indexOf(raw) + 1);
    const reading = command === 'users' || READ_SUBCOMMANDS.has(subcommand);
    if (!reading) {
      return {
        allowed: false,
        reason:
          `"${raw}" changes users or access policies. Turn on "管理コマンドを許可" ` +
          'in this extension\'s settings if that is intended.',
      };
    }
  }

  if (mode === 'full') {
    return { allowed: true };
  }

  // SQL-carrying commands: the statement decides, in both remaining modes.
  if (SQL_COMMANDS.has(command)) {
    const sql = firstPositional(args, args.indexOf(raw) + 1);
    if (isReadOnlySql(sql)) return { allowed: true };
    return {
      allowed: false,
      reason:
        `This connection runs in "${mode}" mode, which allows read-only SQL. ` +
        'The statement must begin with SELECT, WITH, SHOW, DESCRIBE or EXPLAIN ' +
        'and contain no write keywords.',
    };
  }

  if (mode === 'operate' && OPERATE_COMMANDS.has(command)) {
    return { allowed: true };
  }

  if (READ_COMMANDS.has(command)) {
    return { allowed: true };
  }

  if (GROUP_COMMANDS.has(command)) {
    const subcommand = firstPositional(args, args.indexOf(raw) + 1);
    if (subcommand && READ_SUBCOMMANDS.has(subcommand)) {
      return { allowed: true };
    }
    const shown = subcommand ? `${raw} ${subcommand}` : raw;
    return {
      allowed: false,
      reason:
        `This connection runs in "${mode}" mode, so "${shown}" is not allowed. ` +
        `Read-only subcommands are: ${[...READ_SUBCOMMANDS].join(', ')}.`,
    };
  }

  return {
    allowed: false,
    reason:
      `This connection runs in "${mode}" mode and "${raw}" is not on the ` +
      'allowed list. Change the mode in the extension settings if this command ' +
      'is meant to be available.',
  };
}

module.exports = { check, isReadOnlySql, MODES, ALWAYS_BLOCKED };
