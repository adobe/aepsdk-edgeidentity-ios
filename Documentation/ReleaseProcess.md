# GitHub release configuration
## Generate automatic release notes using Release Drafter
The Release Drafter tool uses GitHub actions inputs to control GitHub release elements (tags, release name, draft/full release status, etc.); to control changelog level elements (text format, style, label text, etc.), see [Changelog text and style configuration](#changelog-text-and-style-configuration).  

For all available action inputs, see the reference: [Action Inputs](https://github.com/release-drafter/release-drafter#action-inputs)


### How to control releases
It is possible to have the tool output a draft release version to verify the output is acceptable; it may be helpful to have a workflow input variable to control this behavior. Note that any existing draft releases with the same tag version will be replaced by the newly created draft (that is, automatic cleanup of older drafts).

### Changelog text and style configuration
The Release Drafter tool uses a yaml config file to control the style of output. This config controls changelog text level elements; to control GitHub release level elements (tags, release name, draft/full release status, etc.), see [GitHub release configuration](#github-release-configuration).

By default, the Release Drafter action looks for its configuration at `.github/release-drafter.yml` (note this is one level up from the action's own `workflows` directory). To use a different config filename, specify the `config-name` as in the example below:
```yaml
- uses: release-drafter/release-drafter@v5
  with:
    config-name: custom-config-name.yml
```

### How to control labels
#### Label inclusion/exclusion
It is possible to explicitly include or exclude labels. For example, it could be useful in certain cases to not include a PR in the changelog, and a special label like `skip-changelog` could be used to mark a PR as not needed to be added to the changelog.

#### Label categorization
To categorize/group labels with a custom title in the changelog, create the `categories` header at the top level of the config yaml:
```yaml
categories:
  # Example of multiple labels for a grouping
  - title: '🚀 Features'
    labels:
      - 'feature'
      - 'enhancement'
  # Example of a single label for a grouping
  - title: '🧰 Maintenance'
    label: 'chore'
```

Note that in the default configuration of the tool, unlabeled PRs are grouped together. The categories of PRs follow the same order as in the config yaml file, with the unlabeled category starting first, followed by the defined `categories` order. If you want to exclude unlabeled PRs, define the `include-labels` option as below:

```yaml
include-labels:
  - 'bug'
  - 'bugfix'
  - 'buildscripts'
  - 'deprecated'
  - 'documentation'
  - 'enhancement'
  - 'feature'
  - 'fix'
  - 'maintenance'
```

### How to control changelog output template
See the available environment variables for changelog output populated by the tool: [Template Variables](https://github.com/release-drafter/release-drafter#template-variables)

At the top level of the config yaml:
```yaml
template: |
  ## Changes

  $CHANGES

  **Full Changelog**: https://github.com/$OWNER/$REPOSITORY/compare/$PREVIOUS_TAG...$RESOLVED_VERSION
```

Note that the elements of the changelog itself are broken into smaller standard units by the tool; for example, each PR is represented by a "change" entity, and the format for a single change entry is controlled by the `change-template` property. 

At the top level of the config yaml:
```yaml
change-template: '$TITLE (#$NUMBER) @$AUTHOR'
```
Given a PR whose author is `@username` with title:
```
New API allows for deleting user data #6 
```

The resulting output is:
```
New API allows for deleting user data (#6) @username
```

See the reference for all standard changelog entities: [Configuration Objects](https://github.com/release-drafter/release-drafter#configuration-options)

