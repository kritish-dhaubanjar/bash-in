#!/bin/bash

source $ENV
credentials=$(jq -c '.[]' "$CREDENTIALS")

generateAuthenticationTokens(){
  local refreshToken="$1"

  local response=$(curl -s -w "%{http_code}" -X GET -G "$AUTH_API_ENDPOINT" --data "clientId=lms" --data "token=$refreshToken")

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  accessToken=$(echo $json | jq -r '.data.accessToken')
  refreshToken=$(echo $json | jq -r '.data.refreshToken')

  echo "$accessToken $refreshToken"
}

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

jq_commands=""
prepareUpdateRefreshToken(){
  local index=$1
  local refreshToken=$2
  jq_commands+=".[$index].refreshToken=\"$refreshToken\" | "
}

updateRefreshToken(){
  jq_commands=${jq_commands% | }
  jq "$jq_commands" "$CREDENTIALS" > "$CREDENTIALS~"

  rm "$CREDENTIALS"
  mv "$CREDENTIALS~" "$CREDENTIALS"
}

index=0
while read -r credential; do
  at=$(date +"%Y-%m-%d %H:%M:%S")

  name=$(jq -r '.name' <<< "$credential")
  locations=$(jq '.locations' <<< "$credential")
  refreshToken=$(jq -r '.refreshToken' <<< "$credential")

  ###############################
  # generateAuthenticationTokens
  ###############################
  tokens=$(generateAuthenticationTokens "$refreshToken")

  if [ $? -ne 0 ];then
    logger -p user.err "error: [$at] failed to fetch new access token & refresh token for $name"
    continue
  else
    logger -p user.info "info: [$at] fetched new access token & refresh token for $name"
  fi

  read -r accessToken refreshToken <<< "$tokens"

  ###############
  # checkCalendar
  ###############
  calendar=$(checkCalendar "$accessToken")

  if [ $? -ne 0 ];then
    logger -p user.err "error: [$at] failed to fetch calendar for $workDate"
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

  ############################
  # prepareUpdateRefreshToken
  ############################
  prepareUpdateRefreshToken "$index" "$refreshToken"

  index=$(($index + 1))
done <<< "$credentials"

updateRefreshToken
