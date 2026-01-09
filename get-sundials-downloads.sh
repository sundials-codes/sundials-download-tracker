#!/usr/bin/env python

# SUNDIALS Copyright Start
# Copyright (c) 2002-2020, Lawrence Livermore National Security
# and Southern Methodist University.
# All rights reserved.
#
# See the top-level LICENSE and NOTICE files for details.
#
# SPDX-License-Identifier: BSD-3-Clause
# SUNDIALS Copyright End


import argparse, glob, json, requests, sys
from datetime import datetime, timedelta, timezone


###################################################
# Helper functions
###################################################

def sum_up_clones(all_files, start_date, end_date):
  clone_count = 0
  for f in all_files:
    file_date = datetime.strptime(f.split('.')[1], '%m-%d-%Y').replace(tzinfo=timezone.utc)
    if file_date >= start_date and file_date <= end_date:
      with open(f, 'r') as json_file:
        data = json.load(json_file)
        if 'clones' in data:
          clone_count = clone_count + data['clones']
  return clone_count


def sum_for_release(package_names, data):
  asset_counts = {}
  package_counts = {}
  for release in data['releases']:
    # ignore draft releases
    if release['draft'] == True: break
    for asset in release['assets']:
      for p in package_names:
        if asset['name'].startswith(p):
          asset_counts[asset['name']] = int(asset['download_count'])
          if p in package_counts:
            # print('%s: total = %d + %d' % (asset['name'], package_counts[p], asset['download_count']))
            package_counts[p] = package_counts[p] + int(asset['download_count'])
          else:
            # print('%s: total = %d' % (asset['name'], asset['download_count']))
            package_counts[p] = int(asset['download_count'])
  return package_counts


def find_beginning(all_files, starting_when):
  file_dates = [datetime.strptime(f.split('.')[1], '%m-%d-%Y').replace(tzinfo=timezone.utc) for f in all_files]
  diffs = [(d,idx) for idx, d in enumerate(file_dates) if d-starting_when >= timedelta(days=0)]
  closest_date = min(diffs, key=lambda x: x[0])
  return (all_files[closest_date[1]], closest_date[0])


def find_ending(all_files, ending_when):
  file_dates = [datetime.strptime(f.split('.')[1], '%m-%d-%Y').replace(tzinfo=timezone.utc) for f in all_files]
  diffs = [(d,idx) for idx, d in enumerate(file_dates) if ending_when-d >= timedelta(days=0)]
  closest_date = max(diffs, key=lambda x: x[0])
  return (all_files[closest_date[1]], closest_date[0])

###################################################
# Subcommands
###################################################

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
    starting_when = datetime.strptime(args.date[0], '%m-%d-%Y').replace(tzinfo=timezone.utc)
    ending_when   = datetime.strptime(args.date[1], '%m-%d-%Y').replace(tzinfo=timezone.utc)
  else:
    starting_when = datetime.strptime('01-01-1970', '%m-%d-%Y').replace(tzinfo=timezone.utc)
    ending_when   = datetime.now(tz=timezone.utc)

  # List files in database
  all_files = glob.glob(db_path + '/sundials-github-downloads*.txt')

  # Load beginning file
  start_file, actual_starting_date = find_beginning(all_files, starting_when)
  with open(start_file, 'r') as json_file:
    starting_count = sum_for_release(package_names, json.load(json_file))

  # Load ending file unless doing all time count
  if not args.all_time:
    end_file, actual_ending_date = find_ending(all_files, ending_when)
    with open(end_file, 'r') as json_file:
      ending_count = sum_for_release(package_names, json.load(json_file))
    total_counts = {key: ending_count[key] - starting_count.get(key, 0) for key in ending_count}
  else:
    actual_ending_date = ending_when
    total_counts = starting_count

  # Now sum up clones
  total_counts['clones'] = sum_up_clones(all_files, actual_starting_date, actual_ending_date)

  # Now sum up everything
  total_counts['total'] = sum(total_counts.values())

  print('')
  print('Counting downloads from %s UTC to %s UTC\n' % (actual_starting_date, actual_ending_date))
  print('```')
  print(json.dumps(total_counts, indent=4))
  print('```')


def poll_github(args):
  # Determine database location
  if args.db:
    db_path = args.db
  else:
    db_path = '.'

  headers = {'Authorization': 'token %s' % args.token}

  # Request the releases information from GitHub
  r = requests.get('https://api.github.com/repos/LLNL/sundials/releases', headers=headers)
  r.raise_for_status()
  releases = r.json()
  print(f'releases: {releases}')

  r2 = requests.get('https://api.github.com/repos/LLNL/sundials/traffic/clones?per=day', headers=headers)
  r2.raise_for_status()
  clones = r2.json()

  # Find the clone count for today-1
  combined = { 'releases': releases }
  now = datetime.now(tz=timezone.utc)
  print(f'clones: {clones}')
  for clone in clones['clones']:
    clone_date = datetime.strptime(clone['timestamp'], '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    if clone_date.date() == (now.date() - timedelta(days=1)):
      combined['clones'] = clone['count']
      break

  # Save the response to a text file for archiving
  datestring = '-'.join(map(str, [now.month, now.day, now.year]))
  filename = '%s/sundials-github-downloads.%s.txt' % (db_path, datestring)
  with open(filename, 'w') as outfile:
    json.dump(combined, outfile)
  print('')
  print('Successfully polled GitHub... stats saved to %s' % filename)


###################################################
# Argument parsing
###################################################

parser = argparse.ArgumentParser(description='Script to track the number of SUNDIALS downloads.')
parser.add_argument('--db', type=str,
  help='path to the directory/database containing the daily GitHub statistic pulls')

subparsers = parser.add_subparsers(title='subcommands')

poll_parser = subparsers.add_parser('poll', help='poll GitHub for release download statisitics and store them')
poll_parser.set_defaults(which='poll')
poll_parser.add_argument('token',
  help='GitHub authentication token')

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
