#!/bin/bash

source $ENV
credentials=$(jq -c '.[]' "$CREDENTIALS")

getSubmittedWorklogs(){
  local accessToken="$1"
  local workDate=$(date +"%Y-%m-%d")

  local response=$(curl -s -w "%{http_code}" -X GET -G "$ATTENDANCE_API_ENDPOINT"\
    --data "fetchType=team" \
    --data "startDate=2023-02-13" \
    --data "endDate=$workDate" \
    --data "size=100" \
    --data "status=SUBMITTED" \
    -H "authorization: Bearer $accessToken" \
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  worklogs=$(echo $json | jq -r '.data')

  echo "$worklogs"
}

processWorklog(){
  local accessToken="$1"
  local worklogId="$2"

  local response=$(curl -s -w "%{http_code}" -X PATCH "$ATTENDANCE_API_ENDPOINT/$worklogId/status" \
    -H 'accept: application/json' \
    -H 'content-type: application/json' \
    -H "authorization: Bearer $accessToken" \
    -d "{ \"status\": \"APPROVED\"}"
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
  accessToken=$(jq -r '.accessToken' <<< "$credential")

  #######################
  # approve-worklog
  #######################
  switch=$(jq -r '.switch."approve-worklog"' <<< "$credential")

  if [ "$switch" != "true" ]; then
    logger -p user.info "info: [$at] skipping for $name's team"
    continue
  fi

  #######################
  # getSubmittedWorklogs
  #######################
  worklogs=$(getSubmittedWorklogs "$accessToken")

  if [ $? -ne 0 ];then
    logger -p user.err "error: [$at] failed to fetch SUBMITTED worklogs of $name's team"
    continue
  fi

  worklogs=$(echo "$worklogs" | jq -c '.[]')

  if [ -z "$worklogs" ]; then
    logger -p user.info "info: [$at] no worklogs to approve for $name's team"
    continue
  fi

  while read -r worklog; do
    worklogId=$(jq -r '.id' <<< "$worklog")
    employeeName=$(jq -r '.employee.fullname' <<< "$worklog")
    workDate=$(jq -r '.workDate' <<< "$worklog")

    ##################
    # processWorklog
    ##################
    processWorklog "$accessToken" "$worklogId"

    if [ $? -ne 0 ];then
      logger -p user.err "error: [$at] failed to APPROVE worklogId $worklogId, of $employeeName for $workDate"
      continue
    fi

    logger -p user.info "info: [$at] approved worklogId $worklogId, of $employeeName for $workDate"
  done <<< $worklogs
done <<< $credentials
