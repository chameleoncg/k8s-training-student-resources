import os
import sys
import time
import traceback

required_var = os.environ.get("REQUIRED_ENV")

os.makedirs("/var/log", exist_ok=True)

with open("/var/log/log.txt", "a+") as f:

    print("Writing logs to /var/log")

    if (not required_var or required_var != "true"):

        print("Error in appliation, exiting")

        f.write("Missing or incorrect value for required variable REQUIRED_ENV. Set it to \"true\".\n")
        exit(1)

    while True:
        time.sleep(600)

