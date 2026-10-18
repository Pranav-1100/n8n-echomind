#!/usr/bin/env node
// Static checks for the EchoMind n8n workflow exports. Runs in CI before any
// image is built, so a broken or unsafe workflow never reaches a cluster.
//   node scripts/validate-workflows.mjs [workflows-dir]
import { readdirSync, readFileSync } from 'node:fs';
import { join, basename } from 'node:path';

const dir = process.argv[2] || 'workflows';
const ERROR_WORKFLOW_ID = 'idlaz2HumpPA0ZDI';
// Workflows that must not point at the error logger (it would call itself,
// and the health check is deliberately dependency-free).
const NO_ERROR_WORKFLOW = new Set(['error-logger.json', 'healthcheck.json']);

// Credential IDs the deployment provisions (docker/render-credentials.js).
const KNOWN_CREDENTIALS = new Map([
  ['echoLlmApi000001', 'openAiApi'],
  ['jmVN7xYccnea37Bw', 'huggingFaceApi'],
  ['echoMemoryDb0001', 'postgres'],
  ['echoIngestAuth01', 'httpHeaderAuth'],
  ['echoRecallAuth01', 'httpBasicAuth'],
]);
// Google credentials still referenced by email triage, which stays switched
// off until a Google OAuth client is configured.
const GOOGLE_CREDENTIALS = new Map([
  ['BQUufE0zxR9vozXu', 'gmailOAuth2'],
  ['rT4KDcdWTQem3Kev', 'googleSheetsOAuth2Api'],
]);
const GOOGLE_ALLOWED_IN = new Set(['email-triage.json']);

const RETIRED_NODE_TYPES = ['lmChatGroq', 'vectorStorePinecone'];

// Values that look like real secrets pasted into a workflow.
const SECRET_PATTERNS = [
  /\bsk-[A-Za-z0-9_-]{16,}/,
  /\bnvapi-[A-Za-z0-9_-]{16,}/,
  /\bhf_[A-Za-z0-9]{16,}/,
  /\bghp_[A-Za-z0-9]{20,}/,
  /\bAIza[0-9A-Za-z_-]{30,}/,
  /\bBearer\s+[A-Za-z0-9._-]{16,}/,
];
const SECRET_PARAM_NAMES = /^(api[_-]?key|password|token|secret|access[_-]?token)$/i;

function findSecrets(value, path, problems) {
  if (typeof value === 'string') {
    for (const pattern of SECRET_PATTERNS) {
      if (pattern.test(value)) problems.push(`possible secret in ${path}`);
    }
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((item, i) => findSecrets(item, `${path}[${i}]`, problems));
    return;
  }
  if (value && typeof value === 'object') {
    for (const [key, child] of Object.entries(value)) {
      const childPath = `${path}.${key}`;
      // A literal (non-expression) value in a field named like a secret.
      if (SECRET_PARAM_NAMES.test(key) && typeof child === 'string' && child !== '' && !child.startsWith('=')) {
        problems.push(`literal value in secret-like field ${childPath}`);
      }
      findSecrets(child, childPath, problems);
    }
  }
}

function webhookPaths(node) {
  const type = node.type || '';
  if (type.endsWith('.webhook') && node.parameters?.path) return [node.parameters.path];
  if (type.endsWith('.chatTrigger') && node.webhookId) return [`${node.webhookId}/chat`];
  return [];
}

function validate(file, wf, seenPaths, seenIds) {
  const problems = [];
  for (const field of ['name', 'id']) {
    if (typeof wf[field] !== 'string' || wf[field] === '') problems.push(`missing "${field}"`);
  }
  if (!Array.isArray(wf.nodes) || wf.nodes.length === 0) problems.push('missing "nodes"');
  if (!wf.connections || typeof wf.connections !== 'object') problems.push('missing "connections"');
  if (problems.length) return problems;

  if (seenIds.has(wf.id)) problems.push(`workflow id ${wf.id} also used by ${seenIds.get(wf.id)}`);
  seenIds.set(wf.id, file);

  const names = new Set();
  for (const node of wf.nodes) {
    if (names.has(node.name)) problems.push(`duplicate node name "${node.name}"`);
    names.add(node.name);

    for (const retired of RETIRED_NODE_TYPES) {
      if ((node.type || '').endsWith(`.${retired}`)) problems.push(`node "${node.name}" uses retired type ${retired}`);
    }

    for (const [type, ref] of Object.entries(node.credentials || {})) {
      const known = KNOWN_CREDENTIALS.get(ref?.id);
      const google = GOOGLE_CREDENTIALS.get(ref?.id);
      if (known === type) continue;
      if (google === type && GOOGLE_ALLOWED_IN.has(file)) continue;
      problems.push(`node "${node.name}" references unknown credential ${type}/${ref?.id}`);
    }

    for (const path of webhookPaths(node)) {
      if (seenPaths.has(path)) problems.push(`webhook path "${path}" also used in ${seenPaths.get(path)}`);
      seenPaths.set(path, file);
    }
  }

  for (const [source, outputsByType] of Object.entries(wf.connections)) {
    if (!names.has(source)) problems.push(`connection from unknown node "${source}"`);
    for (const outputs of Object.values(outputsByType || {})) {
      for (const output of outputs || []) {
        for (const link of output || []) {
          if (!names.has(link.node)) problems.push(`connection from "${source}" to unknown node "${link.node}"`);
        }
      }
    }
  }

  const errorWorkflow = wf.settings?.errorWorkflow;
  if (NO_ERROR_WORKFLOW.has(file)) {
    if (errorWorkflow) problems.push(`must not set settings.errorWorkflow (got ${errorWorkflow})`);
  } else if (errorWorkflow !== ERROR_WORKFLOW_ID) {
    problems.push(`settings.errorWorkflow must be ${ERROR_WORKFLOW_ID} (got ${errorWorkflow ?? 'nothing'})`);
  }

  findSecrets(wf, 'workflow', problems);
  return problems;
}

const files = readdirSync(dir).filter((f) => f.endsWith('.json')).sort();
if (files.length === 0) {
  console.error(`no workflow files found in ${dir}`);
  process.exit(1);
}

const seenPaths = new Map();
const seenIds = new Map();
let failed = 0;
for (const file of files) {
  let wf;
  let problems;
  try {
    wf = JSON.parse(readFileSync(join(dir, file), 'utf8'));
    problems = validate(basename(file), wf, seenPaths, seenIds);
  } catch (err) {
    problems = [`invalid JSON: ${err.message}`];
  }
  if (problems.length) {
    failed += 1;
    console.log(`FAIL ${file}`);
    for (const p of problems) console.log(`     - ${p}`);
  } else {
    console.log(`ok   ${file}  (${wf.name}, ${wf.nodes.length} nodes)`);
  }
}

console.log(`\n${files.length - failed}/${files.length} workflows valid`);
process.exit(failed ? 1 : 0);
