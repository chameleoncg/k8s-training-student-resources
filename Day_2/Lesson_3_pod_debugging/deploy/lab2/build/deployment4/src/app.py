import os
import sys
import time


log_level = os.environ.get("LOG_LEVEL")
required_var = os.environ.get("REQUIRED_ENV")

if (not log_level):
    print("Defaulting to default logging, to increase logging, set LOG_LEVEL to DEBUG")

print("LOG_LEVEL:", log_level)


if (log_level == "DEBUG" and (not required_var or required_var != "true")):
    print("Missing or inccorect value for required variable REQUIRED_ENV. Set it to \"true\".")

if (not required_var or required_var != "true"):
    exit(1)

while True:
    time.sleep(600)

