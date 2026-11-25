# Security update reminders

The bar's update indicator turns into a red `!` when an installed package has a known serious security issue and the update that fixes it is ready to install. After the first `omarchy update`, the indicator otherwise watches only Omarchy's own package, so without this an urgent fix in, say, google-chrome on the fast ring would wait unseen until the next Omarchy release.

## The list

Omarchy publishes one list of minimum versions: for each package, the oldest release without a known serious security issue. It is not a list of vulnerable software, and it says nothing about why; it only says "below this version, update".

It is served from the `[omarchy]` repository's hosts, at the root rather than under a channel:

- `https://pkgs.omarchy.org/security/minimum-versions`
- `https://pkgs.omarchy.cn/security/minimum-versions`, the China replica, which must carry the same file

It is a text file. The first line marks the format and must be exactly as shown; then one package per line, its name and its minimum version as pacman writes versions (`epoch:version`, with or without `-pkgrel`, compared with `vercmp`). `#` starts a comment line. A file that breaks any of this is ignored as a whole and the last good copy is kept.

```
# omarchy-security-minimums 1
#
# The oldest version of each package without a known serious security issue.
# Rule: a minimum must never be higher than the version the stable channel
# can install, on x86_64 and aarch64. Check stable-mirror.omarchy.org and
# pkgs.omarchy.org/stable before adding or raising one. A minimum is always
# the release that fixed the issue: while stable has no such release, leave
# the package off the list (or at its previous minimum) rather than listing
# a lower version that is still vulnerable.
google-chrome 157.0.8103.50
```

The list is kept by hand for now: edit the file, check the rule, and upload it to the bucket behind `pkgs.omarchy.org`, from where the China replica copies it.

**The rule for whoever edits it:** a minimum must never be higher than the version the stable channel can install. Stable is the slowest channel, so a minimum it can reach is reachable everywhere a package is published at all. A minimum is also always the release that fixed the issue, never a stand-in: a lower version that is still vulnerable would present an upgrade to it as a security fix. So when stable cannot install the fix yet, the package waits. Chromium is the example: the fix is in 157 while stable's snapshot carries 155, so Chromium stays off the list (or at its previous minimum) and goes in at 157.0.8103.50 once stable can install it. Check both architectures, since aarch64 stable is a different snapshot.

## What the client does

`omarchy-update-available`, which the bar runs every six hours and whenever the network comes up, passes the pending updates from `checkupdates` to `omarchy-update-security scan`. That:

- fetches the list once a day, at a random second of a day picked anew after every fetch, so machines do not all ask at once. It tries the origin of every `Server` of the `[omarchy]` repository in `pacman.conf` order, so a machine with the China region profile asks `pkgs.omarchy.cn` first and `pkgs.omarchy.org` after it. A failed fetch keeps the last list and is retried at the next check, silently.
- reports a package only when it is installed below its minimum and the update `checkupdates` found reaches the minimum. A package held back with `IgnorePkg` is left out. So a reminder always goes away with one `omarchy update`, and a channel or architecture that has no fixed release yet shows nothing, whatever the list says. That also keeps a wrong minimum from asking anyone for something they cannot do.
- prints `security <name> <old> -> <new>` for each, which the indicator reads, and sends one notification the first time it sees a package at a given minimum. A later minimum for the same package is a new issue and notifies again; a check after being offline does not.

A check that could not reach the repositories reports nothing and keeps the last findings, so being offline neither raises nor clears anything.

Clicking the indicator or the notification opens `omarchy update`, whose confirmation lists the security updates. Answering No snoozes them for three days: the indicator stops highlighting them, and no notification repeats. A higher minimum for one of them ends the snooze for it. Findings that an update already fixed are dropped as soon as they are listed, by checking the installed version, so the update itself needs no extra step.

The state lives in `~/.local/state/omarchy/security-updates/`: the cached list, when the next fetch is due, the last findings, which minimums were notified, and the snooze.
