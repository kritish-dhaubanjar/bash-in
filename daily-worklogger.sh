#!/bin/bash

source $ENV
source "$GITHUB_REPORTER"

credentials=$(jq -c '.[]' $CREDENTIALS)

declare -A WORKLOG=(
  Coding=""
  Meeting=""
  Other=""
)

function getJiraIssues() {
  jiraDomain=$1
  jiraAuthHeader=$2
  jiraJQL=$3

  local response=$(curl -s -w "%{http_code}" -X GET -G "$jiraDomain/rest/api/2/search/jql" \
    --data-urlencode "$jiraJQL" \
    --data-urlencode "fields=*all" \
    -H "Content-Type: application/json" \
    -H "$jiraAuthHeader"
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  local jiraIssues=$(jq -r '[.issues[] | { key: .key, summary: .fields.summary, status: .fields.status.name, project: .fields.project.name }]' <<< "$json")

  echo "$jiraIssues"
}

function getOutlookCalendarEvents() {
  outlookCalendarAPI=$1
  outlookAuthHeader=$2

  local response=$(curl -s -w "%{http_code}" -X GET -G "$outlookCalendarAPI" \
    -H "action: FindItem" \
    -H "x-owa-urlpostdata: $(echo $outlookAuthHeader)"
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  outlookCalendarEvents=$(jq -c '[.Body.ResponseMessages.Items[0].RootFolder.Items[] | { subject: .Subject }]' <<< $json)

  echo "$outlookCalendarEvents"
}

function getProjectInvolvement() {
  local accessToken="$1"
  local projectId="$2"

  local response=$(curl -s -w "%{http_code}" -X GET -G "$INVOLVEMENTS_API_ENDPOINT" \
    -H "authorization: Bearer $accessToken" \
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  local projectInvolvement=$(jq -r --arg projectId "$projectId" '.data[] | select(.type=="Project" and .id==$projectId)' <<< "$json")

  echo "$projectInvolvement"
}

function getPendingWorklog() {
  local accessToken=$1
  local date=$2

  local response=$(curl -s -w "%{http_code}" -X GET -G "$CALENDAR_API_ENDPOINT" \
    --data "status=PENDING" \
    --data "fetchType=self" \
    --data "size=1" \
    --data "startDate=$date" \
    --data "endDate=$date" \
    -H "authorization: Bearer $accessToken" \
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  local pendingWorklog=$(jq -r '.data[0]' <<< $json)

  echo "$pendingWorklog"
}

function sendWorklog() {
  local accessToken=$1
  local pendingWorklogId=$2
  local projectInvolvement=$3

  local payload=$(cat <<-EOF
  {
    "status": "PENDING",
    "worklog": [
      {
        "involvement": {
          "id": $(jq -r '.id' <<< "$projectInvolvement"),
          "name": "$(jq -r '.name' <<< "$projectInvolvement")",
          "type": "$(jq -r '.type' <<< "$projectInvolvement")"
        },
        "tasks": [
          {
            "taskType": {
              "id": 1,
              "name": "Coding"
            },
            "note": "$(echo ${WORKLOG["Coding"]} | tr '"' "'")"
          },
          {
            "taskType": {
              "id": 4,
              "name": "Meeting"
            },
            "note": "$(echo ${WORKLOG["Meeting"]} | tr '"' "'")"
          },
          {
            "taskType": {
              "id": 10,
              "name": "Other"
            },
            "note": "$(echo ${WORKLOG["Other"]} | tr '"' "'")"
          }
        ]
      }
    ]
  }
EOF
  )

  local response=$(curl -s -w "%{http_code}" -X PUT "$ATTENDANCE_API_ENDPOINT/$pendingWorklogId" \
    -H 'accept: application/json' \
    -H 'content-type: application/json' \
    -H "authorization: Bearer $accessToken" \
    --data-raw "$payload"
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  return 0
}

while read -r credential; do
  today=$(date +%F)
  at=$(date +"%Y-%m-%d %H:%M:%S")

  name=$(jq -r '.name' <<< "$credential")
  switch=$(jq -r '.switch."daily-worklogger"' <<< "$credential")

  WORKLOG["Coding"]=""
  WORKLOG["Meeting"]=""
  WORKLOG["Other"]=""

  if [ "$switch" != "true" ]; then
    logger -p user.info "info: [$at] skipping daily-worklogger for $name"
    continue
  fi

  ###############
  # getJiraIssues
  ###############
  jiraProject=$(jq -r '.jira.project' <<< "$credential")
  jiraUserId=$(jq -r '.jira.userId' <<< "$credential")
  jiraDomain=$(jq -r '.jira.domain' <<< "$credential")
  jiraUsername=$(jq -r '.jira.username' <<< "$credential")
  jiraApiToken=$(jq -r '.jira.apiToken' <<< "$credential")
  jiraJQL=$(jq -r '.jira.JQL' <<< "$credential")
  jiraAuthHeader="Authorization: Basic $(echo -n "$jiraUsername:$jiraApiToken" | base64 -w 0)"

  jiraIssues=$(getJiraIssues $jiraDomain "$jiraAuthHeader" "$jiraJQL")

  if [ $? -ne 0 ]; then
    logger -p user.err "error: [$at] failed to fetch jira issues of $name"
    continue
  fi

  jiraIssues=$(jq -c '.[]' <<< "$jiraIssues")

  declare -A STATUS=()

  if [[ ! -z $jiraIssues ]]; then
    while read -r jiraIssue; do
      key=$(jq -r '.key' <<< "$jiraIssue")
      summary=$(jq -r '.summary' <<< "$jiraIssue")
      status=$(jq -r '.status' <<< "$jiraIssue")

      logger -p user.info "info: • $key: $summary [$status]"

      STATUS["$status"]+="• $key: $summary\n"
    done <<< "$jiraIssues"

    WORKLOG["Coding"]=""

    for KEY in "${!STATUS[@]}"; do
      WORKLOG["Coding"]+="$KEY\n${STATUS["$KEY"]}\n"
    done

    logger -p user.info "info: ${WORKLOG["Coding"]}"
  fi

  #######################################################
  # git
  #######################################################
  email=$(jq -r '.git.email' <<< "$credential")
  LOGS="$(logex -a "$email" "$REPOSITORIES")"

  if [[ ! -z $LOGS ]]; then
    logger -p user.info "info: ${LOGS}"

    while read -r log; do
      WORKLOG["Coding"]+="\n${log}"
    done <<< "$LOGS"
  fi

  ###########################
  # getGithubReviews
  ##########################
  githubUsername=$(jq -r '.git.username' <<< "$credential")
  githubApiToken=$(jq -r '.git.apiToken' <<< "$credential")

  githubReviews=$(getGithubReviews "$githubUsername" "$githubApiToken" "$today")

  if [ $? -ne 0 ]; then
    logger -p user.err "error: [$at] failed to fetch github reviews for $name"
    continue
  fi

  if [[ ! -z $githubReviews ]]; then
    WORKLOG["Other"]+="PRs Reviewed\n"

    while read -r githubReview; do
      WORKLOG["Other"]+="\n• ${githubReview}"
    done <<< "$githubReviews"
  fi

  ###########################
  # getOutlookCalendarEvents
  ##########################
  outlookProject=$(jq -r '.outlook.project' <<< "$credential")
  outlookCalendarAPI=$(jq -r '.outlook.api' <<< "$credential")
  outlookAuthHeader=$(jq -r '.outlook."x-owa-urlpostdata"' <<< $credential)
  outlookAuthHeader=$(jq \
    --arg startDate "${today}T00:00:00.000" \
    --arg endDate "${today}T23:59:59.999" \
    '.Body.Paging.StartDate = $startDate | .Body.Paging.EndDate = $endDate' <<< "$outlookAuthHeader")

  outlookCalendarEvents=$(getOutlookCalendarEvents $outlookCalendarAPI "$outlookAuthHeader")

  if [ $? -ne 0 ]; then
    logger -p user.err "error: [$at] failed to fetch outlook calendar events for $name"
    continue
  fi

  outlookCalendarEvents=$(jq -c '.[]' <<< "$outlookCalendarEvents")

  if [[ ! -z $outlookCalendarEvents ]]; then
    while read -r outlookCalendarEvent; do
      event=$(jq -r '.subject' <<< "$outlookCalendarEvent")

      logger -p user.info "info: • $event"

      WORKLOG["Meeting"]+="• $event\n"
    done <<< "$outlookCalendarEvents"

    logger -p user.info "info: ${WORKLOG["Meeting"]}"
  fi

  #######################################################
  # getPendingWorklog, getProjectInvolvement, sendWorklog
  #######################################################
  accessToken=$(jq -r '.accessToken' <<< "$credential")
  projectId=$(jq -r '.projectId' <<< "$credential")

  pendingWorklog=$(getPendingWorklog "$accessToken" "$today")

  if [ $? -ne 0 ];then
    logger -p user.err "error: [$at] failed to fetch PENDING worklogs of $name"
    continue
  fi

  pendingWorklogId=$(jq -r '.worklog.id' <<< "$pendingWorklog")
  projectInvolvement=$(getProjectInvolvement "$accessToken" "$projectId")

  if [ $? -ne 0 ]; then
    logger -p user.err "error: [$at] failed to fetch project involvement of $name"
    continue
  fi

  sendWorklog "$accessToken" "$pendingWorklogId" "$projectInvolvement"

  if [ $? -ne 0 ]; then
    logger -p user.err "error: [$at] failed to fill pending worklog of $name for $today"
    continue
  fi

  logger -p user.info "info: [$at] successfully filled worklog of $name for $today, in draft state"
done <<< $credentials
