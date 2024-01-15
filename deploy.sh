#!/bin/sh
# deploy lastest tag and master branch to github.

url=$(git remote get-url github >/dev/null 2>&1)
if [[ $? -ne 0 ]]; then
    echo 'add github remote'
    git remote add github git@github.com:debugly/ijkplayer.git
fi

echo '=== will getch github tags ==='
git fetch github --tag
echo '=== will push master branch to github ==='
git push github master
tag=$(git describe --abbrev=0 --tags)
echo "=== latest tag is ${tag} ==="
#git push github ${tag} --force
git remote remove github