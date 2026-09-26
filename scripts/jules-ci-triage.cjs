'use strict';

function failureKey(run) {
  return `jules-ci:${run.workflow_id}:${run.head_sha}`;
}

function failedSteps(jobs) {
  return jobs.flatMap(job =>
    (job.steps || [])
      .filter(step => step.conclusion === 'failure')
      .map(step => `- ${job.name}: ${step.name}`)
  );
}

function issueBody(run, steps, guide = 'README.md') {
  const marker = `<!-- ${failureKey(run)} -->`;
  const details = steps.length ? steps.join('\n') : '- See the linked run for the failed job and logs.';
  return `${marker}
## Failed workflow

- Run: ${run.html_url}
- Workflow: ${run.name}
- Commit: \`${run.head_sha}\`
- Event: ${run.event}

Failed steps:
${details}

## Jules task

Read ${guide} and the complete failed run logs. Find the root cause, make the smallest fix in **this repository**, run the relevant checks, and open a PR for review. Include the run link and test evidence in the PR. If the build needs missing source, credentials, hardware, or other external input, explain the blocker here instead of hiding the failure or inventing passing evidence. Do not edit the other A/B repository.
`;
}

async function julesRequest(fetchImpl, apiKey, path, options = {}) {
  const response = await fetchImpl(`https://jules.googleapis.com/v1alpha/${path}`, {
    ...options,
    headers: {
      'X-Goog-Api-Key': apiKey,
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });
  if (!response.ok) throw new Error(`Jules API request failed (${response.status}) for ${path}`);
  return response.json();
}

async function findSource(fetchImpl, apiKey, owner, repo) {
  let pageToken = '';
  do {
    const query = new URLSearchParams({pageSize: '100'});
    if (pageToken) query.set('pageToken', pageToken);
    const page = await julesRequest(fetchImpl, apiKey, `sources?${query}`);
    const source = (page.sources || []).find(item =>
      item.githubRepo?.owner?.toLowerCase() === owner.toLowerCase() &&
      item.githubRepo?.repo?.toLowerCase() === repo.toLowerCase());
    if (source) return source.name;
    pageToken = page.nextPageToken || '';
  } while (pageToken);
  throw new Error(`Connect ${owner}/${repo} to Jules before enabling CI triage.`);
}

async function triage({github, context, core, apiKey, guide = 'README.md', fetchImpl = globalThis.fetch}) {
  const run = context.payload.workflow_run;
  const {owner, repo} = context.repo;
  if (!run || run.conclusion !== 'failure' || run.head_branch !== 'main' ||
      run.repository?.full_name !== `${owner}/${repo}`) {
    core.info('Not a failed main-branch run from this repository.');
    return;
  }
  if (!apiKey) throw new Error('Set the JULES_API_KEY GitHub Actions secret before enabling CI triage.');

  const marker = `<!-- ${failureKey(run)} -->`;
  const issues = await github.paginate(github.rest.issues.listForRepo, {
    owner, repo, state: 'all', per_page: 100,
  });
  const existing = issues.find(issue => !issue.pull_request && issue.body?.includes(marker));
  if (existing?.body?.includes('<!-- jules-session:')) {
    core.info(`Already dispatched at ${existing.html_url}`);
    return;
  }

  const source = await findSource(fetchImpl, apiKey, owner, repo);
  let issue = existing;
  if (!issue) {
    const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRun, {
      owner, repo, run_id: run.id, per_page: 100,
    });
    const body = issueBody(run, failedSteps(jobs), guide);
    const title = `Jules: fix ${run.name} failure at ${run.head_sha.slice(0, 12)}`;
    const result = await github.rest.issues.create({owner, repo, title, body});
    issue = result.data;
  }

  const session = await julesRequest(fetchImpl, apiKey, 'sessions', {
    method: 'POST',
    body: JSON.stringify({
      title: `Fix ${run.name} at ${run.head_sha.slice(0, 12)}`,
      prompt: `${issue.body}\nTrack progress in ${issue.html_url}. Open a PR for review; do not merge it.`,
      sourceContext: {source, githubRepoContext: {startingBranch: 'main'}},
      automationMode: 'AUTO_CREATE_PR',
    }),
  });
  const sessionUrl = session.url || `https://jules.google.com/session/${session.id}`;
  await github.rest.issues.update({
    owner, repo, issue_number: issue.number,
    body: `${issue.body}\nJules session: ${sessionUrl}\n<!-- jules-session:${session.name} -->`,
  });
  core.info(`Sent ${issue.html_url} to ${sessionUrl}`);
}

module.exports = triage;
module.exports.failureKey = failureKey;
module.exports.failedSteps = failedSteps;
module.exports.issueBody = issueBody;
module.exports.findSource = findSource;
