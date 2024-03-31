import orgparse
import re
import sys
import json
from datetime import  datetime


def format_date(date_str):
  # Parse the input date string, expected string: Tue 2024 March 26
  date_obj = datetime.strptime(date_str, '%a %Y %B %d')
  formatted_date = date_obj.strftime('%Y-%m-%d')
  return formatted_date


def preprocess_org_content(org_content):
  org_content = org_content.replace("[ ]", "TODO")
  org_content = org_content.replace("[-]", "TODO")
  org_content = org_content.replace("[X]", "DONE")
  return org_content


def get_tasks_list_with_properties(org_content):
  tree = orgparse.loads(org_content)
  todo_list = []
  date = None

  for entry in tree[1:]:
    # if entry.heading matches specific pattern for date
    if entry.heading and not entry.todo and re.match(
        r'^... [0-9]{4} [A-Za-z]+ [0-9]{2}$', entry.heading):
      date = format_date(entry.heading)

    # if current entry is of todo type
    if entry.heading and entry.todo:
      todo_item = {
          "date": date,
          "tags": list(entry.tags) or ['OTHERS'],
          "title": '- ' + entry.heading,
          "status": entry.todo,
          "time_spent": 0,
      }

      # Extract time spent from logbook
      for clock in entry.clock:
        todo_item["time_spent"] += (clock.duration.seconds // 60)

      todo_list.append(todo_item)

  return todo_list


def group_by_date_and_tag(todo_list):
  grouped_by_date_and_tag = {}
  for todo_item in todo_list:
    date = todo_item["date"]
    tags = todo_item["tags"]
    if date not in grouped_by_date_and_tag:
      grouped_by_date_and_tag[date] = {}
    for tag in tags:
      if tag not in grouped_by_date_and_tag[date]:
        grouped_by_date_and_tag[date][tag] = {"tasks": [], "time_spent": 0}
      grouped_by_date_and_tag[date][tag]["tasks"].append(todo_item)
      grouped_by_date_and_tag[date][tag]["time_spent"] += todo_item[
          "time_spent"]
  return grouped_by_date_and_tag


def formatForAPI(grouped_todo_list, involvement, task_types):
  grouped_by_task_types_name = {}
  for task_type in task_types:
    id = task_type["id"]
    name = task_type["name"]

    grouped_by_task_types_name[name.upper().replace(" ", "_")] = { 'id': id, 'name': name }

  formattedData = {}
  for date, value in grouped_todo_list.items():
    worklogs = []
    worklog_item = {}
    worklog_item["involvement"]= { 'id': involvement['id'], 'name': involvement['name'], 'type': involvement['type'] }
    tasks = []
    for tag, task_list in value.items():
      item = {}
      item["taskType"] = grouped_by_task_types_name[tag]
      item["duration"] = task_list['time_spent'] if task_list['time_spent'] > 0 else 60
      notes = []

      for task in task_list['tasks']:
        notes.append(task['title'])

      item['note'] = "\n".join(notes)
      tasks.append(item)


    worklog_item['tasks'] = tasks
    worklogs.append(worklog_item)

    formattedData[date] = worklogs

  return formattedData



def parse_todo_list(org_file):
  # Read Org file content
  with open(org_file, 'r') as f:
    org_content = f.read()

  # Preprocess Org content
  org_content = preprocess_org_content(org_content)
  todo_list = get_tasks_list_with_properties(org_content)
  grouped_todo_list_by_date_and_tag = group_by_date_and_tag(todo_list)

  return grouped_todo_list_by_date_and_tag


# Usage
# org_file = "/mnt/sandisk/Sync/org/todo.org"
org_file = sys.argv[1]
involvement = sys.argv[2]
task_types = sys.argv[3]
parsed_todo_list = parse_todo_list(org_file)
formatted_todo_list_for_api = formatForAPI(parsed_todo_list, json.loads(involvement), json.loads(task_types))
print(json.dumps(formatted_todo_list_for_api))
