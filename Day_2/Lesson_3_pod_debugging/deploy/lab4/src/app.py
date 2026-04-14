import os
import sys
import time


required_var = os.environ.get("REQUIRED_ENV")

with open("/var/log/log.txt", "r+") as f:

    if (!required_var or require_var != True):
        f.write("Missing or incorrect value for required variable REQUIRED_ENV. Set it to True.")
        exit(1)

    while True:
        time.sleep(600)

