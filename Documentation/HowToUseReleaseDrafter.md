# GitHub release configuration
The Release Drafter tool uses GitHub actions inputs to control GitHub release elements (tags, release name, draft/full release status, etc.); to control changelog level elements (text format, style, label text, etc.), see [Changelog text and style configuration](#changelog-text-and-style-configuration).  

For all available action inputs, see the reference: [Action Inputs](https://github.com/release-drafter/release-drafter#action-inputs)


## How to control releases
It is possible to have the tool output a draft release version to verify the output is acceptable; it may be helpful to have a workflow input variable to control this behavior. Note that any existing draft releases with the same tag version will be replaced by the newly created draft (that is, automatic cleanup of older drafts).

# Changelog text and style configuration
The Release Drafter tool uses a yaml config file to control the style of output. This config controls changelog text level elements; to control GitHub release level elements (tags, release name, draft/full release status, etc.), see [GitHub release configuration](#github-release-configuration).

By default, the Release Drafter action looks at the repository's ~/.github/ directory (NOT the same level as the workflow itself; one level above) for a file with the name `release-drafter.yml`. If a different filename is desired, an argurment can be added to the `with` parameters (other `with` parameters not included in example snippet for brevity):  
```yaml
- uses: release-drafter/release-drafter@v5
  with:
    config-name: custom-config-name.yml
```

## How to control labels
### Label inclusion/exclusion
It is possible to explicitly include or exclude labels. For example, it could be useful in certain cases to not include a PR in the changelog, and a special label like `skip-changelog` could be used to mark a PR as not needed to be added to the changelog.

### Label categorization
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

Note that in the default configuration of the tool, unlabeled PRs are grouped together. The categories of PRs follow the same order as in the config yaml file, with the unlabeled category starting first, followed by the defined `categories` order.

## How to control changelog output template
See the available environment variables for changelog output populated by the tool: [Template Variables](https://github.com/release-drafter/release-drafter#template-variables)

At the top level of the config yaml:
```yaml
template: |
  ## Changes

  $CHANGES
```

Note that the elements of the changelog itself are broken into smaller standard units by the tool; for example, each PR is represented by a "change" entity, and the format for a single change entry is controlled by the `change-template` property. 

At the top level of the config yaml:
```yaml
change-template: '- $TITLE @$AUTHOR (#$NUMBER)'
```
Given a PR whose author username is @timkimadobe and a title like:
```
New API allows for deleting user data #6 
```

Results in output like:
```
- New API allows for deleting user data @timkimadobe (#6)
```
You can see that the title text is inserted into the provided format wherever the `$TITLE` variable is defined, along with the `$AUTHOR` and `$NUMBER` (PR number). The tool only provides the raw text values, so if you want to leverage GitHub's own automatic linking to users and/or PRs, include the special prefixes accordingly using the required format.

See the reference for all standard changelog entities: [Configuration Objects](https://github.com/release-drafter/release-drafter#configuration-options)

