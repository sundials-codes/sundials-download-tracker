#!/usr/bin/env python

import argparse, json, pprint, requests, sys
from datetime import datetime, timedelta
from os import listdir

def notify(good):
  if good:
    print('TODO: email sundials-developers with success message')
  else:
    print('TODO: email sundials-developers with fail message')


def poll_github(args):
  # Determine database location
  if args.db:
    db_path = args.db
  else:
    db_path = '.'

  # TODO: Check if the response was successful, and if it was not, retry.
  # Request the releases information from GitHub
  r = requests.get('https://api.github.com/repos/LLNL/sundials/releases')
  if r.ok:
    # Save the response to a text file for archiving
    releases = r.json()
    now = datetime.now()
    datestring = '-'.join(map(str, [now.month, now.day, now.year]))
    filename = '%s/sundials-github-downloads.%s.txt' % (db_path, datestring)
    with open(filename, 'w') as outfile:
      json.dump(releases, outfile)
    print('Successfully polled GitHub... stats saved to %s' % filename)
    if args.notify: notify(True)
  else:
    if args.notify: notify(False)


def sum_for_release(package_names, releases):
  asset_counts = {}
  package_counts = {}
  for release in releases:
    for asset in release['assets']:
      for p in package_names:
        if asset['name'].startswith(p):
          asset_counts[asset['name']] = int(asset['download_count'])
          if p in package_counts:
            package_counts[p] = package_counts[p] + int(asset['download_count'])
          else:
            package_counts[p] = int(asset['download_count'])
  package_counts['total'] = sum(package_counts.values())
  return package_counts


def find_beginning(all_files, starting_when):
  file_dates = [datetime.strptime(f.split('.')[1], '%m-%d-%Y') for f in all_files]
  diffs = [(d,idx) for idx, d in enumerate(file_dates) if d-starting_when >= timedelta(days=0)]
  closest_date = min(diffs, key=lambda x: x[0])
  if closest_date[0] != starting_when:
    print('WARNING: requested starting date is not found in the database, using the next closest date after the starting date')
  return (all_files[closest_date[1]], closest_date[0])


def find_ending(all_files, ending_when):
  file_dates = [datetime.strptime(f.split('.')[1], '%m-%d-%Y') for f in all_files]
  diffs = [(d,idx) for idx, d in enumerate(file_dates) if ending_when-d >= timedelta(days=0)]
  closest_date = max(diffs, key=lambda x: x[0])
  if closest_date[0] != ending_when:
    print('WARNING: requested ending date is not found in the database, using the next closest date before the ending date')
  return (all_files[closest_date[1]], closest_date[0])


def query_stats(args):
  # Determine which packages to check
  if args.package[0] == 'all':
    package_names = ['sundials', 'arkode', 'cvode', 'cvodes', 'ida', 'idas', 'kinsol']
  else:
    package_names = args.package

  # Determine database location
  if args.db:
    db_path = args.db
  else:
    db_path = '.'

  # Determine time to start counting from
  if args.date:
    starting_when = datetime.strptime(args.date[0], '%m-%d-%Y')
    ending_when   = datetime.strptime(args.date[1], '%m-%d-%Y')
  else:
    starting_when = datetime.strptime('01-01-1970', '%m-%d-%Y')
    ending_when   = datetime.now()

  # List files in database
  all_files = listdir(db_path)

  # Load beginning file
  start_file, actual_starting_date = find_beginning(all_files, starting_when)
  with open(db_path + '/' + start_file, 'r') as json_file:
    starting_count = sum_for_release(package_names, json.load(json_file))

  # Loand ending file unless doing all time count
  if not args.all_time:
    end_file, actual_ending_date = find_ending(all_files, ending_when)
    with open(db_path + '/' + end_file, 'r') as json_file:
      ending_count = sum_for_release(package_names, json.load(json_file))
    difference = {key: ending_count[key] - starting_count.get(key, 0) for key in ending_count}
  else:
    actual_ending_date = ending_when
    difference = starting_count

  print('')
  print('Counting downloads from %s to %s' % (actual_starting_date, actual_ending_date))
  print(json.dumps(difference, indent=4))


###

parser = argparse.ArgumentParser(description='Script to track the number of SUNDIALS downloads.')
parser.add_argument('--db', type=str,
  help='path to the directory/database containing the daily GitHub statistic pulls')

subparsers = parser.add_subparsers(title='subcommands')

poll_parser = subparsers.add_parser('poll', help='poll GitHub for release download statisitics and store them')
poll_parser.set_defaults(which='poll')
poll_parser.add_argument('--notify', action='store_true',
  help='send a success email to sundials-devs@llnl.gov with the stats')

query_parser = subparsers.add_parser('query', help='query release download statisitics')
query_parser.set_defaults(which='query')
query_parser.add_argument('package', metavar='package', type=str, nargs='+',
  help='which SUNDIALS package to get the numbers for (all, sundials, arkode, cvode(s), ida(s), kinsol)')
query_parser.add_argument('--all-time', action='store_true',
  help='get the all time count')
query_parser.add_argument('--date', type=str, nargs=2,
  help='date range to count; dates must be in the format mm-dd-yyyy')

args = parser.parse_args()

if args.which == 'poll':
  poll_github(args)
elif args.which == 'query':
  query_stats(args)
