#!/usr/bin/env python

"""
randomly subsample a fastq file to reduce assembly time
"""

import sys
import argparse
import random
from Bio.SeqIO.QualityIO import FastqGeneralIterator    # requires Biopython

# use argparse to grab command line arguments

parser = argparse.ArgumentParser("randomly subsample fastq files")

parser.add_argument('-1', '--forward_reads', type = str,
        nargs = "?", help = "fastq file containing forward R1 reads")
parser.add_argument('-2', '--reverse_reads', type = str,
        nargs = "?", help = "fastq file containing reverse R2 reads (leave blank if only single-end reads)")
parser.add_argument('-n', '--nReads', type = int,
        nargs = "?", default=100000, help = "number of reads required")
parser.add_argument('-o', '--forward_output', type = str,
                    nargs = "?", help = "output name for the subsetted forward file")
parser.add_argument('-r', '--reverse_output', type = str,
                    nargs = "?", help = "output name for the subsetted reverse file (leave blank if only single-end "
                                        "reads)")

# if no args given, print help and exit

if len(sys.argv) == 1:
    parser.print_help(sys.stderr)
    sys.exit(1)

args = parser.parse_args()

# check that the required arguments are provided

if args.forward_reads is None or \
    args.nReads is None or \
    args.forward_output is None:
        print("\n** a required input is missing\n"
              "** a reads file, number of reads to subset, and output prefix is required\n")
        parser.print_help(sys.stderr)
        sys.exit(1)

if args.reverse_reads and args.reverse_output is None:
    print("\n** if reverse reads are given, a reverse file name must be provided\n")
    parser.print_help(sys.stderr)
    sys.exit(1)

# figure out how many total reads are in the file

print("Scanning fastq file and calculating number of reads")

total_reads = 0

with open(args.forward_reads) as f:
    for title, seq, qual in FastqGeneralIterator(f):
        total_reads += 1

print("detected {} reads in {}".format(total_reads, args.forward_reads))

if args.nReads > total_reads:
    print("** warning: only {} reads detected but {} were requested".format(total_reads, args.nReads))
    print("** warning: subsetting aborted")
    sys.exit(1)

# create random numbers of reads to sample

reads_to_sample = set(random.sample(range(total_reads + 1), args.nReads))

# go through forward reads again and write sub-sampled reads to file

record_number = 0
forward_ids = set()
output_forward = open(args.forward_output, "w")

with open(args.forward_reads) as f:
    forward_reads_written = 0
    for title, seq, qual in FastqGeneralIterator(f):
        record_number += 1
        if record_number in reads_to_sample:
            forward_ids.add(title)
            output_forward.write("@{}\n{}\n+\n{}\n".format(title, seq, qual))
            forward_reads_written += 1

print("** wrote {} reads to {}".format(forward_reads_written, args.forward_output))

if args.reverse_reads:
    output_reverse = open(args.reverse_output, "w")
    reverse_reads_written = 0
    with open(args.reverse_reads) as f:
        for title, seq, qual in FastqGeneralIterator(f):
            if title in forward_ids:
                output_reverse.write("@{}\n{}\n+\n{}\n".format(title, seq, qual))
                reverse_reads_written += 1
    print("** wrote {} reads to {}".format(reverse_reads_written, args.reverse_output))
