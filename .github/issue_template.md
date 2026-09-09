name: Issue Templates

body:
  - type: markdown
    id: template
    attributes:
      value: |
        Thank you for opening an issue.

        **Before you report**, check:
        - [ ] I ran `aether-update` and it didn't change anything
        - [ ] I searched existing issues (open and closed)
        - [ ] I'm on `main` HEAD or the latest release tag
        - [ ] I included the output of `aether-update` (if applicable)

        **Android environment**
        | Field        | Value              |
        |--------------|--------------------|
        | Android      | 12 / 13 / 14 / 15 |
        | Termux app   | ____               |
        | Installer    | ________________   |

        **Step**
        - [ ] First run (bootstrap)
        - [ ] Preflight / privilege detection
        - [ ] Base OS (Debian/Ubuntu) install
        - [ ] Toolchain overlay (Kali/Parrot)
        - [ ] Installation footprint (minimal/top10/full)
        - [ ] Agent CLI install
        - [ ] Desktop environment
        - [ ] GPU / display

        **Describe the problem**
        _Put your description here. Include relevant log output (install.log)
        and error messages. If the installer hung, note the last spinner message._

        **Expected vs actual**
        _What should happen?_ / _What actually happened?_ / _What would you suggest?_