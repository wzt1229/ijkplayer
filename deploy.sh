#!/bin/sh
# deploy lastest tag and master branch to github.

url=$(git remote get-url github >/dev/null)
if [[ $? -ne 0 ]]; then
    echo 'add github remote'
    git remote add github git@github.com:debugly/ijkplayer.git
fi

tag=$(git describe --abbrev=0)
echo '=== will push master branch to github ==='
git push github master
echo "=== will push ${tag} tag to github ==="
git push github ${tag}

git remote remove github