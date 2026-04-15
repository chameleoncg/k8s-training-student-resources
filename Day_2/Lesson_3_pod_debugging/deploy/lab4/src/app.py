import os
import sys
import time


required_var = os.environ.get("REQUIRED_ENV4")

with open("/var/log/app/log.txt", "a+") as f:

    if (not required_var or required_var != "true"):
        print("Writing logs to /var/log/app/log.txt")
        f.write("Missing or incorrect value for required variable REQUIRED_ENV4. Set it to \"true\".")
        exit(1)

    while True:
        time.sleep(600)

