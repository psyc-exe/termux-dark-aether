name: Pull request template

body:
  - type: markdown
    id: template
    attributes:
      value: |
        ## Summary
        _Brief description of what this PR changes and why._

        ## Changed files
        - `path/to/file` — _what changed and why_

        ## Tests (if applicable)
        - [ ] `aether-install.sh --resume` ran without errors after this change
        - [ ] Tested on: _____ (Android version, device, GPU)
        - [ ] Screenshots / install.log attached

        ## Risks / notes
        _Anything that might break existing installs — version pin, ABI change, etc._