#!/bin/bash

set -e

# skip if no /merge
echo "Checking if contains '/merge' command..."
(jq -r ".comment.body" "$GITHUB_EVENT_PATH" | grep -E "/merge") || exit 78

# skip if not a PR
echo "Checking if a PR command..."
(jq -r ".issue.pull_request.url" "$GITHUB_EVENT_PATH") || exit 78

# get the SHA to merge
BRANCH_TO_MERGE=$(jq -r ".comment.body" "$GITHUB_EVENT_PATH" | cut -c 8-)

if [[ "$(jq -r ".action" "$GITHUB_EVENT_PATH")" != "created" ]]; then
	echo "This is not a new comment event!"
	exit 78
fi

PR_NUMBER=$(jq -r ".issue.number" "$GITHUB_EVENT_PATH")
REPO_FULLNAME=$(jq -r ".repository.full_name" "$GITHUB_EVENT_PATH")
echo "Collecting information about PR #$PR_NUMBER of $REPO_FULLNAME..."

if [[ -z "$GITHUB_TOKEN" ]]; then
	echo "Set the GITHUB_TOKEN env variable."
	exit 1
fi

URI=https://api.github.com
API_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token $GITHUB_TOKEN"

pr_resp=$(curl -X GET -s -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/$REPO_FULLNAME/pulls/$PR_NUMBER")

HEAD_REPO=$(echo "$pr_resp" | jq -r .head.repo.full_name)
HEAD_BRANCH=$(echo "$pr_resp" | jq -r .head.ref)

echo
echo "  'Nightly Merge Action' is using the following input:"
echo "    - branch to merge = '$BRANCH_TO_MERGE'"
echo "    - branch to checkout and merge into = '$HEAD_BRANCH'"
echo "    - allow_ff = $INPUT_ALLOW_FF"
echo "    - ff_only = $INPUT_FF_ONLY"
echo "    - allow_forks = $INPUT_ALLOW_FORKS"
echo "    - user_name = $INPUT_USER_NAME"
echo "    - user_email = $INPUT_USER_EMAIL"
echo "    - push_token = $INPUT_PUSH_TOKEN = ${!INPUT_PUSH_TOKEN}"
echo

if [[ -z "${!INPUT_PUSH_TOKEN}" ]]; then
  echo "Set the ${INPUT_PUSH_TOKEN} env variable."
  exit 1
fi

FF_MODE="--no-ff"
if $INPUT_ALLOW_FF; then
  FF_MODE="--ff"
  if $INPUT_FF_ONLY; then
    FF_MODE="--ff-only"
  fi
fi

if ! $INPUT_ALLOW_FORKS; then
  if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "Set the GITHUB_TOKEN env variable."
    exit 1
  fi
  URI=https://api.github.com
  API_HEADER="Accept: application/vnd.github.v3+json"
  AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
  pr_resp=$(curl -X GET -s -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/$GITHUB_REPOSITORY")
  if [[ "$(echo "$pr_resp" | jq -r .fork)" != "false" ]]; then
    echo "Nightly merge action is disabled for forks (use the 'allow_forks' option to enable it)."
    exit 0
  fi
fi

git remote set-url origin https://x-access-token:${!INPUT_PUSH_TOKEN}@github.com/$GITHUB_REPOSITORY.git
git config --global user.name "$INPUT_USER_NAME"
git config --global user.email "$INPUT_USER_EMAIL"

set -o xtrace

git fetch origin $BRANCH_TO_MERGE
git checkout -b $BRANCH_TO_MERGE origin/$BRANCH_TO_MERGE

git fetch origin $HEAD_BRANCH
git checkout -b $HEAD_BRANCH origin/$HEAD_BRANCH

if git merge-base --is-ancestor $BRANCH_TO_MERGE $HEAD_BRANCH; then
  echo "No merge is necessary"
  exit 0
fi;

set +o xtrace
echo
echo "  'Nightly Merge Action' is trying to merge the '$BRANCH_TO_MERGE' branch ($(git log -1 --pretty=%H $BRANCH_TO_MERGE))"
echo "  into the '$HEAD_BRANCH' branch ($(git log -1 --pretty=%H $HEAD_BRANCH))"
echo
set -o xtrace

# Do the merge
git merge $FF_MODE --no-edit $BRANCH_TO_MERGE

# Push the branch
git push origin $HEAD_BRANCH
