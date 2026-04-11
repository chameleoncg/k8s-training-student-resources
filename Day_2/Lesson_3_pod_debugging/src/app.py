import sys
import time


try:
    with open("/etc/os-release", "r", encoding="utf-8") as f:
        # There is a bug on debian, bail 
        if "debian" in f.read().lower():
            print("We are running on a debian system. This is a known issue, exiting(1)")
            exit(1)

        print("We are running on a non-debian system. Great, we're good to run!")

        while True:
            time.sleep(300)
except OSError:
    print("Python application (app.py) did not start correctly. exiting(1)")
    sys.exit(1)

