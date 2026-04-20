# Pull Request

## Summary

<!-- One or two sentences: what does this PR change and why? -->

## Type of change

<!-- Check one (or more) -->

- [ ] New chart
- [ ] Chart update (templates, values, schema)
- [ ] Documentation only
- [ ] CI / workflow / repo metadata
- [ ] Other (please describe)

## Affected charts

<!-- List each chart touched, e.g. `nginx-gateway-cr` -->

## Checklist

For chart changes (skip rows that don't apply):

- [ ] Bumped `version` in `Chart.yaml` per [SemVer](https://semver.org/)
- [ ] Added an entry under `artifacthub.io/changes` in `Chart.yaml`
- [ ] Updated `values.schema.json` if `values.yaml` shape changed
- [ ] Updated the chart's `README.md` if values or behavior changed
- [ ] Ran `helm lint charts/<chart>` locally — passes
- [ ] Ran `helm template ci charts/<chart>` locally — renders correctly

For all PRs:

- [ ] Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
- [ ] PR title is clear and follows the same convention

## Additional context

<!-- Screenshots, links, related issues, migration notes, etc. -->
