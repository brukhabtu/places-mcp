# GitHub Project Management Guide

## Overview

This guide shows how to use GitHub's built-in features to manage the Places MCP Server project following our agile plan.

## 1. GitHub Projects (Beta)

### Create Project Board

```bash
# Create a new project
gh project create --owner @me --title "Places MCP Server" --body "Agile development board for Places MCP Server"

# Or create under organization
gh project create --owner YOUR_ORG --title "Places MCP Server"
```

### Project Views

1. **Sprint Board** (Kanban)
   - Columns: Backlog, Sprint Ready, In Progress, Review, Done
   - Group by: Sprint
   - Filter by: Current sprint

2. **Roadmap View** (Timeline)
   - Show epics and milestones
   - Track sprint progress
   - Visualize dependencies

3. **Team View** (Table)
   - Assignee workload
   - Story points per person
   - Sprint velocity tracking

## 2. Issue Templates

### Create Issue Templates

`.github/ISSUE_TEMPLATE/user-story.yml`:
```yaml
name: User Story
description: Create a new user story
title: "[PLCS-XXX] "
labels: ["user-story"]
assignees: []
body:
  - type: markdown
    attributes:
      value: |
        ## User Story Template
  - type: textarea
    id: story
    attributes:
      label: User Story
      description: As a [role], I want [feature] so that [benefit]
      placeholder: "As a developer, I want..."
    validations:
      required: true
  - type: textarea
    id: acceptance
    attributes:
      label: Acceptance Criteria
      description: List the acceptance criteria
      value: |
        - [ ] Criterion 1
        - [ ] Criterion 2
        - [ ] Criterion 3
    validations:
      required: true
  - type: dropdown
    id: priority
    attributes:
      label: Priority
      options:
        - P0 - MVP Critical
        - P1 - Core Features
        - P2 - Enhancements
        - P3 - Nice to Have
    validations:
      required: true
  - type: input
    id: points
    attributes:
      label: Story Points
      description: Estimated story points (1, 2, 3, 5, 8, 13)
      placeholder: "5"
    validations:
      required: true
  - type: dropdown
    id: sprint
    attributes:
      label: Target Sprint
      options:
        - Sprint 1
        - Sprint 2
        - Sprint 3
        - Sprint 4
        - Sprint 5
        - Backlog
    validations:
      required: true
  - type: dropdown
    id: layer
    attributes:
      label: Architecture Layer
      options:
        - Configuration
        - Domain
        - Infrastructure
        - Application
        - Presentation
        - Cross-cutting
    validations:
      required: true
```

`.github/ISSUE_TEMPLATE/task.yml`:
```yaml
name: Task
description: Create a task for a user story
title: "[TASK] "
labels: ["task"]
body:
  - type: input
    id: parent
    attributes:
      label: Parent Story
      description: Link to parent user story (e.g., #123)
      placeholder: "#"
    validations:
      required: true
  - type: textarea
    id: description
    attributes:
      label: Task Description
      description: What needs to be done
    validations:
      required: true
  - type: input
    id: estimate
    attributes:
      label: Time Estimate (hours)
      placeholder: "4"
    validations:
      required: true
```

`.github/ISSUE_TEMPLATE/bug.yml`:
```yaml
name: Bug Report
description: Report a bug
title: "[BUG] "
labels: ["bug"]
body:
  - type: textarea
    id: description
    attributes:
      label: Bug Description
      description: Clear description of the bug
    validations:
      required: true
  - type: textarea
    id: reproduce
    attributes:
      label: Steps to Reproduce
      value: |
        1. 
        2. 
        3. 
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: Expected Behavior
    validations:
      required: true
  - type: dropdown
    id: severity
    attributes:
      label: Severity
      options:
        - Critical
        - High
        - Medium
        - Low
```

## 3. Labels System

### Create Labels Script

