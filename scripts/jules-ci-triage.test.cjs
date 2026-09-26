'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const triage = require('./jules-ci-triage.cjs');

const run = {
  id: 42,
  workflow_id: 7,
  name: 'Aether Update',
  conclusion: 'failure',
  head_branch: 'main',
  head_sha: '1234567890abcdef',
  html_url: 'https://github.com/psyc-exe/termux-dark-aether/actions/runs/42',
  repository: {full_name: 'psyc-exe/termux-dark-aether'},
  event: 'schedule',
};

function harness(existing = []) {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push(['jules', url, options]);
    const payload = url.endsWith('/sessions')
      ? {name: 'sessions/99', id: '99', url: 'https://jules.google.com/session/99'}
      : {sources: [{name: 'sources/github/psyc-exe/termux-dark-aether', githubRepo: {owner: 'psyc-exe', repo: 'termux-dark-aether'}}]};
    return {ok: true, json: async () => payload};
  };
  const github = {
    rest: {
      issues: {
        listForRepo: () => {},
        create: async args => { calls.push(['create', args]); return {data: {number: 3, html_url: 'https://github.com/issue/3', body: args.body}}; },
        update: async args => { calls.push(['update', args]); },
      },
      actions: {listJobsForWorkflowRun: () => {}},
    },
    paginate: async (method) => method === github.rest.issues.listForRepo
      ? existing
      : [{name: 'Patch & Tag', steps: [{name: 'checkout', conclusion: 'failure'}]}],
  };
  return {github, calls, fetchImpl, apiKey: 'test-key', guide: 'handoff.md', context: {payload: {workflow_run: run}, repo: {owner: 'psyc-exe', repo: 'termux-dark-aether'}}, core: {info: () => {}}};
}

test('creates an issue and a Jules session with automatic PR creation', async () => {
  const setup = harness();
  await triage(setup);
  assert.deepEqual(setup.calls.map(call => call[0]), ['jules', 'create', 'jules', 'update']);
  assert.match(setup.calls[1][1].body, /Patch & Tag: checkout/);
  assert.match(setup.calls[1][1].body, /Read handoff.md/);
  assert.match(setup.calls[1][1].body, /<!-- jules-ci:7:1234567890abcdef -->/);
  const session = JSON.parse(setup.calls[2][2].body);
  assert.equal(session.automationMode, 'AUTO_CREATE_PR');
  assert.equal(session.sourceContext.source, 'sources/github/psyc-exe/termux-dark-aether');
  assert.match(setup.calls[3][1].body, /Jules session: https:\/\/jules.google.com\/session\/99/);
});

test('does not dispatch a repeat failure for the same workflow and commit', async () => {
  const setup = harness([{body: '<!-- jules-ci:7:1234567890abcdef --><!-- jules-session:sessions/99 -->'}]);
  await triage(setup);
  assert.equal(setup.calls.length, 0);
});

test('retries an issue whose Jules dispatch did not complete', async () => {
  const setup = harness([{number: 3, html_url: 'https://github.com/issue/3', body: '<!-- jules-ci:7:1234567890abcdef -->'}]);
  await triage(setup);
  assert.deepEqual(setup.calls.map(call => call[0]), ['jules', 'jules', 'update']);
});

test('ignores runs from a fork or another branch', async () => {
  const setup = harness();
  setup.context.payload.workflow_run = {...run, head_branch: 'feature'};
  await triage(setup);
  assert.equal(setup.calls.length, 0);
  setup.context.payload.workflow_run = {...run, repository: {full_name: 'someone/fork'}};
  await triage(setup);
  assert.equal(setup.calls.length, 0);
});
