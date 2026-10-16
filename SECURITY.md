# Security Policy

## Supported versions

Security fixes are made in the latest released version of `nws_text`.

## Reporting a vulnerability

Please do not report security issues in public issues, pull requests, or discussions.

Report them privately through GitHub:

1. Open the repository's **Security** tab.
2. Select **Report a vulnerability**.
3. Describe the issue, the affected version, and steps or input to reproduce it.

We aim to acknowledge reports within 5 business days and will keep you informed while we
investigate and fix the issue.

## Scope

`nws_text` parses untrusted text and embedded CAP XML. Issues of interest include crashes or
unbounded resource use from crafted input, XML entity or DTD handling, and parsed results that
could be mistaken for valid alert data.
