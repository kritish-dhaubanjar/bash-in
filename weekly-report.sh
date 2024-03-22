#!/bin/bash

source $ENV
credentials=$(jq -c '.[]' "$CREDENTIALS")

endDate=$(date -d "last Saturday" +"%Y-%m-%d")
startDate=$(date -d "$endDate - 6 days" +"%Y-%m-%d")

getWeeklyReport() {
  local accessToken="$1"
  local projectId="$2"
  local reportUserIds="$3"

  local response=$(curl -s -w "%{http_code}" -X GET -G "$REPORT_API_ENDPOINT"\
    --data "startDate=$startDate" \
    --data "endDate=$endDate" \
    --data "projectId=$projectId" \
    --data "userIds=$reportUserIds" \
    --data "additionalFields=tasks,allocation" \
    -H "authorization: Bearer $accessToken" \
  )

  local statusCode="${response: -3}"

  if [ "$statusCode" -ne 200 ]; then
    return 1
  fi

  local json="${response%???}"

  echo "$json" | jq -r '.data[] | .worklogs[] | .detail[] | .tasks[] | select(.taskType.name == "Coding") | .note' | sed 's/\\n/\n/g'
}

while read -r credential; do
  at=$(date +"%Y-%m-%d %H:%M:%S")
  name=$(jq -r '.name' <<< "$credential")
  projectId=$(jq -r '.projectId' <<< "$credential")
  accessToken=$(jq -r '.accessToken' <<< "$credential")
  reportUserIds=$(jq -r '.reportUserIds' <<< "$credential")

  switch=$(jq -r '.switch."weekly-report"' <<< "$credential")

  if [ "$switch" != "true" ]; then
      logger -p user.info "info: [$at] skipping weekly report generation for $name's team"
      continue
  fi

  report=$(getWeeklyReport "$accessToken" "$projectId" "$reportUserIds")

  if [ $? -ne 0 ]; then
    logger -p user.err "error: [$at] failed to fetch weekly report for $name's team"
    continue
  fi

  if [ ! -f "~/weekly-psr.txt" ]; then
    touch ~/weekly-psr.txt
  fi

  echo -e "[$startDate] - [$endDate]\n$name's team\n$report\n\n" | cat - ~/weekly-psr.txt > ~/weekly-psr.txt~ && mv ~/weekly-psr.txt~ ~/weekly-psr.txt

  logger -p user.info "info: [$at] generated weekly report for $name's team"
done <<< $credentials
