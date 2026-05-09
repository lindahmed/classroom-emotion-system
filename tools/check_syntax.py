#!/usr/bin/env python3
import sys

with open(r'C:\Users\Linda\classroom-emotion-system\app.R', 'r') as f:
    lines = f.readlines()

# Check lines 778-785
print("Lines 778-785 (0-indexed as 777-784):")
for i in range(777, 785):
    print(f"{i+1:4d}: {repr(lines[i])}")

# Count brackets
open_paren = sum(line.count('(') for line in lines)
close_paren = sum(line.count(')') for line in lines)
print(f"\nTotal opening parens: {open_paren}")
print(f"Total closing parens: {close_paren}")
print(f"Difference: {open_paren - close_paren}")
