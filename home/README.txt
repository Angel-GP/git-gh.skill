This directory is the isolated HOME for the git-gh skill.

It will contain:
  .gitconfig      Git global config for this skill only
  gh\             GH_CONFIG_DIR (gh auth token, hosts.yml)
  .ssh\           private keys, known_hosts, ssh config

Do NOT commit, zip, share or paste the contents of this directory.
The skill never prints private keys or token values.

To start from a clean identity, delete this directory; start.bat recreates
the skeleton on the next run.
