#!/bin/bash

source $ENV

function filterGithubIssues(){
  local pullRequestUrl=$1
  local username=$2
  local token=$3
  local date=$4

  local response=$(curl -s -w "%{http_code}" -X GET -G "$pullRequestUrl/reviews" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $token" \
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  reviews=$(jq --arg username "$username" --arg date "$date" '[ .[] | select(.user.login == $username and .submitted_at >= $date) ]' <<< "$json")

  echo "$reviews"
}

function getGithubReviewedIssues(){
  local username=$1
  local token=$2
  local date=$3

  local response=$(curl -s -w "%{http_code}" -X GET -G "$GITHUB_ISSUE_API_ENDPOINT" \
    --data "q=is:pr+reviewed-by:$username+updated:>=$date" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $token" \
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  local issues=$(jq -r '[.items[] | {pull_request: .pull_request, title: .title}]' <<< "$json")

  echo "$issues"
}

function getGithubReviews(){
  local username=$1
  local token=$2
  local date=$3

  local issues=$(getGithubReviewedIssues "$username" "$token" "$date")

  if [ $? -ne 0 ]; then
    return 1
  fi

  local issues=$(jq -c '.[]' <<< $issues)

  if [[ ! -z $issues ]]; then
    while read -r issue; do
      title=$(jq -r '.title' <<< "$issue")
      pullRequestUrl=$(jq -r '.pull_request.url' <<< $issue)

      reviews=$(filterGithubIssues "$pullRequestUrl" "$username" "$token" "$date")

      if [ $? -ne 0 ]; then
        return 1
      fi

    reviewsCount=$(jq -c '[ .[] ] | length' <<< "$reviews")

      if [ "$reviewsCount" -gt 0 ]; then
        echo "$title"
      fi
    done <<< "$issues"
  fi
}
