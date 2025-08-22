## Install dependencies
### pip3

``` sh
sudo apt install python3-pip
```

### orgparse

``` sh
pip install orgparse
```

### [logex](https://github.com/kritish-dhaubanjar/logex)
```sh
sudo curl -L https://raw.githubusercontent.com/kritish-dhaubanjar/logex/main/logex.sh -o /usr/local/bin/logex && sudo chmod +x /usr/local/bin/logex
```

## bash-in

```
15 3 * * 0-6 ENV=/home/vim1s/bash-in/.env /home/vim1s/bash-in/authenticate.sh
16 3 * * 1-5 ENV=/home/vim1s/bash-in/.env /home/vim1s/bash-in/attendance.sh
17 3 * * 1-5 ENV=/home/vim1s/bash-in/.env /home/vim1s/bash-in/approve-worklog.sh

15 7 * * 2 ENV=/home/vim1s/bash-in/.env /home/vim1s/bash-in/authenticate.sh
16 7 * * 2 ENV=/home/vim1s/bash-in/.env /home/vim1s/bash-in/weekly-report.sh

# midnight
15 18 * * 0-6 ENV=/home/orangepi/workspace/bash-in/.env /home/orangepi/workspace/bash-in/authenticate.sh
16 18 * * 1-5 ENV=/home/orangepi/workspace/bash-in/.env /home/orangepi/workspace/bash-in/fill-worklog.sh
17 18 * * 1-5 ENV=/home/vim1s/bash-in/.env /home/vim1s/bash-in/daily-worklogger.sh
```

![image](https://github.com/kritish-dhaubanjar/bash-in/assets/25634165/eb06e67c-03c9-410c-bab1-cc3eb374a4fa)

### Setup
| Key | Value |
|-|-|
| name | Kritish Dhaubanjar |
| refreshToken | Vyaguta Refresh Token |
| accessToken | Vyaguta Access Token |
| locations | <[SUN, MON, TUE, WED, THU, FRI, SAT]> {null, HOME, OFFICE} |
| projectId | Vyaguta Project ID |
| reportUserIds | Vyaguta User IDs |
| jira.boardId | 19 {https://traytinc.atlassian.net/jira/software/c/projects/AP/boards/19} |
| jira.userId | Jira User ID |
| jira.domain | https://traytinc.atlassian.net |
| jira.username | kritishd@trayt.health |
| jira.apiToken | Jira API Token |
| jira.JQL | JQL |
| switch.* | Feature Flags |
| outlook.calendar | Outlook Public Calendar Link |
| outlook.api | Outlook Public Calendar Link service.svc API |
| outlook.x-owa-urlpostdata | Decoded x-owa-urlpostdata header value |
| git.email | kritish.dhaubanjar@gmail.com |

## rsyslog

1. **/etc/rsyslog.d**
```
module(load="omprog")

if $programname == 'mele' then {
  action(type="omprog" binary="/usr/lib/rsyslog/rsyslog-webhook")
}
```

2. **/usr/lib/rsyslog/rsyslog-webhook**
```
#!/bin/bash

WEBHOOK_URL="https://discord.com/api/webhooks/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

while read line; do
  LINE="${line#*mele:}"

  curl -s -H "Content-Type: application/json" \
    -X POST \
    -d "{\"content\": \"$LINE\"}" \
    "$WEBHOOK_URL" >> /dev/null
done
```

3. **/etc/apparmor.d/rsyslog.d**
```
/usr/bin/* ix,
/usr/lib/rsyslog/* ix,
```
