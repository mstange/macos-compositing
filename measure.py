import csv
import os
import subprocess
import sys

app_bundle_path = "/Users/mstange/Library/Developer/Xcode/DerivedData/IOSurface_compositing-bjcctwkmkjgauvcndwtxseupglst/Build/Products/Debug/IOSurface compositing.app"
powerlog_path = "/Applications/Intel Power Gadget/PowerLog"
csv_path = "/tmp/powerlog.csv"
args = sys.argv[1:] + [
    # "--use-iosurface",
    # "--use-opaque-calayer",
    # "--use-opaque-glcontext",
    # "--use-layer-for-content-view",
    "--close-after-20-seconds"
]

def quote_if_contains_spaces(arg):
    if " " in arg:
        return '"%s"' % arg
    return arg

def arg_list_to_command_line_string(args):
    return " ".join(map(quote_if_contains_spaces, args))

open_cmd = ["open", app_bundle_path, "--args"] + args
powerlog_cmd = [powerlog_path, "-file", csv_path, "-duration", "20s"]

FNULL = open(os.devnull, 'w')

subprocess.call(open_cmd)
subprocess.call(powerlog_cmd, stdout=FNULL)

power_numbers = []

with open(csv_path) as csvfile:
    reader = csv.DictReader(csvfile)
    for row in reader:
        if row['Elapsed Time (sec)'] is None:
            break
        if float(row['Elapsed Time (sec)']) < 2.0:
            continue # Ignore the first two seconds
        power = float(row['Processor Power_0(Watt)']) + float(row['IA Power_0(Watt)'])
        if power != 0.0:
            power_numbers.append(power)

power_numbers.sort()
power_numbers = power_numbers[:len(power_numbers) / 5] # take the lowest 20%

if power_numbers:
    avg_power = sum(power_numbers) / float(len(power_numbers))

    print "Power: {0:.2f} W".format(avg_power)
else:
    print "No power numbers collected. Was it run for less than two seconds?"
