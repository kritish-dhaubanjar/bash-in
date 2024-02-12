#!/bin/bash

source $ENV
credentials=$(jq -c '.[]' "$CREDENTIALS")

checkCalendar(){
  local accessToken="$1"
  local workDate=$(date +"%Y-%m-%d")

  local response=$(curl -s -w "%{http_code}" -X GET -G "$CALENDAR_API_ENDPOINT"\
    --data "fetchType=self" \
    --data "worklog=true" \
    --data "startDate=$workDate" \
    --data "endDate=$workDate" \
    -H "authorization: Bearer $accessToken" \
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  holiday=$(echo $json | jq -r '.data[0].holiday')

  echo "$workDate $holiday"
}

updateAttendance(){
  local locations="$2"
  local accessToken="$1"

  local workDate=$(date +"%Y-%m-%d")
  local workWeekDay=$(date -d "$workDate" +%w)
  local location=$(jq -r ".[$workWeekDay]" <<< "$locations")

  if [ "$location" == "null" ]; then
    return 1
  fi

  local response=$(curl -s -w "%{http_code}" -X POST "$ATTENDANCE_API_ENDPOINT" \
    -H 'accept: application/json' \
    -H 'content-type: application/json' \
    -H "authorization: Bearer $accessToken" \
    -d "{ \"location\": \"$location\", \"workDate\": \"$workDate\" }"
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 201 ]; then
    return 1
  fi

  echo "$workDate $location"
}

while read -r credential; do
  at=$(date +"%Y-%m-%d %H:%M:%S")

  name=$(jq -r '.name' <<< "$credential")
  locations=$(jq '.locations' <<< "$credential")
  accessToken=$(jq -r '.accessToken' <<< "$credential")

  ###############
  # checkCalendar
  ###############
  calendar=$(checkCalendar "$accessToken")

  if [ $? -ne 0 ];then
    logger -p user.err "error: [$at] failed to fetch calendar"
    continue
  fi

  read -r workDate holiday <<< "$calendar"

  if [ "$holiday" != "null" ]; then
    logger -p user.info "info: [$at] skipping for holiday on $workDate"
    continue
  fi

  ###################
  # updateAttendance
  ###################
  attendance=$(updateAttendance "$accessToken" "$locations")

  if [ $? -ne 0 ];then
    logger -p user.err "error: [$at] failed to apply worklog of $workDate for $name"
    continue
  else
    read -r workDate location <<< "$attendance"
    logger -p user.info "info: [$at] applied worklog of $workDate at $location for $name"
  fi
done <<< "$credentials"
