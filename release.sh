#!/bin/bash
# Публикует релиз на GitHub: ./release.sh "что нового"
# Версия берётся из файла VERSION (поднимите её перед релизом).
# Токен — из связки ключей через git credential (тот же, что для git push).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="kzhebenev/browser-picker"
VERSION="$(tr -d '[:space:]' < "$DIR/VERSION")"
TAG="v$VERSION"
cd "$DIR"

[ -z "$(git status --porcelain)" ] || { echo "Есть незакоммиченные изменения"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "Тег $TAG уже есть — поднимите VERSION"; exit 1; }

NOTES="${1:-}"
if [ -z "$NOTES" ]; then
    PREV="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    NOTES="$(git log --pretty='- %s' ${PREV:+$PREV..HEAD} | head -20)"
fi

TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
[ -n "$TOKEN" ] || { echo "Нет токена GitHub в связке ключей"; exit 1; }

"$DIR/build-dmg.sh"

git tag -a "$TAG" -m "BrowserPicker $VERSION"
git push origin HEAD "$TAG"
git remote | grep -qx nas && git push nas HEAD "$TAG" || true

API="https://api.github.com/repos/$REPO"
BODY="$(python3 -c 'import json,sys; print(json.dumps({"tag_name":sys.argv[1],"name":"BrowserPicker "+sys.argv[2],"body":sys.argv[3]}))' "$TAG" "$VERSION" "$NOTES")"
RELEASE="$(curl -fsS -X POST -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$API/releases" -d "$BODY")"
ID="$(printf '%s' "$RELEASE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

curl -fsS -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/x-apple-diskimage" \
    --data-binary @"$DIR/build/BrowserPicker.dmg" \
    "https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=BrowserPicker.dmg" >/dev/null

echo "Релиз $TAG опубликован: https://github.com/$REPO/releases/tag/$TAG"