`scripts/setup-labels.sh`:
```bash
#!/bin/bash

# Priority labels
gh label create "P0: MVP Critical" --color "FF0000" --description "Must have for MVP"
gh label create "P1: Core Features" --color "FF6600" --description "Needed for production"
gh label create "P2: Enhancements" --color "FFAA00" --description "Improve experience"
gh label create "P3: Nice to Have" --color "FFDD00" --description "Future consideration"

# Sprint labels
gh label create "Sprint 1" --color "0052CC"
gh label create "Sprint 2" --color "0052CC"
gh label create "Sprint 3" --color "0052CC"
gh label create "Sprint 4" --color "0052CC"
gh label create "Sprint 5" --color "0052CC"

# Layer labels
gh label create "layer: configuration" --color "5319E7"
gh label create "layer: domain" --color "5319E7"
gh label create "layer: infrastructure" --color "5319E7"
gh label create "layer: application" --color "5319E7"
gh label create "layer: presentation" --color "5319E7"

# Type labels
gh label create "user-story" --color "1D76DB"
gh label create "task" --color "1D76DB"
gh label create "bug" --color "E11D21"
gh label create "tech-debt" --color "006B75"
gh label create "documentation" --color "D4C5F9"

# Status labels
gh label create "blocked" --color "000000"
gh label create "ready" --color "0E8A16"
gh label create "in-progress" --color "FFA500"
gh label create "review" --color "C2E0C6"
```

## 4. Milestones for Sprints

### Create Milestones

```bash
# Create sprint milestones
gh api repos/:owner/:repo/milestones \
  --method POST \
  --field title="Sprint 1: MVP Foundation" \
  --field description="Basic search functionality working end-to-end" \
  --field due_on="2024-01-14T23:59:59Z"

gh api repos/:owner/:repo/milestones \
  --method POST \
  --field title="Sprint 2: Core Features" \
  --field description="Full search capabilities with details and nearby search" \
  --field due_on="2024-01-28T23:59:59Z"

# ... repeat for all sprints
```

## 5. GitHub Actions for Automation

### Sprint Management Workflow

`.github/workflows/sprint-management.yml`:
```yaml
name: Sprint Management

on:
  schedule:
    # Run every Monday at 9 AM
    - cron: '0 9 * * 1'
  workflow_dispatch:

jobs:
  sprint-report:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Generate Sprint Report
        uses: actions/github-script@v6
        with:
          script: |
            const milestone = await github.rest.issues.listMilestones({
              owner: context.repo.owner,
              repo: context.repo.repo,
              state: 'open',
              sort: 'due_on',
              direction: 'asc'
            });
            
            const currentSprint = milestone.data[0];
            const issues = await github.rest.issues.listForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo,
              milestone: currentSprint.number,
              state: 'all'
            });
            
            // Calculate sprint metrics
            const totalPoints = issues.data.reduce((sum, issue) => {
              const points = issue.labels.find(l => l.name.startsWith('points:'));
              return sum + (points ? parseInt(points.name.split(':')[1]) : 0);
            }, 0);
            
            const completed = issues.data.filter(i => i.state === 'closed').length;
            const remaining = issues.data.filter(i => i.state === 'open').length;
            
            // Create sprint report issue
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `Sprint Report: ${currentSprint.title}`,
              body: `## Sprint Metrics
              
              - **Total Stories**: ${issues.data.length}
              - **Completed**: ${completed}
              - **Remaining**: ${remaining}
              - **Story Points**: ${totalPoints}
              - **Completion**: ${Math.round(completed/issues.data.length*100)}%
              
              ## Burndown
              See [Project Board](${context.payload.repository.html_url}/projects/1)
              `,
              labels: ['sprint-report']
            });
```

### Story Point Automation

`.github/workflows/story-points.yml`:
```yaml
name: Story Points

on:
  issues:
    types: [labeled, unlabeled]

jobs:
  update-points:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@v6
        with:
          script: |
            const issue = context.payload.issue;
            const pointsLabel = issue.labels.find(l => l.name.startsWith('points:'));
            
            if (pointsLabel) {
              // Update project field
              const projectItems = await github.graphql(`
                query($owner: String!, $repo: String!, $issue: Int!) {
                  repository(owner: $owner, name: $repo) {
                    issue(number: $issue) {
                      projectItems(first: 10) {
                        nodes {
                          id
                          project {
                            id
                          }
                        }
                      }
                    }
                  }
                }
              `, {
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue: issue.number
              });
              
              // Update story points field in project
              // ... GraphQL mutation to update field
            }
```

## 6. Branch Protection and PR Rules

### Setup Branch Protection

```bash
# Protect main branch
gh api repos/:owner/:repo/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["continuous-integration"]}' \
  --field enforce_admins=false \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
  --field restrictions=null
```

