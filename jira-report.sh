#!/bin/bash

source $ENV

getCurrentSprintId(){
  local jiraDomain="$1"
  local jiraAuthHeader="$2"
  local jiraBoardId="$3"

  local response=$(curl -s -w "%{http_code}" -X GET -G "$jiraDomain/rest/agile/1.0/board/$jiraBoardId/sprint" \
    --data "state=active" \
    -H "Content-Type: application/json" \
    -H "$jiraAuthHeader" \
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  sprintId=$(jq -r '.values[0] | .id' <<< "$json")

  echo "$sprintId"
}

getCurrentSprintEpics(){
  local jiraDomain="$1"
  local jiraAuthHeader="$2"
  local jiraBoardId="$3"
  local jiraSprintId="$4"

  local response=$(curl -s -w "%{http_code}" -X GET -G "$jiraDomain/rest/agile/1.0/board/$jiraBoardId/sprint/$jiraSprintId/issue" \
    --data "maxResults=1000" \
    -H "Content-Type: application/json" \
    -H "$jiraAuthHeader"
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  sprintEpics=$(jq -r '[.issues[] | select(.fields.epic) | {epicId: .fields.epic.id, summary: .fields.epic.summary}] | unique_by(.epicId)' <<< "$json")

  echo "$sprintEpics"
}

getEpicIssues(){
  local jiraDomain="$1"
  local jiraAuthHeader="$2"
  local jiraBoardId="$3"
  local jiraEpicId="$4"

  local response=$(curl -s -w "%{http_code}" -X GET -G "$jiraDomain/rest/agile/1.0/board/$jiraBoardId/epic/$jiraEpicId/issue" \
    --data "maxResults=1000" \
    -H "Content-Type: application/json" \
    -H "$jiraAuthHeader"
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  echo "$json"
}

jiraReport(){
  credential="$1"

  at=$(date +"%Y-%m-%d %H:%M:%S")

  name=$(jq -r '.name' <<< "$credential")

  switch=$(jq -r '.switch."jira-report"' <<< "$credential")

  if [ "$switch" != "true" ]; then
    logger -p user.info "info: [$at] skipping jira report generation for $name's team"
    continue
  fi

  jiraDomain=$(jq -r '.jira.domain' <<< "$credential")
  jiraUsername=$(jq -r '.jira.username' <<< "$credential")
  jiraApiToken=$(jq -r '.jira.apiToken' <<< "$credential")
  jiraBoardId=$(jq -r '.jira.boardId' <<< "$credential")

  jiraAuthHeader="Authorization: Basic $(echo -n "$jiraUsername:$jiraApiToken" | base64 -w 0)"

  currentSprintId=$(getCurrentSprintId "$jiraDomain" "$jiraAuthHeader" "$jiraBoardId")

  if [ $? -ne 0 ]; then
    logger -p user.err "error: [$at] failed to fetch current sprint id for $name's team"
    continue
  fi

  sprintEpics=$(getCurrentSprintEpics "$jiraDomain" "$jiraAuthHeader" "$jiraBoardId" "$currentSprintId")

  if [ $? -ne 0 ]; then
    logger -p user.err "error: [$at] failed to fetch epics for $name's team"
    continue
  fi

  sprintEpics=$(jq -c '.[]' <<< "$sprintEpics")

  epicReport=""

  while read -r epic; do
    epicId=$(jq -r '.epicId' <<< "$epic")
    summary=$(jq -r '.summary' <<< "$epic")

    epicIssues=$(getEpicIssues "$jiraDomain" "$jiraAuthHeader" "$jiraBoardId" "$epicId")

    if [ $? -ne 0 ];then
      logger -p user.err "error: [$at] failed to fetch issues of epic: $summary for $name's team"
      continue
    fi

    totalIssues=$(jq -c '.total' <<< "$epicIssues")
    doneIssues=$(jq -c '[.issues[] | select(.fields.status.name == "Done" or .fields.status.name == "Closed")] | length' <<< "$epicIssues")

    percentageCompletion=0

    if [ $totalIssues -gt 0 ]; then
      percentageCompletion=$(echo "scale=2; ($doneIssues / $totalIssues) * 100" | bc)
    fi

    epicReport="$epicReport\n- $summary: $percentageCompletion%, total: $totalIssues, done: $doneIssues"
  done <<< "$sprintEpics"

  logger -p user.info "info: [$at] jira report generated for $name's team"

  echo "$epicReport"
}
