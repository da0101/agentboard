'use strict';

// delegation-router.js — maps a task description to a role and builds a delegation prompt.

const ROLES = [
  { slug: 'product-manager',      name: 'Senior Product Manager',          model: 'Sonnet',       keywords: ['requirements', 'priorities', 'product', 'shape', 'worth', 'roadmap', 'strategy', 'stakeholder'] },
  { slug: 'tech-advisor',         name: 'Principal Technology Advisor',     model: 'Sonnet',       keywords: ['research', 'comparison', 'recommend', 'vs', 'which', 'evaluate', 'tradeoff', 'compare'] },
  { slug: 'startup-mvp',          name: 'Startup MVP Builder',              model: 'Opus',         keywords: ['from scratch', 'greenfield', 'new app', 'new product', 'new service', 'build app', 'create app', 'mvp'] },
  { slug: 'feature-builder',      name: 'Senior Product Engineer',          model: 'Opus',         keywords: ['add feature', 'add checkout', 'build feature', 'implement feature', 'existing product', 'new endpoint'] },
  { slug: 'backend-architect',    name: 'Backend Systems Architect',        model: 'Opus',         keywords: ['api design', 'data model', 'infrastructure', 'scaling', 'server-side', 'architecture', 'system design'] },
  { slug: 'frontend-engineer',    name: 'Senior Frontend Engineer',         model: 'Sonnet',       keywords: ['ui', 'component', 'screen', 'styling', 'css', 'accessibility', 'layout', 'react', 'frontend'] },
  { slug: 'debugger',             name: 'Production Debugger',              model: 'Sonnet',       keywords: ['bug', 'error', 'crash', 'stopped working', 'broken', 'exception', 'incident', 'fix'] },
  { slug: 'perf-engineer',        name: 'Performance Engineer',             model: 'Sonnet',       keywords: ['slow', 'optimize', 'performance', 'memory', 'scalability', 'speed', 'latency', 'throughput'] },
  { slug: 'qa-engineer',          name: 'Senior QA Engineer',               model: 'Sonnet',       keywords: ['test', 'testing', 'coverage', 'edge case', 'qa', 'ready to ship', 'test plan'] },
  { slug: 'security-engineer',    name: 'Senior Security Engineer',         model: 'Sonnet',       keywords: ['security', 'auth', 'permissions', 'vulnerability', 'safe', 'secure', 'audit', 'injection'] },
  { slug: 'code-auditor',         name: 'Senior Code Auditor',              model: 'Sonnet',       keywords: ['assess', 'audit code', 'code quality', 'risks', 'score', 'review code', 'honest assessment'] },
  { slug: 'refactor-architect',   name: 'Refactoring Architect',            model: 'Opus',         keywords: ['refactor', 'clean up', 'messy', 'migration', 'upgrade', 'restructure', 'simplify code'] },
  { slug: 'devops-engineer',      name: 'Senior DevOps/Platform Engineer',  model: 'Sonnet',       keywords: ['deploy', 'ci', 'cd', 'container', 'docker', 'monitoring', 'server down', 'pipeline', 'infra'] },
  { slug: 'data-analyst',         name: 'Senior Data Analyst',              model: 'Sonnet',       keywords: ['metrics', 'query', 'report', 'dashboard', 'analytics', 'data', 'sql', 'churn', 'insight'] },
  { slug: 'tech-writer',          name: 'Senior Technical Writer',          model: 'Sonnet',       keywords: ['documentation', 'readme', 'api reference', 'guide', 'onboarding', 'docs', 'write docs'] },
  { slug: 'code-simplifier',      name: 'Code Simplifier',                  model: 'Opus',         keywords: ['simplify', 'too complex', 'hard to read', 'too clever', 'over-engineered'] },
  { slug: 'build-error-resolver', name: 'Build Error Resolver',             model: 'Sonnet',       keywords: ['build failing', 'compile error', 'lint error', 'ci failing', 'pipeline failing', 'cannot build'] },
  { slug: 'a11y-engineer',        name: 'Accessibility Engineer',           model: 'Sonnet',       keywords: ['wcag', 'screen reader', 'keyboard nav', 'colour contrast', 'a11y', 'aria', 'accessible'] },
  { slug: 'database-reviewer',    name: 'Database Reviewer',                model: 'Sonnet',       keywords: ['schema', 'migration', 'index', 'query pattern', 'database review', 'db design'] },
  { slug: 'api-engineer',         name: 'API Implementation Engineer',      model: 'Opus',         keywords: ['implement api', 'new endpoint', 'integration', 'rest api', 'graphql', 'from spec', 'openapi'] },
  { slug: 'ml-engineer',          name: 'ML / AI Pipeline Engineer',        model: 'Opus',         keywords: ['ml', 'embedding', 'vector', 'model integration', 'eval harness', 'ai pipeline', 'llm', 'rag'] },
  { slug: 'harness-optimizer',    name: 'Agent Harness Optimizer',          model: 'Sonnet',       keywords: ['agent setup', 'skills not followed', 'context waste', 'hook misfiring', 'optimize harness'] },
  { slug: 'docs-reviewer',        name: 'Documentation Reviewer',           model: 'Sonnet',       keywords: ['review docs', 'stale docs', 'accuracy', 'completeness', 'outdated documentation'] },
  { slug: 'pair-programmer',      name: 'Pair Programmer (default)',         model: 'Sonnet',       keywords: [] },
];

const WORKTREE_ROLES = new Set([
  'feature-builder', 'startup-mvp', 'refactor-architect',
  'api-engineer', 'ml-engineer', 'backend-architect',
  'frontend-engineer', 'code-simplifier',
]);

function matchRole(taskDescription) {
  const desc = (taskDescription || '').toLowerCase();
  let best = null;
  let bestScore = 0;
  for (const role of ROLES) {
    if (!role.keywords.length) continue;
    const score = role.keywords.reduce((s, kw) => s + (desc.includes(kw) ? 1 : 0), 0);
    if (score > bestScore) { bestScore = score; best = role; }
  }
  const matched = bestScore > 0 ? best : ROLES.find(r => r.slug === 'pair-programmer');
  return { slug: matched.slug, name: matched.name, model: matched.model };
}

function buildDelegationPrompt(taskDescription, role, context = {}) {
  const lines = [`[role:${role.slug}]`, ''];
  lines.push(`**Task:** ${taskDescription}`);
  if (context.streamSlug) lines.push(`**Stream:** ${context.streamSlug}`);
  if (context.worktreePath) lines.push(`**Worktree:** ${context.worktreePath}`);
  lines.push('');
  lines.push(`You are acting as: ${role.name}. Adopt this role's process, deliverables, and constraints before starting.`);
  return lines.join('\n');
}

function suggestWorktree(slug) {
  return WORKTREE_ROLES.has(slug);
}

module.exports = { matchRole, buildDelegationPrompt, suggestWorktree };
