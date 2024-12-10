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
