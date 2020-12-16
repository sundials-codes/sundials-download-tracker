This repository contains a script for polling the GitHub API to track the number of SUNDIALS downloads, storing the GitHub responses in json files in the `data` dirctory, and then querying this data to understand the number of SUNDIALS downloads in a particular date range.

## Setup

First, you must have python installed, and the (requests)[https://pypi.org/project/requests/] package.

To install requests with pip:
```
pip install requests
```

Next, clone this repository, or pull the latest to ensure you have the complete database.

```
git clone https://github.com/sundials-codes/sundials-download-tracker # if necessary
git pull origin master
```

## Example: getting the number of downloads in December 2020

To get the numbers for all SUNDIALS package:

```
python get-sundials-downloads.sh --db data query all --date 12-01-2020 12-31-2020
```

If you just want the numbers for a specific package, you can do

```
python get-sundials-downloads.sh --db data query arkode --date 12-01-2020 12-31-2020
```