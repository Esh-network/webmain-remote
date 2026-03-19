#!/bin/bash
# Monitor GitHub Actions build and update download page when done
REPO="Esh-network/webmain-remote"
PAGE="/var/www/remote.webmain.fr/index.html"

echo "[$(date)] Starting build monitor..."

while true; do
    # Get latest run
    STATUS=$(gh run list -R "$REPO" --limit 1 --json status,conclusion,databaseId -q '.[0]')
    RUN_STATUS=$(echo "$STATUS" | jq -r '.status')
    RUN_CONCLUSION=$(echo "$STATUS" | jq -r '.conclusion')
    RUN_ID=$(echo "$STATUS" | jq -r '.databaseId')

    echo "[$(date)] Run $RUN_ID: status=$RUN_STATUS conclusion=$RUN_CONCLUSION"

    if [ "$RUN_STATUS" = "completed" ]; then
        echo "[$(date)] Build completed with: $RUN_CONCLUSION"

        if [ "$RUN_CONCLUSION" = "success" ]; then
            echo "[$(date)] Build SUCCESS! Updating download page..."

            # Get release artifacts URLs from nightly release
            RELEASE_TAG="nightly"
            RELEASE_DATA=$(gh release view "$RELEASE_TAG" -R "$REPO" --json assets -q '.assets[].name' 2>/dev/null)

            if [ -n "$RELEASE_DATA" ]; then
                BASE_URL="https://github.com/$REPO/releases/download/$RELEASE_TAG"

                # Find artifact filenames
                WIN_EXE=$(echo "$RELEASE_DATA" | grep -i '\.exe$' | grep -iv 'portable' | head -1)
                WIN_PORTABLE=$(echo "$RELEASE_DATA" | grep -i 'portable.*\.exe$\|\.exe$' | head -1)
                MAC_DMG=$(echo "$RELEASE_DATA" | grep -i '\.dmg$' | head -1)
                LINUX_DEB=$(echo "$RELEASE_DATA" | grep -i '\.deb$' | grep 'x86_64\|amd64' | head -1)
                ANDROID_APK=$(echo "$RELEASE_DATA" | grep -i '\.apk$' | head -1)
                WEB_TAR=$(echo "$RELEASE_DATA" | grep -i 'web.*\.tar\.gz$' | head -1)

                echo "Found artifacts:"
                echo "  Windows: $WIN_EXE"
                echo "  macOS: $MAC_DMG"
                echo "  Linux: $LINUX_DEB"
                echo "  Android: $ANDROID_APK"
                echo "  Web: $WEB_TAR"

                # Deploy web version if available
                if [ -n "$WEB_TAR" ]; then
                    echo "[$(date)] Deploying web client..."
                    mkdir -p /tmp/webdeploy
                    cd /tmp/webdeploy
                    gh release download "$RELEASE_TAG" -R "$REPO" -p "$WEB_TAR" --clobber
                    tar xzf "$WEB_TAR"
                    rm -rf /var/www/remote.webmain.fr/webclient
                    mv rustdesk-*/  /var/www/remote.webmain.fr/webclient/ 2>/dev/null || mv */ /var/www/remote.webmain.fr/webclient/
                    rm -rf /tmp/webdeploy
                    echo "[$(date)] Web client deployed to /webclient/"
                fi

                # Update the HTML page with real download links
                python3 << PYEOF
import re

with open("$PAGE", "r") as f:
    html = f.read()

replacements = {
    'href="https://github.com/rustdesk/rustdesk/releases/latest/download/rustdesk-1.3.9-x86_64.exe"': 'href="$BASE_URL/${WIN_EXE:-$WIN_PORTABLE}"' if "${WIN_EXE:-$WIN_PORTABLE}" else None,
    'href="https://github.com/rustdesk/rustdesk/releases/latest/download/rustdesk-1.3.9-x86_64.dmg"': 'href="$BASE_URL/$MAC_DMG"' if "$MAC_DMG" else None,
    'href="https://github.com/rustdesk/rustdesk/releases/latest/download/rustdesk-1.3.9-x86_64.deb"': 'href="$BASE_URL/$LINUX_DEB"' if "$LINUX_DEB" else None,
}

for old, new in replacements.items():
    if new:
        html = html.replace(old, new)

with open("$PAGE", "w") as f:
    f.write(html)

print("Download page updated!")
PYEOF

                echo "[$(date)] Page updated with real download links."
            else
                echo "[$(date)] No release found yet, artifacts may still be uploading..."
            fi
        else
            echo "[$(date)] Build FAILED. Check: https://github.com/$REPO/actions"
        fi
        break
    fi

    sleep 120
done

echo "[$(date)] Monitor finished."
