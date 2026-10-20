# Third-party notices

The original git-gh skill code and documentation are licensed under the MIT
License (see `LICENSE`). The bundled tools below keep their own licenses.

## Git for Windows (PortableGit)

- Version: `2.56.0.windows.2`
- Project: <https://gitforwindows.org/>
- Source: <https://github.com/git-for-windows/git>
- Corresponding source: <https://github.com/git-for-windows/git/tree/v2.56.0.windows.2>
- Build system: <https://github.com/git-for-windows/build-extra>
- License: GNU General Public License version 2 (GPL-2.0). See `tools/git/LICENSE.txt`.
- Bundled components (including MSYS2, OpenSSH, OpenSSL, curl and Perl) keep their own licenses under `tools/git/`.

## GitHub CLI (gh)

- Version: `2.102.0`
- Project: <https://cli.github.com/>
- Source: <https://github.com/cli/cli/tree/v2.102.0>
- License: MIT. See `tools/gh/LICENSE`.

## Notes

- The tools are included unmodified to keep the skill self-contained.
- Version, download URL and SHA256 are recorded in `tools/VERSIONS.txt`.
- If you redistribute this skill, keep the license files and this notice together with the binaries.
- The root `LICENSE` applies only to the original git-gh code and documentation, not to `tools/`.
