#!/bin/sh
# deploy lastest tag and develop branch to github.

url=$(git remote get-url github)
if [[ $? -ne 0 ]]; then
    git remote add github git@github.com:debugly/ijkplayer.git
fi

tag=$(git describe --abbrev=0)
echo '=== will push develop branch to github ==='
git push github develop
echo "=== will push ${tag} tag to github ==="
git push github ${tag}

git remote remove github