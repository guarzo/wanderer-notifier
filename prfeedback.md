In Dockerfile lines 84 to 85, the environment variables are set using multiple
lines with a backslash. For better readability and conciseness, combine these
into a single ENV directive by placing both variables on the same line separated
by a space, like ENV REPLACE_OS_VARS=true HOME=/app.

In Dockerfile lines 100 to 101, the healthcheck uses wget which adds unnecessary
image size. Replace the wget command with curl using the flags --fail and
--silent to perform the healthcheck more efficiently. Update the HEALTHCHECK
line to use "curl --fail http://localhost:4000/health || exit 1" to reduce image
size and maintain the same functionality. (this allows us to remove the apk add for wget)

In Dockerfile lines 42 to 49, the RUN command installs Node.js from NodeSource
but lacks an apt-get update after adding the NodeSource repo and does not handle
pipefail, risking installing the wrong nodejs version and masking errors. Fix
this by adding 'set -o pipefail' at the start of the RUN command to catch pipe
errors, and insert an 'apt-get update' immediately after running the NodeSource
setup script before installing nodejs. This ensures the correct NodeSource
packages are installed and errors are properly detected.
