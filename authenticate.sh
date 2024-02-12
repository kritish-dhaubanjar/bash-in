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

jq_commands=""
prepareUpdateRefreshToken(){
  local index=$1
  local refreshToken=$2
  local accessToken=$3
  jq_commands+=".[$index].refreshToken=\"$refreshToken\" | "
  jq_commands+=".[$index].accessToken=\"$accessToken\" | "
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

  ############################
  # prepareUpdateRefreshToken
  ############################
  prepareUpdateRefreshToken "$index" "$refreshToken" "$accessToken"

  index=$(($index + 1))
done <<< "$credentials"

updateRefreshToken
