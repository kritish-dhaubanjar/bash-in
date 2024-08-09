#!/bin/bash

source $ENV
credentials=$(jq -c '.[]' "$CREDENTIALS")

getProjectInvolvement() {
  local accessToken="$1"
  local projectId="$2"
  local today=$(date +"%Y-%m-%d")

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

getTaskTypes() {
  local accessToken="$1"
  local today=$(date +"%Y-%m-%d")

  local response=$(curl -s -w "%{http_code}" -X GET -G "$TASK_TYPES_API_ENDPOINT" \
    -H "authorization: Bearer $accessToken" \
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  local taskTypes=$(echo $json | jq -r '.data')

  echo "$taskTypes"
}

getPendingWorklogs() {
  local accessToken="$1"
  local today=$(date +"%Y-%m-%d")

  local response=$(curl -s -w "%{http_code}" -X GET -G "$CALENDAR_API_ENDPOINT" \
    --data "status=PENDING" \
    --data "fetchType=self" \
    --data "size=32" \
    --data "startDate=2023-07-17" \
    --data "endDate=$today" \
    -H "authorization: Bearer $accessToken" \
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  local pendingWorklogs=$(echo $json | jq -r '.data')

  echo "$pendingWorklogs"
}

sendWorklog() {
  local accessToken="$1"
  local worklog="$2"
  local worklogShifts="$3"
  local todoList="$4"

  local worklogId=$(jq -r '.worklog.id' <<< "$worklog")
  local workDate=$(jq -r '.date' <<< "$worklog")

  local workWeekDay=$(date -d "$workDate" "+%w")

  local worklogShift=$(jq -r ".[$workWeekDay]" <<< "$worklogShifts")
  local worklogs=$(jq --arg d "$workDate" '.[$d]' <<< "$todoList")

  if [ "$worklogShift" == "null" ] || [ "$worklogs" == "null" ]; then
    return 1
  fi

  local jsonData='{
    "status": "PENDING",
    "worklogShift": "'"$worklogShift"'",
    "worklog": '"$worklogs"'
  }'

  local response=$(curl -s -w "%{http_code}" -X PUT "$ATTENDANCE_API_ENDPOINT/$worklogId" \
    -H 'accept: application/json' \
    -H 'content-type: application/json' \
    -H "authorization: Bearer $accessToken" \
    --data-raw "$jsonData"
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  return 0
}

while read -r credential; do
  at=$(date +"%Y-%m-%d %H:%M:%S")

  name=$(jq -r '.name' <<< "$credential")
  projectId=$(jq -r '.projectId' <<< "$credential")
  accessToken=$(jq -r '.accessToken' <<< "$credential")
  orgFilePath=$(jq -r '.orgFilePath' <<< "$credential")
  worklogShifts=$(jq -r '.worklogShifts' <<< "$credential")

  switch=$(jq -r '.switch."fill-worklog"' <<< "$credential")

  if [ "$switch" != "true" ]; then
    logger -p user.info "info: [$at] skipping for $name"
    continue
  fi

  projectInvolvement=$(getProjectInvolvement "$accessToken" "$projectId")

  if [ $? -ne 0 ];then
    logger -p user.err "error: [$at] failed to fetch project involvement of $name"
    continue
  fi

  taskTypes=$(getTaskTypes "$accessToken")

  if [ $? -ne 0 ];then
    logger -p user.err "error: [$at] failed to fetch taskTypes of $name"
    continue
  fi

  pendingWorklogs=$(getPendingWorklogs "$accessToken")
  pendingWorklogs=$(jq -c '.[]' <<< "$pendingWorklogs")

  if [ $? -ne 0 ];then
    logger -p user.err "error: [$at] failed to fetch PENDING worklogs of $name"
    continue
  fi

  todoList=$(python "$ORG_PARSER_PATH" "$orgFilePath" "$projectInvolvement" "$taskTypes")
  if [ $? -ne 0 ];then
    logger -p user.err "error: [$at] failed to parse org file for $name"
    continue
  fi

  logger -p user.info "info: [$at] success to parse org file for $name"

  while read -r pendingWorklog; do
    worklogId=$(jq -r '.worklog.id' <<< "$pendingWorklog")
    workDate=$(jq -r '.date' <<< "$pendingWorklog")

    worklog=$(sendWorklog "$accessToken" "$pendingWorklog" "$worklogShifts" "$todoList")

    if [ $? -ne 0 ];then
      logger -p user.err "error: [$at] failed to fill worklogId $worklogId, of $name for $workDate"
      continue
    fi

    logger -p user.info "info: [$at] successfully filled worklogId $worklogId, of $name for $workDate, in draft state"

  done <<< "$pendingWorklogs"
done <<< "$credentials"
