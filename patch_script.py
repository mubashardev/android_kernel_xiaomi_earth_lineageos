import sys, re

filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

# Replace arg4 with *arg if arg4 is not found in content
# Wait, this script is part of build.sh. I will just use multi_replace_file_content on build.sh!
