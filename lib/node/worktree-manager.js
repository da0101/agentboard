'use strict';

// worktree-manager.js — manage git worktrees for agentboard streams.

const { execSync } = require('child_process');
const path = require('path');

function run(cmd, cwd) {
  return execSync(cmd, { encoding: 'utf8', cwd }).trim();
}

function listWorktrees(repoRoot) {
  try {
    const raw = run('git worktree list --porcelain', repoRoot);
    const worktrees = [];
    let current = {};
    for (const line of raw.split('\n')) {
      if (line.startsWith('worktree ')) {
        if (current.path) worktrees.push(current);
        current = { path: line.slice(9), branch: null, sha: null, isMain: false };
      } else if (line.startsWith('HEAD ')) {
        current.sha = line.slice(5);
      } else if (line.startsWith('branch ')) {
        current.branch = line.slice(7);
      } else if (line === 'bare') {
        current.isMain = false;
      } else if (line.startsWith('worktree') && line.includes('(bare)')) {
        current.isMain = false;
      }
    }
    if (current.path) worktrees.push(current);
    if (worktrees.length) worktrees[0].isMain = true;
    return worktrees;
  } catch (err) {
    process.stderr.write(`[worktree-manager] listWorktrees error: ${err.message}\n`);
    return [];
  }
}

function createWorktree(repoRoot, { streamSlug, baseBranch = 'develop' } = {}) {
  try {
    const worktreePath = `${repoRoot}-${streamSlug}`;
    const branch = `feature/${streamSlug}`;
    run(`git worktree add -b "${branch}" "${worktreePath}" "${baseBranch}"`, repoRoot);
    return { path: worktreePath, branch };
  } catch (err) {
    process.stderr.write(`[worktree-manager] createWorktree error: ${err.message}\n`);
    return null;
  }
}

function removeWorktree(repoRoot, worktreePath) {
  try {
    // Derive branch name from worktree list before removing
    const worktrees = listWorktrees(repoRoot);
    const wt = worktrees.find(w => w.path === worktreePath);
    run(`git worktree remove --force "${worktreePath}"`, repoRoot);
    if (wt && wt.branch) {
      const branchName = wt.branch.replace('refs/heads/', '');
      try { run(`git branch -d "${branchName}"`, repoRoot); } catch (_) {}
    }
  } catch (err) {
    process.stderr.write(`[worktree-manager] removeWorktree error: ${err.message}\n`);
  }
}

function worktreeForStream(repoRoot, streamSlug) {
  try {
    const worktrees = listWorktrees(repoRoot);
    const branch = `refs/heads/feature/${streamSlug}`;
    return worktrees.find(w => w.branch === branch) || null;
  } catch (err) {
    process.stderr.write(`[worktree-manager] worktreeForStream error: ${err.message}\n`);
    return null;
  }
}

module.exports = { listWorktrees, createWorktree, removeWorktree, worktreeForStream };
