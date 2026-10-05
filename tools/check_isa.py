#!/usr/bin/env python3
import re,sys
bad=[]
for line in open(sys.argv[1]):
    m=re.match(r"\s*[0-9a-f]+:\s+[0-9a-f]+\s+(\S+)",line)
    if m and (m[1] in {"mul","mulh","mulhsu","mulhu","div","divu","rem","remu","mret","wfi"} or m[1].startswith("csr")):
        bad.append(line.strip())
if bad: sys.exit("Forbidden instructions: " + str(bad))
print("RV32I instruction scan PASS:",sys.argv[1])