### PR Template

`.github/pull_request_template.md`:
```markdown
## Description
Brief description of changes

## Related Issues
Closes #

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Layer(s) Affected
- [ ] Configuration
- [ ] Domain
- [ ] Infrastructure
- [ ] Application
- [ ] Presentation

## Checklist
- [ ] Tests pass locally
- [ ] Code follows project style
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No new warnings

## Testing
Describe testing performed
```

## 7. GitHub CLI Commands for Daily Use

### Sprint Management

```bash
# View current sprint issues
gh issue list --milestone "Sprint 1" --state all

# Create new story
gh issue create --title "[PLCS-001] Basic configuration" \
  --body "As a developer..." \
  --label "user-story,Sprint 1,layer: configuration" \
  --milestone "Sprint 1"

# Move issue to different sprint
gh issue edit 123 --milestone "Sprint 2"

# View sprint progress
gh issue list --milestone "Sprint 1" --json state --jq 'group_by(.state) | map({state: .[0].state, count: length})'
```

### Daily Standup

```bash
# Create standup script
cat > scripts/daily-standup.sh << 'EOF'
#!/bin/bash

echo "=== Daily Standup Report ==="
echo "Date: $(date)"
echo ""

# In Progress
echo "## In Progress"
gh issue list --label "in-progress" --assignee @me

echo ""
echo "## Blocked"
gh issue list --label "blocked"

echo ""
echo "## Recently Completed"
gh issue list --state closed --limit 5 --assignee @me
EOF

chmod +x scripts/daily-standup.sh
```

### Sprint Velocity Tracking

```bash
# Create velocity tracking script
cat > scripts/sprint-velocity.sh << 'EOF'
#!/bin/bash

SPRINT=$1
echo "=== Sprint $SPRINT Velocity ==="

# Get completed story points
COMPLETED=$(gh issue list --milestone "Sprint $SPRINT" --state closed --json labels \
  --jq '[.[] | .labels[] | select(.name | startswith("points:")) | .name | split(":")[1] | tonumber] | add')

# Get total story points  
TOTAL=$(gh issue list --milestone "Sprint $SPRINT" --json labels \
  --jq '[.[] | .labels[] | select(.name | startswith("points:")) | .name | split(":")[1] | tonumber] | add')

echo "Completed: $COMPLETED points"
echo "Total: $TOTAL points"
echo "Velocity: $(( COMPLETED * 100 / TOTAL ))%"
EOF

chmod +x scripts/sprint-velocity.sh
```

## 8. Integration with External Tools

### Slack Integration

```yaml
# .github/workflows/slack-notify.yml
name: Slack Notifications

on:
  issues:
    types: [opened, closed]
  pull_request:
    types: [opened, merged]

jobs:
  notify:
    runs-on: ubuntu-latest
    steps:
      - name: Notify Slack
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          text: "${{ github.event_name }} in ${{ github.repository }}"
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

## 9. Best Practices

### Issue Management
1. **One issue per story** - Keep stories atomic
2. **Link PRs to issues** - Use "Closes #123" in PRs
3. **Update regularly** - Move cards daily
4. **Add context** - Use comments for updates

### Code Review Process
1. **PR size** - Keep under 400 lines
2. **Review SLA** - Within 24 hours
3. **Require approval** - At least 1 reviewer
4. **Run CI** - All tests must pass

### Sprint Ceremonies via GitHub
1. **Planning** - Create issues for sprint
2. **Daily** - Update issue status
3. **Review** - Close milestone, demo via PR
4. **Retro** - Create discussion thread

## 10. Metrics and Reporting

### GitHub Insights
- Pulse - Weekly activity
- Contributors - Team performance
- Traffic - Repository popularity
- Code frequency - Development pace

### Custom Reports
```bash
# Generate sprint report
gh api graphql -f query='
  query($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      milestones(first: 5, states: OPEN) {
        nodes {
          title
          progress {
            completedPercentage
            totalCount
            completedCount
          }
        }
      }
    }
  }
' -f owner=':owner' -f repo=':repo'
```

This comprehensive GitHub management approach provides:
- Clear issue tracking with templates
- Automated workflows for common tasks  
- Sprint progress visibility
- Team collaboration features
- Metrics for continuous improvement